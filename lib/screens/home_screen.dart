import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../models/song.dart';
import '../services/music_scanner.dart';
import '../services/storage_manager.dart';
import '../services/audio_handler.dart';
import '../services/lyric_parser.dart';
import '../widgets/music_widgets.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'online_screen.dart';
import '../main.dart' show audioHandler, AppColors;

// ─── 浮动音乐笔记粒子 ───
class _FloatingNote {
  double x, y, size, speed, opacity, rot;
  final int type; // 0=♪ 1=♫ 2=♩
  _FloatingNote(this.x, this.y, this.size, this.speed, this.opacity, this.rot, this.type);
}

class _NoteParticleBackground extends StatefulWidget {
  final Widget child;
  const _NoteParticleBackground({required this.child});
  @override
  State<_NoteParticleBackground> createState() => _NoteParticleBackgroundState();
}

class _NoteParticleBackgroundState extends State<_NoteParticleBackground> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  List<_FloatingNote> _notes = [];
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _notes = List.generate(18, (_) => _createNote(init: true));
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 30))..addListener(_update)..repeat();
  }

  _FloatingNote _createNote({bool init = false}) {
    return _FloatingNote(
      _rng.nextDouble() * 400 - 50,
      init ? _rng.nextDouble() * 700 - 100 : -30 - _rng.nextDouble() * 100,
      12 + _rng.nextDouble() * 18,
      0.15 + _rng.nextDouble() * 0.35,
      0.08 + _rng.nextDouble() * 0.2,
      _rng.nextDouble() * math.pi * 2,
      _rng.nextInt(3),
    );
  }

  void _update() {
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _notes.length; i++) {
        _notes[i].y -= _notes[i].speed;
        _notes[i].x += math.sin(_notes[i].y * 0.02) * 0.4;
        _notes[i].rot += 0.003;
        if (_notes[i].y < -60) {
          _notes[i] = _createNote();
          _notes[i].y = 800 + _rng.nextDouble() * 200;
        }
      }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _NotePainter(_notes, _ctrl.value),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotePainter extends CustomPainter {
  final List<_FloatingNote> notes;
  final double t;
  _NotePainter(this.notes, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in notes) {
      canvas.save();
      canvas.translate(n.x, n.y);
      canvas.rotate(n.rot);
      final paint = Paint()
        ..color = AppColors.foxOrange.withValues(alpha: n.opacity)
        ..style = PaintingStyle.fill;
      final textStyle = TextStyle(
        color: AppColors.foxOrange.withValues(alpha: n.opacity),
        fontSize: n.size,
        fontWeight: FontWeight.w300,
      );
      final tp = TextPainter(
        text: TextSpan(text: ['♪', '♫', '♩'][n.type], style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _NotePainter o) => true;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  late final AnimationController _gradientCtrl;

  Map<MusicCategory, List<Song>> _allSongs = {};
  Map<MusicCategory, List<Song>> _filteredSongs = {};
  bool _loading = true;
  String? _error;
  bool _showSearch = false;
  String _scanMode = 'quick';
  StorageManager? _store;

  int _scannedCount = 0;
  int _totalCount = 0;
  String _scanningDir = '';
  StreamSubscription? _songSub;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _gradientCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
    // 监听切歌 → 刷新MiniPlayer（只监听index变化避免频繁setState）
    _songSub = audioHandler.player.currentIndexStream.listen((_) { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addObserver(this);
    _initAndScan();
  }

  Future<void> _initAndScan() async {
    _store = await StorageManager.instance;
    _scanMode = _store!.scanMode;
    final has = await MusicScanner.hasPermission();
    if (!has) {
      setState(() { _loading = false; _permissionDenied = true; _error = '需要存储权限才能扫描本地音乐'; });
      return;
    }
    _scanMusic();
  }

  Future<void> _requestPermissionAndScan() async {
    final granted = await MusicScanner.requestPermission();
    if (!granted) {
      if (mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('需要存储权限', style: TextStyle(color: AppColors.textPrimary)),
            content: const Text('扫描本地音乐需要存储权限。\n请在系统设置中手动开启。', style: TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: AppColors.textSecondary))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('去设置', style: TextStyle(color: AppColors.foxOrange))),
            ],
          ),
        );
        if (go == true) await MusicScanner.openSettings();
      }
      return;
    }
    setState(() { _permissionDenied = false; _error = null; });
    _scanMusic();
  }

  Future<void> _scanMusic({bool forceFull = false}) async {
    setState(() { _loading = true; _error = null; _scannedCount = 0; _totalCount = 0; _scanningDir = ''; });
    try {
      final songs = await MusicScanner.scanAll(
        forceFullScan: forceFull,
        onProgress: (scanned, total, dir) {
          if (mounted) setState(() { _scannedCount = scanned; _totalCount = total; _scanningDir = dir.split('/').last; });
        },
      );
      if (mounted) setState(() { _allSongs = songs; _filteredSongs = Map.from(songs); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '扫描失败: $e'; });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) { _filteredSongs = Map.from(_allSongs); }
      else { _filteredSongs = { for (final e in _allSongs.entries) e.key: e.value.where((s) => s.title.toLowerCase().contains(q)).toList() }; }
    });
  }

  void _playList(List<Song> list, {int startIndex = 0}) { if (list.isEmpty) return; audioHandler.loadSongList(list, startIndex: startIndex); }
  void _openPlayer() { if (audioHandler.currentSong == null) return; Navigator.push(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const PlayerScreen(), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c), transitionDuration: const Duration(milliseconds: 300))); }
  Future<void> _openSettings() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); if (mounted) _scanMusic(forceFull: true); }
  int _countFav() => _store?.getFavorites().length ?? 0;

  // ─── 长按歌曲菜单 ───
  void _onSongLongPress(BuildContext context, Song song) {
    final isLocal = !song.filePath.startsWith('http');
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: AppColors.textSecondary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: AppColors.foxOrange), title: const Text('🎵 歌曲详情', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () { Navigator.pop(ctx); _showSongDetails(context, song); },
            ),
            ListTile(
              leading: const Icon(Icons.lyrics_rounded, color: AppColors.purple), title: const Text('📄 下载歌词', style: TextStyle(color: AppColors.textPrimary)),
              subtitle: const Text('保存.lrc文件到歌曲目录', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              onTap: () { Navigator.pop(ctx); _downloadLyrics(context, song); },
            ),
            if (isLocal) ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent), title: const Text('🗑️ 删除歌曲', style: TextStyle(color: Colors.redAccent)),
              onTap: () { Navigator.pop(ctx); _deleteSong(context, song); },
            ),
          ]),
        ),
      ),
    );
  }

  void _showSongDetails(BuildContext context, Song song) {
    final isLocal = !song.filePath.startsWith('http');
    String sizeStr = '';
    if (isLocal) {
      try { final f = File(song.filePath); if (f.existsSync()) sizeStr = '${(f.lengthSync() / 1024 / 1024).toStringAsFixed(1)}MB'; } catch (_) {}
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: [AppColors.foxOrange, AppColors.purple])), child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 22)),
          const SizedBox(width: 10), Expanded(child: Text(song.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _detailRow('歌手', song.artist.isNotEmpty ? song.artist : '未知'),
          _detailRow('分类', song.category == MusicCategory.dj ? '🔥 DJ' : '🎵 流行'),
          _detailRow('播放次数', '${song.playCount} 次'),
          if (sizeStr.isNotEmpty) _detailRow('文件大小', sizeStr),
          if (song.lastPlayed > 0) _detailRow('上次播放', DateTime.fromMillisecondsSinceEpoch(song.lastPlayed).toString().substring(0, 19)),
          if (isLocal) ...[const SizedBox(height: 6), Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.glass, borderRadius: BorderRadius.circular(8)), child: Text(song.filePath, style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5), fontSize: 10), maxLines: 3, overflow: TextOverflow.ellipsis))],
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭', style: TextStyle(color: AppColors.foxOrange)))],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
      Text('$label：', style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13)),
      Expanded(child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]));
  }

  Future<void> _downloadLyrics(BuildContext context, Song song) async {
    try {
      final lrc = await LyricParser.searchOnline(song.title, song.artist);
      if (lrc.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到歌词'), backgroundColor: Colors.orange));
        return;
      }
      final lrcPath = song.filePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc');
      final lrcText = lrc.map((l) {
        final min = l.time.inMinutes.remainder(60).toString().padLeft(2, '0');
        final sec = l.time.inSeconds.remainder(60).toString().padLeft(2, '0');
        final ms = (l.time.inMilliseconds % 1000).toString().padLeft(3, '0');
        return '[$min:$sec.$ms]${l.text}';
      }).join('\n');
      await File(lrcPath).writeAsString(lrcText);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ 歌词已下载: ${lrcPath.split('/').last}'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 下载歌词失败: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteSong(BuildContext context, Song song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('确认删除', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('确定要删除「${song.title}」吗？\n此操作不可恢复。', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final f = File(song.filePath);
      if (await f.exists()) {
        await f.delete();
        // 删除同目录歌词
        final lrcPath = song.filePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc');
        if (await File(lrcPath).exists()) await File(lrcPath).delete();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ 已移除: ${song.title}'), backgroundColor: Colors.green));
        _scanMusic(forceFull: true);
      }
    } catch (e) {
      if (mounted) {
        final errMsg = e.toString();
        if (errMsg.contains('Permission') || errMsg.contains('denied') || errMsg.contains('Read-only') || errMsg.contains('errno') || errMsg.contains('No such file')) {
          // Android 分区存储限制，File.delete() 即使文件存在也会返回 ENOENT
          showDialog(context: context, builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('⚠️ 无法删除', style: TextStyle(color: AppColors.textPrimary)),
            content: const Text('Android 11+限制应用直接删除文件。\n\n已从列表移除，文件需手动删除：\n用文件管理器找到该文件手动删除即可。', style: TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(onPressed: () {
                if (mounted) {
                  _scanMusic(forceFull: true);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已从列表移除'), backgroundColor: Colors.green));
                }
                Navigator.pop(ctx);
              }, child: const Text('好的，从列表移除', style: TextStyle(color: AppColors.foxOrange))),
            ],
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 删除失败: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  // ─── 顶部歌词显示 ───
  Widget _topLyrics() {
    return StreamBuilder<bool>(
      stream: audioHandler.player.playingStream,
      builder: (_, snap) {
        final playing = snap.data == true;
        final lyrics = audioHandler.lyrics;
        final idx = audioHandler.lyricIndex;
        if (!playing || lyrics.isEmpty || idx < 0) return const SizedBox.shrink();

        final cur = idx < lyrics.length ? lyrics[idx].text : '';
        final next = idx + 1 < lyrics.length ? lyrics[idx + 1].text : '';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Column(children: [
            Text(cur, style: const TextStyle(color: AppColors.foxOrange, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            if (next.isNotEmpty) Text(next, style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.4), fontSize: 11, height: 1.2), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          ]),
        );
      },
    );
  }

  @override
  void dispose() { _tabController.dispose(); _searchCtrl.dispose(); _gradientCtrl.dispose(); _songSub?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final total = (_allSongs[MusicCategory.dj]?.length ?? 0) + (_allSongs[MusicCategory.pop]?.length ?? 0);
    return Scaffold(
      body: _NoteParticleBackground(
        child: Column(children: [
          _foxHeader(total),
          if (!_showSearch) _tabBar(),
          _topLyrics(),
          Expanded(child: _permissionDenied ? _permView() : _loading ? _loadingView() : _error != null ? _errorView() : _showSearch ? _searchResults() : TabBarView(controller: _tabController, children: [
            _songList(MusicCategory.dj), _songList(MusicCategory.pop), _favList(), const OnlineScreen(),
          ])),
          if (!_showSearch && !_permissionDenied) MiniPlayer(onTap: _openPlayer),
        ]),
      ),
    );
  }

  Widget _foxHeader(int total) {
    return AnimatedBuilder(
      animation: _gradientCtrl,
      builder: (_, __) {
        final t = _gradientCtrl.value;
        return Container(
          height: 190,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                Color.lerp(const Color(0xFF1A0A2E), const Color(0xFF2D1040), t)!,
                Color.lerp(const Color(0xFF0D0D1A), const Color(0xFF1A0020), t)!,
              ],
            ),
          ),
          child: Stack(
            children: [
              // 阿狸背景（装饰）
              Positioned(right: -40, top: -30,
                child: Transform.rotate(angle: 0.1,
                  child: Container(width: 210, height: 170,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      image: const DecorationImage(image: AssetImage('assets/images/ali.jpg'), fit: BoxFit.cover, opacity: 0.2),
                      boxShadow: [BoxShadow(color: AppColors.glowOrange.withValues(alpha: 0.2), blurRadius: 40, spreadRadius: 15)],
                    ),
                  ),
                ),
              ),
              // 发光装饰条
              Positioned(bottom: 0, left: 0, right: 0,
                child: Container(height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Color.lerp(AppColors.foxOrange, AppColors.purple, t)!, AppColors.purple, Colors.transparent],
                    ),
                  ),
                ),
              ),
              // 右下角小阿狸
              Positioned(bottom: 8, right: 20,
                child: Container(width: 40, height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: const DecorationImage(image: AssetImage('assets/images/ali.jpg'), fit: BoxFit.cover, opacity: 0.25),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      // 阿狸头像 + 发光圈
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Color.lerp(AppColors.foxOrange, AppColors.purple, t)!.withValues(alpha: 0.7), width: 2.5),
                          boxShadow: [
                            BoxShadow(color: Color.lerp(AppColors.glowOrange, AppColors.glowPurple, t)!, blurRadius: 16, spreadRadius: 4),
                          ],
                          image: const DecorationImage(image: AssetImage('assets/images/ali.jpg'), fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [Color.lerp(AppColors.foxOrange, Colors.pink, t)!, Color.lerp(AppColors.purple, Colors.blue, t)!],
                          ).createShader(bounds),
                          child: const Text('🦊 狸音乐', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                        Text('$total 首 · ${_scanMode == 'full' ? '全局' : '快速'}',
                          style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 12)),
                      ]),
                      const Spacer(),
                      _headerBtn(Icons.search_rounded, () => setState(() => _showSearch = true)),
                      _headerBtn(Icons.settings_rounded, _openSettings),
                      _headerBtn(Icons.refresh_rounded, () => _scanMusic(forceFull: true)),
                    ]),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _headerBtn(IconData icon, VoidCallback onTap) {
    return Container(
      width: 36, height: 36,
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: IconButton(icon: Icon(icon, color: AppColors.textSecondary, size: 18), onPressed: onTap, padding: EdgeInsets.zero),
    );
  }

  Widget _tabBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(children: [
        _tabItem('🔥 DJ', 0, _filteredSongs[MusicCategory.dj]?.length ?? 0),
        const SizedBox(width: 6),
        _tabItem('🎵 流行', 1, _filteredSongs[MusicCategory.pop]?.length ?? 0),
        const SizedBox(width: 6),
        _tabItem('⭐ 收藏', 2, _countFav()),
        const SizedBox(width: 6),
        _tabItem('🌐 在线', 3, null),
      ]),
    );
  }

  Widget _tabItem(String label, int index, int? count) {
    final selected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _tabController.animateTo(index);
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.foxOrange.withValues(alpha: 0.15) : AppColors.glass,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.foxOrange.withValues(alpha: 0.6) : AppColors.glassBorder,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          foregroundDecoration: selected ? BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: AppColors.glowOrange, blurRadius: 18, spreadRadius: 3),
              BoxShadow(color: AppColors.foxOrange.withValues(alpha: 0.5), blurRadius: 10),
            ],
          ) : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(
                color: selected ? AppColors.foxOrange : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                fontSize: 13,
              )),
              if (count != null) ...[
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.foxOrange.withValues(alpha: 0.2) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$count首', style: TextStyle(
                    color: selected ? AppColors.foxOrange.withValues(alpha: 0.8) : AppColors.textSecondary.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  )),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _permView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.folder_off_rounded, size: 64, color: Color(0xFF505060)),
    const SizedBox(height: 16),
    const Text('需要存储权限才能扫描音乐', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
    const SizedBox(height: 8),
    const Text('点击下方按钮授权后自动开始扫描', style: TextStyle(color: Color(0xFF505060), fontSize: 12)),
    const SizedBox(height: 24),
    Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.foxOrange, AppColors.purple]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.glowOrange, blurRadius: 20, spreadRadius: 2)],
      ),
      child: ElevatedButton.icon(
        onPressed: _requestPermissionAndScan,
        icon: const Icon(Icons.security_rounded, color: Colors.white),
        label: const Text('授权并扫描', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
      ),
    ),
  ]));

  Widget _loadingView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: AppColors.foxOrange)),
    const SizedBox(height: 20),
    const Text('正在扫描音乐...', style: TextStyle(color: AppColors.textSecondary)),
    if (_scannedCount > 0) ...[const SizedBox(height: 8), Text('已扫描 $_scannedCount 首', style: TextStyle(color: Color(0xFF606070), fontSize: 12))],
    if (_scanningDir.isNotEmpty) Text('正在扫描: $_scanningDir', style: const TextStyle(color: Color(0xFF505060), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
  ]));

  Widget _errorView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 48, color: AppColors.foxOrange),
    const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
    const SizedBox(height: 16),
    Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [AppColors.foxOrange, AppColors.purple])),
      child: ElevatedButton.icon(onPressed: _scanMusic, icon: const Icon(Icons.refresh), label: const Text('重试'), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent)),
    ),
  ]));

  Widget _searchResults() {
    final all = <Song>[..._filteredSongs[MusicCategory.dj] ?? [], ..._filteredSongs[MusicCategory.pop] ?? []];
    if (all.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.search_off_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
      const SizedBox(height: 12),
      Text('没有找到 "${_searchCtrl.text}"', style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5))),
    ]));
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: all.length,
      itemBuilder: (_, i) => SongTile(song: all[i], isPlaying: _isPlaying(all[i]), isFavorite: _store?.isFavorite(all[i].id) ?? false, onTap: () => _playList(all, startIndex: i), onFavorite: () => _toggleFav(all[i]), onLongPress: () => _onSongLongPress(context, all[i])),
    );
  }

  Widget _songList(MusicCategory cat) {
    final songs = _filteredSongs[cat] ?? [];
    if (songs.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(cat == MusicCategory.dj ? Icons.bolt_rounded : Icons.headphones_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
      const SizedBox(height: 12),
      Text(cat == MusicCategory.dj ? '还没有 DJ 歌曲' : '还没有流行歌曲', style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5), fontSize: 16)),
    ]));
    return Column(children: [
      CategoryHeader(category: cat, count: songs.length),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.only(top: 4),
        itemCount: songs.length,
        itemBuilder: (_, i) { final s = songs[i]; return SongTile(song: s, isPlaying: _isPlaying(s), isFavorite: _store?.isFavorite(s.id) ?? false, onTap: () => _playList(songs, startIndex: i), onFavorite: () => _toggleFav(s), onLongPress: () => _onSongLongPress(context, s)); },
      )),
    ]);
  }

  Widget _favList() {
    final favs = _store?.getFavorites() ?? {};
    final djSongs = _allSongs[MusicCategory.dj]?.where((s) => favs.contains(s.id)) ?? [];
    final popSongs = _allSongs[MusicCategory.pop]?.where((s) => favs.contains(s.id)) ?? [];
    final list = <Song>[...djSongs, ...popSongs];
    if (list.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_outline_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
      const SizedBox(height: 12), const Text('还没有收藏歌曲', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
    ]));
    return Column(children: [
      CategoryHeader(category: MusicCategory.dj, count: list.length),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.only(top: 4),
        itemCount: list.length,
        itemBuilder: (_, i) => SongTile(song: list[i], isPlaying: _isPlaying(list[i]), isFavorite: true, onTap: () => _playList(list, startIndex: i), onFavorite: () => _toggleFav(list[i]), onLongPress: () => _onSongLongPress(context, list[i])),
      )),
    ]);
  }

  bool _isPlaying(Song s) { final cs = audioHandler.currentSong; return cs != null && cs.filePath == s.filePath; }
  Future<void> _toggleFav(Song s) async { if (_store == null) return; await _store!.toggleFavorite(s.id); setState(() {}); }
}

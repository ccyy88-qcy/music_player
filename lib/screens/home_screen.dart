import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabCtrl;
  late final AnimationController _headerAnim;
  final TextEditingController _searchCtrl = TextEditingController();
  Map<MusicCategory, List<Song>> _allSongs = {}, _filteredSongs = {};
  bool _loading = true, _showSearch = false;
  String? _error;
  String _scanMode = 'quick';
  StorageManager? _store;
  int _scannedCount = 0, _totalCount = 0;
  String _scanningDir = '';
  StreamSubscription? _songSub;
  bool _permissionDenied = false;

  static const _tabLabels = ['🔥 DJ', '🎵 流行', '⭐ 收藏', '🌐 在线'];
  static const _tabColors = [
    [AppColors.orange, AppColors.red, AppColors.yellow],
    [AppColors.purple, AppColors.pink, AppColors.blue],
    [AppColors.yellow, AppColors.orange, AppColors.pink],
    [AppColors.cyan, AppColors.blue, AppColors.purple],
  ];

  List<Color> get _currentTabColors => _tabColors[_tabCtrl.index];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this)..addListener(() { if (mounted) setState(() {}); });
    _headerAnim = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
    _songSub = audioHandler.player.currentIndexStream.listen((_) { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addObserver(this);
    _initAndScan();
  }

  Future<void> _initAndScan() async {
    _store = await StorageManager.instance;
    _scanMode = _store!.scanMode;
    if (!await MusicScanner.hasPermission()) {
      setState(() { _loading = false; _permissionDenied = true; _error = '需要存储权限'; });
      return;
    }
    _scanMusic();
  }

  Future<void> _scanMusic({bool forceFull = false}) async {
    setState(() { _loading = true; _error = null; _scannedCount = 0; });
    try {
      final songs = await MusicScanner.scanAll(
        forceFullScan: forceFull,
        onProgress: (s, t, d) { if (mounted) setState(() { _scannedCount = s; _totalCount = t; _scanningDir = d.split('/').last; }); },
      );
      if (mounted) setState(() { _allSongs = songs; _filteredSongs = Map.from(songs); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '扫描失败'; });
    }
  }

  void _playList(List<Song> list, {int si = 0}) { if (list.isEmpty) return; audioHandler.loadSongList(list, startIndex: si); }
  void _openPlayer() { if (audioHandler.currentSong == null) return; Navigator.push(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const PlayerScreen(), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c), transitionDuration: const Duration(milliseconds: 300))); }
  Future<void> _openSettings() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); if (mounted) _scanMusic(forceFull: true); }
  int get _favCount => _store?.getFavorites().length ?? 0;

  @override
  void dispose() { _tabCtrl.dispose(); _headerAnim.dispose(); _searchCtrl.dispose(); _songSub?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final total = (_allSongs[MusicCategory.dj]?.length ?? 0) + (_allSongs[MusicCategory.pop]?.length ?? 0);
    return Scaffold(
      body: Column(children: [
        _buildHeader(total),
        _buildTabs(),
        Expanded(child: _buildBody()),
        if (!_showSearch && !_permissionDenied) MiniPlayer(onTap: _openPlayer),
      ]),
    );
  }

  Widget _buildHeader(int total) {
    final colors = _currentTabColors;
    final hasSongs = _tabCtrl.index < 2;
    return AnimatedBuilder(animation: _headerAnim, builder: (_, __) {
      final t = _headerAnim.value;
      final c1 = Color.lerp(colors[0], colors[1], t)!;
      final c2 = Color.lerp(colors[1], colors[2], t)!;
      return Container(
        height: 170,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [c1.withValues(alpha: 0.3), AppColors.bg],
          ),
        ),
        child: Stack(children: [
          // 装饰光晕
          Positioned(right: -30, top: -30,
            child: Container(width: 180, height: 180,
              decoration: BoxDecoration(shape: BoxShape.circle,
                gradient: RadialGradient(colors: [c1.withValues(alpha: 0.15), Colors.transparent]),
              ),
            ),
          ),
          Positioned(left: -20, bottom: -20,
            child: Container(width: 140, height: 140,
              decoration: BoxDecoration(shape: BoxShape.circle,
                gradient: RadialGradient(colors: [c2.withValues(alpha: 0.1), Colors.transparent]),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  // 头像+发光
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [
                        BoxShadow(color: c1.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: 3),
                        BoxShadow(color: c2.withValues(alpha: 0.2), blurRadius: 24, spreadRadius: 6),
                      ],
                    ),
                    child: const Center(child: Text('🦊', style: TextStyle(fontSize: 26))),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('狸音乐', style: TextStyle(color: c1, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    Text('$total 首 · ${_scanMode == 'full' ? '全局' : '快速'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ]),
                  const Spacer(),
                  _iconBtn(Icons.search_rounded, () => setState(() => _showSearch = !_showSearch), c1),
                  const SizedBox(width: 6),
                  _iconBtn(Icons.tune_rounded, _openSettings, c1),
                  const SizedBox(width: 6),
                  _iconBtn(Icons.refresh_rounded, () => _scanMusic(forceFull: true), c1),
                ]),
                if (hasSongs && audioHandler.currentSong != null) _miniLyrics(),
              ]),
            ),
          ),
        ]),
      );
    });
  }

  Widget _miniLyrics() {
    final lyrics = audioHandler.lyrics;
    final idx = audioHandler.lyricIndex;
    if (lyrics.isEmpty || idx < 0) return const SizedBox.shrink();
    final cur = idx < lyrics.length ? lyrics[idx].text : '';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Text(cur, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, Color color) {
    return Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: IconButton(icon: Icon(icon, color: color, size: 19), onPressed: onTap, padding: EdgeInsets.zero),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(children: List.generate(4, (i) {
        final sel = _tabCtrl.index == i;
        final colors = _tabColors[i];
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: i < 3 ? 6 : 0),
          child: GestureDetector(
            onTap: () => _tabCtrl.animateTo(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                gradient: sel ? LinearGradient(colors: [colors[0].withValues(alpha: 0.2), colors[1].withValues(alpha: 0.1)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                color: sel ? null : AppColors.glass,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sel ? colors[0].withValues(alpha: 0.4) : AppColors.glassBorder, width: sel ? 1.5 : 0.5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ShaderMask(
                  shaderCallback: (b) => LinearGradient(colors: sel ? [colors[0], colors[2]] : [AppColors.textSecondary, AppColors.textSecondary]).createShader(b),
                  child: Text(_tabLabels[i], style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                ),
              ]),
            ),
          ),
        ));
      })),
    );
  }

  Widget _buildBody() {
    if (_permissionDenied) return _permView();
    if (_loading) return _loadingView();
    if (_error != null) return _errorView();
    if (_showSearch) return _searchView();
    return TabBarView(controller: _tabCtrl, children: [
      _songList(MusicCategory.dj, AppColors.catDJ),
      _songList(MusicCategory.pop, AppColors.catPop),
      _favList(),
      const OnlineScreen(),
    ]);
  }

  Widget _songList(MusicCategory cat, List<Color> colors) {
    final songs = _filteredSongs[cat] ?? [];
    final isDJ = cat == MusicCategory.dj;
    if (songs.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(isDJ ? Icons.bolt_rounded : Icons.headphones_rounded, size: 56, color: AppColors.textMuted),
      const SizedBox(height: 12),
      Text(isDJ ? '还没有 DJ 歌曲' : '还没有流行歌曲', style: const TextStyle(color: AppColors.textMuted, fontSize: 15)),
    ]));
    return Column(children: [
      _colorfulHeader(isDJ ? '🔥 DJ' : '🎵 流行', songs.length, colors),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.only(top: 4),
        itemCount: songs.length,
        itemBuilder: (_, i) => _colorfulSongTile(songs[i], colors, songs),
      )),
    ]);
  }

  Widget _colorfulHeader(String label, int count, List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: LinearGradient(colors: [colors[0], colors[1]], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Icon(label.contains('DJ') ? Icons.bolt_rounded : Icons.headphones_rounded, color: Colors.white, size: 17),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [colors[0].withValues(alpha: 0.15), colors[2].withValues(alpha: 0.08)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$count 首', style: TextStyle(color: colors[0], fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _colorfulSongTile(Song song, List<Color> colors, List<Song> allSongs) {
    final playing = audioHandler.currentSong?.filePath == song.filePath;
    final fav = _store?.isFavorite(song.id) ?? false;
    final isDJ = song.category == MusicCategory.dj;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: playing ? colors[0].withValues(alpha: 0.06) : AppColors.surfaceCard,
          border: Border.all(color: playing ? colors[0].withValues(alpha: 0.2) : AppColors.glassBorder),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _playList(allSongs, si: allSongs.indexOf(song)),
            onLongPress: () => _onSongLongPress(context, song),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                // 左侧彩色图标
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    gradient: LinearGradient(
                      colors: playing ? [colors[0], colors[1]] : [colors[0].withValues(alpha: 0.6), colors[1].withValues(alpha: 0.4)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    boxShadow: playing ? [BoxShadow(color: colors[0].withValues(alpha: 0.3), blurRadius: 8)] : null,
                  ),
                  child: Center(
                    child: playing
                        ? _playingAnim()
                        : Icon(isDJ ? Icons.bolt_rounded : Icons.music_note_rounded, color: Colors.white.withValues(alpha: 0.9), size: 21),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(song.title,
                    style: TextStyle(color: playing ? colors[0] : AppColors.textPrimary, fontWeight: playing ? FontWeight.w600 : FontWeight.w500, fontSize: 13),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(isDJ ? 'DJ' : '流行', style: TextStyle(color: playing ? colors[0] : AppColors.textMuted, fontSize: 11)),
                    if (song.playCount > 0) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.play_circle_outline, size: 10, color: AppColors.textMuted),
                      const SizedBox(width: 2),
                      Text('${song.playCount}', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    ],
                  ]),
                ])),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (playing)
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: colors[0].withValues(alpha: 0.15)),
                      child: Icon(Icons.volume_up_rounded, color: colors[0], size: 14),
                    ),
                  IconButton(
                    icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: fav ? AppColors.yellow : AppColors.textMuted, size: 20),
                    onPressed: () => _toggleFav(song),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playingAnim() {
    return _PlayingIndicator(colors: _currentTabColors);
  }

  Widget _favList() {
    final favs = _store?.getFavorites() ?? {};
    final list = <Song>[
      ...?_allSongs[MusicCategory.dj]?.where((s) => favs.contains(s.id)),
      ...?_allSongs[MusicCategory.pop]?.where((s) => favs.contains(s.id)),
    ];
    if (list.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_outline_rounded, size: 56, color: AppColors.textMuted),
      const SizedBox(height: 12), const Text('还没有收藏歌曲', style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
    ]));
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: list.length,
      itemBuilder: (_, i) => _colorfulSongTile(list[i], AppColors.catFav, list),
    );
  }

  Widget _searchView() {
    final all = <Song>[...?_filteredSongs[MusicCategory.dj], ...?_filteredSongs[MusicCategory.pop]];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Container(
          height: 44,
          decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder)),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            decoration: const InputDecoration(
              hintText: '🔍 搜索本地歌曲...', hintStyle: TextStyle(color: AppColors.textMuted),
              prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 22),
              border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onChanged: (_) => _applyFilter(),
          ),
        ),
      ),
      Expanded(
        child: all.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.search_off_rounded, size: 48, color: AppColors.textMuted),
                const SizedBox(height: 8),
                Text('没有找到 "${_searchCtrl.text}"', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.only(top: 6),
                itemCount: all.length,
                itemBuilder: (_, i) => _colorfulSongTile(all[i], _currentTabColors, all),
              ),
      ),
    ]);
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) _filteredSongs = Map.from(_allSongs);
      else _filteredSongs = {for (final e in _allSongs.entries) e.key: e.value.where((s) => s.title.toLowerCase().contains(q)).toList()};
    });
  }

  // ── 长按菜单 ──
  void _onSongLongPress(BuildContext ctx, Song s) {
    final isLocal = !s.filePath.startsWith('http');
    showModalBottomSheet(context: ctx, backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
        ListTile(leading: const Icon(Icons.info_outline_rounded, color: AppColors.orange), title: const Text('🎵 歌曲详情', style: TextStyle(color: AppColors.textPrimary)),
          onTap: () { Navigator.pop(c); _showDetails(s); }),
        ListTile(leading: const Icon(Icons.lyrics_rounded, color: AppColors.purple), title: const Text('📄 下载歌词', style: TextStyle(color: AppColors.textPrimary)),
          subtitle: const Text('保存.lrc文件到歌曲目录', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          onTap: () { Navigator.pop(c); _downloadLyrics(s); }),
        if (isLocal) ListTile(leading: const Icon(Icons.delete_outline_rounded, color: AppColors.red), title: const Text('🗑️ 删除歌曲', style: TextStyle(color: AppColors.red)),
          onTap: () { Navigator.pop(c); _deleteSong(s); }),
      ]))),
    );
  }

  void _showDetails(Song s) {
    final isLocal = !s.filePath.startsWith('http');
    String sizeStr = '';
    if (isLocal) { try { final f = File(s.filePath); if (f.existsSync()) sizeStr = '${(f.lengthSync() / 1024 / 1024).toStringAsFixed(1)}MB'; } catch (_) {} }
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: AppColors.catPop)), child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 22)),
        const SizedBox(width: 10), Expanded(child: Text(s.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _dr('歌手', s.artist.isNotEmpty ? s.artist : '未知'), _dr('分类', s.category == MusicCategory.dj ? '🔥 DJ' : '🎵 流行'),
        _dr('播放次数', '${s.playCount} 次'), if (sizeStr.isNotEmpty) _dr('文件大小', sizeStr),
        if (s.lastPlayed > 0) _dr('上次播放', DateTime.fromMillisecondsSinceEpoch(s.lastPlayed).toString().substring(0, 19)),
        if (isLocal) ...[const SizedBox(height: 6), Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.glass, borderRadius: BorderRadius.circular(8)), child: Text(s.filePath, style: TextStyle(color: AppColors.textMuted, fontSize: 10), maxLines: 3, overflow: TextOverflow.ellipsis))],
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭', style: TextStyle(color: AppColors.orange)))],
    ));
  }

  Widget _dr(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
    Text('$l：', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)), Expanded(child: Text(v, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
  ]));

  Future<void> _downloadLyrics(Song s) async {
    try {
      final lrc = await LyricParser.searchOnline(s.title, s.artist);
      if (lrc.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到歌词'), backgroundColor: AppColors.yellow)); return; }
      final lrcPath = s.filePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc');
      await File(lrcPath).writeAsString(lrc.map((l) {
        final min = l.time.inMinutes.remainder(60).toString().padLeft(2, '0');
        final sec = l.time.inSeconds.remainder(60).toString().padLeft(2, '0');
        return '[$min:$sec.${(l.time.inMilliseconds % 1000).toString().padLeft(3, '0')}]${l.text}';
      }).join('\n'));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ 歌词已下载'), backgroundColor: AppColors.green));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e'), backgroundColor: AppColors.red)); }
  }

  Future<void> _deleteSong(Song s) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: AppColors.surface,
      title: const Text('确认删除', style: TextStyle(color: AppColors.textPrimary)),
      content: Text('确定删除「${s.title}」？', style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消', style: TextStyle(color: AppColors.textSecondary))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除', style: TextStyle(color: AppColors.red))),
      ],
    ));
    if (ok != true) return;
    try {
      bool deleted = false;
      try { deleted = await const MethodChannel('com.alee.music_player/service').invokeMethod<bool>('deleteFile', {'path': s.filePath}) ?? false; } catch (_) {}
      if (!deleted) { final f = File(s.filePath); if (await f.exists()) await f.delete(); }
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ 已删除'), backgroundColor: AppColors.green)); _scanMusic(forceFull: true); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 删除失败'), backgroundColor: AppColors.red)); }
  }

  bool _isPlaying(Song s) { final c = audioHandler.currentSong; return c != null && c.filePath == s.filePath; }
  Future<void> _toggleFav(Song s) async { if (_store == null) return; await _store!.toggleFavorite(s.id); setState(() {}); }

  Widget _permView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.folder_off_rounded, size: 56, color: AppColors.textMuted),
    const SizedBox(height: 16), const Text('需要存储权限', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
    const SizedBox(height: 24),
    Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: AppColors.catDJ), borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.3), blurRadius: 20)]),
      child: ElevatedButton.icon(onPressed: _initAndScan, icon: const Icon(Icons.security_rounded, color: Colors.white), label: const Text('授权并扫描', style: TextStyle(color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14))),
    ),
  ]));

  Widget _loadingView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: AppColors.orange)),
    const SizedBox(height: 20), const Text('正在扫描...', style: TextStyle(color: AppColors.textSecondary)),
    if (_scannedCount > 0) ...[const SizedBox(height: 6), Text('已扫描 $_scannedCount 首', style: TextStyle(color: AppColors.textMuted, fontSize: 12))],
    if (_scanningDir.isNotEmpty) Text('正在扫描: $_scanningDir', style: const TextStyle(color: AppColors.textMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
  ]));

  Widget _errorView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 48, color: AppColors.orange), const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: AppColors.textSecondary)), const SizedBox(height: 16),
    Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: AppColors.catDJ)),
      child: ElevatedButton.icon(onPressed: _scanMusic, icon: const Icon(Icons.refresh), label: const Text('重试'), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent)),
    ),
  ]));
}

class _PlayingIndicator extends StatefulWidget {
  final List<Color> colors;
  const _PlayingIndicator({required this.colors});
  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(); }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(
      size: const Size(22, 22),
      painter: _EqPainer(_c.value, widget.colors),
    ));
  }
}

class _EqPainer extends CustomPainter {
  final double t; final List<Color> colors;
  _EqPainer(this.t, this.colors);
  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 4; i++) {
      final h = 6 + 12 * (0.5 + 0.5 * math.sin(t * math.pi * 2 + i * 1.5));
      final paint = Paint()
        ..color = Color.lerp(colors[0], colors[1], i / 3)!
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(4 + i * 5.0, 20 - h), Offset(4 + i * 5.0, 20), paint);
    }
  }
  @override
  bool shouldRepaint(covariant _EqPainer o) => o.t != t;
}

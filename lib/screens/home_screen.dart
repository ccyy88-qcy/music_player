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
import '../services/chart_service.dart';
import '../services/online_music_service.dart';
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

  // 图表数据
  List<ChartSong> _hotSongs = [];
  bool _chartLoading = true;

  // 最近播放
  List<Song> _recentSongs = [];

  static const _tabLabels = ['🔥 DJ', '🎵 流行', '⭐ 收藏', '🌐 在线'];
  static const _tabColors = [
    AppColors.catDJ, AppColors.catPop,
    AppColors.catFav, AppColors.catOnline,
  ];

  List<Color> get _curColors => _tabColors[_tabCtrl.index];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this)..addListener(() { if (mounted) setState(() {}); });
    _headerAnim = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
    _songSub = audioHandler.player.currentIndexStream.listen((_) { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addObserver(this);
    _init();
    _loadChart();
    // 监听最近播放
    audioHandler.player.currentIndexStream.listen((_) {
      if (mounted) setState(() { _recentSongs = _store?.getRecentSongs() ?? []; });
    });
  }

  Future<void> _init() async {
    _store = await StorageManager.instance;
    _recentSongs = _store?.getRecentSongs() ?? [];
    _scanMode = _store!.scanMode;

    // 先加载缓存显示数据，避免白屏
    final cached = _store!.loadSongCache();
    if (cached.isNotEmpty) {
      final byCat = <MusicCategory, List<Song>>{};
      for (final s in cached.values) {
        byCat.putIfAbsent(s.category, () => []).add(s);
      }
      if (mounted) setState(() { _allSongs = byCat; _filteredSongs = Map.from(byCat); _loading = false; });
    }

    if (!await MusicScanner.hasPermission()) {
      // 自动弹出授权
      final granted = await MusicScanner.requestPermission();
      if (!granted) {
        if (mounted) setState(() { _loading = false; _permissionDenied = true; });
        return;
      }
    }
    _scanMusic();
  }

  Future<void> _loadChart() async {
    try {
      final songs = await NeteaseChart.getChart('3779629'); // 热歌榜
      if (mounted) setState(() { _hotSongs = songs.take(15).toList(); _chartLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _chartLoading = false);
    }
  }

  Future<void> _scanMusic({bool forceFull = false}) async {
    setState(() { _loading = true; _error = null; });
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

  void _playLocal(List<Song> list, {int si = 0}) { if (list.isEmpty) return; audioHandler.loadSongList(list, startIndex: si); }

  void _playChart(ChartSong s, int idx) async {
    // 用QQ源搜并播
    final qq = QQSource();
    final playUrl = await qq.getPlayUrl(OnlineSong(
      id: s.id, title: s.title, artist: s.artist, source: s.source, duration: s.duration, fee: s.fee,
    ));
    if (playUrl != null) {
      final tempSong = Song(title: s.title, artist: s.artist, filePath: playUrl, category: MusicCategory.pop);
      audioHandler.loadSongList([tempSong], startIndex: 0);
      Navigator.push(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const PlayerScreen(),
          transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c), transitionDuration: const Duration(milliseconds: 300)));
    }
  }

  Widget _defaultChartCover(ChartSong s) {
    return Container(
      width: 120, height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: s.rank <= 3
              ? [AppColors.orange, AppColors.red, AppColors.yellow]
              : [AppColors.surfaceLight, AppColors.surfaceCard],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(Icons.music_note_rounded,
        color: Colors.white.withValues(alpha: s.rank <= 3 ? 0.4 : 0.15), size: 44)),
    );
  }

  void _openPlayer() {
    if (audioHandler.currentSong == null) return;
    Navigator.push(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const PlayerScreen(),
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c), transitionDuration: const Duration(milliseconds: 300)));
  }

  Future<void> _openSettings() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); if (mounted) _scanMusic(forceFull: true); }
  int get _favCount => _store?.getFavorites().length ?? 0;

  @override
  void dispose() { _tabCtrl.dispose(); _headerAnim.dispose(); _searchCtrl.dispose(); _songSub?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final total = (_allSongs[MusicCategory.dj]?.length ?? 0) + (_allSongs[MusicCategory.pop]?.length ?? 0);
    return Scaffold(
      body: Column(children: [
        _header(total),
        if (!_showSearch) _tabs(),
        Expanded(child: _body()),
        if (!_showSearch && !_permissionDenied) MiniPlayer(onTap: _openPlayer),
      ]),
    );
  }

  Widget _header(int total) {
    final colors = _curColors;
    return AnimatedBuilder(animation: _headerAnim, builder: (_, __) {
      final t = _headerAnim.value;
      final c1 = Color.lerp(colors[0], colors[1], t)!;
      final c2 = Color.lerp(colors[1], colors[2], t)!;
      return Container(
        height: _showSearch ? 60 : 150,
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [c1.withValues(alpha: 0.2), AppColors.bg],
        )),
        child: Stack(children: [
          Positioned(right: -30, top: -30, child: Container(width: 160, height: 160,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c1.withValues(alpha: 0.12), Colors.transparent])),
          )),
          SafeArea(child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 46, height: 46,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: c1.withValues(alpha: 0.3), blurRadius: 14, spreadRadius: 2)],
                  ),
                  child: const Center(child: Text('🦊', style: TextStyle(fontSize: 24))),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ShaderMask(shaderCallback: (b) => LinearGradient(colors: [c1, c2]).createShader(b),
                    child: const Text('狸音乐', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5))),
                  Text('$total 首 · ${_scanMode == 'full' ? '全局' : '快速'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
                const Spacer(),
                _ibtn(Icons.search_rounded, () => setState(() => _showSearch = !_showSearch), c1),
                const SizedBox(width: 6),
                _ibtn(Icons.tune_rounded, _openSettings, c1),
                const SizedBox(width: 6),
                _ibtn(Icons.refresh_rounded, () => _scanMusic(forceFull: true), c1),
              ]),
            ]),
          )),
        ]),
      );
    });
  }

  Widget _ibtn(IconData ic, VoidCallback onTap, Color c) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.2))),
    child: IconButton(icon: Icon(ic, color: c, size: 18), onPressed: onTap, padding: EdgeInsets.zero),
  );

  Widget _tabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Row(children: List.generate(4, (i) {
        final sel = _tabCtrl.index == i;
        final cs = _tabColors[i];
        return Expanded(child: Padding(padding: EdgeInsets.only(right: i < 3 ? 6 : 0), child: GestureDetector(
          onTap: () => _tabCtrl.animateTo(i),
          child: AnimatedContainer(duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: sel ? LinearGradient(colors: [cs[0].withValues(alpha: 0.15), cs[1].withValues(alpha: 0.08)]) : null,
              color: sel ? null : AppColors.glass,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sel ? cs[0].withValues(alpha: 0.35) : AppColors.glassBorder, width: sel ? 1.5 : 0.5),
            ),
            child: ShaderMask(
              shaderCallback: (b) => LinearGradient(colors: sel ? [cs[0], cs[2]] : [AppColors.textSecondary, AppColors.textSecondary]).createShader(b),
              child: Text(_tabLabels[i], style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
            ),
          ),
        )));
      })),
    );
  }

  Widget _body() {
    if (_permissionDenied) return _permView();
    if (_loading) return _loadingView();
    if (_error != null) return _errorView();
    if (_showSearch) return _searchView();
    return TabBarView(controller: _tabCtrl, children: [
      _localList(MusicCategory.dj, AppColors.catDJ),
      _localList(MusicCategory.pop, AppColors.catPop),
      _favView(),
      Column(children: [
        _hotSection(),
        Expanded(child: const OnlineScreen()),
      ]),
    ]);
  }

  // ── 热门推荐（榜单） ──
  Widget _hotSection() {
    if (_chartLoading || _hotSongs.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.orange, AppColors.red]), borderRadius: BorderRadius.circular(6)),
            child: const Text('HOT', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          const Text('热门推荐', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(onTap: () => _tabCtrl.animateTo(3),
            child: Text('更多 >', style: TextStyle(color: AppColors.orange.withValues(alpha: 0.7), fontSize: 12))),
        ]),
      ),
      SizedBox(
        height: 230,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: _hotSongs.length > 10 ? 10 : _hotSongs.length,
          itemBuilder: (_, i) {
            final s = _hotSongs[i];
            return GestureDetector(
              onTap: () => _playChart(s, i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  // 排名
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: s.rank <= 3
                          ? (s.rank == 1 ? AppColors.yellow : (s.rank == 2 ? AppColors.orange : AppColors.red))
                          : Colors.transparent,
                    ),
                    child: Center(child: Text('${s.rank}',
                      style: TextStyle(
                        color: s.rank <= 3 ? Colors.black : AppColors.textMuted,
                        fontSize: 11, fontWeight: FontWeight.w700),
                    )),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(s.artist, style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ── 最近播放 ──
  Widget _recentSection() {
    if (_recentSongs.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(children: [
          const Icon(Icons.history_rounded, color: AppColors.textMuted, size: 16),
          const SizedBox(width: 6),
          const Text('最近播放', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(onTap: () => _store?.clearRecent(),
            child: Text('清空', style: TextStyle(color: AppColors.textMuted, fontSize: 11))),
        ]),
      ),
      SizedBox(
        height: 110,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: _recentSongs.length,
          itemBuilder: (_, i) {
            final s = _recentSongs[i];
            final isDJ = s.category == MusicCategory.dj;
            return GestureDetector(
              onTap: () {
                audioHandler.loadSongList(_recentSongs, startIndex: i);
                _openPlayer();
              },
              child: Container(
                width: 100,
                margin: const EdgeInsets.only(right: 10),
                child: Column(children: [
                  Container(
                    width: 100, height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(colors: isDJ ? AppColors.catDJ : AppColors.catPop),
                    ),
                    child: Center(child: Text('🦊', style: TextStyle(fontSize: 30))),
                  ),
                  const SizedBox(height: 4),
                  Text(s.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ── 本地列表 ──
  Widget _localList(MusicCategory cat, List<Color> colors) {
    final songs = _filteredSongs[cat] ?? [];
    final isDJ = cat == MusicCategory.dj;
    if (songs.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(isDJ ? Icons.bolt_rounded : Icons.headphones_rounded, size: 48, color: AppColors.textMuted),
      const SizedBox(height: 10), Text(isDJ ? '还没有 DJ 歌曲' : '还没有流行歌曲', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
    ]));
    return ListView(children: [
      _recentSection(),
      _secHeader(isDJ ? '🔥 DJ' : '🎵 流行', songs.length, colors),
      ...songs.map((s) => _songTile(s, colors, songs)),
    ]);
  }

  Widget _secHeader(String label, int count, List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(7),
            gradient: LinearGradient(colors: [colors[0], colors[1]], begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: Icon(label.contains('DJ') ? Icons.bolt_rounded : Icons.headphones_rounded, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: colors[0].withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
          child: Text('$count 首', style: TextStyle(color: colors[0], fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _songTile(Song song, List<Color> colors, List<Song> all) {
    final playing = audioHandler.currentSong?.filePath == song.filePath;
    final fav = _store?.isFavorite(song.id) ?? false;
    final isDJ = song.category == MusicCategory.dj;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: playing ? colors[0].withValues(alpha: 0.05) : AppColors.surfaceCard,
          border: Border.all(color: playing ? colors[0].withValues(alpha: 0.15) : AppColors.glassBorder),
        ),
        child: Material(color: Colors.transparent, child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _playLocal(all, si: all.indexOf(song)),
          onLongPress: () => _onSongLongPress(song),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Container(width: 42, height: 42,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(9),
                  gradient: LinearGradient(colors: playing ? [colors[0], colors[1]] : [colors[0].withValues(alpha: 0.5), colors[1].withValues(alpha: 0.3)]),
                  boxShadow: playing ? [BoxShadow(color: colors[0].withValues(alpha: 0.2), blurRadius: 6)] : null,
                ),
                child: Center(child: playing ? _playAnim() : Icon(isDJ ? Icons.bolt_rounded : Icons.music_note_rounded, color: Colors.white.withValues(alpha: 0.85), size: 20)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(song.title, style: TextStyle(color: playing ? colors[0] : AppColors.textPrimary, fontWeight: playing ? FontWeight.w600 : FontWeight.w500, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(children: [
                  Text(isDJ ? 'DJ' : '流行', style: TextStyle(color: playing ? colors[0] : AppColors.textMuted, fontSize: 11)),
                  if (song.playCount > 0) ...[const SizedBox(width: 6), Icon(Icons.play_circle_outline, size: 9, color: AppColors.textMuted), Text('${song.playCount}', style: TextStyle(fontSize: 9, color: AppColors.textMuted))],
                ]),
              ])),
              if (playing) Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: colors[0].withValues(alpha: 0.12)), child: Icon(Icons.volume_up_rounded, color: colors[0], size: 13)),
              IconButton(icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded, color: fav ? AppColors.yellow : AppColors.textMuted, size: 19), onPressed: () => _toggleFav(song), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 34)),
            ]),
          ),
        )),
      ),
    );
  }

  Widget _playAnim() => _PlayingIndicator(colors: _curColors);

  Widget _favView() {
    final favs = _store?.getFavorites() ?? {};
    final list = <Song>[...?_allSongs[MusicCategory.dj]?.where((s) => favs.contains(s.id)), ...?_allSongs[MusicCategory.pop]?.where((s) => favs.contains(s.id))];
    if (list.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_outline_rounded, size: 48, color: AppColors.textMuted), const SizedBox(height: 10), const Text('还没有收藏歌曲', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
    ]));
    return ListView.builder(padding: const EdgeInsets.only(top: 4), itemCount: list.length, itemBuilder: (_, i) => _songTile(list[i], AppColors.catFav, list));
  }

  Widget _searchView() {
    final all = <Song>[...?_filteredSongs[MusicCategory.dj], ...?_filteredSongs[MusicCategory.pop]];
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: Container(
        height: 42,
        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.glassBorder)),
        child: TextField(controller: _searchCtrl, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: const InputDecoration(hintText: '🔍 搜索本地歌曲...', hintStyle: TextStyle(color: AppColors.textMuted), prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
          onChanged: (_) => _applyFilter()),
      )),
      Expanded(child: all.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.search_off_rounded, size: 44, color: AppColors.textMuted), const SizedBox(height: 8), Text('没有找到 "${_searchCtrl.text}"', style: TextStyle(color: AppColors.textMuted, fontSize: 13))]))
        : ListView.builder(padding: const EdgeInsets.only(top: 4), itemCount: all.length, itemBuilder: (_, i) => _songTile(all[i], _curColors, all))),
    ]);
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() { _filteredSongs = q.isEmpty ? Map.from(_allSongs) : {for (final e in _allSongs.entries) e.key: e.value.where((s) => s.title.toLowerCase().contains(q)).toList()}; });
  }

  // ── 长按菜单 ──
  void _onSongLongPress(Song s) {
    final isLocal = !s.filePath.startsWith('http');
    showModalBottomSheet(context: context, backgroundColor: AppColors.surface, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
        ListTile(leading: const Icon(Icons.info_outline_rounded, color: AppColors.orange), title: const Text('🎵 歌曲详情', style: TextStyle(color: AppColors.textPrimary)), onTap: () { Navigator.pop(c); _showDetails(s); }),
        ListTile(leading: const Icon(Icons.lyrics_rounded, color: AppColors.purple), title: const Text('📄 下载歌词', style: TextStyle(color: AppColors.textPrimary)), subtitle: const Text('保存.lrc文件', style: TextStyle(color: AppColors.textMuted, fontSize: 11)), onTap: () { Navigator.pop(c); _dlLyrics(s); }),
        if (isLocal) ListTile(leading: const Icon(Icons.delete_outline_rounded, color: AppColors.red), title: const Text('🗑️ 删除歌曲', style: TextStyle(color: AppColors.red)), onTap: () { Navigator.pop(c); _delSong(s); }),
      ]))),
    );
  }

  void _showDetails(Song s) {
    String sz = '';
    if (!s.filePath.startsWith('http')) { try { final f = File(s.filePath); if (f.existsSync()) sz = '${(f.lengthSync() / 1024 / 1024).toStringAsFixed(1)}MB'; } catch (_) {} }
    showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), gradient: const LinearGradient(colors: AppColors.catPop)), child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 20)), const SizedBox(width: 10), Expanded(child: Text(s.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 2))]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _dr('歌手', s.artist.isNotEmpty ? s.artist : '未知'), _dr('分类', s.category == MusicCategory.dj ? 'DJ' : '流行'), _dr('播放次数', '${s.playCount}'),
        if (sz.isNotEmpty) _dr('大小', sz), if (s.lastPlayed > 0) _dr('上次播放', DateTime.fromMillisecondsSinceEpoch(s.lastPlayed).toString().substring(0, 19)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭', style: TextStyle(color: AppColors.orange)))],
    ));
  }

  Widget _dr(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [Text('$l：', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)), Expanded(child: Text(v, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)))]));

  Future<void> _dlLyrics(Song s) async {
    try {
      final lrc = await LyricParser.searchOnline(s.title, s.artist);
      if (lrc.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到歌词'), backgroundColor: AppColors.yellow)); return; }
      final p = s.filePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc');
      await File(p).writeAsString(lrc.map((l) => '[${l.time.inMinutes.remainder(60).toString().padLeft(2, '0')}:${l.time.inSeconds.remainder(60).toString().padLeft(2, '0')}.${(l.time.inMilliseconds % 1000).toString().padLeft(3, '0')}]${l.text}').join('\n'));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 歌词已下载'), backgroundColor: AppColors.green));
    } catch (_) {}
  }

  Future<void> _delSong(Song s) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: AppColors.surface, title: const Text('确认删除', style: TextStyle(color: AppColors.textPrimary)), content: Text('确定删除「${s.title}」？', style: const TextStyle(color: AppColors.textSecondary)),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消', style: TextStyle(color: AppColors.textSecondary))), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除', style: TextStyle(color: AppColors.red)))]));
    if (ok != true) return;
    try { await File(s.filePath).delete(); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已删除'), backgroundColor: AppColors.green)); _scanMusic(forceFull: true); } } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ 删除失败'), backgroundColor: AppColors.red)); }
  }

  Future<void> _toggleFav(Song s) async { if (_store == null) return; await _store!.toggleFavorite(s.id); setState(() {}); }

  Widget _permView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.folder_off_rounded, size: 52, color: AppColors.textMuted), const SizedBox(height: 14), const Text('需要存储权限', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)), const SizedBox(height: 20),
    Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: AppColors.catDJ), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.25), blurRadius: 16)]),
      child: ElevatedButton.icon(onPressed: _init, icon: const Icon(Icons.security_rounded, color: Colors.white), label: const Text('授权并扫描', style: TextStyle(color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12))),
    ),
  ]));

  Widget _loadingView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: AppColors.orange)), const SizedBox(height: 16), const Text('正在扫描...', style: TextStyle(color: AppColors.textSecondary)),
    if (_scannedCount > 0) ...[const SizedBox(height: 6), Text('已扫描 $_scannedCount 首', style: TextStyle(color: AppColors.textMuted, fontSize: 12))],
    if (_scanningDir.isNotEmpty) Text('$_scanningDir', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
  ]));

  Widget _errorView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 40, color: AppColors.orange), const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: AppColors.textSecondary)), const SizedBox(height: 14),
    Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const LinearGradient(colors: AppColors.catDJ)),
      child: ElevatedButton.icon(onPressed: _scanMusic, icon: const Icon(Icons.refresh, size: 18), label: const Text('重试', style: TextStyle(fontSize: 13)), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent)),
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
    return AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(size: const Size(20, 20), painter: _EqP(_c.value, widget.colors)));
  }
}

class _EqP extends CustomPainter {
  final double t; final List<Color> cs;
  _EqP(this.t, this.cs);
  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 4; i++) {
      final h = 6 + 12 * (0.5 + 0.5 * math.sin(t * math.pi * 2 + i * 1.5));
      canvas.drawLine(Offset(3 + i * 5.0, 20 - h), Offset(3 + i * 5.0, 20), Paint()..color = Color.lerp(cs[0], cs[1], i / 3)!..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    }
  }
  @override
  bool shouldRepaint(covariant _EqP o) => o.t != t;
}

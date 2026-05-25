import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/music_scanner.dart';
import '../services/storage_manager.dart';
import '../services/audio_handler.dart';
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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  Map<MusicCategory, List<Song>> _allSongs = {};
  Map<MusicCategory, List<Song>> _filteredSongs = {};
  bool _loading = true;
  String? _error;
  bool _showSearch = false;
  String _scanMode = 'quick';
  StorageManager? _store;

  // 扫描进度
  int _scannedCount = 0;
  int _totalCount = 0;
  String _scanningDir = '';
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
  void _openPlayer() { if (audioHandler.currentSong == null) return; Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen())).then((_) => mounted ? setState(() {}) : null); }
  Future<void> _openSettings() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); if (mounted) _scanMusic(forceFull: true); }
  int _countFav() => _store?.getFavorites().length ?? 0;

  @override
  void dispose() { _tabController.dispose(); _searchCtrl.dispose(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final total = (_allSongs[MusicCategory.dj]?.length ?? 0) + (_allSongs[MusicCategory.pop]?.length ?? 0);
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Column(children: [
        // 阿狸主题头图
        _foxHeader(total),
        // 标签栏
        if (!_showSearch) _tabBar(),
        // 内容区
        Expanded(child: _permissionDenied ? _permView() : _loading ? _loadingView() : _error != null ? _errorView() : _showSearch ? _searchResults() : TabBarView(controller: _tabController, children: [
          _songList(MusicCategory.dj),
          _songList(MusicCategory.pop),
          _favList(),
          const OnlineScreen(),
        ])),
        if (!_showSearch && !_permissionDenied) MiniPlayer(onTap: _openPlayer),
      ]),
    );
  }

  Widget _foxHeader(int total) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1A0A2E), Color(0xFF0D0D1A)],
        ),
      ),
      child: Stack(
        children: [
          // 背景阿狸图（模糊装饰）
          Positioned(
            right: -40, top: -30,
            child: Transform.rotate(
              angle: 0.1,
              child: Container(
                width: 200, height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  image: const DecorationImage(
                    image: AssetImage('assets/images/ali.jpg'),
                    fit: BoxFit.cover,
                    opacity: 0.25,
                  ),
                  boxShadow: [BoxShadow(color: AppColors.glowOrange.withValues(alpha: 0.15), blurRadius: 30, spreadRadius: 10)],
                ),
              ),
            ),
          ),
          // 右下小阿狸装饰
          Positioned(
            bottom: -5, right: 20,
            child: Container(
              width: 60, height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                image: const DecorationImage(
                  image: AssetImage('assets/images/ali.jpg'),
                  fit: BoxFit.cover,
                  opacity: 0.15,
                ),
              ),
            ),
          ),
          // 内容
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    // 阿狸头像圆
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.foxOrange.withValues(alpha: 0.6), width: 2),
                        boxShadow: [BoxShadow(color: AppColors.glowOrange, blurRadius: 12)],
                        image: const DecorationImage(image: AssetImage('assets/images/ali.jpg'), fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Text('🦊 狸音乐', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        SizedBox(width: 8),
                        Text('v2', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                      ]),
                      Text('$total 首 · ${_scanMode == 'full' ? '全局扫描' : '快速扫描'}',
                        style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.7), fontSize: 12)),
                    ]),
                    const Spacer(),
                    // 操作按钮
                    _headerBtn(Icons.search_rounded, () => setState(() => _showSearch = true)),
                    _headerBtn(Icons.settings_rounded, _openSettings),
                    _headerBtn(Icons.refresh_rounded, () => _scanMusic(forceFull: true)),
                  ]),
                ],
              ),
            ),
          ),
          // 底部光晕
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 2,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, AppColors.foxOrange, AppColors.purple, Colors.transparent],
                ),
              ),
            ),
          ),
        ],
      ),
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
      child: IconButton(
        icon: Icon(icon, color: AppColors.textSecondary, size: 18),
        onPressed: onTap,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _tabBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        _tabItem('🔥 DJ', 0, _filteredSongs[MusicCategory.dj]?.length ?? 0),
        _tabItem('🎵 流行', 1, _filteredSongs[MusicCategory.pop]?.length ?? 0),
        _tabItem('⭐ 收藏', 2, _countFav()),
        _tabItem('🌐 在线', 3, null),
        const Spacer(),
      ]),
    );
  }

  Widget _tabItem(String label, int index, int? count) {
    final selected = _tabController.index == index;
    return GestureDetector(
      onTap: () => _tabController.animateTo(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.foxOrange.withValues(alpha: 0.15) : AppColors.glass,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.foxOrange.withValues(alpha: 0.4) : AppColors.glassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(
            color: selected ? AppColors.foxOrange : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          )),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text('$count', style: TextStyle(
              color: selected ? AppColors.foxOrange.withValues(alpha: 0.6) : AppColors.textSecondary.withValues(alpha: 0.5),
              fontSize: 11,
            )),
          ],
        ]),
      ),
    );
  }

  Widget _permView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.folder_off_rounded, size: 64, color: Color(0xFF505060)),
    const SizedBox(height: 16),
    const Text('需要存储权限才能扫描音乐', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
    const SizedBox(height: 8),
    const Text('点击下方按钮授权后自动开始扫描', style: TextStyle(color: Color(0xFF505060), fontSize: 12)),
    const SizedBox(height: 20),
    Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.foxOrange, AppColors.purple]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.glowOrange, blurRadius: 12)],
      ),
      child: ElevatedButton.icon(
        onPressed: _requestPermissionAndScan,
        icon: const Icon(Icons.security_rounded, color: Colors.white),
        label: const Text('授权并扫描', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
    ),
  ]));

  Widget _loadingView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: AppColors.foxOrange)),
    const SizedBox(height: 16),
    const Text('正在扫描音乐...', style: TextStyle(color: AppColors.textSecondary)),
    if (_scannedCount > 0) ...[const SizedBox(height: 8), Text('已扫描 $_scannedCount 首', style: TextStyle(color: Color(0xFF606070), fontSize: 12))],
    if (_scanningDir.isNotEmpty) Text('正在扫描: $_scanningDir', style: const TextStyle(color: Color(0xFF505060), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
  ]));

  Widget _errorView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 48, color: AppColors.foxOrange),
    const SizedBox(height: 12),
    Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
    const SizedBox(height: 12),
    ElevatedButton.icon(onPressed: _scanMusic, icon: const Icon(Icons.refresh), label: const Text('重试')),
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
      itemBuilder: (_, i) => SongTile(song: all[i], isPlaying: _isPlaying(all[i]), isFavorite: _store?.isFavorite(all[i].id) ?? false, onTap: () => _playList(all, startIndex: i), onFavorite: () => _toggleFav(all[i])),
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
        itemBuilder: (_, i) { final s = songs[i]; return SongTile(song: s, isPlaying: _isPlaying(s), isFavorite: _store?.isFavorite(s.id) ?? false, onTap: () => _playList(songs, startIndex: i), onFavorite: () => _toggleFav(s)); },
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
      const SizedBox(height: 12),
      const Text('还没有收藏歌曲', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
    ]));
    return Column(children: [
      CategoryHeader(category: MusicCategory.dj, count: list.length),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.only(top: 4),
        itemCount: list.length,
        itemBuilder: (_, i) => SongTile(song: list[i], isPlaying: _isPlaying(list[i]), isFavorite: true, onTap: () => _playList(list, startIndex: i), onFavorite: () => _toggleFav(list[i]))),
      ),
    ]);
  }

  bool _isPlaying(Song s) { final cs = audioHandler.currentSong; return cs != null && cs.filePath == s.filePath; }
  Future<void> _toggleFav(Song s) async { if (_store == null) return; await _store!.toggleFavorite(s.id); setState(() {}); }
}

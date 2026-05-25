import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/music_scanner.dart';
import '../services/storage_manager.dart';
import '../services/audio_handler.dart';
import '../widgets/music_widgets.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'online_screen.dart';
import '../main.dart' show audioHandler;

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
    // 检查权限
    final has = await MusicScanner.hasPermission();
    if (!has) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
        _error = '需要存储权限才能扫描本地音乐';
      });
      return;
    }
    _scanMusic();
  }

  Future<void> _requestPermissionAndScan() async {
    final granted = await MusicScanner.requestPermission();
    if (!granted) {
      // 用户拒绝了，引导去系统设置
      if (mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: const Text('需要存储权限', style: TextStyle(color: Colors.white)),
            content: const Text('扫描本地音乐需要存储权限。\n请在系统设置中手动开启。', style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: Colors.white54))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('去设置', style: TextStyle(color: Colors.pinkAccent))),
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
    setState(() {
      _loading = true; _error = null;
      _scannedCount = 0; _totalCount = 0; _scanningDir = '';
    });
    try {
      final songs = await MusicScanner.scanAll(
        forceFullScan: forceFull,
        onProgress: (scanned, total, dir) {
          if (mounted) setState(() {
            _scannedCount = scanned;
            _totalCount = total;
            _scanningDir = dir.split('/').last;
          });
        },
      );
      if (mounted) setState(() {
        _allSongs = songs;
        _filteredSongs = Map.from(songs);
        _loading = false;
      });
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
    return Scaffold(body: Column(children: [
      Container(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 8, left: 16, right: 16),
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)])),
        child: _showSearch ? _searchBar() : _titleBar(total),
      ),
      if (!_showSearch) Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)])),
        child: TabBar(controller: _tabController, indicatorColor: Colors.pinkAccent, indicatorWeight: 3, labelColor: Colors.white, unselectedLabelColor: Colors.white38, labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), tabs: [
          Tab(text: '🔥 DJ (${_filteredSongs[MusicCategory.dj]?.length ?? 0})'),
          Tab(text: '🎵 流行 (${_filteredSongs[MusicCategory.pop]?.length ?? 0})'),
          Tab(text: '⭐ 收藏 (${_countFav()})'),
          const Tab(text: '🌐 在线'),
        ]),
      ),
      Expanded(child: _permissionDenied ? _permView() : _loading ? _loadingView() : _error != null ? _errorView() : _showSearch ? _searchResults() : TabBarView(controller: _tabController, children: [_songList(MusicCategory.dj), _songList(MusicCategory.pop), _favList(), OnlineScreen()])),
      if (!_showSearch && !_permissionDenied) MiniPlayer(onTap: _openPlayer),
    ]));
  }

  Widget _permView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.folder_off_rounded, size: 64, color: Colors.grey), const SizedBox(height: 16),
    const Text('需要存储权限才能扫描音乐', style: TextStyle(color: Colors.grey, fontSize: 16)), const SizedBox(height: 8),
    const Text('点击下方按钮授权后自动开始扫描', style: TextStyle(color: Colors.white38, fontSize: 12)), const SizedBox(height: 20),
    ElevatedButton.icon(onPressed: _requestPermissionAndScan, icon: const Icon(Icons.security_rounded), label: const Text('授权并扫描'), style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent)),
  ]));

  Widget _titleBar(int total) => Row(children: [
    const Icon(Icons.music_note_rounded, color: Colors.pinkAccent, size: 28), const SizedBox(width: 8),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('🦊 狸音乐', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      Text('$total 首 · ${_scanMode == 'full' ? '全局' : '快速'}', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
    ]),
    const Spacer(),
    IconButton(icon: const Icon(Icons.search_rounded, color: Colors.white70), onPressed: () => setState(() => _showSearch = true)),
    IconButton(icon: const Icon(Icons.settings_rounded, color: Colors.white70), onPressed: _openSettings),
    IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white70), onPressed: () => _scanMusic(forceFull: true)),
  ]);

  Widget _searchBar() => Row(children: [
    IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () { _searchCtrl.clear(); _applyFilter(); setState(() => _showSearch = false); }),
    Expanded(child: TextField(controller: _searchCtrl, autofocus: true, style: const TextStyle(color: Colors.white, fontSize: 16), decoration: const InputDecoration(hintText: '搜索歌曲...', hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none), onChanged: (_) => _applyFilter())),
    if (_searchCtrl.text.isNotEmpty) IconButton(icon: const Icon(Icons.clear, color: Colors.white38), onPressed: () { _searchCtrl.clear(); _applyFilter(); }),
  ]);

  Widget _loadingView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const CircularProgressIndicator(color: Colors.pinkAccent), const SizedBox(height: 16),
    const Text('扫描音乐中...', style: TextStyle(color: Colors.grey)),
    if (_scannedCount > 0) ...[const SizedBox(height: 8), Text('已扫描 $_scannedCount 首', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))],
    if (_scanningDir.isNotEmpty) Text('正在扫描: $_scanningDir', style: TextStyle(color: Colors.grey.shade700, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
  ]));

  Widget _errorView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 48, color: Colors.orange), const SizedBox(height: 12),
    Text(_error!, style: const TextStyle(color: Colors.grey)), const SizedBox(height: 12),
    ElevatedButton.icon(onPressed: _scanMusic, icon: const Icon(Icons.refresh), label: const Text('重试')),
  ]));

  Widget _searchResults() {
    final all = <Song>[..._filteredSongs[MusicCategory.dj] ?? [], ..._filteredSongs[MusicCategory.pop] ?? []];
    if (all.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade600), const SizedBox(height: 12), Text('没有找到 "${_searchCtrl.text}"', style: TextStyle(color: Colors.grey.shade500))]));
    return ListView.builder(itemCount: all.length, itemBuilder: (_, i) => SongTile(song: all[i], isPlaying: _isPlaying(all[i]), isFavorite: _store?.isFavorite(all[i].id) ?? false, onTap: () => _playList(all, startIndex: i), onFavorite: () => _toggleFav(all[i])));
  }

  Widget _songList(MusicCategory cat) {
    final songs = _filteredSongs[cat] ?? [];
    if (songs.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(cat == MusicCategory.dj ? Icons.bolt_rounded : Icons.headphones_rounded, size: 64, color: Colors.grey.shade600), const SizedBox(height: 12), Text(cat == MusicCategory.dj ? '还没有 DJ 歌曲' : '还没有流行歌曲', style: TextStyle(color: Colors.grey.shade500, fontSize: 16))]));
    return Column(children: [CategoryHeader(category: cat, count: songs.length), Expanded(child: ListView.builder(itemCount: songs.length, itemBuilder: (_, i) { final s = songs[i]; return SongTile(song: s, isPlaying: _isPlaying(s), isFavorite: _store?.isFavorite(s.id) ?? false, onTap: () => _playList(songs, startIndex: i), onFavorite: () => _toggleFav(s)); }))]);
  }

  Widget _favList() {
    final favs = _store?.getFavorites() ?? {};
    final list = <Song>[..._allSongs[MusicCategory.dj]?.where((s) => favs.contains(s.id)) ?? [], ..._allSongs[MusicCategory.pop]?.where((s) => favs.contains(s.id)) ?? []];
    if (list.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.star_outline_rounded, size: 64, color: Colors.grey.shade600), const SizedBox(height: 12), const Text('还没有收藏歌曲', style: TextStyle(color: Colors.grey, fontSize: 16))]));
    return Column(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.amber.shade800, Colors.orange.shade700])), child: Row(children: [const Icon(Icons.star_rounded, color: Colors.white, size: 24), const SizedBox(width: 10), const Text('⭐ 我的收藏', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)), child: Text('${list.length} 首', style: const TextStyle(color: Colors.white, fontSize: 13)))])), Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (_, i) => SongTile(song: list[i], isPlaying: _isPlaying(list[i]), isFavorite: true, onTap: () => _playList(list, startIndex: i), onFavorite: () => _toggleFav(list[i])))]);
  }

  bool _isPlaying(Song s) { final cs = audioHandler.currentSong; return cs != null && cs.filePath == s.filePath; }
  Future<void> _toggleFav(Song s) async { if (_store == null) return; await _store!.toggleFavorite(s.id); setState(() {}); }
}

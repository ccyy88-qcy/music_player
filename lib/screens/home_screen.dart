import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/music_scanner.dart';
import '../services/audio_player.dart';
import '../services/storage_manager.dart';
import '../widgets/music_widgets.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'online_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  final AudioPlayerService _audioService = AudioPlayerService();
  final TextEditingController _searchCtrl = TextEditingController();

  Map<MusicCategory, List<Song>> _allSongs = {};
  Map<MusicCategory, List<Song>> _filteredSongs = {};
  bool _loading = true;
  String? _error;
  bool _showSearch = false;
  String _scanMode = 'quick';
  int _scanProgress = 0;
  StorageManager? _store;

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
    _scanMusic();
  }

  Future<void> _scanMusic({bool forceFull = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _scanProgress = 0;
    });

    final granted = await MusicScanner.requestPermission();
    if (!granted) {
      setState(() {
        _loading = false;
        _error = '需要存储权限才能扫描音乐文件';
      });
      return;
    }

    try {
      final songs = await MusicScanner.scanAll(forceFullScan: forceFull);
      setState(() {
        _allSongs = songs;
        _filteredSongs = Map.from(songs);
        _loading = false;
        _scanProgress = 100;
      });
      _applyFilter();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '扫描失败: $e';
      });
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase().trim();
    if (query.isEmpty) {
      _filteredSongs = Map.from(_allSongs);
    } else {
      _filteredSongs = {
        for (final entry in _allSongs.entries)
          entry.key: entry.value
              .where((s) => s.title.toLowerCase().contains(query))
              .toList(),
      };
    }
    setState(() {});
  }

  void _playCategory(MusicCategory category, {int startIndex = 0}) {
    final list = _filteredSongs[category] ?? [];
    if (list.isEmpty) return;
    _audioService.loadPlaylist(list, startIndex: startIndex);
  }

  void _openPlayer() {
    final song = _audioService.currentSong;
    if (song == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(audioService: _audioService),
      ),
    ).then((_) {
      // 返回时刷新收藏状态
      if (mounted) setState(() {});
    });
  }

  void _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    // 设置返回后重新扫描
    if (mounted) _scanMusic(forceFull: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _audioService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      // 从后台回来时增量扫描
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSongs =
        (_allSongs[MusicCategory.dj]?.length ?? 0) +
        (_allSongs[MusicCategory.pop]?.length ?? 0);

    return Scaffold(
      body: Column(
        children: [
          // 顶部标题栏
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              bottom: 8,
              left: 16,
              right: 16,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              ),
            ),
            child: _showSearch ? _buildSearchBar() : _buildTitleBar(totalSongs),
          ),

          // Tab 栏
          if (!_showSearch)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.pinkAccent,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                tabs: [
                  Tab(
                    text:
                        '🔥 DJ (${_filteredSongs[MusicCategory.dj]?.length ?? 0})',
                  ),
                  Tab(
                    text:
                        '🎵 流行 (${_filteredSongs[MusicCategory.pop]?.length ?? 0})',
                  ),
                  Tab(
                    text: '⭐ 收藏 (${_countFavorites()})',
                  ),
                  const Tab(text: '🌐 在线'),
                ],
              ),
            ),

          // 内容
          Expanded(
            child: _loading
                ? _buildLoadingView()
                : _error != null
                    ? _buildErrorView()
                    : _showSearch
                        ? _buildSearchResults()
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              _buildSongList(MusicCategory.dj),
                              _buildSongList(MusicCategory.pop),
                              _buildFavoritesList(),
                              OnlineScreen(audioService: _audioService),
                            ],
                          ),
          ),

          // 迷你播放器
          if (!_showSearch)
            MiniPlayer(
              audioService: _audioService,
              onTap: _openPlayer,
            ),
        ],
      ),
    );
  }

  int _countFavorites() {
    return _store?.getFavorites().length ?? 0;
  }

  Widget _buildTitleBar(int total) {
    return Row(
      children: [
        const Icon(Icons.music_note_rounded, color: Colors.pinkAccent, size: 28),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🦊 狸音乐',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            Text('$total 首 · ${_scanMode == 'full' ? '全局' : '快速'}扫描',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
          ],
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.search_rounded, color: Colors.white70),
          onPressed: () => setState(() => _showSearch = true),
        ),
        IconButton(
          icon: const Icon(Icons.settings_rounded, color: Colors.white70),
          onPressed: _openSettings,
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          onPressed: () => _scanMusic(forceFull: true),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () {
            _searchCtrl.clear();
            _applyFilter();
            setState(() => _showSearch = false);
          },
        ),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: const InputDecoration(
              hintText: '搜索歌曲...',
              hintStyle: TextStyle(color: Colors.white38),
              border: InputBorder.none,
            ),
            onChanged: (_) => _applyFilter(),
          ),
        ),
        if (_searchCtrl.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear, color: Colors.white38),
            onPressed: () {
              _searchCtrl.clear();
              _applyFilter();
            },
          ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.pinkAccent),
          const SizedBox(height: 16),
          const Text('扫描音乐中...', style: TextStyle(color: Colors.grey)),
          if (_scanProgress > 0) ...[
            const SizedBox(height: 8),
            Text('$_scanProgress%',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.orange),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _scanMusic,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final allResults = <Song>[
      ..._filteredSongs[MusicCategory.dj] ?? [],
      ..._filteredSongs[MusicCategory.pop] ?? [],
    ];

    if (allResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text('没有找到 "${_searchCtrl.text}"',
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: allResults.length,
      itemBuilder: (context, index) {
        final song = allResults[index];
        final isPlaying = _isSongPlaying(song);
        return SongTile(
          song: song,
          isPlaying: isPlaying,
          isFavorite: _store?.isFavorite(song.id) ?? false,
          onTap: () => _audioService.loadPlaylist(allResults, startIndex: index),
          onFavorite: () => _toggleFav(song),
        );
      },
    );
  }

  Widget _buildSongList(MusicCategory category) {
    final songs = _filteredSongs[category] ?? [];

    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              category == MusicCategory.dj
                  ? Icons.bolt_rounded
                  : Icons.headphones_rounded,
              size: 64,
              color: Colors.grey.shade600,
            ),
            const SizedBox(height: 12),
            Text(
              category == MusicCategory.dj ? '还没有 DJ 歌曲' : '还没有流行歌曲',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text('把音乐放入 Music/Download 或全盘扫描',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      children: [
        CategoryHeader(category: category, count: songs.length),
        Expanded(
          child: ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              final isPlaying = _isSongPlaying(song);
              return SongTile(
                song: song,
                isPlaying: isPlaying,
                isFavorite: _store?.isFavorite(song.id) ?? false,
                onTap: () => _playCategory(category, startIndex: index),
                onFavorite: () => _toggleFav(song),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesList() {
    final favIds = _store?.getFavorites() ?? {};
    final favSongs = <Song>[
      ..._allSongs[MusicCategory.dj]?.where((s) => favIds.contains(s.id)) ?? [],
      ..._allSongs[MusicCategory.pop]?.where((s) => favIds.contains(s.id)) ?? [],
    ];

    if (favSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_outline_rounded, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text('还没有收藏歌曲',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('点击歌曲右侧 ☆ 即可收藏',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.amber.shade800, Colors.orange.shade700],
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              const Text('⭐ 我的收藏',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Text('${favSongs.length} 首', style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: favSongs.length,
            itemBuilder: (context, index) {
              final song = favSongs[index];
              final isPlaying = _isSongPlaying(song);
              return SongTile(
                song: song,
                isPlaying: isPlaying,
                isFavorite: true,
                onTap: () => _audioService.loadPlaylist(favSongs, startIndex: index),
                onFavorite: () => _toggleFav(song),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isSongPlaying(Song song) {
    final cs = _audioService.currentSong;
    final ci = _audioService.currentIndex;
    final q = _audioService.queue;
    return cs != null && ci >= 0 && ci < q.length && q[ci].filePath == song.filePath;
  }

  Future<void> _toggleFav(Song song) async {
    if (_store == null) return;
    await _store!.toggleFavorite(song.id);
    setState(() {});
  }
}

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/music_scanner.dart';
import '../services/audio_player.dart';
import '../widgets/music_widgets.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final AudioPlayerService _audioService = AudioPlayerService();
  final TextEditingController _searchCtrl = TextEditingController();

  Map<MusicCategory, List<Song>> _allSongs = {};
  Map<MusicCategory, List<Song>> _filteredSongs = {};
  bool _loading = true;
  String? _error;
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scanMusic();
  }

  Future<void> _scanMusic() async {
    setState(() {
      _loading = true;
      _error = null;
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
      final songs = await MusicScanner.scanAll();
      setState(() {
        _allSongs = songs;
        _filteredSongs = Map.from(songs);
        _loading = false;
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
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── 顶部标题栏 ──
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
            child: _showSearch ? _buildSearchBar() : _buildTitleBar(),
          ),

          // ── Tab 栏 ──
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
                labelStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
                tabs: [
                  Tab(
                    text:
                        '🔥 DJ (${_filteredSongs[MusicCategory.dj]?.length ?? 0})',
                  ),
                  Tab(
                    text:
                        '🎵 流行 (${_filteredSongs[MusicCategory.pop]?.length ?? 0})',
                  ),
                ],
              ),
            ),

          // ── 内容区 ──
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.pinkAccent),
                        SizedBox(height: 16),
                        Text('扫描音乐中...',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 48, color: Colors.orange),
                            const SizedBox(height: 12),
                            Text(_error!,
                                style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _scanMusic,
                              icon: const Icon(Icons.refresh),
                              label: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : _showSearch
                        ? _buildSearchResults()
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              _buildSongList(MusicCategory.dj),
                              _buildSongList(MusicCategory.pop),
                            ],
                          ),
          ),

          // ── 迷你播放器 ──
          if (!_showSearch)
            MiniPlayer(
              audioService: _audioService,
              onTap: _openPlayer,
            ),
        ],
      ),
    );
  }

  Widget _buildTitleBar() {
    return Row(
      children: [
        const Icon(Icons.music_note_rounded,
            color: Colors.pinkAccent, size: 28),
        const SizedBox(width: 8),
        const Text(
          '🦊 狸音乐',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.search_rounded, color: Colors.white70),
          onPressed: () => setState(() => _showSearch = true),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          onPressed: _scanMusic,
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
            Icon(Icons.search_off_rounded,
                size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text('没有找到 "${_searchCtrl.text}"',
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    final currentSong = _audioService.currentSong;
    final currentIndex = _audioService.currentIndex;

    return ListView.builder(
      itemCount: allResults.length,
      itemBuilder: (context, index) {
        final song = allResults[index];
        final allQueue = _audioService.queue;
        final isPlaying = currentSong != null &&
            allQueue.length > currentIndex &&
            currentIndex < allQueue.length &&
            allQueue[currentIndex].filePath == song.filePath;
        return SongTile(
          song: song,
          isPlaying: isPlaying,
          onTap: () {
            // 用搜索结果构造临时播放列表（保持分类）
            _audioService.loadPlaylist(allResults, startIndex: index);
          },
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
            const Text(
              '把音乐文件放入 Music 或 Download 文件夹',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final currentSong = _audioService.currentSong;
    final currentIndex = _audioService.currentIndex;

    return Column(
      children: [
        CategoryHeader(category: category, count: songs.length),
        Expanded(
          child: ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              final allQueue = _audioService.queue;
              final isPlaying = currentSong != null &&
                  allQueue.length > currentIndex &&
                  currentIndex < allQueue.length &&
                  allQueue[currentIndex].filePath == song.filePath;
              return SongTile(
                song: song,
                isPlaying: isPlaying,
                onTap: () => _playCategory(category, startIndex: index),
              );
            },
          ),
        ),
      ],
    );
  }
}

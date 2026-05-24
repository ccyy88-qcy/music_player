import 'package:flutter/material.dart';
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

  Map<MusicCategory, List<Song>> _songs = {};
  bool _loading = true;
  String? _error;

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
        _songs = songs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '扫描失败: $e';
      });
    }
  }

  void _playCategory(MusicCategory category, {int startIndex = 0}) {
    final list = _songs[category] ?? [];
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
            child: Row(
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
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                  onPressed: _scanMusic,
                ),
              ],
            ),
          ),

          // ── Tab 栏 ──
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
                  text: '🔥 DJ (${_songs[MusicCategory.dj]?.length ?? 0})',
                ),
                Tab(
                  text: '🎵 流行 (${_songs[MusicCategory.pop]?.length ?? 0})',
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
                        Text('扫描音乐中...', style: TextStyle(color: Colors.grey)),
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
                            Text(_error!, style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _scanMusic,
                              icon: const Icon(Icons.refresh),
                              label: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildSongList(MusicCategory.dj),
                          _buildSongList(MusicCategory.pop),
                        ],
                      ),
          ),

          // ── 迷你播放器 ──
          MiniPlayer(
            audioService: _audioService,
            onTap: _openPlayer,
          ),
        ],
      ),
    );
  }

  Widget _buildSongList(MusicCategory category) {
    final songs = _songs[category] ?? [];

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
            Text(
              '把音乐文件放入 Music 或 Download 文件夹',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
      );
    }

    // 判断当前正在播放哪首歌
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
              final isPlaying = currentSong != null &&
                  _audioService.queue == songs &&
                  currentIndex == index;
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

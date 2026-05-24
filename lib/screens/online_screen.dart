import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/online_music_service.dart';
import '../services/audio_player.dart';
import '../services/lyric_parser.dart';
import 'player_screen.dart';

class OnlineScreen extends StatefulWidget {
  final AudioPlayerService audioService;

  const OnlineScreen({super.key, required this.audioService});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  List<OnlineSong> _results = [];
  bool _searching = false;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  String? _playingId;
  Set<String> _downloadingIds = {};
  Map<String, double> _downloadProgress = {};
  MusicSource? _source;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {});
    _initSource();
  }

  Future<void> _initSource() async {
    _source = await getMusicSourceAsync();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _search({bool loadMore = false}) async {
    final keyword = _searchCtrl.text.trim();
    if (keyword.isEmpty) return;

    if (!loadMore) {
      setState(() {
        _searching = true;
        _error = null;
        _results = [];
        _page = 1;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final songs =
          await _source!.search(keyword, page: _page, limit: 20);
      setState(() {
        if (loadMore) {
          _results.addAll(songs);
        } else {
          _results = songs;
        }
        _page++;
        _searching = false;
        _loadingMore = false;
        if (_results.isEmpty && !loadMore) {
          _error = '未找到相关歌曲';
        }
      });
    } catch (e) {
      setState(() {
        _searching = false;
        _loadingMore = false;
        _error = '搜索失败: $e';
      });
    }
  }

  Future<void> _playOnline(OnlineSong song) async {
    setState(() => _playingId = song.id);

    // 获取播放URL
    final playUrl = await _source!.getPlayUrl(song);
    if (playUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取播放地址失败，尝试其他歌曲'), backgroundColor: Colors.red),
        );
      }
      setState(() => _playingId = null);
      return;
    }

    // 获取歌词
    String? lrcText;
    try {
      lrcText = await _source!.getLyric(song);
    } catch (_) {}

    // 创建临时 Song 对象用于播放
    final tempSong = Song(
      title: song.title,
      artist: song.artist,
      filePath: playUrl, // 直接播放在线URL
      category: MusicCategory.pop,
    );

    // 构造播放列表（单曲）
    widget.audioService.loadPlaylist([tempSong], startIndex: 0);

    // 设置在线歌词
    if (lrcText != null && lrcText.isNotEmpty) {
      // 通过 LyricParser 解析
      final lyrics = LyricParser.parse(lrcText);
      // 更新播放器歌词（需要暴露方法）
      widget.audioService.setOnlineLyrics(lyrics);
    }

    // 打开播放器
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(audioService: widget.audioService),
        ),
      );
    }

    setState(() => _playingId = null);
  }

  Future<void> _downloadSong(OnlineSong song) async {
    if (_downloadingIds.contains(song.id)) return;

    setState(() {
      _downloadingIds.add(song.id);
      _downloadProgress[song.id] = 0;
    });

    final playUrl = await _source!.getPlayUrl(song);
    if (playUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取下载地址失败'), backgroundColor: Colors.red),
        );
      }
      setState(() => _downloadingIds.remove(song.id));
      return;
    }

    final saveDir = '/storage/emulated/0/Music/xmp3';
    final path = await DownloadManager.downloadSong(song, playUrl, saveDir);

    if (mounted) {
      setState(() {
        _downloadingIds.remove(song.id);
        _downloadProgress.remove(song.id);
      });

      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 下载完成: ${song.title}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载失败'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 搜索栏
        Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 4,
            left: 12,
            right: 12,
            bottom: 8,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(21),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '🔍 搜索在线歌曲...',
                      hintStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                      prefixIcon:
                          const Icon(Icons.search_rounded, color: Colors.white38, size: 22),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _search(),
                    textInputAction: TextInputAction.search,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _searching
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.pinkAccent),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send_rounded,
                          color: Colors.pinkAccent, size: 24),
                      onPressed: _search,
                    ),
            ],
          ),
        ),

        // 源标识
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: Colors.black26,
          child: Row(
            children: [
              Icon(Icons.cloud_download_rounded,
                  size: 14, color: Colors.green.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text(
                _source!.name,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
              ),
              const Spacer(),
              if (_results.isNotEmpty)
                Text(
                  '${_results.length} 首',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                ),
            ],
          ),
        ),

        // 结果列表
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _buildResults() {
    if (_searching && _results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.pinkAccent),
            SizedBox(height: 12),
            Text('搜索中...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_error != null && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            const Text('输入歌名搜索，如"夜曲"、"DJ"',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded, size: 64, color: Colors.grey.shade700),
            const SizedBox(height: 12),
            const Text('🔍 输入歌名搜索在线音乐',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
            const SizedBox(height: 6),
            const Text('支持多源聚合，自动降级',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            _scrollCtrl.position.pixels >=
                _scrollCtrl.position.maxScrollExtent - 100 &&
            !_loadingMore) {
          _search(loadMore: true);
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollCtrl,
        itemCount: _results.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _results.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return _songCard(_results[index]);
        },
      ),
    );
  }

  Widget _songCard(OnlineSong song) {
    final isPlaying = _playingId == song.id;
    final isDownloading = _downloadingIds.contains(song.id);
    final progress = _downloadProgress[song.id] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isPlaying
            ? Colors.pink.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: isPlaying
            ? Border.all(color: Colors.pink.withValues(alpha: 0.3))
            : null,
      ),
      child: ListTile(
        onTap: () => _playOnline(song),
        leading: Stack(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: isPlaying
                      ? [Colors.pink.shade400, Colors.purple.shade400]
                      : [Colors.blueGrey.shade700, Colors.blueGrey.shade800],
                ),
              ),
              child: Icon(
                isDownloading ? Icons.downloading_rounded : Icons.music_note_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 22,
              ),
            ),
            if (isDownloading)
              Positioned.fill(
                child: CircularProgressIndicator(
                  value: progress > 0 ? progress : null,
                  strokeWidth: 2,
                  color: Colors.green,
                  backgroundColor: Colors.white12,
                ),
              ),
          ],
        ),
        title: Text(
          song.title,
          style: TextStyle(
            color: isPlaying ? Colors.pink.shade300 : Colors.white,
            fontSize: 14,
            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${song.artist}${song.album.isNotEmpty ? ' · ${song.album}' : ''}',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPlaying)
              const Icon(Icons.volume_up_rounded,
                  color: Colors.pink, size: 20)
            else
              IconButton(
                icon: const Icon(Icons.download_rounded,
                    color: Colors.white30, size: 22),
                onPressed: isDownloading ? null : () => _downloadSong(song),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36),
              ),
            IconButton(
              icon: Icon(Icons.play_circle_outline_rounded,
                  color: isPlaying ? Colors.pink : Colors.white38, size: 22),
              onPressed: () => _playOnline(song),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36),
            ),
          ],
        ),
      ),
    );
  }
}

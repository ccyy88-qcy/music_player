import 'package:flutter/material.dart';
import 'dart:io';
import '../models/song.dart';
import '../services/online_music_service.dart';
import '../services/audio_handler.dart';
import '../services/lyric_parser.dart';
import '../main.dart' show audioHandler;
import 'player_screen.dart';

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

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
  MusicSource? _source;

  @override
  void initState() {
    super.initState();
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
    if (keyword.isEmpty || _source == null) return;
    if (!loadMore) {
      setState(() { _searching = true; _error = null; _results = []; _page = 1; });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final songs = await _source!.search(keyword, page: _page, limit: 20);
      setState(() {
        if (loadMore) { _results.addAll(songs); } else { _results = songs; }
        _page++;
        _searching = false; _loadingMore = false;
        if (_results.isEmpty && !loadMore) _error = '未找到相关歌曲';
      });
    } catch (e) {
      setState(() { _searching = false; _loadingMore = false; _error = '搜索失败: 请检查网络连接，或在设置中添加可用音乐源'; });
    }
  }

  Future<void> _playOnline(OnlineSong song) async {
    setState(() => _playingId = song.id);
    final playUrl = await _source!.getPlayUrl(song);
    if (playUrl == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('获取播放地址失败'), backgroundColor: Colors.red));
      setState(() => _playingId = null);
      return;
    }
    String? lrcText;
    try { lrcText = await _source!.getLyric(song); } catch (_) {}
    final tempSong = Song(title: song.title, artist: song.artist, filePath: playUrl, category: MusicCategory.pop);
    audioHandler.loadSongList([tempSong], startIndex: 0);
    if (lrcText != null && lrcText.isNotEmpty) {
      audioHandler.setOnlineLyrics(LyricParser.parse(lrcText));
    }
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
    setState(() => _playingId = null);
  }

  Future<void> _download(OnlineSong song) async {
    if (_downloadingIds.contains(song.id)) return;
    setState(() => _downloadingIds.add(song.id));
    
    // 显示下载中提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 12),
          Text('正在下载: ${song.title}...'),
        ]),
        duration: const Duration(seconds: 30),
      ));
    }
    
    final playUrl = await _source!.getPlayUrl(song);
    if (playUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ 获取播放地址失败，该歌曲可能需要VIP'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ));
      }
      setState(() => _downloadingIds.remove(song.id));
      return;
    }
    
    final path = await DownloadManager.downloadSong(song, playUrl, '/storage/emulated/0/Music/xmp3');
    if (mounted) {
      setState(() => _downloadingIds.remove(song.id));
      if (path != null) {
        final file = File(path);
        final sizeStr = file.existsSync() ? '${(file.lengthSync() / 1024 / 1024).toStringAsFixed(1)}MB' : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ 下载完成: ${song.title} ($sizeStr)'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ 下载失败，可能该歌曲需要VIP或有版权限制'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4, left: 12, right: 12, bottom: 8),
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)])),
        child: Row(children: [
          Expanded(child: Container(height: 42, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(21)), child: TextField(controller: _searchCtrl, style: const TextStyle(color: Colors.white, fontSize: 15), decoration: InputDecoration(hintText: '🔍 搜索在线歌曲...', hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)), prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 22), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)), onSubmitted: (_) => _search(), textInputAction: TextInputAction.search))),
          const SizedBox(width: 8),
          _searching ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent)) : IconButton(icon: const Icon(Icons.send_rounded, color: Colors.pinkAccent, size: 24), onPressed: _search),
        ]),
      ),
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), color: Colors.black26, child: Row(children: [
        Icon(Icons.cloud_download_rounded, size: 14, color: Colors.green.withValues(alpha: 0.7)), const SizedBox(width: 4),
        Text(_source?.name ?? '加载中...', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
        const Spacer(),
        if (_results.isNotEmpty) Text('${_results.length} 首', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
      ])),
      Expanded(child: _buildResults()),
    ]);
  }

  Widget _buildResults() {
    if (_searching && _results.isEmpty) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.pinkAccent), SizedBox(height: 12), Text('搜索中...', style: TextStyle(color: Colors.grey))]));
    if (_error != null && _results.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey.shade600), SizedBox(height: 12), Text(_error!, style: TextStyle(color: Colors.grey.shade500))]));
    if (_results.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.music_note_rounded, size: 64, color: Colors.grey.shade700), SizedBox(height: 12), const Text('🔍 输入歌名搜索在线音乐', style: TextStyle(color: Colors.grey, fontSize: 15))]));
    return NotificationListener<ScrollNotification>(onNotification: (n) { if (n is ScrollEndNotification && _scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 100 && !_loadingMore) _search(loadMore: true); return false; }, child: ListView.builder(controller: _scrollCtrl, itemCount: _results.length + (_loadingMore ? 1 : 0), itemBuilder: (_, i) {
      if (i >= _results.length) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)));
      final s = _results[i];
      final isPlay = _playingId == s.id;
      final isDL = _downloadingIds.contains(s.id);
      return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: isPlay ? Colors.pink.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10), border: isPlay ? Border.all(color: Colors.pink.withValues(alpha: 0.3)) : null), child: ListTile(
        onTap: () => _playOnline(s),
        leading: Container(width: 44, height: 44, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(colors: isPlay ? [Colors.pink.shade400, Colors.purple.shade400] : [Colors.blueGrey.shade700, Colors.blueGrey.shade800])), child: Icon(isDL ? Icons.downloading_rounded : Icons.music_note_rounded, color: Colors.white.withValues(alpha: 0.7), size: 22)),
        title: Text(s.title, style: TextStyle(color: isPlay ? Colors.pink.shade300 : Colors.white, fontSize: 14, fontWeight: isPlay ? FontWeight.w600 : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${s.artist}${s.album.isNotEmpty ? ' · ${s.album}' : ''}', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (isPlay) const Icon(Icons.volume_up_rounded, color: Colors.pink, size: 20)
          else IconButton(icon: const Icon(Icons.download_rounded, color: Colors.white30, size: 22), onPressed: isDL ? null : () => _download(s), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36)),
          IconButton(icon: Icon(Icons.play_circle_outline_rounded, color: isPlay ? Colors.pink : Colors.white38, size: 22), onPressed: () => _playOnline(s), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36)),
        ]),
      ));
    }));
  }
}

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../services/online_music_service.dart';
import '../services/chart_service.dart';
import '../services/audio_handler.dart';
import '../services/lyric_parser.dart';
import '../services/storage_manager.dart';
import '../widgets/music_widgets.dart';
import '../main.dart' show audioHandler, AppColors;
import 'player_screen.dart';

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});
  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  List<OnlineSong> _results = [];
  bool _searching = false;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  String? _playingId;
  Set<String> _downloadingIds = {};
  final List<Map<String, dynamic>> _downloadBubbles = [];
  MusicSource? _source;

  // 批量选择
  bool _selectMode = false;
  Set<String> _selectedIds = {};

  // 排行榜模式
  bool _chartMode = false;
  List<ChartSong> _chartSongs = [];
  bool _chartLoading = false;
  String? _chartSource; // 'netease' | 'qq' | 'kugou'
  String? _currentChartId;

  // 批量下载进度
  bool _batchDownloading = false;
  int _batchDone = 0;
  int _batchTotal = 0;
  List<DownloadTask> _batchTasks = [];

  // JS源
  List<String> _jsSourceNames = [];
  String? _activeJsSource;

  @override
  void initState() {
    super.initState();
    _initSource();
    _loadJsSources();
  }

  Future<void> _loadJsSources() async {
    final store = await StorageManager.instance;
    final jsSources = store.getJsSources();
    final names = jsSources.map((s) {
      final parts = s.split('|||');
      return parts.isNotEmpty ? parts[0] : 'JS源';
    }).toList();
    if (mounted) setState(() => _jsSourceNames = names);
  }

  void _activateJsSource(String name) {
    setState(() => _activeJsSource = name == _activeJsSource ? null : name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_activeJsSource == name ? '✅ JS源已激活: $name' : '已关闭JS源'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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

  // ──── 搜索 ────
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
      setState(() { _searching = false; _loadingMore = false; _error = '搜索失败: 请检查网络连接'; });
    }
  }

  // ──── 排行榜 ────
  void _enterChartMode(String sourceKey) {
    setState(() {
      _chartMode = true;
      _chartSource = sourceKey;
      _chartSongs = [];
      _currentChartId = null;
      _results = [];
    });
  }

  Future<void> _loadChart(String topId) async {
    if (_chartSource == null) return;
    setState(() { _chartLoading = true; _currentChartId = topId; });
    List<ChartSong> songs;
    switch (_chartSource!) {
      case 'netease':
        songs = await NeteaseChart.getChart(topId);
        break;
      case 'qq':
        songs = await QQChart.getChart(topId);
        break;
      case 'kugou':
        songs = await KugouChart.getChart(topId);
        break;
      default:
        songs = [];
    }
    setState(() { _chartSongs = songs; _chartLoading = false; });
  }

  void _exitChartMode() {
    setState(() {
      _chartMode = false;
      _chartSource = null;
      _chartSongs = [];
      _currentChartId = null;
      _results = [];
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _playOnline(OnlineSong song) async {
    setState(() => _playingId = song.id);
    String? playUrl;
    String? playErr;
    try {
      playUrl = await _source!.getPlayUrl(song);
    } catch (e) {
      playErr = e.toString();
    }
    // 失败时主动跨源搜索替代版本
    if ((playUrl == null) && (song.fee > 0 || playErr != null)) {
      try { playUrl = await _searchAltUrl(song); } catch (_) {}
    }
    if (playUrl == null) {
      if (mounted) {
        final msg = playErr != null ? '${song.title} - $playErr' : '${song.title} - 无可用播放源(需VIP)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
        );
      }
      setState(() => _playingId = null);
      return;
    }
    String? lrcText;
    try { lrcText = await _source!.getLyric(song); } catch (_) {}
    // 如果没找到歌词，清理标题再试一次
    if (lrcText == null || lrcText.isEmpty) {
      try {
        final cleanTitle = song.title.replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').trim();
        if (cleanTitle != song.title) {
          final altSong = OnlineSong(id: song.id, title: cleanTitle, artist: song.artist, source: song.source, duration: song.duration);
          lrcText = await _source!.getLyric(altSong);
        }
      } catch (_) {}
    }
    audioHandler.player.stop();
    final tempSong = Song(title: song.title, artist: song.artist, filePath: playUrl, category: MusicCategory.pop);
    audioHandler.loadSongList([tempSong], startIndex: 0);
    if (lrcText != null && lrcText.isNotEmpty) {
      audioHandler.setOnlineLyrics(LyricParser.parse(lrcText));
    }
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
    }
    setState(() => _playingId = null);
  }

  /// VIP歌曲跨源搜索免费替代版本
  Future<String?> _searchAltUrl(OnlineSong song) async {
    try {
      final srcs = [_source]; // 用聚合源搜索
      final kw = '${song.title} ${song.artist}';
      for (final s in [NeteaseSource(), QQSource(), KugouSource()]) {
        try {
          final results = await s.search(kw, limit: 10);
          for (final alt in results) {
            if (alt.fee == 0 && alt.id != song.id) {
              try {
                final u = await s.getPlayUrl(alt);
                if (u != null && u.startsWith('http')) return u;
              } catch (_) {}
            }
            // 也试同一首歌（不同源可能有不同付费策略）
            if (alt.title.contains(song.title) && alt.id != song.id) {
              try {
                final u = await s.getPlayUrl(alt);
                if (u != null && u.startsWith('http')) return u;
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  // ──── 排行榜列表播放（整榜） ────
  Future<void> _playChartList(List<ChartSong> songs, int startIndex) async {
    setState(() => _playingId = songs[startIndex].id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('解析播放地址...'), duration: Duration(seconds: 5)),
      );
    }

    // 直接解析用户点击的单首歌曲，不批量
    final song = songs[startIndex];
    String? playUrl;
    try {
      playUrl = await _source!.getPlayUrl(song);
    } catch (_) {}

    if (playUrl == null || !playUrl.startsWith('http')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该歌曲暂时无法播放'), backgroundColor: Colors.red),
        );
      }
      setState(() => _playingId = null);
      return;
    }

    final tempSong = Song(title: song.title, artist: song.artist, filePath: playUrl, category: MusicCategory.pop);
    audioHandler.loadSongList([tempSong], startIndex: 0);

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
    }
    setState(() => _playingId = null);
  }

  // ──── 单曲下载 ────
  Future<void> _download(OnlineSong song) async {
    if (_downloadingIds.contains(song.id)) return;
    setState(() => _downloadingIds.add(song.id));

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ ${song.title} - 获取播放地址失败，该歌曲可能需要VIP', style: const TextStyle(fontSize: 12)),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ));
      }
      setState(() => _downloadingIds.remove(song.id));
      return;
    }

    String? path = await DownloadManager.downloadSong(song, playUrl, '/storage/emulated/0/Music/狸音乐');
    if (path == null) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) path = await DownloadManager.downloadSong(song, playUrl, '${extDir.path}/Music/xmp3');
      } catch (_) {}
    }
    if (path == null) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        path = await DownloadManager.downloadSong(song, playUrl, '${docDir.path}/下载/xmp3');
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _downloadingIds.remove(song.id));
      _addBubble(path != null, song.title, path);
    }
  }

  // ──── 批量下载 ────
  Future<void> _batchDownload() async {
    List<OnlineSong> targets;
    if (_selectMode && _selectedIds.isNotEmpty) {
      targets = _results.where((s) => _selectedIds.contains('${s.id}_${s.source}')).toList();
      if (_chartMode) {
        targets = _chartSongs.cast<OnlineSong>().where((s) => _selectedIds.contains('${s.id}_${s.source}')).toList();
      }
    } else {
      targets = _chartMode ? _chartSongs.cast<OnlineSong>() : _results;
    }
    if (targets.isEmpty) return;

    final saveDir = '/storage/emulated/0/Music/狸音乐';
    final dir = Directory(saveDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    setState(() {
      _batchDownloading = true;
      _batchDone = 0;
      _batchTotal = targets.length;
      _selectMode = false;
      _selectedIds.clear();
    });

    final downloader = BatchDownloadManager(
      source: _source!,
      saveDir: saveDir,
      onTaskUpdate: (task) { if (mounted) setState(() {}); },
      onProgress: (done, total) { if (mounted) setState(() { _batchDone = done; _batchTotal = total; }); },
    );

    final tasks = await downloader.downloadAll(targets);

    setState(() {
      _batchDownloading = false;
      _batchTasks = tasks;
    });

    // 显示结果
    final success = tasks.where((t) => t.status == DownloadTaskStatus.success).length;
    final failed = tasks.where((t) => t.status == DownloadTaskStatus.failed).length;
    final skipped = tasks.where((t) => t.status == DownloadTaskStatus.skipped).length;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('下载完成: $success 成功 / $failed 失败 / $skipped 跳过'),
        backgroundColor: failed > 0 ? Colors.orange : Colors.green,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: '详情', textColor: Colors.white, onPressed: () => _showBatchResult(tasks)),
      ));
    }
  }

  void _showBatchResult(List<DownloadTask> tasks) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final success = tasks.where((t) => t.status == DownloadTaskStatus.success).length;
        final failed = tasks.where((t) => t.status == DownloadTaskStatus.failed).length;
        final skipped = tasks.where((t) => t.status == DownloadTaskStatus.skipped).length;
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(color: AppColors.textSecondary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _statChip('✅ 成功', '$success', Colors.green),
                _statChip('❌ 失败', '$failed', Colors.red),
                _statChip('⏭️ 跳过', '$skipped', Colors.orange),
              ])),
            const Divider(color: AppColors.glassBorder, thickness: 0.5),
            Flexible(child: ListView.builder(
              shrinkWrap: true,
              itemCount: tasks.length,
              itemBuilder: (_, i) {
                final t = tasks[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    t.status == DownloadTaskStatus.success ? Icons.check_circle :
                    t.status == DownloadTaskStatus.failed ? Icons.error : Icons.skip_next,
                    color: t.status == DownloadTaskStatus.success ? Colors.green :
                           t.status == DownloadTaskStatus.failed ? Colors.red : Colors.orange,
                    size: 20,
                  ),
                  title: Text(t.song.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${t.song.artist} · ${t.statusLabel}', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                );
              },
            )),
          ]),
        );
      },
    );
  }

  Widget _statChip(String label, String count, Color color) {
    return Column(children: [
      Text(count, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
    ]);
  }

  void _addBubble(bool success, String title, String? path) {
    String? sizeStr;
    if (path != null && success) {
      final f = File(path);
      if (f.existsSync()) sizeStr = '${(f.lengthSync() / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    final bubble = <String, dynamic>{'title': title, 'success': success, 'size': sizeStr, 'key': UniqueKey()};
    setState(() => _downloadBubbles.insert(0, bubble));
    if (_downloadBubbles.length > 3) _downloadBubbles.removeLast();
  }

  // ──── 构建UI ────
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Column(children: [
        _buildHeader(),
        if (_chartMode) _buildChartBar(),
        if (_batchDownloading) _buildBatchProgress(),
        Expanded(child: _chartMode ? _buildChartView() : _buildResults()),
      ]),
      _buildDownloadBubbles(),
    ]);
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4, left: 12, right: 12, bottom: 8),
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)])),
      child: Column(children: [
        Row(children: [
          if (_chartMode)
            IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70), onPressed: _exitChartMode),
          Expanded(child: Container(
            height: 34,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(17)),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: _chartMode ? '搜索排行榜歌曲...' : '🔍 搜索在线歌曲...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 22),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _chartMode ? null : _search(),
              textInputAction: TextInputAction.search,
              enabled: !_chartMode,
            ),
          )),
          const SizedBox(width: 8),
          if (_searching)
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent))
          else if (_selectMode)
            IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70), onPressed: () { setState(() { _selectMode = false; _selectedIds.clear(); }); })
          else
            IconButton(icon: Icon(_chartMode ? Icons.trending_up : Icons.send_rounded, color: Colors.pinkAccent, size: 24),
              onPressed: _chartMode ? null : _search),
        ]),
        // 排行榜快捷入口 + 批量操作栏
        if (!_chartMode && !_selectMode)
          Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
            _chipBtn('🔥 网易热歌', () => _enterChartMode('netease')),
            const SizedBox(width: 6),
            _chipBtn('🎵 QQ音乐', () => _enterChartMode('qq')),
            const SizedBox(width: 6),
            _chipBtn('🎧 酷狗', () => _enterChartMode('kugou')),
            // JS源脚本
            if (_jsSourceNames.isNotEmpty) ...[
              const SizedBox(width: 6),
              ..._jsSourceNames.map((name) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _chipBtn('⚡ $name', () => _activateJsSource(name)),
              )),
            ],
            const Spacer(),
            if (_results.isNotEmpty)
              GestureDetector(onTap: () { setState(() => _selectMode = true); },
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.glass, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.glassBorder)),
                  child: Text('多选', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)))),
          ])),
        // 批量操作栏
        if (_selectMode)
          Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
            Text('已选 ${_selectedIds.length} 首', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const Spacer(),
            GestureDetector(onTap: () {
              final all = _chartMode ? _chartSongs.map((s) => '${s.id}_${s.source}').toSet() : _results.map((s) => '${s.id}_${s.source}').toSet();
              setState(() => _selectedIds = all.difference(_selectedIds).length < all.length / 2 ? all : {});
            }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: Text('全选', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)))),
            const SizedBox(width: 8),
            GestureDetector(onTap: _selectedIds.isEmpty ? null : _batchDownload,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  gradient: _selectedIds.isEmpty ? null : const LinearGradient(colors: [Colors.green, Color(0xFF00C853)]),
                  color: _selectedIds.isEmpty ? Colors.white.withValues(alpha: 0.05) : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('批量下载', style: TextStyle(color: _selectedIds.isEmpty ? Colors.white30 : Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
            const SizedBox(width: 8),
            if (_selectedIds.isNotEmpty)
              GestureDetector(onTap: () async {
                final songs = _chartMode
                  ? _chartSongs.where((s) => _selectedIds.contains('${s.id}_${s.source}')).toList()
                  : _results.where((s) => _selectedIds.contains('${s.id}_${s.source}')).toList();
                // 构建在线播放列表
                final firstSong = songs.first;
                final playUrl = await _source!.getPlayUrl(firstSong);
                if (playUrl != null) {
                  final idx = songs.indexOf(firstSong);
                  final tempSongs = songs.map((s) => Song(title: s.title, artist: s.artist, filePath: '', category: MusicCategory.pop)).toList();
                  tempSongs[idx] = Song(title: firstSong.title, artist: firstSong.artist, filePath: playUrl, category: MusicCategory.pop);
                  audioHandler.loadSongList(tempSongs, startIndex: idx);
                  if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
                }
              }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.purple, Colors.deepPurple]), borderRadius: BorderRadius.circular(8)),
                child: const Text('播放所选', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
          ])),
      ]),
    );
  }

  Widget _chipBtn(String label, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.glass, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.glassBorder)),
      child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
    ));
  }

  Widget _buildChartBar() {
    if (_chartSource == null) return const SizedBox.shrink();
    List<ChartCategory> cats;
    switch (_chartSource!) {
      case 'netease': cats = NeteaseChart.categories; break;
      case 'qq': cats = QQChart.categories; break;
      case 'kugou': cats = KugouChart.categories; break;
      default: cats = [];
    }
    return Container(
      height: 48,
      color: Colors.black26,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: cats.length,
        itemBuilder: (_, i) {
          final cat = cats[i];
          final selected = _currentChartId == cat.id;
          return GestureDetector(onTap: () => _loadChart(cat.id), child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? Colors.pink.withValues(alpha: 0.2) : AppColors.glass,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? Colors.pink.withValues(alpha: 0.5) : AppColors.glassBorder),
            ),
            child: Center(child: Text('${cat.icon} ${cat.name}', style: TextStyle(color: selected ? Colors.pink.shade300 : Colors.white.withValues(alpha: 0.6), fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.normal))),
          ));
        },
      ),
    );
  }

  Widget _buildBatchProgress() {
    final pct = _batchTotal > 0 ? (_batchDone / _batchTotal * 100).round() : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black26,
      child: Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green)),
        const SizedBox(width: 12),
        Text('批量下载中... $_batchDone/$_batchTotal ($pct%)', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const Spacer(),
        GestureDetector(onTap: () => setState(() => _batchDownloading = false),
          child: const Icon(Icons.close, color: Colors.white38, size: 18)),
      ]),
    );
  }

  Widget _buildChartView() {
    if (_chartLoading) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.pinkAccent), SizedBox(height: 12), Text('加载排行榜...', style: TextStyle(color: Colors.grey))]));
    if (_currentChartId == null) return const Center(child: Text('选择上方分类查看排行榜', style: TextStyle(color: Colors.grey)));
    if (_chartSongs.isEmpty) return const Center(child: Text('排行榜为空', style: TextStyle(color: Colors.grey)));

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification && _scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 100 && !_loadingMore) {
          // 排行榜不分页，但可以加载更多
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollCtrl,
        itemCount: _chartSongs.length,
        itemBuilder: (_, i) {
          final s = _chartSongs[i];
          final isPlay = _playingId == s.id;
          final isDL = _downloadingIds.contains(s.id);
          final isSelected = _selectedIds.contains('${s.id}_${s.source}');
          return GestureDetector(
            onLongPress: () { setState(() { _selectMode = true; _selectedIds.add('${s.id}_${s.source}'); }); },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.pink.withValues(alpha: 0.1) : (isPlay ? Colors.pink.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.03)),
                borderRadius: BorderRadius.circular(8),
                border: isSelected ? Border.all(color: Colors.pink.withValues(alpha: 0.4)) : (isPlay ? Border.all(color: Colors.pink.withValues(alpha: 0.3)) : null),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                visualDensity: VisualDensity.compact,
                onTap: _selectMode ? () {
                  setState(() {
                    final key = '${s.id}_${s.source}';
                    if (_selectedIds.contains(key)) _selectedIds.remove(key);
                    else _selectedIds.add(key);
                    if (_selectedIds.isEmpty) _selectMode = false;
                  });
                } : () => _playChartList(_chartSongs, i),
                leading: Stack(children: [
                  Container(width: 36, height: 36,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(6),
                      gradient: LinearGradient(colors: isPlay ? [Colors.pink.shade400, Colors.purple.shade400] : [Colors.blueGrey.shade700, Colors.blueGrey.shade800])),
                    child: Center(child: isDL ? const Icon(Icons.downloading_rounded, color: Colors.white70, size: 16) : Text('${s.rank}', style: TextStyle(color: Colors.white.withValues(alpha: s.rank <= 3 ? 1.0 : 0.6), fontSize: s.rank <= 3 ? 16 : 12, fontWeight: s.rank <= 3 ? FontWeight.bold : FontWeight.normal))),
                  ),
                  if (_selectMode)
                    Positioned(top: 0, right: 0, child: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? Colors.pink : Colors.white38, size: 14)),
                ]),
                title: Row(children: [
                  Expanded(child: Text(s.title, style: TextStyle(color: isPlay ? Colors.pink.shade300 : Colors.white, fontSize: 12, fontWeight: isPlay ? FontWeight.w600 : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (s.fee > 0) Container(margin: const EdgeInsets.only(left: 4), padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0), decoration: BoxDecoration(color: s.feeColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3), border: Border.all(color: s.feeColor.withValues(alpha: 0.3))), child: Text(s.feeLabel, style: TextStyle(color: s.feeColor, fontSize: 8, fontWeight: FontWeight.w600))),
                ]),
                subtitle: Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0), margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(3)), child: Text(s.source.toUpperCase(), style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8, fontWeight: FontWeight.w600))),
                  if (s.duration != null && s.duration! > 0) ...[
                    Icon(Icons.access_time_rounded, size: 9, color: Colors.white.withValues(alpha: 0.2)),
                    const SizedBox(width: 2),
                    Text('${(s.duration! / 60000).floor()}:${((s.duration! % 60000) / 1000).floor().toString().padLeft(2, "0")}', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 9)),
                    const SizedBox(width: 6),
                  ],
                  Expanded(child: Text(s.artist, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
                trailing: _selectMode ? null : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isPlay) const Icon(Icons.volume_up_rounded, color: Colors.pink, size: 16)
                  else IconButton(icon: const Icon(Icons.download_rounded, color: Colors.white30, size: 18), onPressed: isDL ? null : () => _download(s), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30)),
                  IconButton(icon: Icon(Icons.play_circle_outline_rounded, color: isPlay ? Colors.pink : Colors.white38, size: 18), onPressed: () => _playChartList(_chartSongs, i), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30)),
                ]),
              ),
            ),
          );
        },
      ),
    );
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
      final isSelected = _selectedIds.contains('${s.id}_${s.source}');
      return GestureDetector(
        onLongPress: () { setState(() { _selectMode = true; _selectedIds.add('${s.id}_${s.source}'); }); },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? Colors.pink.withValues(alpha: 0.1) : (isPlay ? Colors.pink.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(8),
            border: isSelected ? Border.all(color: Colors.pink.withValues(alpha: 0.4)) : (isPlay ? Border.all(color: Colors.pink.withValues(alpha: 0.3)) : null),
          ),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            visualDensity: VisualDensity.compact,
            onTap: _selectMode ? () {
              setState(() {
                final key = '${s.id}_${s.source}';
                if (_selectedIds.contains(key)) _selectedIds.remove(key);
                else _selectedIds.add(key);
                if (_selectedIds.isEmpty) _selectMode = false;
              });
            } : () => _playOnline(s),
            leading: Container(width: 36, height: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), gradient: LinearGradient(colors: isPlay ? [Colors.pink.shade400, Colors.purple.shade400] : [Colors.blueGrey.shade700, Colors.blueGrey.shade800])), child: Icon(isDL ? Icons.downloading_rounded : (_selectMode ? (isSelected ? Icons.check_circle : Icons.circle_outlined) : Icons.music_note_rounded), color: Colors.white.withValues(alpha: 0.7), size: 18)),
            title: Row(children: [
              Expanded(child: Text(s.title, style: TextStyle(color: isPlay ? Colors.pink.shade300 : Colors.white, fontSize: 12, fontWeight: isPlay ? FontWeight.w600 : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (s.fee > 0) Container(margin: const EdgeInsets.only(left: 4), padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0), decoration: BoxDecoration(color: s.feeColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3), border: Border.all(color: s.feeColor.withValues(alpha: 0.3))), child: Text(s.feeLabel, style: TextStyle(color: s.feeColor, fontSize: 8, fontWeight: FontWeight.w600))),
            ]),
            subtitle: Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0), margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(3)), child: Text(s.source.toUpperCase(), style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8, fontWeight: FontWeight.w600))),
              if (s.duration != null && s.duration! > 0) ...[
                Icon(Icons.access_time_rounded, size: 9, color: Colors.white.withValues(alpha: 0.2)),
                const SizedBox(width: 2),
                Text('${(s.duration! / 60000).floor()}:${((s.duration! % 60000) / 1000).floor().toString().padLeft(2, "0")}', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 9)),
                const SizedBox(width: 6),
              ],
              Expanded(child: Text(s.artist, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            trailing: _selectMode ? null : Row(mainAxisSize: MainAxisSize.min, children: [
              if (isPlay) const Icon(Icons.volume_up_rounded, color: Colors.pink, size: 16)
              else IconButton(icon: const Icon(Icons.download_rounded, color: Colors.white30, size: 18), onPressed: isDL ? null : () => _download(s), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30)),
              IconButton(icon: Icon(Icons.play_circle_outline_rounded, color: isPlay ? Colors.pink : Colors.white38, size: 18), onPressed: () => _playOnline(s), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30)),
            ]),
          ),
        ),
      );
    }));
  }

  Widget _buildDownloadBubbles() {
    return Positioned(
      left: 16, right: 16, bottom: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _downloadBubbles.asMap().entries.map((e) {
          final b = e.value;
          return Padding(
            padding: EdgeInsets.only(bottom: e.key == 0 ? 8.0 : 0),
            child: DownloadBubble(
              key: b['key'],
              title: b['title'] as String,
              isSuccess: b['success'] as bool,
              size: b['size'] as String?,
              onDismiss: () {
                if (mounted) setState(() => _downloadBubbles.remove(b));
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

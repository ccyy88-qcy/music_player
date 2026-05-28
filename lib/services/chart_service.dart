import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'online_music_service.dart';

/// 排行榜歌曲（扩展OnlineSong，增加排名字段）
class ChartSong extends OnlineSong {
  final int rank;
  final String? hotScore;

  const ChartSong({
    required super.id,
    required super.title,
    required super.artist,
    super.album,
    super.coverUrl,
    super.source,
    super.duration,
    super.fee,
    required this.rank,
    this.hotScore,
  });
}

/// 排行榜分类信息
class ChartCategory {
  final String id;
  final String name;
  final String icon;

  const ChartCategory(this.id, this.name, this.icon);
}

/// 网易云排行榜
class NeteaseChart {
  static const sourceKey = 'netease';

  static List<ChartCategory> get categories => [
    ChartCategory('19723756', '飙升榜', '🚀'),
    ChartCategory('3779629', '热歌榜', '🔥'),
    ChartCategory('2884035', '原创榜', '✍️'),
    ChartCategory('3778678', '经典榜', '🎼'),
    ChartCategory('5213838', '电音榜', '🎧'),
    ChartCategory('991319590', 'UK排行榜', '🇬🇧'),
    ChartCategory('2250011882', '抖音排行榜', '📱'),
    ChartCategory('71384707', '古典榜', '🎻'),
  ];

  static Future<List<ChartSong>> getChart(String topId) async {
    final url = 'https://music.163.com/api/playlist/detail?id=$topId';
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'https://music.163.com/',
        'Cookie': 'NMTID=00OKlEq2nVNMgNF05CFI1JjHgQehWAAAQJZovaw',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final d = jsonDecode(resp.body);
      final tracks = d['result']?['tracks'] as List?;
      if (tracks == null || tracks.isEmpty) return [];
      final list = <ChartSong>[];
      for (int i = 0; i < tracks.length; i++) {
        final s = tracks[i];
        if (s == null) continue;
        final name = s['name'] ?? '';
        if (name.isEmpty) continue;
        final artists = s['artists'] as List?;
        final artistStr = artists?.map((a) => a['name'] ?? '').join('/') ?? '';
        final album = s['album'] as Map?;
        final id = s['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        list.add(ChartSong(
          id: id, title: name, artist: artistStr,
          album: album?['name'] ?? '',
          coverUrl: album?['picUrl'],
          source: 'netease',
          duration: s['duration'] as int?,
          fee: s['fee'] as int? ?? 0,
          rank: i + 1,
          hotScore: s['score']?.toString(),
        ));
      }
      return list;
    } catch (_) { return []; }
  }
}

/// QQ音乐排行榜
class QQChart {
  static const sourceKey = 'qq';

  static List<ChartCategory> get categories => [
    ChartCategory('26', '热歌榜', '🔥'),
    ChartCategory('27', '新歌榜', '🆕'),
    ChartCategory('4', '流行指数榜', '📊'),
    ChartCategory('52', '台湾Hito榜', '🇹🇼'),
    ChartCategory('62', '美国Billboard榜', '🇺🇸'),
    ChartCategory('58', '韩国Melon榜', '🇰🇷'),
    ChartCategory('57', '日本公信榜', '🇯🇵'),
    ChartCategory('28', '网络歌曲榜', '🌐'),
  ];

  static Future<List<ChartSong>> getChart(String topId) async {
    final url = 'https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg?topid=$topId&format=json';
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'https://y.qq.com/',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final d = jsonDecode(resp.body);
      final songList = d['songlist'] as List?;
      if (songList == null || songList.isEmpty) return [];
      final list = <ChartSong>[];
      for (int i = 0; i < songList.length; i++) {
        final s = songList[i]['data'];
        if (s == null) continue;
        final name = s['songname'] ?? '';
        if (name.isEmpty) continue;
        final artists = s['singer'] as List?;
        final artistStr = artists?.map((a) => a['name'] ?? '').join('/') ?? '';
        final songmid = s['songmid']?.toString() ?? '';
        if (songmid.isEmpty) continue;
        list.add(ChartSong(
          id: songmid, title: name, artist: artistStr,
          album: s['albumname'] ?? '',
          coverUrl: s['albummid'] != null ? 'https://y.gtimg.cn/music/photo_new/T002R300x300M000${s["albummid"]}.jpg' : null,
          source: 'qq',
          duration: (s['interval'] as int?) != null ? (s['interval'] as int) * 1000 : null,
          rank: i + 1,
          hotScore: s['listenCount']?.toString(),
        ));
      }
      return list;
    } catch (_) { return []; }
  }
}

/// 酷狗排行榜
class KugouChart {
  static const sourceKey = 'kugou';

  static List<ChartCategory> get categories => [
    ChartCategory('6666', '飙升榜', '🚀'),
    ChartCategory('8888', 'TOP500', '🏆'),
    ChartCategory('37361', '华语榜', '🇨🇳'),
    ChartCategory('37362', '欧美榜', '🇪🇺'),
    ChartCategory('37363', '韩国榜', '🇰🇷'),
    ChartCategory('37364', '日本榜', '🇯🇵'),
  ];

  static Future<List<ChartSong>> getChart(String rankId) async {
    final url = 'http://mobilecdn.kugou.com/api/v3/rank/song?rankid=$rankId&pagesize=50';
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final d = jsonDecode(resp.body);
      final songs = d['data']?['info'] as List?;
      if (songs == null || songs.isEmpty) return [];
      final list = <ChartSong>[];
      for (int i = 0; i < songs.length; i++) {
        final s = songs[i];
        final name = s['songname'] ?? '';
        if (name.isEmpty) continue;
        final hash = s['hash']?.toString() ?? '';
        if (hash.isEmpty) continue;
        list.add(ChartSong(
          id: hash, title: name,
          artist: s['singername'] ?? '',
          album: s['album_name'] ?? '',
          coverUrl: s['album_img']?.toString().replaceAll('{size}', '300'),
          source: 'kugou',
          duration: (s['duration'] as int?) != null ? (s['duration'] as int) * 1000 : null,
          rank: i + 1,
        ));
      }
      return list;
    } catch (_) { return []; }
  }
}

/// 批量下载任务状态
enum DownloadTaskStatus { pending, checking, downloading, success, failed, skipped }

class DownloadTask {
  final OnlineSong song;
  DownloadTaskStatus status;
  String? filePath;
  String? errorMsg;
  int progress; // 0-100

  DownloadTask(this.song, {this.status = DownloadTaskStatus.pending, this.filePath, this.errorMsg, this.progress = 0});

  String get statusLabel {
    switch (status) {
      case DownloadTaskStatus.pending: return '等待中';
      case DownloadTaskStatus.checking: return '检查中';
      case DownloadTaskStatus.downloading: return '下载中 $progress%';
      case DownloadTaskStatus.success: return '✅ 完成';
      case DownloadTaskStatus.failed: return '❌ 失败';
      case DownloadTaskStatus.skipped: return '⏭️ 跳过';
    }
  }
}

/// 批量下载管理器
class BatchDownloadManager {
  final MusicSource source;
  final String saveDir;
  final void Function(DownloadTask task)? onTaskUpdate;
  final void Function(int done, int total)? onProgress;

  BatchDownloadManager({required this.source, required this.saveDir, this.onTaskUpdate, this.onProgress});

  /// 批量下载：先检查可播放性，过滤不可用的，再下载
  Future<List<DownloadTask>> downloadAll(List<OnlineSong> songs) async {
    final tasks = songs.map((s) => DownloadTask(s)).toList();
    final dir = Directory(saveDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    int done = 0;
    final total = songs.length;

    for (int i = 0; i < songs.length; i++) {
      final task = tasks[i];
      final song = task.song;

      // 检查是否已下载
      final safe = '${song.title} - ${song.artist}'.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final path = '$saveDir/$safe.mp3';
      if (File(path).existsSync()) {
        task.status = DownloadTaskStatus.skipped;
        task.filePath = path;
        task.errorMsg = '已存在';
        onTaskUpdate?.call(task);
        done++; onProgress?.call(done, total);
        continue;
      }

      // 第一步：获取播放地址（检查可播放性）
      task.status = DownloadTaskStatus.checking;
      onTaskUpdate?.call(task);

      String? playUrl;
      try {
        playUrl = await source.getPlayUrl(song);
      } catch (_) {}

      if (playUrl == null || !playUrl.startsWith('http')) {
        task.status = DownloadTaskStatus.failed;
        task.errorMsg = '无法获取播放地址（可能需要VIP）';
        onTaskUpdate?.call(task);
        done++; onProgress?.call(done, total);
        continue;
      }

      // 第二步：下载
      task.status = DownloadTaskStatus.downloading;
      task.progress = 0;
      onTaskUpdate?.call(task);

      try {
        final result = await DownloadManager.downloadSong(song, playUrl, saveDir);
        if (result != null) {
          task.status = DownloadTaskStatus.success;
          task.filePath = result;
          task.progress = 100;
        } else {
          task.status = DownloadTaskStatus.failed;
          task.errorMsg = '下载失败（文件校验不通过）';
        }
      } catch (e) {
        task.status = DownloadTaskStatus.failed;
        task.errorMsg = '下载异常: $e';
      }

      onTaskUpdate?.call(task);
      done++; onProgress?.call(done, total);
    }

    return tasks;
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'storage_manager.dart';

/// 在线歌曲数据
class OnlineSong {
  final String id;          // 平台歌曲ID
  final String title;
  final String artist;
  final String album;
  final String? coverUrl;
  final String? lyricUrl;
  final String source;      // 来源平台名
  final int? duration;

  const OnlineSong({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.coverUrl,
    this.lyricUrl,
    this.source = '',
    this.duration,
  });

  factory OnlineSong.fromJson(Map<String, dynamic> json, {String source = ''}) {
    return OnlineSong(
      id: (json['id'] ?? json['songid'] ?? json['song_id'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? json['songname'] ?? '').toString(),
      artist: (json['artist'] ?? json['author'] ?? json['singer'] ?? '').toString(),
      album: (json['album'] ?? json['albumname'] ?? '').toString(),
      coverUrl: json['cover'] ?? json['pic'] ?? json['coverUrl'],
      lyricUrl: json['lyric'] ?? json['lrcurl'] ?? json['lyricUrl'],
      source: source,
      duration: json['duration'] is int
          ? json['duration']
          : int.tryParse((json['duration'] ?? '0').toString()),
    );
  }
}

/// 音乐源接口
abstract class MusicSource {
  String get name;
  String get baseUrl;

  /// 搜索歌曲
  Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20});

  /// 获取播放URL
  Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'});

  /// 获取歌词
  Future<String?> getLyric(OnlineSong song);

  /// 获取封面图
  Future<String?> getCoverUrl(OnlineSong song);
}

/// ============================================
/// 小熊猫风格音乐源 (免费API聚合)
/// 兼容主流格式：网易云/QQ/酷狗/酷我等解析接口
/// ============================================
class XiaoPandaSource extends MusicSource {
  final String _apiUrl;

  XiaoPandaSource({String apiUrl = ''}) : _apiUrl = apiUrl;

  @override
  String get name => '小熊猫音乐';

  @override
  String get baseUrl => _apiUrl;

  /// 内置多源降级搜索
  @override
  Future<List<OnlineSong>> search(String keyword,
      {int page = 1, int limit = 20}) async {
    final results = <OnlineSong>[];

    // 源1: 通用音乐搜索API (JSONP风格)
    try {
      final songs = await _searchSource1(keyword, page, limit);
      results.addAll(songs);
    } catch (_) {}

    // 源2: 备用搜索API
    if (results.isEmpty) {
      try {
        final songs = await _searchSource2(keyword, page, limit);
        results.addAll(songs);
      } catch (_) {}
    }

    return results;
  }

  /// 源1 - 通用免费音乐搜索API
  Future<List<OnlineSong>> _searchSource1(
      String keyword, int page, int limit) async {
    final query = Uri.encodeComponent(keyword);
    final url = 'https://api.xmp3.cc/search?key=$query&page=$page&limit=$limit';

    final resp = await http.get(
      Uri.parse(url),
      headers: _headers(),
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) return [];

    final data = jsonDecode(resp.body);
    final list = (data['data'] ?? data['list'] ?? data['result'] ?? []) as List;

    return list.map((item) {
      final song = OnlineSong.fromJson(item as Map<String, dynamic>, source: '源1');
      return song;
    }).toList();
  }

  /// 源2 - 备用API
  Future<List<OnlineSong>> _searchSource2(
      String keyword, int page, int limit) async {
    final query = Uri.encodeComponent(keyword);
    final url =
        'https://api.itooi.cn/music/tencent/search?keyword=$query&page=$page&limit=$limit';

    final resp = await http.get(
      Uri.parse(url),
      headers: _headers(),
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) return [];

    final data = jsonDecode(resp.body);
    final list = (data['data'] ?? data['list'] ?? data['result'] ?? []) as List;

    return list.map((item) {
      return OnlineSong.fromJson(item as Map<String, dynamic>, source: '源2');
    }).toList();
  }

  /// 获取播放URL
  @override
  Future<String?> getPlayUrl(OnlineSong song,
      {String quality = '320'}) async {
    // 尝试多个解析源
    for (final resolver in _resolvers) {
      try {
        final url = await resolver(song.id, quality);
        if (url != null && url.isNotEmpty && url.startsWith('http')) {
          return url;
        }
      } catch (_) {}
    }
    return null;
  }

  /// 多源URL解析器
  final List<Future<String?> Function(String id, String quality)> _resolvers = [
    _resolveUrl1,
    _resolveUrl2,
    _resolveUrl3,
  ];

  static Future<String?> _resolveUrl1(String id, String quality) async {
    final url =
        'https://api.xmp3.cc/url?id=$id&quality=$quality';
    final resp = await http.get(Uri.parse(url),
        headers: _headers()).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    return data['url'] ?? data['data']?['url'] ?? data['playUrl'];
  }

  static Future<String?> _resolveUrl2(String id, String quality) async {
    final url =
        'https://api.itooi.cn/music/tencent/url?id=$id&quality=$quality';
    final resp = await http.get(Uri.parse(url),
        headers: _headers()).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    return data['url'] ?? data['data']?['url'] ?? data['playUrl'];
  }

  static Future<String?> _resolveUrl3(String id, String quality) async {
    final url =
        'https://api.uomg.com/api/get.music.tencent?id=$id';
    final resp = await http.get(Uri.parse(url),
        headers: _headers()).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    return data['url'] ?? data['data']?['url'];
  }

  /// 获取歌词
  @override
  Future<String?> getLyric(OnlineSong song) async {
    for (final lyricFetcher in _lyricFetchers) {
      try {
        final lrc = await lyricFetcher(song.id);
        if (lrc != null && lrc.isNotEmpty) return lrc;
      } catch (_) {}
    }
    return null;
  }

  final List<Future<String?> Function(String id)> _lyricFetchers = [
    _fetchLyric1,
    _fetchLyric2,
  ];

  static Future<String?> _fetchLyric1(String id) async {
    final url = 'https://api.xmp3.cc/lyric?id=$id';
    final resp = await http.get(Uri.parse(url),
        headers: _headers()).timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    return data['lyric'] ?? data['lrc'] ?? data['data']?['lyric'];
  }

  static Future<String?> _fetchLyric2(String id) async {
    final url = 'https://api.itooi.cn/music/tencent/lrc?id=$id';
    final resp = await http.get(Uri.parse(url),
        headers: _headers()).timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    return data['lyric'] ?? data['lrc'] ?? data['data']?['lyric'];
  }

  /// 获取封面（在线源通常自带，这里提供兜底）
  @override
  Future<String?> getCoverUrl(OnlineSong song) async {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      return song.coverUrl;
    }
    return null;
  }

  static Map<String, String> _headers() => {
    'Accept': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  };
}

// ============================================
// 全局单例（支持自定义源）
// ============================================
XiaoPandaSource? _defaultSource;

Future<MusicSource> getMusicSourceAsync() async {
  // 从存储加载自定义源
  final store = await storage;
  final customSources = store.getMusicSources();

  if (customSources.isNotEmpty) {
    // 有自定义源时使用聚合源
    final sources = <MusicSource>[
      if (_defaultSource == null) _defaultSource = XiaoPandaSource(),
      _defaultSource!,
      for (final s in customSources)
        CustomApiSource(
          name: s['name'] ?? '自定义源',
          searchUrl: '${s['url'] ?? ''}/search?key={keyword}&page={page}&limit={limit}',
          playUrl: '${s['url'] ?? ''}/url?id={id}&quality={quality}',
          lyricUrl: '${s['url'] ?? ''}/lyric?id={id}',
        ),
    ];
    return AggregateSource(sources);
  }
  _defaultSource ??= XiaoPandaSource();
  return _defaultSource!;
}

/// 同步获取（用于不依赖自定义源的场景）
MusicSource get musicSource {
  _defaultSource ??= XiaoPandaSource();
  return _defaultSource!;
}

/// ============================================
/// 自定义API源
/// ============================================
class CustomApiSource extends MusicSource {
  final String _name;
  final String _searchUrl;
  final String _playUrl;
  final String _lyricUrl;

  CustomApiSource({
    required String name,
    required String searchUrl,
    required String playUrl,
    required String lyricUrl,
  })  : _name = name,
        _searchUrl = searchUrl,
        _playUrl = playUrl,
        _lyricUrl = lyricUrl;

  @override
  String get name => _name;

  @override
  String get baseUrl => _searchUrl;

  @override
  Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    final url = _searchUrl
        .replaceAll('{keyword}', Uri.encodeComponent(keyword))
        .replaceAll('{page}', page.toString())
        .replaceAll('{limit}', limit.toString());
    final resp = await http.get(Uri.parse(url),
        headers: XiaoPandaSource._headers()).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body);
    final list = (data['data'] ?? data['list'] ?? data['result'] ?? []) as List;
    return list.map((e) => OnlineSong.fromJson(e as Map<String, dynamic>, source: _name)).toList();
  }

  @override
  Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    final url = _playUrl
        .replaceAll('{id}', song.id)
        .replaceAll('{quality}', quality);
    final resp = await http.get(Uri.parse(url),
        headers: XiaoPandaSource._headers()).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    return data['url'] ?? data['data']?['url'] ?? data['playUrl'];
  }

  @override
  Future<String?> getLyric(OnlineSong song) async {
    final url = _lyricUrl.replaceAll('{id}', song.id);
    final resp = await http.get(Uri.parse(url),
        headers: XiaoPandaSource._headers()).timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    return data['lyric'] ?? data['lrc'] ?? data['data']?['lyric'];
  }

  @override
  Future<String?> getCoverUrl(OnlineSong song) async => song.coverUrl;
}

/// ============================================
/// 聚合源（多源并发搜索）
/// ============================================
class AggregateSource extends MusicSource {
  final List<MusicSource> _sources;

  AggregateSource(this._sources);

  @override
  String get name => _sources.map((s) => s.name).join('+');

  @override
  String get baseUrl => '';

  @override
  Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    final results = <OnlineSong>[];
    for (final src in _sources) {
      try {
        final songs = await src.search(keyword, page: page, limit: limit);
        results.addAll(songs);
      } catch (_) {}
      if (results.isNotEmpty) break; // 第一个成功就返回
    }
    return results;
  }

  @override
  Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    for (final src in _sources) {
      try {
        final url = await src.getPlayUrl(song, quality: quality);
        if (url != null && url.startsWith('http')) return url;
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<String?> getLyric(OnlineSong song) async {
    for (final src in _sources) {
      try {
        final lrc = await src.getLyric(song);
        if (lrc != null && lrc.isNotEmpty) return lrc;
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<String?> getCoverUrl(OnlineSong song) async => song.coverUrl;
}

/// ============================================
/// 下载管理器
/// ============================================
class DownloadManager {
  static Future<String?> downloadSong(
    OnlineSong song,
    String playUrl,
    String saveDir,
  ) async {
    try {
      final dir = Directory(saveDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);

      // 清理文件名
      final safeName = '${song.title} - ${song.artist}'
          .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final filePath = '$saveDir/$safeName.mp3';

      // 检查是否已存在
      if (File(filePath).existsSync()) return filePath;

      final resp = await http.get(
        Uri.parse(playUrl),
        headers: XiaoPandaSource._headers(),
      ).timeout(const Duration(minutes: 3));

      if (resp.statusCode != 200) return null;

      final file = File(filePath);
      await file.writeAsBytes(resp.bodyBytes);
      return filePath;
    } catch (e) {
      return null;
    }
  }

  /// 流式下载（大文件友好）
  static Future<String?> downloadStream(
    String url,
    String filePath,
    void Function(double progress)? onProgress,
  ) async {
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(XiaoPandaSource._headers());
      final streamedResp = await request.send().timeout(const Duration(minutes: 3));

      if (streamedResp.statusCode != 200) return null;

      final totalBytes = streamedResp.contentLength ?? 0;
      var downloadedBytes = 0;
      final file = File(filePath);
      final sink = file.openWrite();

      await for (final chunk in streamedResp.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(downloadedBytes / totalBytes);
        }
      }

      await sink.close();
      return filePath;
    } catch (_) {
      return null;
    }
  }
}

/// ============================================
/// JS源文件解析器 — 从JS源文件中提取API URL
/// ============================================

/// 从小熊猫风格JS源文件中提取 API 配置
List<Map<String, String>> parseJsSource(String content) {
  final sources = <Map<String, String>>[];

  // 模式1: var/const 配置对象
  final nameRe = RegExp(r'''['"]name['"]\s*[:=]\s*['"]([^'"]+)['"]''');
  final urlRe = RegExp(r'''https?://[^\s'"`\[\]{}()<>]+\.[^\s'"`\[\]{}()<>]+''');

  // 提取所有URL
  final urls = urlRe.allMatches(content).map((m) => m.group(0)!).toSet();

  // 提取名称
  String name = '导入源';
  final nameMatch = nameRe.firstMatch(content);
  if (nameMatch != null) {
    name = nameMatch.group(1)!;
  }

  // 对每个找到的API URL，尝试作为源
  for (final url in urls) {
    // 过滤明显不是API的URL
    if (url.contains('github.com') || url.contains('example.com') ||
        url.contains('localhost') || url.contains('127.0.0.1')) continue;

    // 提取根URL（去掉路径部分，保留到域名+第一段路径）
    final uri = Uri.tryParse(url);
    if (uri == null) continue;
    final rootUrl = '${uri.scheme}://${uri.host}';
    // 如果路径有 /api 之类，保留第一段
    final segments = uri.pathSegments;
    if (segments.isNotEmpty && segments.first.isNotEmpty) {
      final base = '$rootUrl/${segments.first}';
      sources.add({'name': name, 'url': base});
    } else {
      sources.add({'name': name, 'url': rootUrl});
    }
  }

  // 去重
  final seen = <String>{};
  return sources.where((s) => seen.add(s['url']!)).toList();
}

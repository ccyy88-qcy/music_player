import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'storage_manager.dart';

class OnlineSong {
  final String id, title, artist, album, source;
  final String? coverUrl;
  final int? duration;

  const OnlineSong({
    required this.id, required this.title, required this.artist,
    this.album = '', this.coverUrl, this.source = '', this.duration,
  });

  factory OnlineSong.fromJson(Map<String, dynamic> json, {String source = ''}) {
    return OnlineSong(
      id: (json['id'] ?? json['songid'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? json['songname'] ?? '').toString(),
      artist: (json['artist'] ?? json['author'] ?? json['singer'] ?? (json['ar'] is List ? (json['ar'] as List).map((a) => a is Map ? a['name'] ?? '' : '$a').join('/') : '')).toString(),
      album: (json['album'] is Map ? json['album']['name'] ?? '' : json['album'] ?? '').toString(),
      coverUrl: json['cover'] ?? json['pic'],
      source: source,
      duration: int.tryParse((json['duration'] ?? '0').toString()),
    );
  }
}

abstract class MusicSource {
  String get name;
  Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20});
  Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'});
  Future<String?> getLyric(OnlineSong song);
}

Map<String, String> _headers() => {'Accept': 'application/json', 'User-Agent': 'Mozilla/5.0'};

/// ==================== Meting源 ====================
class MetingSource extends MusicSource {
  @override String get name => 'Meting';

  @override
  Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    final q = Uri.encodeComponent(keyword);
    final url = 'https://api.injahow.cn/meting/?server=netease&type=search&id=$q&limit=$limit&page=$page';
    final resp = await http.get(Uri.parse(url), headers: _headers()).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    try {
      final data = jsonDecode(resp.body);
      final list = (data is List) ? data : (data['result'] ?? data['songs'] ?? []);
      if (list is! List || list.isEmpty) return [];
      return list.map((e) => OnlineSong.fromJson(e as Map<String, dynamic>, source: 'netease')).toList();
    } catch (_) { return []; }
  }

  @override
  Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    final url = 'https://api.injahow.cn/meting/?server=netease&type=url&id=${song.id}&level=standard';
    final resp = await http.get(Uri.parse(url), headers: _headers()).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    try {
      final u = jsonDecode(resp.body)['url'];
      return u?.toString();
    } catch (_) { return null; }
  }

  @override
  Future<String?> getLyric(OnlineSong song) async {
    final url = 'https://api.injahow.cn/meting/?server=netease&type=lyric&id=${song.id}';
    final resp = await http.get(Uri.parse(url), headers: _headers()).timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) return null;
    try { return jsonDecode(resp.body)['lyric']?.toString() ?? jsonDecode(resp.body)['lrc']?.toString(); } catch (_) { return null; }
  }
}

/// ==================== 自定义源 ====================
class CustomApiSource extends MusicSource {
  final String _name, _searchUrl, _playUrl, _lyricUrl;
  CustomApiSource({required String name, required String searchUrl, required String playUrl, required String lyricUrl})
    : _name = name, _searchUrl = searchUrl, _playUrl = playUrl, _lyricUrl = lyricUrl;
  @override String get name => _name;

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    final u = _searchUrl.replaceAll('{keyword}', Uri.encodeComponent(keyword)).replaceAll('{page}', '$page').replaceAll('{limit}', '$limit');
    final r = await http.get(Uri.parse(u), headers: _headers()).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return [];
    try { final l = (jsonDecode(r.body)['data'] ?? jsonDecode(r.body)['list'] ?? []) as List; return l.map((e) => OnlineSong.fromJson(e as Map<String, dynamic>, source: _name)).toList(); } catch (_) { return []; }
  }
  @override Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    final u = _playUrl.replaceAll('{id}', song.id).replaceAll('{quality}', quality);
    final r = await http.get(Uri.parse(u), headers: _headers()).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    try { return (jsonDecode(r.body)['url'] ?? jsonDecode(r.body)['data']?['url'])?.toString(); } catch (_) { return null; }
  }
  @override Future<String?> getLyric(OnlineSong song) async {
    final u = _lyricUrl.replaceAll('{id}', song.id);
    final r = await http.get(Uri.parse(u), headers: _headers()).timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) return null;
    try { return (jsonDecode(r.body)['lyric'] ?? jsonDecode(r.body)['lrc'])?.toString(); } catch (_) { return null; }
  }
}

/// ==================== 全局聚合 ====================
Future<MusicSource> getMusicSourceAsync() async {
  final store = await storage;
  final custom = store.getMusicSources();
  final srcs = <MusicSource>[MetingSource()];
  for (final s in custom) {
    srcs.add(CustomApiSource(
      name: s['name'] ?? '自定义', searchUrl: '${s['url']}/search?key={keyword}&page={page}&limit={limit}',
      playUrl: '${s['url']}/url?id={id}&quality={quality}', lyricUrl: '${s['url']}/lyric?id={id}',
    ));
  }
  return AggregateSource(srcs);
}

MusicSource get musicSource => MetingSource();

class AggregateSource extends MusicSource {
  final List<MusicSource> _srcs;
  AggregateSource(this._srcs);
  @override String get name => _srcs.map((s) => s.name).join('+');
  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    for (final s in _srcs) {
      try { final r = await s.search(keyword, page: page, limit: limit); if (r.isNotEmpty) return r; } catch (_) {}
    }
    return [];
  }
  @override Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    for (final s in _srcs) {
      try { final u = await s.getPlayUrl(song, quality: quality); if (u != null) return u; } catch (_) {}
    }
    return null;
  }
  @override Future<String?> getLyric(OnlineSong song) async {
    for (final s in _srcs) {
      try { final l = await s.getLyric(song); if (l != null) return l; } catch (_) {}
    }
    return null;
  }
}

/// ==================== 下载 ====================
class DownloadManager {
  static Future<String?> downloadSong(OnlineSong song, String playUrl, String saveDir) async {
    try {
      final dir = Directory(saveDir); if (!dir.existsSync()) dir.createSync(recursive: true);
      final safe = '${song.title} - ${song.artist}'.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final path = '$saveDir/$safe.mp3';
      if (File(path).existsSync()) return path;
      final r = await http.get(Uri.parse(playUrl), headers: _headers()).timeout(const Duration(minutes: 3));
      if (r.statusCode != 200) return null;
      await File(path).writeAsBytes(r.bodyBytes); return path;
    } catch (_) { return null; }
  }
}

/// ==================== JS解析 ====================
List<Map<String, String>> parseJsSource(String content) {
  final sources = <Map<String, String>>[];
  final nameRe = RegExp(r'''['"]name['"]\s*[:=]\s*['"]([^'"]+)['"]''');
  final urlRe = RegExp(r'''https?://[^\s'"`\[\]{}()<>]+\.[^\s'"`\[\]{}()<>]+''');
  final urls = urlRe.allMatches(content).map((m) => m.group(0)!).toSet();
  String name = '导入源';
  final nm = nameRe.firstMatch(content); if (nm != null) name = nm.group(1)!;
  for (final url in urls) {
    if (url.contains('github.com') || url.contains('example.com') || url.contains('localhost')) continue;
    final uri = Uri.tryParse(url); if (uri == null) continue;
    final seg = uri.pathSegments;
    final base = seg.isNotEmpty && seg.first.isNotEmpty ? '${uri.scheme}://${uri.host}/${seg.first}' : '${uri.scheme}://${uri.host}';
    sources.add({'name': name, 'url': base});
  }
  final seen = <String>{};
  return sources.where((s) => seen.add(s['url']!)).toList();
}

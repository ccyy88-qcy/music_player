import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'storage_manager.dart';

/// 在线歌曲数据
class OnlineSong {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? coverUrl;
  final String? lyricUrl;
  final String source;
  final int? duration;

  const OnlineSong({
    required this.id, required this.title, required this.artist,
    this.album = '', this.coverUrl, this.lyricUrl, this.source = '', this.duration,
  });

  factory OnlineSong.fromJson(Map<String, dynamic> json, {String source = ''}) {
    return OnlineSong(
      id: (json['id'] ?? json['songid'] ?? json['song_id'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? json['songname'] ?? '').toString(),
      artist: (json['artist'] ?? json['author'] ?? json['singer'] ?? json['ar']?.toString() ?? '').toString(),
      album: (json['album'] ?? json['albumname'] ?? json['al']?.toString() ?? '').toString(),
      coverUrl: json['cover'] ?? json['pic'] ?? json['coverUrl'],
      lyricUrl: json['lyric'] ?? json['lrcurl'],
      source: source,
      duration: json['duration'] is int ? json['duration'] : int.tryParse((json['duration'] ?? '0').toString()),
    );
  }
}

abstract class MusicSource {
  String get name;
  Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20});
  Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'});
  Future<String?> getLyric(OnlineSong song);
  Future<String?> getCoverUrl(OnlineSong song);
}

/// ============================================
/// 多源聚合搜索器
/// ============================================
class XiaoPandaSource extends MusicSource {
  @override String get name => '聚合搜索';

  @override
  Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    // 源1: Meting API (netease)
    try {
      final q = Uri.encodeComponent(keyword);
      final url = 'https://api.injahow.cn/meting/?server=netease&type=search&id=$q&limit=$limit&page=$page';
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final list = data is List ? data : (data['result'] ?? data['data'] ?? data['songs'] ?? []);
        if (list is List && list.isNotEmpty) {
          return list.map((e) => _parseMeting(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}

    // 源2: 备用API
    try {
      final q = Uri.encodeComponent(keyword);
      final url = 'https://api.uomg.com/api/music.search?key=$q&page=$page&limit=$limit';
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final list = data['data'] ?? data['list'] ?? data['result'] ?? [];
        if (list is List && list.isNotEmpty) {
          return list.map((e) => OnlineSong.fromJson(e as Map<String, dynamic>, source: '源2')).toList();
        }
      }
    } catch (_) {}

    return [];
  }

  OnlineSong _parseMeting(Map<String, dynamic> item) {
    final artists = item['artist'] ?? item['ar'] ?? '';
    final artistStr = artists is List ? artists.map((a) => a is Map ? (a['name'] ?? '') : '$a').join('/') : '$artists';
    return OnlineSong(
      id: (item['id'] ?? item['songid'] ?? '').toString(),
      title: (item['title'] ?? item['name'] ?? '').toString(),
      artist: artistStr,
      album: item['album'] is Map ? item['album']['name'] ?? '' : (item['album'] ?? '').toString(),
      coverUrl: item['cover'] ?? item['pic'] ?? item['coverUrl'],
      source: 'netease',
    );
  }

  @override
  Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    // 源1: Meting
    try {
      final url = 'https://api.injahow.cn/meting/?server=netease&type=url&id=${song.id}&level=standard';
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final playUrl = data['url'] ?? data['data']?['url'];
        if (playUrl != null && playUrl.toString().startsWith('http')) return playUrl.toString();
      }
    } catch (_) {}

    // 源2
    try {
      final url = 'https://api.uomg.com/api/music.url?id=${song.id}';
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final playUrl = data['url'] ?? data['data']?['url'];
        if (playUrl != null && playUrl.toString().startsWith('http')) return playUrl.toString();
      }
    } catch (_) {}

    return null;
  }

  @override
  Future<String?> getLyric(OnlineSong song) async {
    try {
      final url = 'https://api.injahow.cn/meting/?server=netease&type=lyric&id=${song.id}';
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final lrc = data['lyric'] ?? data['lrc'] ?? data['data']?['lyric'];
        if (lrc != null && lrc.toString().isNotEmpty) return lrc.toString();
      }
    } catch (_) {}
    return null;
  }

  @override Future<String?> getCoverUrl(OnlineSong song) async => song.coverUrl;

  static Map<String, String> _h() => {
    'Accept': 'application/json',
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
  };
}

// ============================================
// 全局单例
// ============================================
XiaoPandaSource? _defaultSrc;
MusicSource? _cachedSrc;
bool _loadedCustom = false;

Future<MusicSource> getMusicSourceAsync() async {
  if (_cachedSrc != null) return _cachedSrc!;

  final store = await storage;
  final custom = store.getMusicSources();

  if (custom.isNotEmpty && !_loadedCustom) {
    _loadedCustom = true;
    final sources = <MusicSource>[
      XiaoPandaSource(),
      for (final s in custom) CustomApiSource(
        name: s['name'] ?? '自定义',
        searchUrl: '${s['url']}/search?key={keyword}&page={page}&limit={limit}',
        playUrl: '${s['url']}/url?id={id}&quality={quality}',
        lyricUrl: '${s['url']}/lyric?id={id}',
      ),
    ];
    _cachedSrc = AggregateSource(sources);
    return _cachedSrc!;
  }

  _defaultSrc ??= XiaoPandaSource();
  return _defaultSrc!;
}

MusicSource get musicSource {
  _defaultSrc ??= XiaoPandaSource();
  return _defaultSrc!;
}

class CustomApiSource extends MusicSource {
  final String _name, _searchUrl, _playUrl, _lyricUrl;
  CustomApiSource({required String name, required String searchUrl, required String playUrl, required String lyricUrl})
    : _name = name, _searchUrl = searchUrl, _playUrl = playUrl, _lyricUrl = lyricUrl;
  @override String get name => _name;
  @override String get baseUrl => _searchUrl;

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    final url = _searchUrl.replaceAll('{keyword}', Uri.encodeComponent(keyword)).replaceAll('{page}', '$page').replaceAll('{limit}', '$limit');
    final resp = await http.get(Uri.parse(url), headers: XiaoPandaSource._h()).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    final list = (jsonDecode(resp.body)['data'] ?? jsonDecode(resp.body)['list'] ?? jsonDecode(resp.body)['result'] ?? []) as List;
    return list.map((e) => OnlineSong.fromJson(e as Map<String, dynamic>, source: _name)).toList();
  }
  @override Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    final url = _playUrl.replaceAll('{id}', song.id).replaceAll('{quality}', quality);
    final resp = await http.get(Uri.parse(url), headers: XiaoPandaSource._h()).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    return (jsonDecode(resp.body)['url'] ?? jsonDecode(resp.body)['data']?['url'])?.toString();
  }
  @override Future<String?> getLyric(OnlineSong song) async {
    final url = _lyricUrl.replaceAll('{id}', song.id);
    final resp = await http.get(Uri.parse(url), headers: XiaoPandaSource._h()).timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) return null;
    return (jsonDecode(resp.body)['lyric'] ?? jsonDecode(resp.body)['lrc'])?.toString();
  }
  @override Future<String?> getCoverUrl(OnlineSong song) async => song.coverUrl;
}

class AggregateSource extends MusicSource {
  final List<MusicSource> _sources;
  AggregateSource(this._sources);
  @override String get name => _sources.map((s) => s.name).join('+');
  @override String get baseUrl => '';
  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    for (final src in _sources) {
      try { final r = await src.search(keyword, page: page, limit: limit); if (r.isNotEmpty) return r; } catch (_) {}
    }
    return [];
  }
  @override Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    for (final src in _sources) {
      try { final u = await src.getPlayUrl(song, quality: quality); if (u != null) return u; } catch (_) {}
    }
    return null;
  }
  @override Future<String?> getLyric(OnlineSong song) async {
    for (final src in _sources) {
      try { final l = await src.getLyric(song); if (l != null) return l; } catch (_) {}
    }
    return null;
  }
  @override Future<String?> getCoverUrl(OnlineSong song) async => song.coverUrl;
}

class DownloadManager {
  static Future<String?> downloadSong(OnlineSong song, String playUrl, String saveDir) async {
    try {
      final dir = Directory(saveDir); if (!dir.existsSync()) dir.createSync(recursive: true);
      final safe = '${song.title} - ${song.artist}'.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final path = '$saveDir/$safe.mp3';
      if (File(path).existsSync()) return path;
      final resp = await http.get(Uri.parse(playUrl), headers: XiaoPandaSource._h()).timeout(const Duration(minutes: 3));
      if (resp.statusCode != 200) return null;
      await File(path).writeAsBytes(resp.bodyBytes);
      return path;
    } catch (_) { return null; }
  }
}

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

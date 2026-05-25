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
      title: (json['name'] ?? json['title'] ?? json['songname'] ?? '').toString(),
      artist: (json['artist'] ?? json['author'] ?? json['singer'] ?? (json['ar'] is List ? (json['ar'] as List).map((a) => a is Map ? a['name'] ?? '' : '$a').join('/') : '')).toString(),
      album: (json['album'] is Map ? json['album']['name'] ?? '' : json['album'] ?? '').toString(),
      coverUrl: json['cover'] ?? json['pic'] ?? json['albumPic'],
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

Map<String, String> _h() => {
  'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  'Referer': 'https://music.163.com/',
  'X-Requested-With': 'XMLHttpRequest',
};

/// ========== 网易云音乐 API ==========
class NeteaseSource extends MusicSource {
  @override String get name => '网易云';

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, limit = 20}) async {
    final url = 'https://music.163.com/api/search/get?s=${Uri.encodeComponent(keyword)}&type=1&limit=$limit&offset=${(page - 1) * limit}';
    final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    try {
      final d = jsonDecode(resp.body);
      final songs = d['result']?['songs'] as List?;
      if (songs == null || songs.isEmpty) return [];
      return songs.map((s) {
        final artists = s['artists'] as List?;
        final artistStr = artists?.map((a) => a['name'] ?? '').join('/') ?? '';
        final album = s['album'] as Map?;
        return OnlineSong(
          id: s['id'].toString(),
          title: s['name'] ?? '',
          artist: artistStr,
          album: album?['name'] ?? '',
          coverUrl: album?['picUrl'],
          source: 'netease',
          duration: s['duration'],
        );
      }).toList();
    } catch (_) { return []; }
  }

  @override Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    // 尝试多个接口获取播放地址
    final apis = [
      'https://music.163.com/api/song/enhance/player/url?id=${song.id}&ids=%5B${song.id}%5D&br=${quality}000',
      'https://music.163.com/api/song/enhance/player/url/v1?id=${song.id}&ids=%5B${song.id}%5D&level=standard&encodeType=mp3',
    ];
    for (final url in apis) {
      try {
        final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final d = jsonDecode(resp.body);
          final data = d['data'] as List?;
          if (data != null && data.isNotEmpty) {
            final urlStr = data[0]['url'];
            if (urlStr != null && urlStr.toString().startsWith('http')) return urlStr.toString();
          }
        }
      } catch (_) {}
    }
    return null;
  }

  @override Future<String?> getLyric(OnlineSong song) async {
    final url = 'https://music.163.com/api/song/lyric?id=${song.id}&lv=1&kv=1&tv=-1';
    try {
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        return d['lrc']?['lyric']?.toString();
      }
    } catch (_) {}
    return null;
  }
}

/// ========== QQ音乐 API ==========
class QQSource extends MusicSource {
  @override String get name => 'QQ音乐';

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, limit = 20}) async {
    final url = 'https://c.y.qq.com/soso/fcgi-bin/client_search_cp?format=json&w=${Uri.encodeComponent(keyword)}&p=$page&n=$limit&cr=1&g_tk=5381';
    final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    try {
      final d = jsonDecode(resp.body);
      final songs = d['data']?['song']?['list'] as List?;
      if (songs == null || songs.isEmpty) return [];
      return songs.map((s) {
        final artists = s['singer'] as List?;
        final artistStr = artists?.map((a) => a['name'] ?? '').join('/') ?? '';
        return OnlineSong(
          id: s['songmid']?.toString() ?? s['songid']?.toString() ?? '',
          title: s['songname'] ?? '',
          artist: artistStr,
          album: s['albumname'] ?? '',
          coverUrl: s['albummid'] != null ? 'https://y.gtimg.cn/music/photo_new/T002R300x300M000${s["albummid"]}.jpg' : null,
          source: 'qq',
          duration: (s['interval'] as int?) != null ? (s['interval'] as int) * 1000 : null,
        );
      }).toList();
    } catch (_) { return []; }
  }

  @override Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    try {
      final guid = DateTime.now().millisecondsSinceEpoch % 1000000000;
      final url = 'https://u.y.qq.com/cgi-bin/musicu.fcg?format=json&data=%7B%22req_0%22%3A%7B%22module%22%3A%22vkey.GetVkeyServer%22%2C%22method%22%3A%22CgiGetVkey%22%2C%22param%22%3A%7B%22guid%22%3A%22$guid%22%2C%22songmid%22%3A%5B%22${song.id}%22%5D%2C%22songtype%22%3A%5B0%5D%2C%22uin%22%3A%220%22%2C%22loginflag%22%3A1%2C%22platform%22%3A%2220%22%7D%7D%7D';
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        final midurlinfo = d['req_0']?['data']?['midurlinfo'] as List?;
        if (midurlinfo != null && midurlinfo.isNotEmpty) {
          final purl = midurlinfo[0]['purl']?.toString();
          if (purl != null && purl.isNotEmpty) return 'http://ws.stream.qqmusic.qq.com/$purl';
        }
      }
    } catch (_) {}
    return null;
  }

  @override Future<String?> getLyric(OnlineSong song) async {
    final url = 'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=${song.id}&format=json&nobase64=1';
    try {
      final resp = await http.get(Uri.parse(url), headers: {..._h(), 'Referer': 'https://y.qq.com/'}).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        return d['lyric']?.toString();
      }
    } catch (_) {}
    return null;
  }
}

/// ========== 酷狗音乐 API ==========
class KugouSource extends MusicSource {
  @override String get name => '酷狗';

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, limit = 20}) async {
    final url = 'http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=${Uri.encodeComponent(keyword)}&page=$page&pagesize=$limit';
    final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    try {
      final d = jsonDecode(resp.body);
      final songs = d['data']?['info'] as List?;
      if (songs == null || songs.isEmpty) return [];
      return songs.map((s) {
        return OnlineSong(
          id: s['hash']?.toString() ?? s['songid']?.toString() ?? '',
          title: s['songname'] ?? '',
          artist: s['singername'] ?? '',
          album: s['album_name'] ?? '',
          coverUrl: s['album_img']?.toString().replaceAll('{size}', '300'),
          source: 'kugou',
          duration: (s['duration'] as int?) != null ? (s['duration'] as int) * 1000 : null,
        );
      }).toList();
    } catch (_) { return []; }
  }

  @override Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    final url = 'http://trackercdn.kugou.com/i/v2/?cmd=25&key=${song.id}&hash=${song.id}&behavior=play&appid=1005&mid=0&userid=0&version=0&vipType=0&token=0';
    try {
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        final urlStr = d['url']?.toString();
        if (urlStr != null && urlStr.startsWith('http')) return urlStr;
      }
    } catch (_) {}
    return null;
  }

  @override Future<String?> getLyric(OnlineSong song) async {
    final url = 'http://krcs.kugou.com/search?keyword=${Uri.encodeComponent(song.title)}&hash=${song.id}&client=mobi&man=yes';
    try {
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        final candidates = d['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final id = candidates[0]['id']?.toString();
          final accesskey = candidates[0]['accesskey']?.toString();
          if (id != null && accesskey != null) {
            final lrcUrl = 'http://lyrics.kugou.com/download?client=mobi&id=$id&accesskey=$accesskey&fmt=lrc&charset=utf8';
            final lrcResp = await http.get(Uri.parse(lrcUrl)).timeout(const Duration(seconds: 6));
            if (lrcResp.statusCode == 200) {
              final lrcD = jsonDecode(lrcResp.body);
              return lrcD['content']?.toString();
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }
}

class CustomApiSource extends MusicSource {
  final String _name, _searchUrl, _playUrl, _lyricUrl;
  CustomApiSource({required String name, required String searchUrl, required String playUrl, required String lyricUrl})
    : _name = name, _searchUrl = searchUrl, _playUrl = playUrl, _lyricUrl = lyricUrl;
  @override String get name => _name;

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    final u = _searchUrl.replaceAll('{keyword}', Uri.encodeComponent(keyword)).replaceAll('{page}', '$page').replaceAll('{limit}', '$limit');
    final r = await http.get(Uri.parse(u), headers: _h()).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return [];
    try { final l = (jsonDecode(r.body)['data'] ?? jsonDecode(r.body)['list'] ?? jsonDecode(r.body)['result'] ?? jsonDecode(r.body)['songs'] ?? []) as List; return l.map((e) => OnlineSong.fromJson(e as Map<String, dynamic>, source: _name)).toList(); } catch (_) { return []; }
  }
  @override Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    final u = _playUrl.replaceAll('{id}', song.id).replaceAll('{quality}', quality);
    final r = await http.get(Uri.parse(u), headers: _h()).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    try { return (jsonDecode(r.body)['url'] ?? jsonDecode(r.body)['data']?['url'] ?? jsonDecode(r.body)['playurl'])?.toString(); } catch (_) { return null; }
  }
  @override Future<String?> getLyric(OnlineSong song) async {
    final u = _lyricUrl.replaceAll('{id}', song.id);
    final r = await http.get(Uri.parse(u), headers: _h()).timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) return null;
    try { return (jsonDecode(r.body)['lyric'] ?? jsonDecode(r.body)['lrc'] ?? jsonDecode(r.body)['data']?['lyric'])?.toString(); } catch (_) { return null; }
  }
}

/// ========== 聚合多源 ==========
Future<MusicSource> getMusicSourceAsync() async {
  final store = await storage;
  final custom = store.getMusicSources();
  final srcs = <MusicSource>[NeteaseSource(), QQSource(), KugouSource()];
  for (final s in custom) {
    srcs.add(CustomApiSource(
      name: s['name'] ?? '自定义',
      searchUrl: '${s['url']}/search?key={keyword}&page={page}&limit={limit}',
      playUrl: '${s['url']}/url?id={id}&quality={quality}',
      lyricUrl: '${s['url']}/lyric?id={id}',
    ));
  }
  return AggregateSource(srcs);
}

MusicSource get musicSource => NeteaseSource();

class AggregateSource extends MusicSource {
  final List<MusicSource> _srcs;
  AggregateSource(this._srcs);
  @override String get name => _srcs.map((s) => s.name).join('+');
  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    for (final s in _srcs) { try { final r = await s.search(keyword, page: page, limit: limit); if (r.isNotEmpty) return r; } catch (_) {} }
    return [];
  }
  @override Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    for (final s in _srcs) { try { final u = await s.getPlayUrl(song, quality: quality); if (u != null && u.startsWith('http')) return u; } catch (_) {} }
    return null;
  }
  @override Future<String?> getLyric(OnlineSong song) async {
    for (final s in _srcs) { try { final l = await s.getLyric(song); if (l != null && l.isNotEmpty) return l; } catch (_) {} }
    return null;
  }
}

class DownloadManager {
  static Future<String?> downloadSong(OnlineSong song, String playUrl, String saveDir) async {
    try {
      final dir = Directory(saveDir); if (!dir.existsSync()) dir.createSync(recursive: true);
      final safe = '${song.title} - ${song.artist}'.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final path = '$saveDir/$safe.mp3';
      if (File(path).existsSync()) return path;
      final r = await http.get(Uri.parse(playUrl), headers: _h()).timeout(const Duration(minutes: 3));
      if (r.statusCode != 200) return null;
      await File(path).writeAsBytes(r.bodyBytes); return path;
    } catch (_) { return null; }
  }
}

/// JS源文件解析器
List<Map<String, String>> parseJsSource(String content) {
  final sources = <Map<String, String>>[];
  final nameRe = RegExp(r'''['"]name['"]\s*[:=]\s*['"]([^'"]+)['"]''');
  final urlRe = RegExp(r'''https?://[^\s'"`\[\]{}()<>]+\.[^\s'"`\[\]{}()<>]+''');
  final urls = urlRe.allMatches(content).map((m) => m.group(0)!).toSet();
  String name = '导入源';
  final nm = nameRe.firstMatch(content); if (nm != null) name = nm.group(1)!;
  for (final url in urls) {
    if (url.contains('github.com') || url.contains('example.com') || url.contains('localhost') || url.length < 10) continue;
    final uri = Uri.tryParse(url); if (uri == null) continue;
    final seg = uri.pathSegments;
    final base = seg.isNotEmpty && seg.first.isNotEmpty ? '${uri.scheme}://${uri.host}/${seg.first}' : '${uri.scheme}://${uri.host}';
    sources.add({'name': name, 'url': base});
  }
  final seen = <String>{};
  return sources.where((s) => seen.add(s['url']!)).toList();
}

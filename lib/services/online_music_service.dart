import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
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

/// ========== 网易云音乐 API（含加密）==========
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
    // 使用加密接口获取播放地址
    final br = '${quality}000';
    final data = jsonEncode({
      'ids': [int.tryParse(song.id) ?? song.id],
      'br': int.tryParse(br) ?? 320000,
      'csrf_token': '',
    });

    final encrypted = _encryptRequest(data);
    if (encrypted == null) return null;

    final url = 'https://music.163.com/weapi/song/enhance/player/url';
    try {
      final resp = await http.post(Uri.parse(url), headers: _h(), body: {
        'params': encrypted['encText'],
        'encSecKey': encrypted['encSecKey'],
      }).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        if (d['code'] == 200) {
          final dataList = d['data'] as List?;
          if (dataList != null && dataList.isNotEmpty) {
            final urlStr = dataList[0]['url'];
            if (urlStr != null && urlStr.toString().startsWith('http')) return urlStr.toString();
          }
        }
      }
    } catch (_) {}

    // 降级：尝试 outer/url
    return 'https://music.163.com/song/media/outer/url?id=${song.id}.mp3';
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

  /// 网易云 weapi 加密
  Map<String, String>? _encryptRequest(String text) {
    try {
      const modulus = '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';
      const nonce = '0CoJUm6Qyw8W8jud';
      const pubKey = '010001';

      // 1. 生成随机16字节密钥
      final secKey = _randomString(16);

      // 2. AES-128-CBC 加密（第一次，用 nonce）
      final encText1 = _aesEncrypt(text, nonce);
      // 3. AES-128-CBC 加密（第二次，用 secKey）
      final encText2 = _aesEncrypt(encText1, secKey);

      // 4. RSA 加密 secKey
      final encSecKey = _rsaEncrypt(secKey, pubKey, modulus);

      return {'encText': encText2, 'encSecKey': encSecKey};
    } catch (_) { return null; }
  }

  String _aesEncrypt(String text, String key) {
    final keyBytes = utf8.encode(key);
    final textBytes = utf8.encode(text);
    // PKCS7 padding
    final blockSize = 16;
    final padLen = blockSize - (textBytes.length % blockSize);
    final padded = List<int>.from(textBytes)..addAll(List.filled(padLen, padLen));

    final encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.cbc, padding: null));
    final iv = List<int>.filled(16, 0); // weapi 使用全0 IV
    final encrypted = encrypter.encryptBytes(padded, iv: encrypt.IV(iv));
    return base64.encode(encrypted.bytes);
  }

  String _rsaEncrypt(String text, String pubKey, String modulus) {
    // 反转文本
    final reversed = text.split('').reversed.join('');
    // 转大整数
    final textBigInt = BigInt.parse(utf8.encode(reversed).map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16);
    final keyBigInt = BigInt.parse(pubKey, radix: 16);
    final modBigInt = BigInt.parse(modulus, radix: 16);
    // RSA 加密: c = m^e mod n
    final result = textBigInt.modPow(keyBigInt, modBigInt);
    return result.toRadixString(16).padLeft(256, '0');
  }

  String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

/// ========== QQ音乐 API ==========
class QQSource extends MusicSource {
  @override String get name => 'QQ音乐';

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
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
      final data = jsonEncode({
        'req_0': {
          'module': 'vkey.GetVkeyServer',
          'method': 'CgiGetVkey',
          'param': {
            'guid': guid.toString(),
            'songmid': [song.id],
            'songtype': [0],
            'uin': '0',
            'loginflag': 1,
            'platform': '20',
          }
        }
      });
      final url = 'https://u.y.qq.com/cgi-bin/musicu.fcg?format=json&data=${Uri.encodeComponent(data)}';
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

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    final url = 'http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=${Uri.encodeComponent(keyword)}&page=$page&pagesize=$limit';
    final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    try {
      final d = jsonDecode(resp.body);
      final songs = d['data']?['info'] as List?;
      if (songs == null || songs.isEmpty) return [];
      return songs.map((s) => OnlineSong(
        id: s['hash']?.toString() ?? s['songid']?.toString() ?? '',
        title: s['songname'] ?? '',
        artist: s['singername'] ?? '',
        album: s['album_name'] ?? '',
        coverUrl: s['album_img']?.toString().replaceAll('{size}', '300'),
        source: 'kugou',
        duration: (s['duration'] as int?) != null ? (s['duration'] as int) * 1000 : null,
      )).toList();
    } catch (_) { return []; }
  }

  @override Future<String?> getPlayUrl(OnlineSong song, {String quality = '320'}) async {
    final url = 'http://trackercdn.kugou.com/i/v2/?cmd=25&key=${song.id}&hash=${song.id}&behavior=play&appid=1005&mid=0&userid=0&version=0&vipType=0&token=0';
    try {
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        final urlList = d['url'] as List?;
        if (urlList != null && urlList.isNotEmpty) {
          final urlStr = urlList[0]?.toString();
          if (urlStr != null && urlStr.startsWith('http')) return urlStr;
        }
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

/// ========== 自定义 API 源 ==========
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
    // 优先用歌曲来源的平台
    for (final s in _srcs) {
      if (s.name.contains(song.source) || song.source.contains(s.name)) {
        try { final u = await s.getPlayUrl(song, quality: quality); if (u != null && u.startsWith('http')) return u; } catch (_) {}
      }
    }
    // 降级：依次尝试所有平台
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
      final r = await http.get(Uri.parse(playUrl), headers: _h()).timeout(const Duration(minutes: 5));
      if (r.statusCode != 200) return null;
      // 检查下载的是否是音频文件（不是HTML错误页面）
      final contentType = r.headers['content-type'] ?? '';
      final bodyBytes = r.bodyBytes;
      if (bodyBytes.length < 1000) return null; // 太小的文件可能是错误页面
      // 检查文件头（MP3: ID3 或 FF FB, FLAC: fLaC, AAC: FF F1）
      if (bodyBytes.length > 4) {
        final header = bodyBytes.sublist(0, 4);
        final isAudio = (header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33) || // ID3
            (header[0] == 0xFF && (header[1] == 0xFB || header[1] == 0xF3 || header[1] == 0xF2)) || // MP3
            (header[0] == 0x66 && header[1] == 0x4C && header[2] == 0x61 && header[3] == 0x43) || // FLAC
            contentType.contains('audio') || contentType.contains('octet-stream');
        if (!isAudio) return null; // 不是音频文件
      }
      await File(path).writeAsBytes(bodyBytes);
      return path;
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

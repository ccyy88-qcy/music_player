import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'storage_manager.dart';

class OnlineSong {
  final String id, title, artist, album, source;
  final String? coverUrl;
  final int? duration;
  final int fee; // 0=免费, 1=会员, 4=付费, 8=VIP

  const OnlineSong({
    required this.id, required this.title, required this.artist,
    this.album = '', this.coverUrl, this.source = '', this.duration,
    this.fee = 0,
  });

  factory OnlineSong.fromJson(Map<String, dynamic> json, {String source = ''}) {
    return OnlineSong(
      id: (json['id'] ?? json['songid'] ?? '').toString(),
      title: (json['name'] ?? json['title'] ?? '').toString(),
      artist: (json['artist'] ?? json['singer'] ?? (json['ar'] is List ? (json['ar'] as List).map((a) => a is Map ? a['name'] ?? '' : '$a').join('/') : '')).toString(),
      album: (json['album'] is Map ? json['album']['name'] ?? '' : json['album'] ?? '').toString(),
      coverUrl: json['cover'] ?? json['pic'],
      source: source,
      duration: int.tryParse((json['duration'] ?? '0').toString()),
      fee: json['fee'] as int? ?? 0,
    );
  }

  String get feeLabel {
    switch (fee) {
      case 0: return '免费';
      case 1: return '会员';
      case 4: return '付费';
      case 8: return 'VIP';
      default: return '';
    }
  }

  Color get feeColor {
    switch (fee) {
      case 0: return Colors.green;
      case 1: return Colors.orange;
      case 4: return Colors.red;
      case 8: return Colors.purple;
      default: return Colors.grey;
    }
  }
}

abstract class MusicSource {
  String get name;
  String get key; // 短key，与OnlineSong.source匹配
  Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20});
  Future<String?> getPlayUrl(OnlineSong song);
  Future<String?> getLyric(OnlineSong song);
}

Map<String, String> _h() => {
  'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  'Referer': 'https://music.163.com/',
};

/// ========== 网易云音乐 API ==========
class NeteaseSource extends MusicSource {
  @override String get name => '网易云';
  @override String get key => 'netease';

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, limit = 20}) async {
    final results = <OnlineSong>[];
    
    // 排除关键词对网易云搜索API无效（返回0结果），全靠搜索结果后过滤
    final coverKeywords = ['钢琴版', '钢琴曲', 'Cover', 'cover', '翻唱', '翻弹', '改编', '指弹', '纯音乐', '伴奏', 'DJ版', 'Remix', 'Live'];
    
    final url = 'https://music.163.com/api/search/get?s=${Uri.encodeComponent(keyword)}&type=1&limit=$limit&offset=${(page - 1) * limit}';
    final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    
    try {
      final d = jsonDecode(resp.body);
      final songs = d['result']?['songs'] as List?;
      if (songs == null || songs.isEmpty) return [];
      
      for (final s in songs) {
        final fee = s['fee'] ?? 0;
        final name = s['name'] ?? '';
        final artistStr = ((s['artists'] as List?)?.map((a) => a['name'] ?? '').join('/') ?? '');
        final album = s['album'] as Map?;
        
        // 过滤VIP专享（fee=8）— 这些播放地址通常是30秒试听
        if (fee >= 8) continue;
        
        // 过滤明显翻唱
        bool isCover = coverKeywords.any((kw) => name.contains(kw));
        if (isCover) continue;
        
        // 过滤时长太短的（<60秒通常是试听或片段）
        final duration = s['duration'] as int? ?? 0;
        if (duration > 0 && duration < 60000) continue;
        
        results.add(OnlineSong(
          id: s['id'].toString(),
          title: name,
          artist: artistStr,
          album: album?['name'] ?? '',
          coverUrl: album?['picUrl'],
          source: 'netease',
          duration: duration,
          fee: fee,
        ));
      }
      
      // 排序：免费优先 > 时长优先
      results.sort((a, b) {
        // 免费优先
        if (a.fee != b.fee) return a.fee.compareTo(b.fee);
        // 时长优先
        return (b.duration ?? 0).compareTo(a.duration ?? 0);
      });
      
      return results;
    } catch (_) { return []; }
  }

  @override Future<String?> getPlayUrl(OnlineSong song) async {
    // 使用不需要加密的接口（已验证可用）
    final url = 'https://music.163.com/api/song/enhance/player/url?id=${song.id}&ids=%5B${song.id}%5D&br=320000';
    try {
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        final data = d['data'] as List?;
        if (data != null && data.isNotEmpty) {
          final urlStr = data[0]['url'];
          if (urlStr != null && urlStr.toString().startsWith('http')) return urlStr.toString();
        }
      }
    } catch (_) {}
    // 降级：outer/url
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
}

/// ========== QQ音乐 API ==========
class QQSource extends MusicSource {
  @override String get name => 'QQ音乐';
  @override String get key => 'qq';

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
        return OnlineSong(id: s['songmid']?.toString() ?? '', title: s['songname'] ?? '', artist: artists?.map((a) => a['name'] ?? '').join('/') ?? '', album: s['albumname'] ?? '', coverUrl: s['albummid'] != null ? 'https://y.gtimg.cn/music/photo_new/T002R300x300M000${s["albummid"]}.jpg' : null, source: 'qq', duration: (s['interval'] as int?) != null ? (s['interval'] as int) * 1000 : null);
      }).toList();
    } catch (_) { return []; }
  }

  @override Future<String?> getPlayUrl(OnlineSong song) async {
    try {
      final guid = DateTime.now().millisecondsSinceEpoch % 1000000000;
      final data = jsonEncode({'req_0': {'module': 'vkey.GetVkeyServer', 'method': 'CgiGetVkey', 'param': {'guid': guid.toString(), 'songmid': [song.id], 'songtype': [0], 'uin': '0', 'loginflag': 1, 'platform': '20'}}});
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
  @override String get key => 'kugou';

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    final url = 'http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=${Uri.encodeComponent(keyword)}&page=$page&pagesize=$limit';
    final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    try {
      final d = jsonDecode(resp.body);
      final songs = d['data']?['info'] as List?;
      if (songs == null || songs.isEmpty) return [];
      return songs.map((s) => OnlineSong(id: s['hash']?.toString() ?? '', title: s['songname'] ?? '', artist: s['singername'] ?? '', album: s['album_name'] ?? '', coverUrl: s['album_img']?.toString().replaceAll('{size}', '300'), source: 'kugou', duration: (s['duration'] as int?) != null ? (s['duration'] as int) * 1000 : null)).toList();
    } catch (_) { return []; }
  }

  @override Future<String?> getPlayUrl(OnlineSong song) async {
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
            final lrcResp = await http.get(Uri.parse('http://lyrics.kugou.com/download?client=mobi&id=$id&accesskey=$accesskey&fmt=lrc&charset=utf8')).timeout(const Duration(seconds: 6));
            if (lrcResp.statusCode == 200) return jsonDecode(lrcResp.body)['content']?.toString();
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
  @override String get key => _name;
  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    final u = _searchUrl.replaceAll('{keyword}', Uri.encodeComponent(keyword)).replaceAll('{page}', '$page').replaceAll('{limit}', '$limit');
    final r = await http.get(Uri.parse(u), headers: _h()).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return [];
    try { final l = (jsonDecode(r.body)['data'] ?? jsonDecode(r.body)['list'] ?? jsonDecode(r.body)['result'] ?? []) as List; return l.map((e) => OnlineSong.fromJson(e as Map<String, dynamic>, source: _name)).toList(); } catch (_) { return []; }
  }
  @override Future<String?> getPlayUrl(OnlineSong song) async {
    final u = _playUrl.replaceAll('{id}', song.id);
    final r = await http.get(Uri.parse(u), headers: _h()).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    try { return (jsonDecode(r.body)['url'] ?? jsonDecode(r.body)['data']?['url'])?.toString(); } catch (_) { return null; }
  }
  @override Future<String?> getLyric(OnlineSong song) async {
    final u = _lyricUrl.replaceAll('{id}', song.id);
    final r = await http.get(Uri.parse(u), headers: _h()).timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) return null;
    try { return (jsonDecode(r.body)['lyric'] ?? jsonDecode(r.body)['lrc'])?.toString(); } catch (_) { return null; }
  }
}

/// ========== 聚合多源 ==========
Future<MusicSource> getMusicSourceAsync() async {
  final store = await storage;
  final custom = store.getMusicSources();
  final srcs = <MusicSource>[NeteaseSource(), QQSource(), KugouSource()];
  for (final s in custom) { srcs.add(CustomApiSource(name: s['name'] ?? '自定义', searchUrl: '${s['url']}/search?key={keyword}&page={page}&limit={limit}', playUrl: '${s['url']}/url?id={id}', lyricUrl: '${s['url']}/lyric?id={id}')); }
  return AggregateSource(srcs);
}

MusicSource get musicSource => NeteaseSource();

class AggregateSource extends MusicSource {
  final List<MusicSource> _srcs;
  final Map<String, MusicSource> _srcMap;

  AggregateSource(this._srcs) : _srcMap = {for (final s in _srcs) s.key: s};

  @override String get name => _srcs.map((s) => s.name).join('+');
  @override String get key => name;

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    // 并查所有源，合并去重
    final all = <String, OnlineSong>{};
    final results = await Future.wait(_srcs.map((s) => s.search(keyword, page: page, limit: limit).catchError((_) => <OnlineSong>[])));
    for (final r in results) {
      for (final song in r) {
        all.putIfAbsent('${song.id}_${song.source}', () => song);
      }
    }
    final merged = all.values.toList();
    merged.sort((a, b) => a.fee.compareTo(b.fee));
    return merged.take(limit * 2).toList();
  }

  /// 根据song.source路由到正确的源获取播放地址
  @override Future<String?> getPlayUrl(OnlineSong song) async {
    // 已知源名直接路由
    final known = _srcMap[song.source];
    if (known != null) {
      try {
        final u = await known.getPlayUrl(song);
        if (u != null && u.startsWith('http')) return u;
      } catch (_) {}
    }
    // 降级：遍历所有源
    for (final s in _srcs) {
      try { final u = await s.getPlayUrl(song); if (u != null && u.startsWith('http')) return u; } catch (_) {}
    }
    return null;
  }

  @override Future<String?> getLyric(OnlineSong song) async {
    final known = _srcMap[song.source];
    if (known != null) {
      try { final l = await known.getLyric(song); if (l != null && l.isNotEmpty) return l; } catch (_) {}
    }
    for (final s in _srcs) {
      try { final l = await s.getLyric(song); if (l != null && l.isNotEmpty) return l; } catch (_) {}
    }
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

      // 手动处理302跳转
      var url = playUrl;
      for (int i = 0; i < 5; i++) { // 最多5次跳转
        final req = http.Request('GET', Uri.parse(url));
        req.headers.addAll({
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
          'Accept': '*/*',
        });
        req.followRedirects = false;
        final resp = await http.Client().send(req).timeout(const Duration(seconds: 30));
        if (resp.statusCode == 302 || resp.statusCode == 301) {
          url = resp.headers['location'] ?? '';
          if (url.isEmpty) return null;
          continue;
        }
        if (resp.statusCode != 200) return null;
        final bytes = await resp.stream.toBytes();
        if (bytes.length < 1000) return null; // 太小可能是错误页面
        // 检查文件头
        if (bytes.length > 4) {
          final isAudio = (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) || // ID3
              (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) || // MP3 sync
              (bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43); // FLAC
          if (!isAudio) return null;
        }
        await File(path).writeAsBytes(bytes);
        return path;
      }
      return null;
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
    if (url.contains('github.com') || url.contains('example.com') || url.contains('localhost') || url.length < 10) continue;
    final uri = Uri.tryParse(url); if (uri == null) continue;
    final seg = uri.pathSegments;
    final base = seg.isNotEmpty && seg.first.isNotEmpty ? '${uri.scheme}://${uri.host}/${seg.first}' : '${uri.scheme}://${uri.host}';
    sources.add({'name': name, 'url': base});
  }
  final seen = <String>{};
  return sources.where((s) => seen.add(s['url']!)).toList();
}

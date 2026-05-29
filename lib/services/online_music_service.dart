import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'storage_manager.dart';
import 'netease_crypto.dart';

class OnlineSong {
  final String id, title, artist, album, source;
  final String? coverUrl;
  final int? duration;
  final int fee;

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
  String get key;
  Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20});
  Future<String?> getPlayUrl(OnlineSong song);
  Future<String?> getLyric(OnlineSong song);
}

Map<String, String> _h() => {
  'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
  'Referer': 'https://music.163.com/',
};

/// 解析302/301重定向获取真实CDN地址
Future<String?> _resolveRedirect(String url, {int maxFollow = 5}) async {
  var currentUrl = url;
  for (int i = 0; i < maxFollow; i++) {
    try {
      final req = http.Request('GET', Uri.parse(currentUrl));
      req.headers.addAll({
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'https://music.163.com/',
        'Accept': '*/*',
      });
      req.followRedirects = false;
      final resp = await http.Client().send(req).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 302 || resp.statusCode == 301) {
        final loc = resp.headers['location'] ?? '';
        if (loc.isEmpty) return null;
        currentUrl = loc.startsWith('http') ? loc : '${Uri.parse(currentUrl).origin}$loc';
        continue;
      }
      if (resp.statusCode == 200) return currentUrl;
      return null;
    } catch (_) { return null; }
  }
  return currentUrl;
}

/// ========== 网易云音乐 API ==========
class NeteaseSource extends MusicSource {
  @override String get name => '网易云';
  @override String get key => 'netease';

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, limit = 20}) async {
    final results = <OnlineSong>[];
    final instrumentalKeywords = ['伴奏', '纯音乐', 'inst', 'instrumental'];
    final searchHeaders = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
      'Referer': 'https://music.163.com/',
      'Cookie': 'NMTID=00OKlEq2nVNMgNF05CFI1JjHgQehWAAAQJZovaw',
    };
    final url = 'https://music.163.com/api/search/get?s=${Uri.encodeComponent(keyword)}&type=1&limit=$limit&offset=${(page - 1) * limit}';
    final resp = await http.get(Uri.parse(url), headers: searchHeaders).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    try {
      final d = jsonDecode(resp.body);
      final songs = d['result']?['songs'] as List?;
      if (songs == null || songs.isEmpty) return [];
      for (final s in songs) {
        final name = s['name'] ?? '';
        final artistStr = ((s['artists'] as List?)?.map((a) => a['name'] ?? '').join('/') ?? '');
        final album = s['album'] as Map?;
        final duration = s['duration'] as int? ?? 0;
        if (instrumentalKeywords.any((kw) => name.contains(kw))) continue;
        if (duration > 0 && duration < 60000) continue;
        results.add(OnlineSong(
          id: s['id'].toString(), title: name, artist: artistStr,
          album: album?['name'] ?? '', coverUrl: album?['picUrl'],
          source: 'netease', duration: duration, fee: s['fee'] as int? ?? 0,
        ));
      }
      results.sort((a, b) {
        if (a.fee != b.fee) return a.fee.compareTo(b.fee);
        return (b.duration ?? 0).compareTo(a.duration ?? 0);
      });
      return results;
    } catch (_) { return []; }
  }

  @override Future<String?> getPlayUrl(OnlineSong song) async {
    // 1. EAPI加密调用（interface3，LX Music用的端点）
    try {
      final path = '/api/song/enhance/player/url';
      final body = jsonEncode({
        'ids': jsonEncode([song.id]),
        'br': song.fee > 0 ? 128000 : 320000, // VIP歌用128k
        'encodeType': 'mp3',
      });
      final params = eapiEncrypt(path, body);
      final resp = await http.post(
        Uri.parse('https://interface3.music.163.com/eapi/song/enhance/player/url'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': 'NMTID=00OKlEq2nVNMgNF05CFI1JjHgQehWAAAQJZovaw; os=pc',
        },
        body: {'params': params},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        final data = d['data'] as List?;
        if (data != null && data.isNotEmpty) {
          final urlStr = data[0]['url'];
          final freeTrialInfo = data[0]['freeTrialInfo'];
          // 跳过免费试听片段（VIP歌曲会返回freeTrialInfo）
          if (urlStr != null && urlStr.toString().startsWith('http') && freeTrialInfo == null) {
            return urlStr.toString().split('?')[0];
          }
        }
      }
    } catch (_) {}

    // 2. 降级：原来的公共enhance API
    try {
      final url = 'https://music.163.com/api/song/enhance/player/url?id=${song.id}&ids=%5B${song.id}%5D&br=320000';
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        final data = d['data'] as List?;
        if (data != null && data.isNotEmpty) {
          final urlStr = data[0]['url'];
          if (urlStr != null && urlStr.toString().startsWith('http')) return urlStr.toString();
        }
      }
    } catch (_) {}

    // 3. outer/url + 重定向解析
    try {
      final outerUrl = 'https://music.163.com/song/media/outer/url?id=${song.id}.mp3';
      final resolved = await _resolveRedirect(outerUrl);
      if (resolved != null && resolved.startsWith('http') && !resolved.contains('404')) return resolved;
    } catch (_) {}
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
      // 用dart:io HttpClient（比http包更稳定）
      final client = HttpClient();
      client.userAgent = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36';
      try {
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set('Referer', 'https://music.163.com/');
        final resp = await req.close().timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final d = jsonDecode(body) as Map;
          final midurlinfo = (d['req_0'] as Map?)?['data']?['midurlinfo'] as List?;
          if (midurlinfo != null && midurlinfo.isNotEmpty) {
            final purl = midurlinfo[0]['purl']?.toString() ?? '';
            if (purl.isNotEmpty) return 'http://ws.stream.qqmusic.qq.com/$purl';
          }
        }
      } finally { client.close(); }
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
      return songs.map((s) => OnlineSong(
        id: s['hash']?.toString() ?? '', title: s['songname'] ?? '',
        artist: s['singername'] ?? '', album: s['album_name'] ?? '',
        coverUrl: s['album_img']?.toString().replaceAll('{size}', '300'),
        source: 'kugou', duration: (s['duration'] as int?) != null ? (s['duration'] as int) * 1000 : null
      )).toList();
    } catch (_) { return []; }
  }

  @override Future<String?> getPlayUrl(OnlineSong song) async {
    // LX Music方式：wwwapi.kugou.com + getdata
    try {
      final albumId = song.album.isNotEmpty ? song.album : '0';
      final url = 'https://wwwapi.kugou.com/yy/index.php?r=play/getdata&hash=${song.id}&platid=4&album_id=$albumId&mid=00000000000000000000000000000000';
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        if (d['status'] != 1) return null;
        if ((d['data']?['privilege'] as int? ?? 0) > 9) return null; // VIP
        var playUrl = d['data']?['play_backup_url']?.toString();
        if (playUrl == null || !playUrl.startsWith('http')) {
          playUrl = d['data']?['play_url']?.toString();
        }
        if (playUrl != null && playUrl.startsWith('http')) return playUrl;
      }
    } catch (_) {}
    // 降级：原方式
    try {
      final url = 'http://trackercdn.kugou.com/i/v2/?cmd=25&hash=${song.id}&behavior=play&appid=1005&mid=0&userid=0&version=0&vipType=0';
      final resp = await http.get(Uri.parse(url), headers: _h()).timeout(const Duration(seconds: 5));
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

/// ========== 酷我音乐 API ==========
class KuwoSource extends MusicSource {
  @override String get name => '酷我';
  @override String get key => 'kuwo';

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    final url = 'http://search.kuwo.cn/r.s?all=${Uri.encodeComponent(keyword)}&ft=music&itemset=web_2013&pn=${page - 1}&rn=$limit&rformat=json&encoding=utf8&client=kt';
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'http://kuwo.cn/',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final raw = resp.body.replaceFirst('MUSIC_', ''); // 有时返回JSONP
      final d = jsonDecode(raw);
      final list = d['abslist'] as List?;
      if (list == null || list.isEmpty) return [];
      return list.map((s) {
        final rid = (s['MUSICRID'] ?? '').toString().replaceFirst('MUSIC_', '');
        return OnlineSong(
          id: rid, title: s['SONGNAME'] ?? '', artist: s['ARTIST'] ?? '',
          album: s['ALBUM'] ?? '', coverUrl: s['web_albumpic_short'] != null ? 'http://img.kuwo.cn/star/albumcover/${s["web_albumpic_short"]}' : null,
          source: 'kuwo', fee: 0,
        );
      }).toList();
    } catch (_) { return []; }
  }

  @override Future<String?> getPlayUrl(OnlineSong song) async {
    // 酷我反防盗链地址解析
    try {
      final url = 'http://antiserver.kuwo.cn/anti.s?type=convert_url&rid=MUSIC_${song.id}&format=mp3';
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'http://kuwo.cn/',
      }).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = resp.body.trim();
        if (body.startsWith('http')) return body;
      }
    } catch (_) {}
    return null;
  }

  @override Future<String?> getLyric(OnlineSong song) async {
    try {
      final url = 'http://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=${song.id}';
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'http://kuwo.cn/',
      }).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        final lrcList = d['data']?['lrclist'] as List?;
        if (lrcList != null && lrcList.isNotEmpty) {
          return lrcList.map((l) {
            final t = (l['time'] as num?)?.toDouble() ?? 0.0;
            final min = (t / 60).floor();
            final sec = (t % 60).toStringAsFixed(2).padLeft(5, '0');
            return '[$min:$sec]${l["lineLyric"]}';
          }).join('\n');
        }
      }
    } catch (_) {}
    return null;
  }
}

/// ========== 咪咕音乐 API ==========
class MiguSource extends MusicSource {
  @override String get name => '咪咕';
  @override String get key => 'migu';

  @override Future<List<OnlineSong>> search(String keyword, {int page = 1, int limit = 20}) async {
    final url = 'https://m.music.migu.cn/migu/remoting/scr_search_tag?keyword=${Uri.encodeComponent(keyword)}&pgc=$page&rows=$limit&type=2';
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'https://m.music.migu.cn/',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final d = jsonDecode(resp.body);
      final list = d['musics'] as List? ?? d['result'] as List?;
      if (list == null || list.isEmpty) return [];
      return list.map((s) {
        final sMap = s is Map ? s : {};
        final songId = (sMap['id'] ?? sMap['songId'] ?? '').toString();
        final copyrightId = (sMap['copyrightId'] ?? '').toString();
        final id = copyrightId.isNotEmpty ? copyrightId : songId;
        final artists = sMap['singerName'] ?? sMap['artist'] ?? '';
        return OnlineSong(
          id: id, title: sMap['name'] ?? sMap['songName'] ?? '',
          artist: artists.toString(),
          album: sMap['albumName'] ?? sMap['album'] ?? '',
          coverUrl: sMap['cover']?.toString().replaceAll('{size}', '300') ?? sMap['albumPic']?.toString(),
          source: 'migu', duration: (sMap['duration'] as int?) ?? (sMap['length'] as int?),
        );
      }).toList();
    } catch (_) { return []; }
  }

  @override Future<String?> getPlayUrl(OnlineSong song) async {
    // LX Music方式：MIGUM2.0 strategy接口
    try {
      final url = 'https://app.c.nf.migu.cn/MIGUM2.0/strategy/listen-url/v2.2?netType=01&resourceType=E&songId=${song.id}&toneFlag=HQ';
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'https://app.c.nf.migu.cn/',
        'channel': '0146951',
        'uid': '0',
      }).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        var playUrl = d['data']?['url']?.toString();
        if (playUrl != null) {
          if (playUrl.startsWith('//')) playUrl = 'https:$playUrl';
          return playUrl.replaceAll('+', '%2B').split('?')[0];
        }
      }
    } catch (_) {}
    // 降级：旧方式
    try {
      final url = 'https://app.pd.nf.migu.cn/MIGUM3.0/v1.0/content/sub/listenSong.do?toneFlag=HQ&songId=${song.id}';
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'https://app.pd.nf.migu.cn/',
      }).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        final playUrl = d['data']?['playUrl']?.toString();
        if (playUrl != null && playUrl.startsWith('http')) return playUrl;
      }
    } catch (_) {}
    // 降级：MiguWeb接口
    try {
      final url = 'https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resource/listen.do?copyrightId=${song.id}&netType=01';
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'https://music.migu.cn/',
      }).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        final resource = d['resource'] as List?;
        if (resource != null && resource.isNotEmpty) {
          final urlStr = resource[0]['playUrl']?.toString();
          if (urlStr != null && urlStr.startsWith('http')) return urlStr;
        }
      }
    } catch (_) {}
    return null;
  }

  @override Future<String?> getLyric(OnlineSong song) async {
    try {
      final url = 'https://music.migu.cn/v3/api/music/audioPlayer/getLyric?copyrightId=${song.id}';
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'https://music.migu.cn/',
      }).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        return d['lyric']?.toString();
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
  final srcs = <MusicSource>[NeteaseSource(), QQSource(), KugouSource(), KuwoSource(), MiguSource()];
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
    final all = <String, OnlineSong>{};
    final results = await Future.wait(_srcs.map((s) => s.search(keyword, page: page, limit: limit).catchError((_) => <OnlineSong>[])));
    for (final r in results) {
      for (final song in r) {
        all.putIfAbsent('${song.id}_${song.source}', () => song);
      }
    }
    final merged = all.values.toList();
    merged.sort((a, b) => a.fee.compareTo(b.fee));
    return merged;
  }

  @override Future<String?> getPlayUrl(OnlineSong song) async {
    // 1. 直接路由到歌曲来源（快速）
    final known = _srcMap[song.source];
    if (known != null) {
      try { final u = await known.getPlayUrl(song); if (u != null && u.startsWith('http')) return u; } catch (_) {}
    }
    // 2. 遍历其他源
    for (final s in _srcs) {
      if (s.key == song.source) continue;
      try { final u = await s.getPlayUrl(song); if (u != null && u.startsWith('http')) return u; } catch (_) {}
    }
    // 3. 跨源搜索同名歌曲（VIP歌曲在QQ/酷狗找替代版本）
    try {
      final others = _srcs.where((s) => s.key != song.source).toList();
      for (final s in others) {
        final results = await s.search('${song.title} ${song.artist}', limit: 5);
        for (final result in results) {
          try {
            final u = await s.getPlayUrl(result);
            if (u != null && u.startsWith('http')) return u;
          } catch (_) {}
        }
      }
    } catch (_) {}
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

      var url = playUrl;
      for (int i = 0; i < 5; i++) {
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
        if (bytes.length < 1000) return null;
        if (bytes.length > 4) {
          final isAudio = (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
              (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) ||
              (bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43) ||
              (bytes.length > 8 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70);
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
  final nameRe = RegExp(r'''['\"]name['\"]\s*[:=]\s*['\"]([^'\"]+)['\"]''');
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

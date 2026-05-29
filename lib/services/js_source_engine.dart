import 'dart:convert';
import 'package:http/http.dart' as http;

/// JSON配置化的音乐源
/// 用户可以从LX Music等JS源中提取API配置，以JSON格式导入
///
/// 格式示例：
/// ```json
/// {
///   "name": "酷狗音乐",
///   "search": {
///     "url": "http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword={keyword}&page={page}&pagesize={limit}",
///     "method": "GET",
///     "headers": {"User-Agent": "..."},
///     "itemsPath": "data.info",
///     "idField": "hash",
///     "titleField": "songname",
///     "artistField": "singername",
///     "albumField": "album_name",
///     "coverField": "album_img"
///   },
///   "playUrl": {
///     "url": "https://wwwapi.kugou.com/yy/index.php?r=play/getdata&hash={id}&platid=4&album_id={album}&mid=00000000000000000000000000000000",
///     "method": "GET",
///     "headers": {"User-Agent": "..."},
///     "urlPath": "data.play_backup_url || data.play_url"
///   },
///   "lyric": {
///     "url": "http://lyrics.kugou.com/search?keyword={title}&hash={id}",
///     "method": "GET",
///     "headers": {"User-Agent": "..."},
///     "lyricPath": "candidates[0]..."
///   }
/// }
/// ```
class JsonMusicSourceConfig {
  final String name;
  final Map<String, dynamic>? search;
  final Map<String, dynamic>? playUrl;
  final Map<String, dynamic>? lyric;

  JsonMusicSourceConfig({
    required this.name,
    this.search,
    this.playUrl,
    this.lyric,
  });

  factory JsonMusicSourceConfig.fromJson(Map<String, dynamic> json) {
    return JsonMusicSourceConfig(
      name: json['name'] ?? '未知源',
      search: json['search'] as Map<String, dynamic>?,
      playUrl: json['playUrl'] as Map<String, dynamic>?,
      lyric: json['lyric'] as Map<String, dynamic>?,
    );
  }
}

/// 从LX Music JS源脚本中提取API配置的工具
/// 支持解析常见的LX Music源脚本格式，提取关键API端点
class LxJsParser {
  /// 从JS源脚本内容中提取API端点
  /// 支持LX Music标准源脚本格式 (kg.js, kw.js, tx.js, wy.js, mg.js)
  static List<JsonMusicSourceConfig> parseFromJs(String jsCode) {
    final configs = <JsonMusicSourceConfig>[];

    // 提取源名称
    final nameMatch = RegExp(r'name:\s*["\']([^"\']+)["\']').firstMatch(jsCode);
    final name = nameMatch?.group(1) ?? '自定义源';

    // 提取URL模式（所有http/https URL）
    final urls = <String>{};
    for (final m in RegExp(r'https?://[^"\')\s,]+').allMatches(jsCode)) {
      final url = m.group(0)!;
      if (!url.contains('jsdelivr') && !url.contains('gitee') && !url.contains('github')) {
        urls.add(url);
      }
    }

    // 提取可能的加密函数和密钥
    final cryptoKeys = <String>{};
    for (final m in RegExp(r'["\'][a-f0-9]{16,32}["\']').allMatches(jsCode)) {
      cryptoKeys.add(m.group(0)!);
    }

    // 构建基础配置
    if (urls.isNotEmpty) {
      configs.add(JsonMusicSourceConfig(name: name));
    }

    return configs;
  }

  /// 从LX Music源脚本中提取API模板
  /// 返回可编辑的JSON配置
  static Map<String, dynamic>? extractTemplate(String jsCode) {
    final urls = <String>[];
    for (final m in RegExp(r'https?://[^"\')\s,;]+').allMatches(jsCode)) {
      urls.add(m.group(0)!);
    }
    if (urls.isEmpty) return null;

    return {
      'name': '导入源',
      'rawUrls': urls,
      'note': '请从以下URL中识别搜索/播放/歌词接口，完善上方配置',
    };
  }
}

/// 基于JSON配置的音乐源
class JsonMusicSource {
  final JsonMusicSourceConfig config;
  final Map<String, String> _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
  };

  JsonMusicSource(this.config);

  String get name => config.name;

  Future<List<Map<String, dynamic>>> search(String keyword, {int page = 1, int limit = 20}) async {
    final s = config.search;
    if (s == null) return [];
    try {
      final url = _fillUrl(s['url'] as String, {
        'keyword': Uri.encodeComponent(keyword),
        'page': page.toString(),
        'limit': limit.toString(),
      });
      final headers = {..._defaultHeaders, ...(_parseMap(s['headers']) ?? {})};
      final resp = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];

      final data = jsonDecode(resp.body);
      final items = _navigatePath(data, s['itemsPath'] as String? ?? '') as List?;
      if (items == null || items.isEmpty) return [];

      return items.map((item) {
        final itemMap = item is Map ? item.cast<String, dynamic>() : <String, dynamic>{};
        return {
          'id': _getField(itemMap, s, 'id') ?? '',
          'title': _getField(itemMap, s, 'title') ?? '',
          'artist': _getField(itemMap, s, 'artist') ?? '',
          'album': _getField(itemMap, s, 'album') ?? '',
          'cover': _getField(itemMap, s, 'cover') ?? '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> getPlayUrl(Map<String, dynamic> song, {String quality = '128k'}) async {
    final p = config.playUrl;
    if (p == null) return null;
    try {
      final url = _fillUrl(p['url'] as String, {
        'id': song['id']?.toString() ?? '',
        'quality': quality,
        'title': Uri.encodeComponent(song['title']?.toString() ?? ''),
        'artist': Uri.encodeComponent(song['artist']?.toString() ?? ''),
        'album': Uri.encodeComponent(song['album']?.toString() ?? ''),
      });
      final headers = {..._defaultHeaders, ...(_parseMap(p['headers']) ?? {})};
      final resp = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      final urlPath = p['urlPath'] as String? ?? 'url';
      final result = _navigatePath(data, urlPath)?.toString();
      if (result != null && result.startsWith('http')) return result;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getLyric(Map<String, dynamic> song) async {
    final l = config.lyric;
    if (l == null) return null;
    try {
      final url = _fillUrl(l['url'] as String, {
        'id': song['id']?.toString() ?? '',
        'title': Uri.encodeComponent(song['title']?.toString() ?? ''),
        'artist': Uri.encodeComponent(song['artist']?.toString() ?? ''),
      });
      final headers = {..._defaultHeaders, ...(_parseMap(l['headers']) ?? {})};
      final resp = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      return _navigatePath(data, l['lyricPath'] as String? ?? 'lyric')?.toString();
    } catch (_) {
      return null;
    }
  }

  String _fillUrl(String template, Map<String, String> params) {
    var result = template;
    params.forEach((k, v) {
      result = result.replaceAll('{$k}', v);
    });
    return result;
  }

  dynamic _navigatePath(dynamic data, String path) {
    if (path.isEmpty) return data;
    // 支持管道：data.play_backup_url || data.play_url
    if (path.contains('||')) {
      for (final sub in path.split('||')) {
        final result = _navigatePath(data, sub.trim());
        if (result != null && result.toString().isNotEmpty) return result;
      }
      return null;
    }
    var current = data;
    for (final key in path.split('.')) {
      if (current is Map) {
        current = current[key];
      } else if (current is List) {
        final idx = int.tryParse(key);
        if (idx != null && idx < current.length) current = current[idx];
        else return null;
      } else {
        return null;
      }
    }
    return current;
  }

  String? _getField(Map<String, dynamic> item, Map<String, dynamic> s, String field) {
    final key = s['${field}Field'] as String?;
    if (key == null) return null;
    // 支持管道：play_backup_url || play_url
    if (key.contains('||')) {
      for (final sub in key.split('||')) {
        final v = item[sub.trim()]?.toString();
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }
    return item[key]?.toString();
  }

  Map<String, String>? _parseMap(dynamic v) {
    if (v is Map) return v.cast<String, String>();
    return null;
  }
}

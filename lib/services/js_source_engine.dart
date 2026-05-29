import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

/// ============================================================
/// 狸音乐 JS源引擎
/// 两种模式：
/// 1. JSON配置源 — 轻量，纯Dart
/// 2. WebView JS引擎 — 加载LX Music源脚本，WebView自带V8
/// ============================================================

// ─────────────────────────────────────────────
// 模式1: JSON配置源
// ─────────────────────────────────────────────

/// JSON源配置格式
class JsonMusicSourceConfig {
  final String name;
  final Map<String, dynamic>? search;
  final Map<String, dynamic>? playUrl;
  final Map<String, dynamic>? lyric;

  JsonMusicSourceConfig({required this.name, this.search, this.playUrl, this.lyric});

  factory JsonMusicSourceConfig.fromJson(Map<String, dynamic> json) => JsonMusicSourceConfig(
    name: json['name'] ?? '未知源',
    search: json['search'] as Map<String, dynamic>?,
    playUrl: json['playUrl'] as Map<String, dynamic>?,
    lyric: json['lyric'] as Map<String, dynamic>?,
  );
}

/// 基于JSON配置的源（纯Dart）
class JsonMusicSource {
  final JsonMusicSourceConfig config;
  final Map<String, String> _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
  };

  JsonMusicSource(this.config);
  String get name => config.name;

  Future<List<Map<String, dynamic>>> search(String keyword, {int page = 1, int limit = 20}) async {
    final s = config.search; if (s == null) return [];
    try {
      final url = _fillUrl(s['url'] as String, {
        'keyword': Uri.encodeComponent(keyword), 'page': '$page', 'limit': '$limit',
      });
      final headers = {..._defaultHeaders, ...(_parseMap(s['headers']) ?? {})};
      final resp = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final items = _navigate(data, s['itemsPath'] as String? ?? '') as List?;
      if (items == null || items.isEmpty) return [];
      return items.map((item) {
        final m = item is Map ? item.cast<String, dynamic>() : <String, dynamic>{};
        return {'id': _field(m, s, 'id') ?? '', 'title': _field(m, s, 'title') ?? '', 'artist': _field(m, s, 'artist') ?? '', 'album': _field(m, s, 'album') ?? '', 'cover': _field(m, s, 'cover') ?? ''};
      }).toList();
    } catch (_) { return []; }
  }

  Future<String?> getPlayUrl(Map<String, dynamic> song, {String quality = '128k'}) async {
    final p = config.playUrl; if (p == null) return null;
    try {
      final sid = song['id'].toString();
      final stitle = Uri.encodeComponent(song['title']?.toString() ?? '');
      final sartist = Uri.encodeComponent(song['artist']?.toString() ?? '');
      final salbum = Uri.encodeComponent(song['album']?.toString() ?? '');
      final url = _fillUrl(p['url'] as String, {'id': sid, 'quality': quality, 'title': stitle, 'artist': sartist, 'album': salbum});
      final headers = {..._defaultHeaders, ...(_parseMap(p['headers']) ?? {})};
      final resp = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      final result = _navigate(data, p['urlPath'] as String? ?? 'url')?.toString();
      if (result != null && result.startsWith('http')) return result;
      return null;
    } catch (_) { return null; }
  }

  Future<String?> getLyric(Map<String, dynamic> song) async {
    final l = config.lyric; if (l == null) return null;
    try {
      final sid = song['id'].toString();
      final stitle = Uri.encodeComponent(song['title']?.toString() ?? '');
      final sartist = Uri.encodeComponent(song['artist']?.toString() ?? '');
      final url = _fillUrl(l['url'] as String, {'id': sid, 'title': stitle, 'artist': sartist});
      final resp = await http.get(Uri.parse(url), headers: {..._defaultHeaders, ...(_parseMap(l['headers']) ?? {})}).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      return _navigate(jsonDecode(resp.body), l['lyricPath'] as String? ?? 'lyric')?.toString();
    } catch (_) { return null; }
  }

  String _fillUrl(String t, Map<String, String> p) { var r = t; p.forEach((k, v) { r = r.replaceAll('{$k}', v); }); return r; }
  dynamic _navigate(dynamic d, String p) {
    if (p.isEmpty) return d;
    if (p.contains('||')) { for (final s in p.split('||')) { final r = _navigate(d, s.trim()); if (r != null && '${r}'.isNotEmpty) return r; } return null; }
    var c = d; for (final k in p.split('.')) { if (c is Map) c = c[k]; else if (c is List) { final i = int.tryParse(k); if (i != null && i < c.length) c = c[i]; else return null; } else return null; } return c;
  }
  String? _field(Map<String, dynamic> m, Map<String, dynamic> s, String f) {
    final k = s['${f}Field'] as String?; if (k == null) return null;
    if (k.contains('||')) { for (final sub in k.split('||')) { final v = m[sub.trim()]?.toString(); if (v != null && v.isNotEmpty) return v; } return null; }
    return m[k]?.toString();
  }
  Map<String, String>? _parseMap(dynamic v) { if (v is Map) return v.cast<String, String>(); return null; }
}

// ─────────────────────────────────────────────
// 模式2: WebView JS引擎 — 加载LX Music源脚本
// ─────────────────────────────────────────────

/// JS源脚本加载后的回调
typedef JsSourceCallback = void Function(String name, JsMusicSource source);

/// WebView驱动的JS源引擎
/// 内部创建不可见的WebView，利用V8执行JS
class JsEngineManager {
  static JsEngineManager? _instance;
  WebViewController? _controller;
  bool _ready = false;
  int _reqId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};
  final List<_RegisteredSource> _sources = [];

  static JsEngineManager get instance {
    _instance ??= JsEngineManager._();
    return _instance!;
  }

  JsEngineManager._();

  /// 初始化WebView引擎
  Future<void> init() async {
    if (_ready) return;
    final completer = Completer<void>();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
        _setupBridge();
        _ready = true;
        completer.complete();
      }))
      ..loadHtmlString(_getEngineHtml());

    await completer.future.timeout(const Duration(seconds: 10));
  }

  String _getEngineHtml() => '''
<!DOCTYPE html><html><body><script>
var _lx_callbacks = {};
var _lx_callback_id = 0;
var _lx_sources = [];

// 注册源
function lxRegisterSource(src) { _lx_sources.push(src); }

// HTTP请求桥
function lxRequest(url, options) {
  return new Promise(function(resolve, reject) {
    var id = ++_lx_callback_id;
    _lx_callbacks[id] = {resolve: resolve, reject: reject};
    LxBridge.postMessage(JSON.stringify({
      type: 'request', id: id, url: url,
      method: (options && options.method) || 'GET',
      headers: (options && options.headers) || {},
      body: (options && options.body) || null
    }));
  });
}

// Crypto工具
var lxCrypto = {
  md5: function(str) {
    var id = ++_lx_callback_id;
    _lx_callbacks[id] = {resolve: function(r) { return r; }, reject: function(e) { throw e; }};
    LxBridge.postMessage(JSON.stringify({type: 'md5', id: id, str: str}));
    return _lx_callbacks[id].result;
  },
  aesEncrypt: function(data, mode, key, iv) {
    var id = ++_lx_callback_id;
    LxBridge.postMessage(JSON.stringify({type: 'aes', id: id, data: data, mode: mode, key: key, iv: iv}));
    return "pending";
  }
};
</script></body></html>
''';

  /// 建立Dart↔JS通信桥
  void _setupBridge() {
    _controller?.addJavaScriptChannel('LxBridge', onMessageReceived: (msg) {
      try {
        final data = jsonDecode(msg.message) as Map<String, dynamic>;
        final type = data['type'] as String;
        final id = data['id'] as int;

        if (type == 'request') {
          _handleJsRequest(id, data['url'] as String, data['method'] as String? ?? 'GET',
              (data['headers'] as Map?)?.cast<String, String>() ?? {}, data['body'] as String?);
        } else if (type == 'result') {
          final completer = _pendingRequests.remove(id);
          completer?.complete(data);
        }
      } catch (_) {}
    });
  }

  /// 加载本地JS源脚本文件
  Future<void> loadJsFile(String jsCode, {JsSourceCallback? onLoaded}) async {
    await init();
    // 注入bridge函数定义
    await _controller?.runJavaScript('''
      (function() {
        // 替换原始request实现为lxRequest
        $jsCode
        // 遍历已注册的源
        for (var i = 0; i < _lx_sources.length; i++) {
          var src = _lx_sources[i];
          LxBridge.postMessage(JSON.stringify({
            type: 'source_registered',
            name: src.info ? src.info.name : ('源' + i)
          }));
        }
      })()
    ''');
  }

  /// 调用JS源获取播放URL
  Future<String?> getMusicUrl(String sourceName, Map<String, dynamic> params, String quality) async {
    if (!_ready) return null;
    try {
      final result = await _controller?.runJavaScriptReturningResult('''
        (async function() {
          for (var i = 0; i < _lx_sources.length; i++) {
            var s = _lx_sources[i];
            if (s.info && s.info.name == '$sourceName') {
              try {
                var url = await s.musicUrl(${jsonEncode(params)}, '$quality');
                return JSON.stringify({url: url});
              } catch(e) {
                return JSON.stringify({error: e.message});
              }
            }
          }
          return JSON.stringify({error: 'source not found'});
        })()
      ''');
      final resultStr = result?.toString() ?? '{}';
      final data = jsonDecode(resultStr);
      if (data is Map && data['url'] != null) return data['url'].toString();
      return null;
    } catch (_) { return null; }
  }

  /// 处理JS发起的HTTP请求
  Future<void> _handleJsRequest(int id, String url, String method, Map<String, String> headers, String? body) async {
    try {
      final uri = Uri.parse(url);
      final req = http.Request(method, uri);
      req.headers.addAll({'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36', ...headers});
      if (body != null && method == 'POST') req.body = body;
      final streamed = await req.send().timeout(const Duration(seconds: 15));
      final respBody = await streamed.stream.bytesToString();
      final parsed = _tryParseJson(respBody);
      final resp = {'status': streamed.statusCode, 'body': parsed ?? respBody, 'headers': streamed.headers};

      await _controller?.runJavaScript('''
        (function() {
          var cb = _lx_callbacks[$id];
          if (cb) {
            delete _lx_callbacks[$id];
            cb.resolve(${jsonEncode(resp)});
          }
        })()
      ''');
    } catch (e) {
      await _controller?.runJavaScript('''
        (function() {
          var cb = _lx_callbacks[$id];
          if (cb) { delete _lx_callbacks[$id]; cb.reject("${e.toString().replaceAll('"', '\\"')}"); }
        })()
      ''');
    }
  }

  dynamic _tryParseJson(String text) { try { return jsonDecode(text); } catch (_) { return null; } }

  void dispose() {
    _controller = null;
    _ready = false;
    _instance = null;
  }
}

/// WebView JS源实例（包装一个已加载的JS源）
class JsMusicSource {
  final String name;
  final JsEngineManager _engine;

  JsMusicSource(this.name, this._engine);

  Future<String?> getPlayUrl(Map<String, dynamic> params, String quality) async {
    return await _engine.getMusicUrl(name, params, quality);
  }
}

class _RegisteredSource {
  final String name;
  _RegisteredSource(this.name);
}

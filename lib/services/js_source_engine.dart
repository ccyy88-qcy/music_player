import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;

/// LX Music 风格的JS源脚本引擎
/// 提供 request/crypto 等原生函数给 JS 环境
class JsEngine {
  late final JavascriptRuntime _runtime;
  bool _initialized = false;

  // JS回调映射
  int _callbackId = 0;
  final Map<int, void Function(Map<String, dynamic>)> _callbacks = {};

  /// 初始化JS引擎
  JsEngine() {
    _runtime = getJavascriptRuntime();
  }

  /// 加载预置的bridge脚本和用户源脚本
  Future<void> loadSource(String jsCode) async {
    if (!_initialized) {
      _initBridge();
      _initialized = true;
    }
    _runtime.evaluate(jsCode);
  }

  /// 调用JS中的 source.musicUrl 获取播放地址
  Future<String?> getMusicUrl(Map<String, dynamic> params, String quality) async {
    final jsCode = '''
      (async () => {
        try {
          const result = await _lx_sources[0].musicUrl(${jsonEncode(params)}, '$quality');
          return JSON.stringify(result);
        } catch(e) {
          return JSON.stringify({error: e.message || 'failed'});
        }
      })()
    ''';
    final result = _runtime.evaluate(jsCode);
    final data = jsonDecode(result.stringResult);
    if (data is Map && data['error'] != null) return null;
    return data is String ? data : data['url']?.toString();
  }

  /// 调用JS中的 source.search 搜索歌曲
  Future<List<Map<String, dynamic>>> search(String keyword, {int page = 1, int limit = 20}) async {
    final jsCode = '''
      (async () => {
        try {
          const result = await _lx_sources[0].search('${keyword.replaceAll("'", "\\'")}', $page, $limit);
          return JSON.stringify(result);
        } catch(e) {
          return JSON.stringify([]);
        }
      })()
    ''';
    final result = _runtime.evaluate(jsCode);
    final list = jsonDecode(result.stringResult) as List?;
    if (list == null) return [];
    return list.cast<Map<String, dynamic>>();
  }

  /// 获取源信息
  Map<String, dynamic>? get sourceInfo {
    final result = _runtime.evaluate('''JSON.stringify(_lx_sources[0]?.info || {})''');
    final data = jsonDecode(result.stringResult);
    if (data is Map && data.isNotEmpty) return data.cast<String, dynamic>();
    return null;
  }

  /// 初始化bridge：定义JS全局函数
  void _initBridge() {
    // 源注册函数
    _runtime.evaluate('''
      var _lx_sources = [];
      var _lx_callback_id = 0;
      var _lx_callbacks = {};

      function lxSourceRegister(source) {
        _lx_sources.push(source);
      }

      // request: HTTP请求
      function lxRequest(url, options) {
        return new Promise((resolve, reject) => {
          var id = ++_lx_callback_id;
          _lx_callbacks[id] = { resolve, reject };
          sendMessage('request', JSON.stringify({
            id: id,
            url: url,
            method: options?.method || 'GET',
            headers: options?.headers || {},
            body: options?.body || null
          }));
        });
      }
    ''');

    // 注册收到JS消息的回调
    _runtime.onMessage('request', (args) {
      final data = jsonDecode(args[0] as String);
      final id = data['id'] as int;
      final url = data['url'] as String;
      final method = data['method'] as String? ?? 'GET';
      final headers = (data['headers'] as Map?)?.cast<String, String>() ?? {};
      final body = data['body'] as String?;
      _handleHttpRequest(id, url, method, headers, body);
    });
  }

  Future<void> _handleHttpRequest(int id, String url, String method, Map<String, String> headers, String? body) async {
    try {
      final http = await _makeHttpCall(url, method, headers, body);
      final jsCode = '''
        (function() {
          var cb = _lx_callbacks['$id'];
          if (cb) {
            delete _lx_callbacks['$id'];
            cb.resolve(JSON.parse('${jsonEncode(http).replaceAll("'", "\\'")}'));
          }
        })()
      ''';
      _runtime.evaluate(jsCode);
    } catch (e) {
      final jsCode = '''
        (function() {
          var cb = _lx_callbacks['$id'];
          if (cb) {
            delete _lx_callbacks['$id'];
            cb.reject(new Error('${e.toString().replaceAll("'", "\\'").replaceAll(RegExp(r'[\n\r]'), ' ')}'));
          }
        })()
      ''';
      _runtime.evaluate(jsCode);
    }
  }

  Future<Map<String, dynamic>> _makeHttpCall(String url, String method, Map<String, String> headers, String? body) async {
    try {
      final uri = Uri.parse(url);
      final request = http.Request(method, uri);
      request.headers.addAll({'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36', ...headers});
      if (body != null && method == 'POST') request.body = body;
      final streamed = await request.send().timeout(const Duration(seconds: 15));
      final responseBody = await streamed.stream.bytesToString();
      final respHeaders = streamed.headers;
      return {
        'status': streamed.statusCode,
        'body': _tryParseJson(responseBody) ?? responseBody,
        'headers': respHeaders,
      };
    } catch (e) {
      return {'status': 0, 'body': e.toString(), 'headers': <String, String>{}};
    }
  }

  dynamic _tryParseJson(String text) {
    try { return jsonDecode(text); } catch (_) { return null; }
  }

  void dispose() {
    // flutter_js doesn't have explicit dispose in older versions
  }
}

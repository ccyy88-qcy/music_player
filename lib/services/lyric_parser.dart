import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// LRC 歌词行
class LyricLine {
  final Duration time;
  final String text;

  const LyricLine(this.time, this.text);
}

/// LRC 格式解析器 + 在线搜索
class LyricParser {
  /// 从文件路径解析歌词（找同名 .lrc 文件）
  static Future<List<LyricLine>> fromAudioPath(String audioPath) async {
    final lrcPath = _findLrcFile(audioPath);
    if (lrcPath == null) return [];

    try {
      final content = await File(lrcPath).readAsString();
      return parse(content);
    } catch (_) {
      return [];
    }
  }

  /// 查找同名的 .lrc 文件
  static String? _findLrcFile(String audioPath) {
    for (final ext in ['.lrc', '.LRC']) {
      final lrcPath = audioPath.replaceAll(RegExp(r'\.[^.]+$'), ext);
      if (File(lrcPath).existsSync()) return lrcPath;
    }
    return null;
  }

  /// 在线搜索歌词（使用 LRCLIB API + 网易云 fallback）
  static Future<List<LyricLine>> searchOnline(
    String title,
    String artist,
  ) async {
    // 尝试多种搜索方式：原歌名 → 清理后 → 括号前 → 只要歌名主体
    final searchQueries = <String>[];
    searchQueries.add(title);
    final cleaned = _cleanTitle(title);
    if (cleaned != title && cleaned.isNotEmpty) searchQueries.add(cleaned);
    // 取括号/破折号前的主体部分
    final mainPart = title.split(RegExp(r'[\(（\-—]')).first.trim();
    if (mainPart != title && mainPart != cleaned && mainPart.isNotEmpty) searchQueries.add(mainPart);

    for (final query in searchQueries) {
      try {
        final lrc = await _searchLRCLIB(query, artist);
        if (lrc.isNotEmpty) return lrc;
      } catch (_) {}
      try {
        final neteaseLrc = await _searchNetease(query, artist);
        if (neteaseLrc.isNotEmpty) return neteaseLrc;
      } catch (_) {}
    }
    return [];
  }

  /// LRCLIB 歌词搜索
  static Future<List<LyricLine>> _searchLRCLIB(String title, String artist) async {
    final queryTitle = Uri.encodeComponent(_cleanTitle(title));
    final queryArtist = artist.isNotEmpty ? Uri.encodeComponent(artist) : '';

    final url = queryArtist.isNotEmpty
        ? 'https://lrclib.net/api/search?track_name=$queryTitle&artist_name=$queryArtist'
        : 'https://lrclib.net/api/search?track_name=$queryTitle';

    final response = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return [];

    final results = jsonDecode(response.body) as List;
    if (results.isEmpty) return [];
    final best = results.first as Map<String, dynamic>;
    final syncedLyrics = best['syncedLyrics'] as String?;
    if (syncedLyrics != null && syncedLyrics.isNotEmpty) return parse(syncedLyrics);

    final plainLyrics = best['plainLyrics'] as String?;
    if (plainLyrics != null && plainLyrics.isNotEmpty) return _plainToLyric(plainLyrics);
    return [];
  }

  /// 网易云歌词搜索（用于中文歌曲）
  static Future<List<LyricLine>> _searchNetease(String title, String artist) async {
    // 先搜索获取歌曲ID
    final cleanTitle = _cleanTitle(title);
    final searchUrl = 'https://music.163.com/api/search/get?s=${Uri.encodeComponent(cleanTitle)}&type=1&limit=5';
    final searchResp = await http.get(Uri.parse(searchUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
      'Referer': 'https://music.163.com/',
    }).timeout(const Duration(seconds: 8));
    if (searchResp.statusCode != 200) return [];

    final searchData = jsonDecode(searchResp.body);
    final songs = searchData['result']?['songs'] as List?;
    if (songs == null || songs.isEmpty) return [];

    // 取第一个匹配结果
    final firstId = songs.first['id'];
    if (firstId == null) return [];

    // 获取歌词
    final lyricUrl = 'https://music.163.com/api/song/lyric?id=$firstId&lv=1&kv=1&tv=-1';
    final lyricResp = await http.get(Uri.parse(lyricUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
      'Referer': 'https://music.163.com/',
    }).timeout(const Duration(seconds: 6));
    if (lyricResp.statusCode != 200) return [];

    final lyricData = jsonDecode(lyricResp.body);
    final lrcText = lyricData['lrc']?['lyric']?.toString();
    if (lrcText != null && lrcText.isNotEmpty) return parse(lrcText);

    final tlyric = lyricData['tlyric']?['lyric']?.toString();
    if (tlyric != null && tlyric.isNotEmpty) return parse(tlyric);
    return [];
  }

  /// 清理歌名（去掉多余标记），DJ歌也能匹配到原版歌词
  static String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'[\[\(].*?(?:原版|伴奏|inst|cover|live|remix|DJ|dj|版|mix|heap|伟然|默涵|版|九天|九零|heap|Heap).*?[\]\)]'), '')
        .replaceAll(RegExp(r'[\[\(].*?[\]\)]'), '')
        .replaceAll(RegExp(r'\s*[-–—]\s*.*$'), '')
        .trim();
  }

  /// 纯文本转换为伪 LRC（每行 5 秒间隔）
  static List<LyricLine> _plainToLyric(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return List.generate(lines.length, (i) {
      return LyricLine(
        Duration(seconds: i * 5),
        lines[i].trim(),
      );
    });
  }

  /// 解析 LRC 文本
  static List<LyricLine> parse(String content) {
    final lines = <LyricLine>[];
    final timeRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

    for (final line in content.split('\n')) {
      final matches = timeRegex.allMatches(line).toList();
      final text = line.replaceAll(timeRegex, '').trim();

      if (text.isEmpty) continue;

      for (final match in matches) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        var msStr = match.group(3)!;
        if (msStr.length == 2) msStr = '${msStr}0';
        final ms = int.parse(msStr);

        lines.add(LyricLine(
          Duration(minutes: min, seconds: sec, milliseconds: ms),
          text,
        ));
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// 根据当前播放位置找到对应的歌词行索引
  static int findCurrentIndex(List<LyricLine> lyrics, Duration position) {
    if (lyrics.isEmpty) return 0;
    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (position >= lyrics[i].time) return i;
    }
    return -1;
  }
}

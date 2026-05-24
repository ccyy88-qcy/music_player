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

  /// 在线搜索歌词（使用 LRCLIB API）
  static Future<List<LyricLine>> searchOnline(
    String title,
    String artist,
  ) async {
    try {
      final queryTitle = Uri.encodeComponent(_cleanTitle(title));
      final queryArtist = artist.isNotEmpty
          ? Uri.encodeComponent(artist)
          : '';

      // LRCLIB API - 免费歌词服务
      final url = queryArtist.isNotEmpty
          ? 'https://lrclib.net/api/search?track_name=$queryTitle&artist_name=$queryArtist'
          : 'https://lrclib.net/api/search?track_name=$queryTitle';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];

      final results = jsonDecode(response.body) as List;
      if (results.isEmpty) return [];

      // 取第一个匹配结果
      final best = results.first as Map<String, dynamic>;
      final syncedLyrics = best['syncedLyrics'] as String?;

      if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
        return parse(syncedLyrics);
      }

      // 如果没有同步歌词，尝试纯文本
      final plainLyrics = best['plainLyrics'] as String?;
      if (plainLyrics != null && plainLyrics.isNotEmpty) {
        return _plainToLyric(plainLyrics);
      }
    } catch (_) {}

    return [];
  }

  /// 清理歌名（去掉多余标记）
  static String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'[\[\(].*?(?:原版|伴奏|inst|cover|live|DJ|Remix).*?[\]\)]',
            caseSensitive: false), '')
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
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

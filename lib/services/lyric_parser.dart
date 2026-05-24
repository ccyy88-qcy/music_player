import 'dart:io';

/// LRC 歌词行
class LyricLine {
  final Duration time;
  final String text;

  const LyricLine(this.time, this.text);
}

/// LRC 格式解析器
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
    // 尝试同目录同名 .lrc
    for (final ext in ['.lrc', '.LRC']) {
      final lrcPath = audioPath.replaceAll(RegExp(r'\.[^.]+$'), ext);
      if (File(lrcPath).existsSync()) return lrcPath;
    }
    return null;
  }

  /// 解析 LRC 文本内容
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
        // 统一为毫秒
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
    if (lyrics.isEmpty) return -1;
    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (position >= lyrics[i].time) return i;
    }
    return -1;
  }
}

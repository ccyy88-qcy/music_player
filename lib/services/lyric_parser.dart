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

  /// 在线搜索歌词
  static Future<List<LyricLine>> searchOnline(String title, String artist) async {
    final searchQueries = <String>[];
    searchQueries.add(title);
    final cleaned = _cleanTitle(title);
    if (cleaned != title && cleaned.isNotEmpty) searchQueries.add(cleaned);
    final mainPart = title.split(RegExp(r'[\\(（\\\\-—]')).first.trim();
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
    try {
      final resp = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return [];
      final results = jsonDecode(resp.body) as List;
      if (results.isEmpty) return [];
      final best = results.first as Map<String, dynamic>;
      final synced = best['syncedLyrics'] as String?;
      if (synced != null && synced.isNotEmpty) return parse(synced);
      final plain = best['plainLyrics'] as String?;
      if (plain != null && plain.isNotEmpty) return _plainToLyric(plain);
      return [];
    } catch (_) { return []; }
  }

  /// 网易云歌词搜索
  static Future<List<LyricLine>> _searchNetease(String title, String artist) async {
    final cleanTitle = _cleanTitle(title);
    try {
      final searchUrl = 'https://music.163.com/api/search/get?s=${Uri.encodeComponent(cleanTitle)}&type=1&limit=5';
      final sr = await http.get(Uri.parse(searchUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'https://music.163.com/',
      }).timeout(const Duration(seconds: 8));
      if (sr.statusCode != 200) return [];
      final sd = jsonDecode(sr.body);
      final songs = sd['result']?['songs'] as List?;
      if (songs == null || songs.isEmpty) return [];
      final firstId = songs.first['id'];
      if (firstId == null) return [];
      final lyricUrl = 'https://music.163.com/api/song/lyric?id=$firstId&lv=1&kv=1&tv=-1';
      final lr = await http.get(Uri.parse(lyricUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'https://music.163.com/',
      }).timeout(const Duration(seconds: 6));
      if (lr.statusCode != 200) return [];
      final ld = jsonDecode(lr.body);
      final lrc = ld['lrc']?['lyric']?.toString();
      if (lrc != null && lrc.isNotEmpty) return parse(lrc);
      final tlrc = ld['tlyric']?['lyric']?.toString();
      if (tlrc != null && tlrc.isNotEmpty) return parse(tlrc);
      return [];
    } catch (_) { return []; }
  }

  /// 清理歌名（去掉多余标记）
  static String _cleanTitle(String title) {
    // 先清理括号内的各种标记
    String result = title
        .replaceAll(RegExp(
            r'[\[（(][^）\]]*?(?:原版|伴奏|inst|cover|live|remix|DJ|dj|版|'
            r'mix|heap|伟然|默涵|九天|九零|Heap|翻唱|官方|纯净|'
            r'人声|鼓点|Bass|Dubstep|Trap|Hardstyle|Future|浩室|'
            r'慢摇|慢嗨|串烧|车载|重低音|低音炮|EDM|House|Techno|'
            r'Trance|Club|Party|夜店|嗨曲|摇头|劲爆|弹跳|越南鼓|'
            r'舞曲|电音|蹦迪|Remix|混音|DJ版|完整版|'
            r'高音质|高品质|无损|FLAC|320K|超清)[^）\]]*[）\]]'),
            '')
        .replaceAll(RegExp(r'[\[（(][^）\]]*[）\]]'), '')
        .replaceAll(RegExp(r'\s*[-–—|/]\s*.*$'), '')
        .trim();
    return result;
  }

  /// 纯文本转换为伪 LRC（根据行数估算间隔）
  static List<LyricLine> _plainToLyric(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return [];
    const estimatedSec = 240;
    final interval = (estimatedSec / lines.length).clamp(2.0, 8.0);
    return List.generate(lines.length, (i) => LyricLine(
      Duration(milliseconds: (i * interval * 1000).round()),
      lines[i].trim(),
    ));
  }

  /// 解析 LRC 文本（支持多种时间格式）
  static List<LyricLine> parse(String content) {
    final lines = <LyricLine>[];
    final timeRegex = RegExp(r'\[(\d{1,2})[:.](\d{2})[:.](\d{2,3})\]');
    for (final line in content.split('\n')) {
      final matches = timeRegex.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final text = line.replaceAll(timeRegex, '').trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        String ms = m.group(3)!;
        if (ms.length == 2) ms = '${ms}0';
        else if (ms.length > 3) ms = ms.substring(0, 3);
        lines.add(LyricLine(
          Duration(minutes: min, seconds: sec, milliseconds: int.parse(ms)),
          text,
        ));
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    // 去重：连续相同文本只保留第一个
    final deduped = <LyricLine>[];
    for (int i = 0; i < lines.length; i++) {
      if (i > 0 && lines[i].text == lines[i - 1].text) continue;
      deduped.add(lines[i]);
    }
    return deduped;
  }

  /// 根据播放位置找到歌词行索引（带偏移校正）
  static int findCurrentIndex(List<LyricLine> lyrics, Duration position, [int offsetMs = 0]) {
    if (lyrics.isEmpty) return -1;
    final adjusted = position.inMilliseconds + offsetMs;
    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (adjusted >= lyrics[i].time.inMilliseconds) return i;
    }
    return 0;
  }
}

/// DJ 分类关键词 — 匹配文件夹名或文件名
const djKeywords = [
  'DJ', 'dj', 'Remix', 'remix',
  '混音', '串烧', '慢摇', '电音', '舞曲', '蹦迪',
  'EDM', 'House', 'Techno', 'Trance', 'Dubstep',
  'Club', 'Party', '车载', '重低音', '低音炮',
  'Bass', 'Drop', 'Trap', 'Hardstyle',
  '夜店', '嗨曲', '摇头', '劲爆',
];

/// 支持的音频格式
const audioExtensions = ['.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma'];

enum MusicCategory { dj, pop }

class Song {
  final String title;
  final String artist;
  final String filePath;
  final MusicCategory category;
  final int? durationMs;

  const Song({
    required this.title,
    required this.artist,
    required this.filePath,
    required this.category,
    this.durationMs,
  });

  /// 从文件路径判断分类
  static MusicCategory classifySong(String filePath, String fileName) {
    final combined = '${filePath}/$fileName'.toLowerCase();
    for (final kw in djKeywords) {
      if (combined.contains(kw.toLowerCase())) {
        return MusicCategory.dj;
      }
    }
    return MusicCategory.pop;
  }

  /// 从文件路径提取歌名（去扩展名）
  static String extractTitle(String fileName) {
    for (final ext in audioExtensions) {
      if (fileName.toLowerCase().endsWith(ext)) {
        return fileName.substring(0, fileName.length - ext.length);
      }
    }
    return fileName;
  }
}

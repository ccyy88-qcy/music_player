/// DJ 分类关键词 — 匹配文件夹名或文件名
const djKeywords = [
  'DJ', 'dj', 'Remix', 'remix',
  '混音', '串烧', '慢摇', '电音', '舞曲', '蹦迪',
  'EDM', 'House', 'Techno', 'Trance', 'Dubstep',
  'Club', 'Party', '车载', '重低音', '低音炮',
  'Bass', 'Drop', 'Trap', 'Hardstyle',
  '夜店', '嗨曲', '摇头', '劲爆', '弹跳', '越南鼓',
  'Future Bass', 'Big Room', 'Progressive',
];

/// 全格式音频扩展名
const audioExtensions = [
  '.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma',
  '.opus', '.aiff', '.alac', '.ape', '.wv', '.tta', '.mp2',
  '.ac3', '.dts', '.amr', '.mid', '.midi', '.ra', '.mpc',
  '.spx', '.caf', '.au', '.pcm', '.aif', '.mka', '.3gp',
  '.weba', '.webm',
];

/// 跳过的系统目录
const skipDirs = {
  'Android', 'Lost.Dir', 'System Volume Information',
  '.thumbnails', '.Trash', 'cache', 'temp', 'tmp',
};

enum MusicCategory { dj, pop }

class Song {
  final String title;
  final String artist;
  final String filePath;
  final MusicCategory category;
  final int fileSize;       // 字节
  final int lastModified;   // epoch ms
  bool isFavorite;
  int playCount;
  int lastPlayed;           // epoch ms

  Song({
    required this.title,
    required this.artist,
    required this.filePath,
    required this.category,
    this.fileSize = 0,
    this.lastModified = 0,
    this.isFavorite = false,
    this.playCount = 0,
    this.lastPlayed = 0,
  });

  /// 唯一标识（文件路径）
  String get id => filePath;

  /// 从文件路径判断分类
  static MusicCategory classifySong(String filePath, String fileName) {
    final combined = '$filePath/$fileName'.toLowerCase();
    for (final kw in djKeywords) {
      if (combined.contains(kw.toLowerCase())) {
        return MusicCategory.dj;
      }
    }
    return MusicCategory.pop;
  }

  /// 从文件路径提取歌名（去扩展名，清理多余标记）
  static String extractTitle(String fileName) {
    var name = fileName;
    for (final ext in audioExtensions) {
      if (name.toLowerCase().endsWith(ext)) {
        name = name.substring(0, name.length - ext.length);
        break;
      }
    }
    // 清理常见下载标记
    name = name.replaceAll(RegExp(r'[\[\(]www\..*?[\]\)]'), '');
    name = name.replaceAll(RegExp(r'（.*?(?:原版|伴奏|inst|cover).*?）'), '');
    return name.trim();
  }

  /// JSON 序列化（用于缓存）
  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'filePath': filePath,
    'category': category.name,
    'fileSize': fileSize,
    'lastModified': lastModified,
    'isFavorite': isFavorite,
    'playCount': playCount,
    'lastPlayed': lastPlayed,
  };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    title: json['title'] as String,
    artist: json['artist'] as String? ?? '',
    filePath: json['filePath'] as String,
    category: MusicCategory.values.firstWhere(
      (e) => e.name == json['category'],
      orElse: () => MusicCategory.pop,
    ),
    fileSize: json['fileSize'] as int? ?? 0,
    lastModified: json['lastModified'] as int? ?? 0,
    isFavorite: json['isFavorite'] as bool? ?? false,
    playCount: json['playCount'] as int? ?? 0,
    lastPlayed: json['lastPlayed'] as int? ?? 0,
  );

  Song copyWith({
    bool? isFavorite,
    int? playCount,
    int? lastPlayed,
  }) => Song(
    title: title,
    artist: artist,
    filePath: filePath,
    category: category,
    fileSize: fileSize,
    lastModified: lastModified,
    isFavorite: isFavorite ?? this.isFavorite,
    playCount: playCount ?? this.playCount,
    lastPlayed: lastPlayed ?? this.lastPlayed,
  );
}

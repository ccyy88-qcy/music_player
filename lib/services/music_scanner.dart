import 'dart:io';
import 'dart:isolate';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';
import 'storage_manager.dart';

/// 全格式音乐扫描器 — 支持全盘/自定义目录/增量扫描
class MusicScanner {
  /// 请求权限
  static Future<bool> requestPermission() async {
    final audio = await Permission.audio.request();
    if (audio.isGranted) return true;
    final storage = await Permission.storage.request();
    if (storage.isGranted) return true;
    final manage = await Permission.manageExternalStorage.request();
    return manage.isGranted;
  }

  /// 扫描所有音乐 — 根据设置选择模式
  static Future<Map<MusicCategory, List<Song>>> scanAll({
    bool forceFullScan = false,
  }) async {
    final store = await StorageManager.instance;

    // 增量扫描：如果有缓存且非强制全扫，只检查新文件
    if (!forceFullScan && store.lastScanTime > 0) {
      final cached = store.loadSongCache();
      if (cached.isNotEmpty) {
        return _incrementalScan(cached, await _getScanDirs());
      }
    }

    return _fullScan(await _getScanDirs());
  }

  /// 获取要扫描的目录
  static Future<List<String>> _getScanDirs() async {
    final store = await StorageManager.instance;
    final mode = store.scanMode;

    if (mode == 'full') {
      // 全盘扫描：遍历 /storage/emulated/0 下的所有一级目录（跳过系统目录）
      return _getFullScanDirs();
    }

    // 快速模式：预设 + 自定义目录
    return store.getScanDirs();
  }

  /// 获取全盘扫描目录列表
  static List<String> _getFullScanDirs() {
    const root = '/storage/emulated/0';
    final dirs = <String>[root];
    try {
      final rootDir = Directory(root);
      if (rootDir.existsSync()) {
        for (final entity in rootDir.listSync()) {
          if (entity is Directory) {
            final name = entity.uri.pathSegments.last;
            if (!skipDirs.contains(name) && !name.startsWith('.')) {
              dirs.add(entity.path);
            }
          }
        }
      }
    } catch (_) {}
    return dirs;
  }

  /// 全量扫描（后台 isolate）
  static Future<Map<MusicCategory, List<Song>>> _fullScan(
      List<String> dirs) async {
    final allSongs = <Song>[];

    for (final dir in dirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      allSongs.addAll(await _scanDirAsync(d, maxDepth: 4));
    }

    return _categorize(allSongs);
  }

  /// 增量扫描：基于缓存，只检查新增/修改的文件
  static Future<Map<MusicCategory, List<Song>>> _incrementalScan(
    Map<String, Song> cached,
    List<String> dirs,
  ) async {
    // 先扫描当前文件
    final current = <String, Song>{};
    for (final dir in dirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      final songs = await _scanDirAsync(d, maxDepth: 4);
      for (final s in songs) {
        current[s.id] = s;
      }
    }

    // 增量合并：保留缓存中的收藏/播放计数
    for (final entry in current.entries) {
      final cachedSong = cached[entry.key];
      if (cachedSong != null) {
        entry.value.isFavorite = cachedSong.isFavorite;
        entry.value.playCount = cachedSong.playCount;
        entry.value.lastPlayed = cachedSong.lastPlayed;
      }
    }

    // 保存缓存
    final store = await StorageManager.instance;
    await store.saveSongCache(current);
    await store.setLastScanTime(DateTime.now().millisecondsSinceEpoch);

    return _categorize(current.values.toList());
  }

  /// 异步扫描目录（递归）
  static Future<List<Song>> _scanDirAsync(Directory dir,
      {int maxDepth = 3}) async {
    return await Isolate.run(() => _scanDirSync(dir.path, maxDepth));
  }

  /// 同步扫描（在 isolate 中运行）
  static List<Song> _scanDirSync(String dirPath, int depth) {
    final songs = <Song>[];
    if (depth <= 0) return songs;

    final dir = Directory(dirPath);
    List<FileSystemEntity> entities;
    try {
      entities = dir.listSync(recursive: false, followLinks: false);
    } catch (_) {
      return songs;
    }

    for (final entity in entities) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        final ext = name.toLowerCase();
        if (audioExtensions.any((e) => ext.endsWith(e))) {
          final title = Song.extractTitle(name);
          if (title.length > 1) {
            try {
              final stat = entity.statSync();
              songs.add(Song(
                title: title,
                artist: '',
                filePath: entity.path,
                category: Song.classifySong(dirPath, name),
                fileSize: stat.size,
                lastModified: stat.modified.millisecondsSinceEpoch,
              ));
            } catch (_) {
              songs.add(Song(
                title: title,
                artist: '',
                filePath: entity.path,
                category: Song.classifySong(dirPath, name),
              ));
            }
          }
        }
      } else if (entity is Directory) {
        final name = entity.uri.pathSegments.last;
        if (!skipDirs.contains(name) && !name.startsWith('.')) {
          songs.addAll(_scanDirSync(entity.path, depth - 1));
        }
      }
    }
    return songs;
  }

  /// 分类排序
  static Map<MusicCategory, List<Song>> _categorize(List<Song> songs) {
    final dj = <Song>[];
    final pop = <Song>[];
    for (final s in songs) {
      (s.category == MusicCategory.dj ? dj : pop).add(s);
    }
    dj.sort((a, b) => a.title.compareTo(b.title));
    pop.sort((a, b) => a.title.compareTo(b.title));
    return {MusicCategory.dj: dj, MusicCategory.pop: pop};
  }

  /// 获取单个目录的歌曲数（预览用）
  static int countSongsInDir(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return 0;
    var count = 0;
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          final ext = entity.uri.pathSegments.last.toLowerCase();
          if (audioExtensions.any((e) => ext.endsWith(e))) count++;
        }
      }
    } catch (_) {}
    return count;
  }
}

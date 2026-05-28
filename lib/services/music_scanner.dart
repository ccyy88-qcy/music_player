import 'dart:io';
import 'dart:isolate';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';
import 'storage_manager.dart';

/// 扫描进度回调
typedef ScanProgressCallback = void Function(int scanned, int current, String dir);

class MusicScanner {
  /// 请求权限（优先MANAGE_EXTERNAL_STORAGE以支持文件扫描）
  static Future<bool> requestPermission() async {
    // 管理所有文件权限（Android 11+，可读全部目录）
    if (await Permission.manageExternalStorage.request().isGranted) return true;
    // Android 13+ - 读取音频权限
    if (await Permission.audio.request().isGranted) return true;
    // 老版本存储权限
    if (await Permission.storage.request().isGranted) return true;
    return false;
  }

  /// 检查权限是否已授予（不弹框）
  static Future<bool> hasPermission() async {
    if (await Permission.audio.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    return false;
  }

  /// 打开系统设置页让用户手动授权
  static Future<void> openSettings() async {
    await openAppSettings();
  }

  /// 扫描所有音乐
  static Future<Map<MusicCategory, List<Song>>> scanAll({
    bool forceFullScan = false,
    ScanProgressCallback? onProgress,
  }) async {
    final store = await StorageManager.instance;

    // 增量扫描
    if (!forceFullScan && store.lastScanTime > 0) {
      final cached = store.loadSongCache();
      if (cached.isNotEmpty) {
        return _incrementalScan(cached, await _getScanDirs(), onProgress);
      }
    }

    return _fullScan(await _getScanDirs(), onProgress);
  }

  static Future<List<String>> _getScanDirs() async {
    final store = await StorageManager.instance;
    if (store.scanMode == 'full') return _getFullScanDirs();
    return store.getScanDirs();
  }

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

  /// 全量扫描
  static Future<Map<MusicCategory, List<Song>>> _fullScan(
      List<String> dirs, ScanProgressCallback? onProgress) async {
    final allSongs = <String, Song>{}; // 用 Map 去重（key = filePath）
    int scanned = 0;

    for (final dir in dirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      final songs = await _scanDirAsync(d, maxDepth: 4);
      for (final s in songs) {
        // 去重：同一路径只保留一次
        if (!allSongs.containsKey(s.filePath)) {
          allSongs[s.filePath] = s;
          scanned++;
          onProgress?.call(scanned, songs.length, dir);
        }
      }
    }

    // 保存缓存
    final store = await StorageManager.instance;
    await store.saveSongCache(allSongs);
    await store.setLastScanTime(DateTime.now().millisecondsSinceEpoch);

    return _categorize(allSongs.values.toList());
  }

  /// 增量扫描
  static Future<Map<MusicCategory, List<Song>>> _incrementalScan(
      Map<String, Song> cached, List<String> dirs, ScanProgressCallback? onProgress) async {
    final current = <String, Song>{};
    int scanned = 0;

    for (final dir in dirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      final songs = await _scanDirAsync(d, maxDepth: 4);
      for (final s in songs) {
        if (!current.containsKey(s.filePath)) {
          current[s.filePath] = s;
          // 保留缓存中的收藏/播放计数
          final cachedSong = cached[s.filePath];
          if (cachedSong != null) {
            s.isFavorite = cachedSong.isFavorite;
            s.playCount = cachedSong.playCount;
            s.lastPlayed = cachedSong.lastPlayed;
          }
          scanned++;
          onProgress?.call(scanned, songs.length, dir);
        }
      }
    }

    final store = await StorageManager.instance;
    await store.saveSongCache(current);
    await store.setLastScanTime(DateTime.now().millisecondsSinceEpoch);

    return _categorize(current.values.toList());
  }

  static Future<List<Song>> _scanDirAsync(Directory dir, {int maxDepth = 3}) async {
    return await Isolate.run(() => _scanDirSync(dir.path, maxDepth));
  }

  static List<Song> _scanDirSync(String dirPath, int depth) {
    final songs = <Song>[];
    if (depth <= 0) return songs;
    final dir = Directory(dirPath);
    List<FileSystemEntity> entities;
    try {
      entities = dir.listSync(recursive: false, followLinks: false);
    } catch (_) { return songs; }

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
                title: title, artist: '', filePath: entity.path,
                category: Song.classifySong(dirPath, name),
                fileSize: stat.size, lastModified: stat.modified.millisecondsSinceEpoch,
              ));
            } catch (_) {
              songs.add(Song(title: title, artist: '', filePath: entity.path, category: Song.classifySong(dirPath, name)));
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

  static Map<MusicCategory, List<Song>> _categorize(List<Song> songs) {
    final dj = <Song>[];
    final pop = <Song>[];
    for (final s in songs) (s.category == MusicCategory.dj ? dj : pop).add(s);
    dj.sort((a, b) => a.title.compareTo(b.title));
    pop.sort((a, b) => a.title.compareTo(b.title));
    return {MusicCategory.dj: dj, MusicCategory.pop: pop};
  }

  static int countSongsInDir(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return 0;
    var count = 0;
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && audioExtensions.any((e) => entity.uri.pathSegments.last.toLowerCase().endsWith(e))) count++;
      }
    } catch (_) {}
    return count;
  }
}

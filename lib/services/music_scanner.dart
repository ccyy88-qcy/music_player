import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';

class MusicScanner {
  /// 常用音乐目录
  static const _searchDirs = [
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Android/media',
    '/storage/emulated/0/DCIM',
  ];

  /// 请求权限
  static Future<bool> requestPermission() async {
    final status = await Permission.audio.request();
    if (status.isGranted) return true;

    // Android 13+ 用 READ_MEDIA_AUDIO，老版本用 storage
    if (await Permission.storage.request().isGranted) return true;
    if (await Permission.manageExternalStorage.request().isGranted) return true;

    return false;
  }

  /// 扫描所有音乐文件
  static Future<Map<MusicCategory, List<Song>>> scanAll() async {
    final allSongs = <Song>[];

    for (final dir in _searchDirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      allSongs.addAll(_scanDir(d, depth: 3));
    }

    final dj = <Song>[];
    final pop = <Song>[];

    for (final song in allSongs) {
      if (song.category == MusicCategory.dj) {
        dj.add(song);
      } else {
        pop.add(song);
      }
    }

    // 排序：DJ 按名称，流行按名称
    dj.sort((a, b) => a.title.compareTo(b.title));
    pop.sort((a, b) => a.title.compareTo(b.title));

    return {MusicCategory.dj: dj, MusicCategory.pop: pop};
  }

  /// 递归扫描目录
  static List<Song> _scanDir(Directory dir, {int depth = 0}) {
    final songs = <Song>[];
    if (depth <= 0) return songs;

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
          if (title.length > 2) {
            // 过滤太短的文件名（系统音效等）
            songs.add(Song(
              title: title,
              artist: '',
              filePath: entity.path,
              category: Song.classifySong(dir.path, name),
            ));
          }
        }
      } else if (entity is Directory) {
        songs.addAll(_scanDir(entity, depth: depth - 1));
      }
    }
    return songs;
  }
}

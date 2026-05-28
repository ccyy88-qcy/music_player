import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

/// 本地持久化管理：扫描缓存、收藏、设置、播放历史
class StorageManager {
  static const _keyScanCache = 'scan_cache';
  static const _keyScanDirs = 'scan_dirs';
  static const _keyFavorites = 'favorites';
  static const _keyScanMode = 'scan_mode'; // 'quick' | 'full'
  static const _keyLastScan = 'last_scan_time';
  static const _keySleepMinutes = 'sleep_minutes';
  static const _keyEqPreset = 'eq_preset';
  static const _keySpeed = 'playback_speed';
  static const _keyMusicSources = 'music_sources';
  static const _keyRecentSongs = 'recent_songs'; // 自定义音乐源JSON列表

  static StorageManager? _instance;
  late SharedPreferences _prefs;
  String? _cacheDir;

  static Future<StorageManager> get instance async {
    if (_instance != null) return _instance!;
    _instance = StorageManager._();
    await _instance!._init();
    return _instance!;
  }

  StorageManager._();

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationDocumentsDirectory();
    _cacheDir = dir.path;
  }

  // ─────────── 扫描缓存 ───────────

  /// 加载缓存的歌曲列表
  Map<String, Song> loadSongCache() {
    final jsonStr = _prefs.getString(_keyScanCache);
    if (jsonStr == null || jsonStr.isEmpty) return {};
    try {
      final list = jsonDecode(jsonStr) as List;
      final map = <String, Song>{};
      for (final item in list) {
        final song = Song.fromJson(item as Map<String, dynamic>);
        map[song.id] = song;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// 保存歌曲缓存
  Future<void> saveSongCache(Map<String, Song> songs) async {
    final list = songs.values.map((s) => s.toJson()).toList();
    await _prefs.setString(_keyScanCache, jsonEncode(list));
  }

  /// 清除扫描缓存
  Future<void> clearScanCache() async {
    await _prefs.remove(_keyScanCache);
  }

  /// 上次扫描时间
  int get lastScanTime => _prefs.getInt(_keyLastScan) ?? 0;
  Future<void> setLastScanTime(int time) async {
    await _prefs.setInt(_keyLastScan, time);
  }

  // ─────────── 自定义扫描目录 ───────────

  /// 获取自定义扫描目录
  List<String> getScanDirs() {
    final dirs = _prefs.getStringList(_keyScanDirs);
    if (dirs == null || dirs.isEmpty) {
      return _defaultDirs();
    }
    return dirs.where((d) => Directory(d).existsSync()).toList();
  }

  /// 添加扫描目录
  Future<void> addScanDir(String dir) async {
    final dirs = getScanDirs();
    if (!dirs.contains(dir)) {
      dirs.add(dir);
      await _prefs.setStringList(_keyScanDirs, dirs);
    }
  }

  /// 移除扫描目录
  Future<void> removeScanDir(String dir) async {
    final dirs = getScanDirs();
    dirs.remove(dir);
    await _prefs.setStringList(_keyScanDirs, dirs);
  }

  /// 重置为默认目录
  Future<void> resetScanDirs() async {
    await _prefs.remove(_keyScanDirs);
  }

  List<String> _defaultDirs() => [
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Download',
  ];

  // ─────────── 扫描模式 ───────────

  /// 扫描模式: 'quick'(预设目录) | 'full'(全盘)
  String get scanMode => _prefs.getString(_keyScanMode) ?? 'quick';
  Future<void> setScanMode(String mode) async {
    await _prefs.setString(_keyScanMode, mode);
  }

  // ─────────── 收藏 ───────────

  Set<String> getFavorites() {
    final list = _prefs.getStringList(_keyFavorites) ?? [];
    return list.toSet();
  }

  Future<void> toggleFavorite(String songId) async {
    final favs = getFavorites();
    if (favs.contains(songId)) {
      favs.remove(songId);
    } else {
      favs.add(songId);
    }
    await _prefs.setStringList(_keyFavorites, favs.toList());
  }

  bool isFavorite(String songId) => getFavorites().contains(songId);

  // ─────────── 最近播放 ───────────

  List<Song> getRecentSongs() {
    final json = _prefs.getString(_keyRecentSongs);
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  Future<void> addRecentSong(Song song) async {
    final list = getRecentSongs();
    list.removeWhere((s) => s.id == song.id);
    list.insert(0, song);
    if (list.length > 30) list.removeLast();
    await _prefs.setString(_keyRecentSongs, jsonEncode(list.map((s) => s.toJson()).toList()));
  }

  Future<void> clearRecent() async {
    await _prefs.remove(_keyRecentSongs);
  }

  // ─────────── 播放器设置 ───────────

  int get sleepMinutes => _prefs.getInt(_keySleepMinutes) ?? 0;
  Future<void> setSleepMinutes(int mins) async {
    await _prefs.setInt(_keySleepMinutes, mins);
  }

  String get eqPreset => _prefs.getString(_keyEqPreset) ?? 'flat';
  Future<void> setEqPreset(String preset) async {
    await _prefs.setString(_keyEqPreset, preset);
  }

  double get playbackSpeed => _prefs.getDouble(_keySpeed) ?? 1.0;
  Future<void> setPlaybackSpeed(double speed) async {
    await _prefs.setDouble(_keySpeed, speed);
  }

  // ─────────── 音乐源管理 ───────────

  /// 获取所有自定义音乐源
  List<Map<String, String>> getMusicSources() {
    final jsonStr = _prefs.getString(_keyMusicSources);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List;
      return list.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存音乐源列表
  Future<void> saveMusicSources(List<Map<String, String>> sources) async {
    await _prefs.setString(_keyMusicSources, jsonEncode(sources));
  }

  /// 添加音乐源
  Future<void> addMusicSource(String name, String apiUrl) async {
    final sources = getMusicSources();
    sources.add({'name': name, 'url': apiUrl});
    await saveMusicSources(sources);
  }

  /// 删除音乐源
  Future<void> removeMusicSource(int index) async {
    final sources = getMusicSources();
    if (index >= 0 && index < sources.length) {
      sources.removeAt(index);
      await saveMusicSources(sources);
    }
  }

  // ─────────── 清理 ───────────

  Future<void> clearAll() async {
    await _prefs.clear();
  }
}

/// 全局单例获取
Future<StorageManager> get storage => StorageManager.instance;

import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import 'lyric_parser.dart';

enum PlayMode { sequential, repeatOne, repeatAll, shuffle }
enum EqPreset { flat, djBass, pop, vocal, classical, heavyBass }

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final List<Song> _queue = [];
  int _currentIndex = -1;
  PlayMode _playMode = PlayMode.repeatAll;
  EqPreset _eqPreset = EqPreset.flat;
  double _speed = 1.0;

  // 歌词
  List<LyricLine> _lyrics = [];
  int _lyricIndex = -1;

  // 睡眠定时器
  Timer? _sleepTimer;
  int _sleepRemaining = 0; // 剩余秒数

  // ── 暴露给 UI ──
  AudioPlayer get player => _player;
  int get currentIndex => _currentIndex;
  List<Song> get queue => List.unmodifiable(_queue);
  PlayMode get playMode => _playMode;
  EqPreset get eqPreset => _eqPreset;
  double get speed => _speed;
  List<LyricLine> get lyrics => _lyrics;
  int get lyricIndex => _lyricIndex;
  int get sleepRemaining => _sleepRemaining;
  bool get sleepActive => _sleepTimer != null && _sleepTimer!.isActive;

  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;

  // ─────────── 播放控制 ───────────

  Future<void> loadPlaylist(List<Song> songs, {int startIndex = 0}) async {
    _queue.clear();
    _queue.addAll(songs);
    _currentIndex = startIndex;

    await _player.setAudioSource(
      ConcatenatingAudioSource(
        children: songs.map((s) => AudioSource.file(s.filePath)).toList(),
      ),
      initialIndex: startIndex,
    );

    _applyPlayMode();
    _applySpeed();
    _player.play();
    _loadLyrics();
  }

  void togglePlay() {
    if (_player.playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  Future<void> next() async {
    if (_player.hasNext) {
      _currentIndex++;
      await _player.seekToNext();
      _loadLyrics();
    }
  }

  Future<void> previous() async {
    if (_player.hasPrevious) {
      _currentIndex--;
      await _player.seekToPrevious();
      _loadLyrics();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  Future<void> skipToIndex(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      await _player.seek(Duration.zero, index: index);
      _player.play();
      _loadLyrics();
    }
  }

  // ─────────── 播放模式 ───────────

  void cyclePlayMode() {
    switch (_playMode) {
      case PlayMode.sequential:
        _playMode = PlayMode.repeatOne;
        break;
      case PlayMode.repeatOne:
        _playMode = PlayMode.repeatAll;
        break;
      case PlayMode.repeatAll:
        _playMode = PlayMode.shuffle;
        break;
      case PlayMode.shuffle:
        _playMode = PlayMode.sequential;
        break;
    }
    _applyPlayMode();
  }

  void setPlayMode(PlayMode mode) {
    _playMode = mode;
    _applyPlayMode();
  }

  void _applyPlayMode() {
    switch (_playMode) {
      case PlayMode.sequential:
        _player.setLoopMode(LoopMode.off);
        _player.setShuffleModeEnabled(false);
      case PlayMode.repeatOne:
        _player.setLoopMode(LoopMode.one);
        _player.setShuffleModeEnabled(false);
      case PlayMode.repeatAll:
        _player.setLoopMode(LoopMode.all);
        _player.setShuffleModeEnabled(false);
      case PlayMode.shuffle:
        _player.setLoopMode(LoopMode.all);
        _player.setShuffleModeEnabled(true);
    }
  }

  String get playModeIcon {
    switch (_playMode) {
      case PlayMode.sequential: return '→';
      case PlayMode.repeatOne:  return '🔂';
      case PlayMode.repeatAll:  return '🔁';
      case PlayMode.shuffle:    return '🔀';
    }
  }

  String get playModeLabel {
    switch (_playMode) {
      case PlayMode.sequential: return '顺序';
      case PlayMode.repeatOne:  return '单曲';
      case PlayMode.repeatAll:  return '循环';
      case PlayMode.shuffle:    return '随机';
    }
  }

  // ─────────── 播放速度 ───────────

  Future<void> setPlaybackSpeed(double speed) async {
    _speed = speed.clamp(0.5, 2.0);
    await _applySpeed();
  }

  Future<void> cycleSpeed() async {
    final speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final idx = speeds.indexOf(_speed);
    _speed = speeds[(idx + 1) % speeds.length];
    await _applySpeed();
  }

  Future<void> _applySpeed() async {
    await _player.setSpeed(_speed);
  }

  String get speedLabel {
    if (_speed == 1.0) return '正常';
    return '${_speed}x';
  }

  // ─────────── EQ 预设 ───────────

  void cycleEqPreset() {
    const presets = EqPreset.values;
    final idx = presets.indexOf(_eqPreset);
    _eqPreset = presets[(idx + 1) % presets.length];
    _applyEqPreset();
  }

  void setEqPreset(EqPreset preset) {
    _eqPreset = preset;
    _applyEqPreset();
  }

  void _applyEqPreset() {
    // EQ 预设仅做 UI 视觉标识，实际音效需要平台通道
    // Android 均衡器可通过 android_audio_effects 包实现
  }

  String get eqPresetLabel {
    switch (_eqPreset) {
      case EqPreset.flat:       return '标准';
      case EqPreset.djBass:     return 'DJ低音';
      case EqPreset.pop:        return '流行';
      case EqPreset.vocal:      return '人声';
      case EqPreset.classical:  return '古典';
      case EqPreset.heavyBass:  return '重低音';
    }
  }

  // ─────────── 睡眠定时 ───────────

  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepRemaining = minutes * 60;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _sleepRemaining--;
      if (_sleepRemaining <= 0) {
        timer.cancel();
        _player.pause();
        _sleepRemaining = 0;
      }
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepRemaining = 0;
  }

  void cycleSleepTimer() {
    if (sleepActive) {
      cancelSleepTimer();
      return;
    }
    // 循环: 15min → 30min → 60min → 90min → 关
    const options = [15, 30, 60, 90];
    final currentMins = _sleepRemaining ~/ 60;
    final idx = options.indexOf(currentMins);
    if (idx < 0 || idx >= options.length - 1) {
      startSleepTimer(options.first);
    } else {
      startSleepTimer(options[idx + 1]);
    }
  }

  String get sleepTimerLabel {
    if (!sleepActive) return '定时';
    final mins = _sleepRemaining ~/ 60;
    final secs = _sleepRemaining % 60;
    return '${mins}:${secs.toString().padLeft(2, '0')}';
  }

  // ─────────── 歌词 ───────────

  Future<void> _loadLyrics() async {
    final song = currentSong;
    if (song == null) {
      _lyrics = [];
      _lyricIndex = -1;
      return;
    }
    // 先尝试本地 LRC
    _lyrics = await LyricParser.fromAudioPath(song.filePath);
    // 如果本地没有，尝试在线搜索
    if (_lyrics.isEmpty) {
      _lyrics = await LyricParser.searchOnline(
        song.title,
        song.artist,
      );
    }
    _lyricIndex = -1;
  }

  void updateLyricPosition(Duration position) {
    _lyricIndex = LyricParser.findCurrentIndex(_lyrics, position);
  }

  /// 设置在线歌词（从在线源获取的已解析歌词）
  void setOnlineLyrics(List<LyricLine> lyrics) {
    _lyrics = lyrics;
    _lyricIndex = -1;
  }

  // ─────────── 释放 ───────────

  void dispose() {
    _sleepTimer?.cancel();
    _player.dispose();
  }
}

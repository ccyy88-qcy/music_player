import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import 'lyric_parser.dart';

enum PlayMode { sequential, repeatOne, repeatAll, shuffle }
enum EqPreset { flat, djBass, pop, vocal, classical, heavyBass }

class AudioPlayerHandler {
  final AudioPlayer _player = AudioPlayer();
  final List<Song> _songQueue = [];
  int _currentIndex = -1;

  List<LyricLine> _lyrics = [];
  int _lyricIndex = -1;
  Timer? _sleepTimer;
  int _sleepRemaining = 0;
  PlayMode _playMode = PlayMode.repeatAll;
  EqPreset _eqPreset = EqPreset.flat;
  double _speed = 1.0;

  AudioPlayer get player => _player;
  int get currentIndex => _currentIndex;
  List<Song> get songQueue => List.unmodifiable(_songQueue);
  PlayMode get playMode => _playMode;
  EqPreset get eqPreset => _eqPreset;
  double get speed => _speed;
  List<LyricLine> get lyrics => _lyrics;
  int get lyricIndex => _lyricIndex;
  int get sleepRemaining => _sleepRemaining;
  bool get sleepActive => _sleepTimer != null && _sleepTimer!.isActive;
  Song? get currentSong => _currentIndex >= 0 && _currentIndex < _songQueue.length ? _songQueue[_currentIndex] : null;

  AudioPlayerHandler() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_player.hasNext) { _currentIndex++; }
        else if (_playMode == PlayMode.repeatAll) { _currentIndex = 0; _player.seek(Duration.zero, index: 0); return; }
        else { _currentIndex = -1; _stopForeground(); }
      }
    });
    _player.playingStream.listen((playing) {
      if (playing) { _startForeground(); } else { _updateForeground(); }
    });
  }

  /// 启动前台服务（通知栏保活）
  Future<void> _startForeground() async {
    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        notificationTitle: '🦊 狸音乐',
        notificationText: currentSong?.title ?? '正在播放',
        callback: _foregroundCallback,
      );
    } else {
      _updateForeground();
    }
  }

  void _updateForeground() {
    final song = currentSong;
    FlutterForegroundTask.updateService(
      notificationTitle: '🦊 狸音乐',
      notificationText: song != null ? '${song.title}${_player.playing ? " ▶" : " ⏸"}' : '已暂停',
    );
  }

  void _stopForeground() {
    FlutterForegroundTask.stopService();
  }

  @pragma('vm:entry-point')
  static void _foregroundCallback() {
    FlutterForegroundTask.setTaskHandler(ForegroundTaskHandler());
  }

  Future<void> loadSongList(List<Song> songs, {int startIndex = 0}) async {
    _songQueue.clear(); _songQueue.addAll(songs); _currentIndex = startIndex;
    await _player.setAudioSource(
      ConcatenatingAudioSource(children: songs.map((s) => AudioSource.file(s.filePath)).toList()),
      initialIndex: startIndex,
    );
    _applyPlayMode(); _player.setSpeed(_speed); _player.play();
    _loadLyrics(); _startForeground();
  }

  void togglePlay() {
    if (_player.playing) { _player.pause(); } else { _player.play(); }
  }

  Future<void> skipToNext() async {
    if (_player.hasNext) { _currentIndex++; await _player.seekToNext(); _loadLyrics(); _updateForeground(); }
  }

  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) { _currentIndex--; await _player.seekToPrevious(); _loadLyrics(); _updateForeground(); }
    else { await _player.seek(Duration.zero); }
  }

  Future<void> skipToIndex(int i) async {
    if (i >= 0 && i < _songQueue.length) { _currentIndex = i; await _player.seek(Duration.zero, index: i); _player.play(); _loadLyrics(); _updateForeground(); }
  }

  Future<void> seek(Duration p) async => _player.seek(p);

  void cyclePlayMode() { _playMode = PlayMode.values[(_playMode.index + 1) % PlayMode.values.length]; _applyPlayMode(); }
  void _applyPlayMode() {
    _player.setLoopMode(_playMode == PlayMode.repeatOne ? LoopMode.one : _playMode == PlayMode.sequential ? LoopMode.off : LoopMode.all);
    _player.setShuffleModeEnabled(_playMode == PlayMode.shuffle);
  }
  String get playModeIcon => ['→', '🔂', '🔁', '🔀'][_playMode.index];
  String get playModeLabel => ['顺序', '单曲', '循环', '随机'][_playMode.index];

  Future<void> cycleSpeed() async {
    const s = [0.75, 1.0, 1.25, 1.5, 2.0]; _speed = s[(s.indexOf(_speed) + 1) % s.length]; await _player.setSpeed(_speed);
  }
  String get speedLabel => _speed == 1.0 ? '正常' : '${_speed}x';

  void cycleEqPreset() => _eqPreset = EqPreset.values[(_eqPreset.index + 1) % EqPreset.values.length];
  String get eqPresetLabel => ['标准', 'DJ低音', '流行', '人声', '古典', '重低音'][_eqPreset.index];

  void cycleSleepTimer() {
    if (sleepActive) { cancelSleepTimer(); return; }
    const o = [15, 30, 60, 90]; final i = o.indexOf(_sleepRemaining ~/ 60);
    startSleepTimer(i < 0 || i >= o.length - 1 ? o.first : o[i + 1]);
  }
  void startSleepTimer(int m) { _sleepTimer?.cancel(); _sleepRemaining = m * 60; _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (--_sleepRemaining <= 0) { _sleepTimer?.cancel(); _player.pause(); }}); }
  void cancelSleepTimer() { _sleepTimer?.cancel(); _sleepTimer = null; _sleepRemaining = 0; }
  String get sleepTimerLabel => !sleepActive ? '定时' : '${(_sleepRemaining ~/ 60)}:${(_sleepRemaining % 60).toString().padLeft(2, '0')}';

  Future<void> _loadLyrics() async {
    final s = currentSong; if (s == null) { _lyrics = []; _lyricIndex = -1; return; }
    _lyrics = await LyricParser.fromAudioPath(s.filePath);
    if (_lyrics.isEmpty) _lyrics = await LyricParser.searchOnline(s.title, s.artist);
    _lyricIndex = -1;
  }
  void updateLyricPosition(Duration p) => _lyricIndex = LyricParser.findCurrentIndex(_lyrics, p);
  void setOnlineLyrics(List<LyricLine> l) { _lyrics = l; _lyricIndex = -1; }

  void dispose() { _sleepTimer?.cancel(); _stopForeground(); _player.dispose(); }
}

class ForegroundTaskHandler extends TaskHandler {
  @override Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override Future<void> onRepeatEvent(DateTime timestamp) async {}
  @override Future<void> onDestroy(DateTime timestamp) async {}
}

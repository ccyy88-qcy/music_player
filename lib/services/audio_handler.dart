import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import 'lyric_parser.dart';

/// 将 AudioPlayerService 与 audio_service 后台播放桥接
class AudioPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final List<Song> _songQueue = [];
  int _currentIndex = -1;

  // 歌词
  List<LyricLine> _lyrics = [];
  int _lyricIndex = -1;

  // 睡眠定时器
  Timer? _sleepTimer;
  int _sleepRemaining = 0;

  // 状态
  PlayMode _playMode = PlayMode.repeatAll;
  EqPreset _eqPreset = EqPreset.flat;
  double _speed = 1.0;

  // ── 暴露给 UI ──
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

  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _songQueue.length
          ? _songQueue[_currentIndex]
          : null;

  AudioPlayerHandler() {
    // 将 just_audio 状态同步到 audio_service
    _player.playbackEventStream.listen(_onPlaybackEvent);
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // 自动下一首
        if (_player.hasNext) {
          _currentIndex++;
        } else if (_playMode == PlayMode.repeatAll) {
          _currentIndex = 0;
          _player.seek(Duration.zero, index: 0);
          return;
        } else {
          _currentIndex = -1;
        }
      }
    });
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      if (_player.playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];

    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex >= 0 ? _currentIndex : null,
    ));
  }

  // ─────────── 播放控制 ───────────

  Future<void> loadSongList(List<Song> songs, {int startIndex = 0}) async {
    _songQueue.clear();
    _songQueue.addAll(songs);
    _currentIndex = startIndex;

    final mediaItems = songs.map((s) => MediaItem(
      id: s.filePath,
      title: s.title,
      artist: s.artist.isNotEmpty ? s.artist : (s.category == MusicCategory.dj ? 'DJ劲爆' : '流行歌曲'),
      artUri: null,
    )).toList();

    // 更新 audio_service 队列
    queue.add(mediaItems);

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
    _updateMediaItem();
  }

  @override
  Future<void> play() async {
    _player.play();
    _updateMediaItem();
  }

  @override
  Future<void> pause() async => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    _currentIndex = -1;
  }

  @override
  Future<void> seek(Duration position) async => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      _currentIndex++;
      await _player.seekToNext();
      _loadLyrics();
      _updateMediaItem();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      _currentIndex--;
      await _player.seekToPrevious();
      _loadLyrics();
      _updateMediaItem();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _songQueue.length) {
      _currentIndex = index;
      await _player.seek(Duration.zero, index: index);
      _player.play();
      _loadLyrics();
      _updateMediaItem();
    }
  }

  void togglePlay() {
    if (_player.playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  void _updateMediaItem() {
    final song = currentSong;
    if (song == null) return;
    mediaItem.add(MediaItem(
      id: song.filePath,
      title: song.title,
      artist: song.artist.isNotEmpty ? song.artist : (song.category == MusicCategory.dj ? 'DJ劲爆' : '流行歌曲'),
    ));
  }

  // ─────────── 播放模式 ───────────

  void cyclePlayMode() {
    switch (_playMode) {
      case PlayMode.sequential: _playMode = PlayMode.repeatOne; break;
      case PlayMode.repeatOne:  _playMode = PlayMode.repeatAll; break;
      case PlayMode.repeatAll:  _playMode = PlayMode.shuffle; break;
      case PlayMode.shuffle:    _playMode = PlayMode.sequential; break;
    }
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

  // ─────────── 速度 ───────────

  Future<void> cycleSpeed() async {
    final speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final idx = speeds.indexOf(_speed);
    _speed = speeds[(idx + 1) % speeds.length];
    await _player.setSpeed(_speed);
  }

  Future<void> _applySpeed() async => _player.setSpeed(_speed);

  String get speedLabel => _speed == 1.0 ? '正常' : '${_speed}x';

  // ─────────── EQ ───────────

  void cycleEqPreset() {
    const presets = EqPreset.values;
    final idx = presets.indexOf(_eqPreset);
    _eqPreset = presets[(idx + 1) % presets.length];
  }

  String get eqPresetLabel {
    switch (_eqPreset) {
      case EqPreset.flat: return '标准';
      case EqPreset.djBass: return 'DJ低音';
      case EqPreset.pop: return '流行';
      case EqPreset.vocal: return '人声';
      case EqPreset.classical: return '古典';
      case EqPreset.heavyBass: return '重低音';
    }
  }

  // ─────────── 睡眠定时 ───────────

  void cycleSleepTimer() {
    if (sleepActive) { cancelSleepTimer(); return; }
    const options = [15, 30, 60, 90];
    final mins = _sleepRemaining ~/ 60;
    final idx = options.indexOf(mins);
    startSleepTimer(idx < 0 || idx >= options.length - 1 ? options.first : options[idx + 1]);
  }

  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepRemaining = minutes * 60;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sleepRemaining--;
      if (_sleepRemaining <= 0) {
        _sleepTimer?.cancel();
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

  String get sleepTimerLabel {
    if (!sleepActive) return '定时';
    final m = _sleepRemaining ~/ 60;
    final s = _sleepRemaining % 60;
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  // ─────────── 歌词 ───────────

  Future<void> _loadLyrics() async {
    final song = currentSong;
    if (song == null) {
      _lyrics = [];
      _lyricIndex = -1;
      return;
    }
    _lyrics = await LyricParser.fromAudioPath(song.filePath);
    if (_lyrics.isEmpty) {
      _lyrics = await LyricParser.searchOnline(song.title, song.artist);
    }
    _lyricIndex = -1;
  }

  void updateLyricPosition(Duration pos) {
    _lyricIndex = LyricParser.findCurrentIndex(_lyrics, pos);
  }

  void setOnlineLyrics(List<LyricLine> lrc) {
    _lyrics = lrc;
    _lyricIndex = -1;
  }

  @override
  Future<void> dispose() async {
    _sleepTimer?.cancel();
    await _player.dispose();
  }
}

// 保留原有枚举（兼容性）
enum PlayMode { sequential, repeatOne, repeatAll, shuffle }
enum EqPreset { flat, djBass, pop, vocal, classical, heavyBass }

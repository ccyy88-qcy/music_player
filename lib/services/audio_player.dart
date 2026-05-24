import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import 'lyric_parser.dart';

enum PlayMode { sequential, repeatOne, repeatAll, shuffle }

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final List<Song> _queue = [];
  int _currentIndex = -1;
  PlayMode _playMode = PlayMode.repeatAll;

  // 当前歌词
  List<LyricLine> _lyrics = [];
  int _lyricIndex = -1;

  // ── 暴露给 UI ──
  AudioPlayer get player => _player;
  int get currentIndex => _currentIndex;
  List<Song> get queue => List.unmodifiable(_queue);
  PlayMode get playMode => _playMode;
  List<LyricLine> get lyrics => _lyrics;
  int get lyricIndex => _lyricIndex;

  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;

  /// 加载播放列表
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
    _player.play();
    _loadLyrics();
  }

  /// 切换播放模式
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

  void _applyPlayMode() {
    switch (_playMode) {
      case PlayMode.sequential:
        _player.setLoopMode(LoopMode.off);
        _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.repeatOne:
        _player.setLoopMode(LoopMode.one);
        _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.repeatAll:
        _player.setLoopMode(LoopMode.all);
        _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.shuffle:
        _player.setLoopMode(LoopMode.all);
        _player.setShuffleModeEnabled(true);
        break;
    }
  }

  String get playModeIcon {
    switch (_playMode) {
      case PlayMode.sequential:
        return '→';
      case PlayMode.repeatOne:
        return '🔂';
      case PlayMode.repeatAll:
        return '🔁';
      case PlayMode.shuffle:
        return '🔀';
    }
  }

  /// 加载当前歌曲的歌词
  Future<void> _loadLyrics() async {
    final song = currentSong;
    if (song == null) {
      _lyrics = [];
      _lyricIndex = -1;
      return;
    }
    _lyrics = await LyricParser.fromAudioPath(song.filePath);
    _lyricIndex = -1;
  }

  /// 更新歌词位置
  void updateLyricPosition(Duration position) {
    _lyricIndex = LyricParser.findCurrentIndex(_lyrics, position);
  }

  /// 播放/暂停
  void togglePlay() {
    if (_player.playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  /// 下一首
  Future<void> next() async {
    if (_player.hasNext) {
      _currentIndex++;
      await _player.seekToNext();
      _loadLyrics();
    }
  }

  /// 上一首
  Future<void> previous() async {
    if (_player.hasPrevious) {
      _currentIndex--;
      await _player.seekToPrevious();
      _loadLyrics();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  /// 跳转到指定歌曲
  Future<void> skipToIndex(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      await _player.seek(Duration.zero, index: index);
      _player.play();
      _loadLyrics();
    }
  }

  /// 释放资源
  void dispose() {
    _player.dispose();
  }
}

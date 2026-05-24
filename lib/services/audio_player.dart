import 'package:just_audio/just_audio.dart';
import '../models/song.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final List<Song> _queue = [];
  int _currentIndex = -1;

  // ── 暴露给 UI ──
  AudioPlayer get player => _player;
  int get currentIndex => _currentIndex;
  List<Song> get queue => List.unmodifiable(_queue);
  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;

  /// 加载播放列表并播放第一首（或指定 index）
  Future<void> loadPlaylist(List<Song> songs, {int startIndex = 0}) async {
    _queue.clear();
    _queue.addAll(songs);
    _currentIndex = startIndex;

    await _player.setAudioSource(
      ConcatenatingAudioSource(
        children: songs.map((s) => AudioSource.file(s.filePath)).toList(),
        initialIndex: startIndex,
      ),
    );
    _player.play();
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
    }
  }

  /// 上一首
  Future<void> previous() async {
    if (_player.hasPrevious) {
      _currentIndex--;
      await _player.seekToPrevious();
    } else {
      // 重新开始当前歌曲
      await _player.seek(Duration.zero);
    }
  }

  /// 跳转到指定歌曲
  Future<void> skipToIndex(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      await _player.seek(Duration.zero, index: index);
      _player.play();
    }
  }

  /// 释放资源
  void dispose() {
    _player.dispose();
  }
}

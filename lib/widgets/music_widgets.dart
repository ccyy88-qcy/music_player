import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/audio_player.dart';

class MiniPlayer extends StatelessWidget {
  final AudioPlayerService audioService;
  final VoidCallback onTap;

  const MiniPlayer({
    super.key,
    required this.audioService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final song = audioService.currentSong;
    if (song == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 封面占位
            Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: song.category == MusicCategory.dj
                      ? [Colors.orange, Colors.deepOrange]
                      : [Colors.blue, Colors.lightBlue],
                ),
              ),
              child: Icon(
                Icons.music_note,
                color: Colors.white.withValues(alpha: 0.8),
                size: 28,
              ),
            ),
            // 歌曲信息
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.category == MusicCategory.dj ? '🔥 DJ' : '🎵 流行',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // 播放控制
            StreamBuilder<PlayerState>(
              stream: audioService.player.playerStateStream,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                return IconButton(
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                  onPressed: audioService.togglePlay,
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white70),
              onPressed: () => audioService.next(),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// 分类标签头
class CategoryHeader extends StatelessWidget {
  final MusicCategory category;
  final int count;

  const CategoryHeader({
    super.key,
    required this.category,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final isDJ = category == MusicCategory.dj;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDJ
              ? [Colors.orange.shade800, Colors.deepOrange.shade700]
              : [Colors.blue.shade700, Colors.lightBlue.shade600],
        ),
      ),
      child: Row(
        children: [
          Icon(
            isDJ ? Icons.bolt_rounded : Icons.headphones_rounded,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 10),
          Text(
            isDJ ? 'DJ 劲爆' : '流行歌曲',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count 首',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// 歌曲列表项
class SongTile extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final VoidCallback onTap;

  const SongTile({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            colors: song.category == MusicCategory.dj
                ? [Colors.orange.shade400, Colors.deepOrange.shade300]
                : [Colors.blue.shade400, Colors.lightBlue.shade300],
          ),
        ),
        child: Icon(
          isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
      title: Text(
        song.title,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
          color: isPlaying ? Colors.pink.shade400 : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        song.category == MusicCategory.dj ? 'DJ' : '流行',
        style: TextStyle(
          fontSize: 12,
          color: isPlaying ? Colors.pink.shade300 : Colors.grey,
        ),
      ),
      trailing: isPlaying
          ? Icon(Icons.volume_up_rounded, color: Colors.pink.shade400, size: 20)
          : null,
    );
  }
}

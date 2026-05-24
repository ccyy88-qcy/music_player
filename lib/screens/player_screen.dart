import 'dart:math';
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/audio_player.dart';

class PlayerScreen extends StatelessWidget {
  final AudioPlayerService audioService;

  const PlayerScreen({super.key, required this.audioService});

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final song = audioService.currentSong;
    final isDJ = song?.category == MusicCategory.dj;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDJ
                ? [const Color(0xFF2D1B00), const Color(0xFF1A1A2E)]
                : [const Color(0xFF0D1B3E), const Color(0xFF1A1A2E)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── 顶部栏 ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white70, size: 32),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      isDJ ? 'DJ 模式' : '流行模式',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              const Spacer(),

              // ── 封面艺术（动画旋转） ──
              StreamBuilder<PlayerState>(
                stream: audioService.player.playerStateStream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: playing ? 2 * pi : 0),
                    duration: const Duration(seconds: 20),
                    builder: (context, value, child) {
                      return Transform.rotate(angle: value, child: child);
                    },
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isDJ
                              ? [Colors.orange.shade600, Colors.red.shade400]
                              : [Colors.blue.shade600, Colors.pink.shade400],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isDJ ? Colors.orange : Colors.blue)
                                .withValues(alpha: 0.3),
                            blurRadius: 40,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: Colors.white,
                        size: 80,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 40),

              // ── 歌曲信息 ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Text(
                      song?.title ?? '未选择歌曲',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      song?.category == MusicCategory.dj ? '🔥 DJ 劲爆' : '🎵 流行歌曲',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── 进度条 ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: StreamBuilder<Duration?>(
                  stream: audioService.player.durationStream,
                  builder: (context, durSnapshot) {
                    return StreamBuilder<Duration>(
                      stream: audioService.player.positionStream,
                      builder: (context, posSnapshot) {
                        final duration = durSnapshot.data ?? Duration.zero;
                        final position = posSnapshot.data ?? Duration.zero;
                        final sliderValue =
                            duration.inMilliseconds > 0
                                ? position.inMilliseconds /
                                    duration.inMilliseconds
                                : 0.0;

                        return Column(
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14),
                                activeTrackColor: isDJ
                                    ? Colors.orange.shade400
                                    : Colors.pink.shade400,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                overlayColor: (isDJ
                                        ? Colors.orange
                                        : Colors.pink)
                                    .withValues(alpha: 0.2),
                              ),
                              child: Slider(
                                value: sliderValue.clamp(0.0, 1.0),
                                onChanged: (v) {
                                  final ms =
                                      (v * duration.inMilliseconds).round();
                                  audioService.player
                                      .seek(Duration(milliseconds: ms));
                                },
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(position),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(duration),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // ── 播放控制 ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shuffle_rounded,
                          color: Colors.white38, size: 26),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded,
                          color: Colors.white, size: 40),
                      onPressed: () => audioService.previous(),
                    ),
                    StreamBuilder<PlayerState>(
                      stream: audioService.player.playerStateStream,
                      builder: (context, snapshot) {
                        final playing = snapshot.data?.playing ?? false;
                        return Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: isDJ
                                  ? [Colors.orange, Colors.deepOrange]
                                  : [Colors.pink, Colors.purple],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isDJ ? Colors.orange : Colors.pink)
                                    .withValues(alpha: 0.4),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                            onPressed: audioService.togglePlay,
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded,
                          color: Colors.white, size: 40),
                      onPressed: () => audioService.next(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.repeat_rounded,
                          color: Colors.white38, size: 26),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ── 队列预览 ──
              Container(
                height: 100,
                margin: const EdgeInsets.only(bottom: 16),
                child: _buildQueuePreview(isDJ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueuePreview(bool isDJ) {
    final queue = audioService.queue;
    final currentIdx = audioService.currentIndex;

    if (queue.length <= 1) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '播放队列 (${queue.length} 首)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: queue.length,
            itemBuilder: (context, index) {
              final s = queue[index];
              final isCurrent = index == currentIdx;
              return GestureDetector(
                onTap: () => audioService.skipToIndex(index),
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isCurrent
                        ? (isDJ
                            ? Colors.orange.withValues(alpha: 0.3)
                            : Colors.pink.withValues(alpha: 0.3))
                        : Colors.white.withValues(alpha: 0.05),
                    border: isCurrent
                        ? Border.all(
                            color: isDJ ? Colors.orange : Colors.pink, width: 2)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isCurrent
                            ? Icons.volume_up_rounded
                            : Icons.music_note_rounded,
                        color: isCurrent
                            ? (isDJ ? Colors.orange : Colors.pink)
                            : Colors.white38,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.title,
                        style: TextStyle(
                          color: isCurrent ? Colors.white : Colors.white54,
                          fontSize: 10,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../models/song.dart';
import '../services/audio_handler.dart';
import '../main.dart' show audioHandler, AppColors;

/// 玻璃质感卡片包装
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? borderColor;
  final bool glowing;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 14,
    this.borderColor,
    this.glowing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: AppColors.glass,
        border: Border.all(color: borderColor ?? AppColors.glassBorder, width: 0.5),
        boxShadow: glowing ? [
          BoxShadow(color: AppColors.glowOrange, blurRadius: 12, spreadRadius: 1),
          BoxShadow(color: AppColors.glowPurple, blurRadius: 20, spreadRadius: -4),
        ] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: child,
        ),
      ),
    );
  }
}

/// 渐变色圆形容器
class GradientCircle extends StatelessWidget {
  final double size;
  final IconData? icon;
  final double iconSize;

  const GradientCircle({super.key, this.size = 44, this.icon, this.iconSize = 22});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [AppColors.foxOrange, AppColors.purple], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: AppColors.glowOrange, blurRadius: 8, spreadRadius: 1)],
      ),
      child: icon != null ? Icon(icon, color: Colors.white, size: iconSize) : null,
    );
  }
}

/// 迷你播放器
class MiniPlayer extends StatelessWidget {
  final VoidCallback onTap;
  const MiniPlayer({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final song = audioHandler.currentSong;
    if (song == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.surface, Color(0xFF15152A)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
          border: Border(top: BorderSide(color: AppColors.glassBorder, width: 0.5)),
          boxShadow: [BoxShadow(color: AppColors.glowOrange.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, -4))],
        ),
        child: Row(children: [
          const SizedBox(width: 10),
          // 播放图标圆
          StreamBuilder<bool>(
            stream: audioHandler.player.playingStream,
            builder: (_, snap) => Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [AppColors.foxOrange, AppColors.purple]),
                boxShadow: [BoxShadow(color: AppColors.glowOrange.withValues(alpha: 0.4), blurRadius: 8)],
              ),
              child: Icon(snap.data == true ? Icons.equalizer_rounded : Icons.music_note_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          // 歌曲信息
          Expanded(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(song.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: (song.category == MusicCategory.dj ? AppColors.foxOrange : AppColors.purple).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4)), child: Text(song.category == MusicCategory.dj ? 'DJ' : '流行', style: TextStyle(fontSize: 9, color: song.category == MusicCategory.dj ? AppColors.foxOrange : AppColors.purple, fontWeight: FontWeight.w600))),
                const SizedBox(width: 6),
                Text(audioHandler.eqPresetLabel, style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.7), fontSize: 11)),
              ]),
            ],
          )),
          // 播放控制
          StreamBuilder<bool>(
            stream: audioHandler.player.playingStream,
            builder: (_, snap) => IconButton(
              icon: Icon(snap.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded, color: AppColors.textPrimary),
              onPressed: audioHandler.togglePlay,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next_rounded, color: AppColors.textSecondary),
            onPressed: () => audioHandler.skipToNext(),
          ),
          const SizedBox(width: 4),
        ]),
      ),
    );
  }
}

/// 分类标题头
class CategoryHeader extends StatelessWidget {
  final MusicCategory category;
  final int count;
  const CategoryHeader({super.key, required this.category, required this.count});

  @override
  Widget build(BuildContext context) {
    final isDJ = category == MusicCategory.dj;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        GradientCircle(size: 32, icon: isDJ ? Icons.bolt_rounded : Icons.headphones_rounded, iconSize: 16),
        const SizedBox(width: 10),
        Text(isDJ ? '🔥 DJ' : '🎵 流行', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Text('$count 首', style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.8), fontSize: 12)),
        ),
      ]),
    );
  }
}

/// 歌曲列表卡片
class SongTile extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;

  const SongTile({super.key, required this.song, required this.isPlaying, this.isFavorite = false, required this.onTap, this.onFavorite});

  @override
  Widget build(BuildContext context) {
    final isDJ = song.category == MusicCategory.dj;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: GlassCard(
        glowing: isPlaying,
        borderColor: isPlaying ? AppColors.foxOrange.withValues(alpha: 0.5) : null,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                // 封面/图标
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: isDJ ? [const Color(0xFFFF6B35), const Color(0xFFE85D2C)] : [const Color(0xFFA855F7), const Color(0xFF7C3AED)],
                    ),
                    boxShadow: isPlaying ? [BoxShadow(color: (isDJ ? AppColors.glowOrange : AppColors.glowPurple), blurRadius: 8)] : null,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: isPlaying
                      ? _EqualizerIcon(key: ValueKey('eq_${song.filePath}'))
                      : Icon(Icons.music_note_rounded, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                // 文本
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(song.title, style: TextStyle(
                    color: isPlaying ? AppColors.foxOrange : AppColors.textPrimary,
                    fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    Text(isDJ ? 'DJ' : '流行', style: TextStyle(fontSize: 11, color: isPlaying ? AppColors.foxLight : AppColors.textSecondary)),
                    if (song.playCount > 0) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.play_circle_outline, size: 10, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                      const SizedBox(width: 2),
                      Text('${song.playCount}', style: TextStyle(fontSize: 10, color: AppColors.textSecondary.withValues(alpha: 0.5))),
                    ],
                  ]),
                ])),
                // 右侧操作
                if (isPlaying)
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.foxOrange.withValues(alpha: 0.2),
                    ),
                    child: const Icon(Icons.volume_up_rounded, color: AppColors.foxOrange, size: 14),
                  ),
                if (onFavorite != null)
                  IconButton(
                    icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: isFavorite ? AppColors.foxOrange : AppColors.textSecondary.withValues(alpha: 0.4), size: 20),
                    onPressed: onFavorite,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// 均衡器动画图标
class _EqualizerIcon extends StatefulWidget {
  const _EqualizerIcon({super.key});

  @override
  State<_EqualizerIcon> createState() => _EqualizerIconState();
}

class _EqualizerIconState extends State<_EqualizerIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => CustomPaint(
        size: const Size(22, 22),
        painter: _EqualizerPainter(_controller.value),
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  final double t;
  _EqualizerPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    const bars = 4;
    for (int i = 0; i < bars; i++) {
      final h = 6 + 12 * (0.5 + 0.5 * math.sin(t * math.pi * 2 + i * 1.5));
      final x = 4 + i * 5.0;
      canvas.drawLine(Offset(x, 20 - h), Offset(x, 20), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerPainter o) => o.t != t;
}

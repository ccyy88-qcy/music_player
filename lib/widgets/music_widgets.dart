import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../models/song.dart';
import '../services/audio_handler.dart';
import '../main.dart' show audioHandler, AppColors;

/// 磨砂卡片
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? borderColor;
  final bool glowing;
  final List<BoxShadow>? boxShadow;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 12,
    this.borderColor,
    this.glowing = false,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: AppColors.glass,
        border: Border.all(color: borderColor ?? AppColors.glassBorder),
        boxShadow: boxShadow ?? (glowing ? [
          BoxShadow(color: AppColors.glowPrimary, blurRadius: 12, spreadRadius: 1),
          BoxShadow(color: AppColors.glowAccent, blurRadius: 20, spreadRadius: -4),
        ] : null),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: padding != null ? Padding(padding: padding!, child: child) : child,
        ),
      ),
    );
  }
}

/// 渐变圆形图标
class GradientCircle extends StatelessWidget {
  final double size;
  final IconData? icon;
  final double iconSize;
  final List<Color>? colors;
  const GradientCircle({super.key, this.size = 42, this.icon, this.iconSize = 20, this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors ?? AppColors.gradientPrimary,
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: AppColors.glowPrimary, blurRadius: 8, spreadRadius: 1)],
      ),
      child: icon != null ? Center(child: Icon(icon, color: Colors.white, size: iconSize)) : null,
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
          color: AppColors.surface.withValues(alpha: 0.95),
          border: Border(top: BorderSide(color: AppColors.glassBorder)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, -4)),
            BoxShadow(color: AppColors.glowPrimary.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -4)),
          ],
        ),
        child: Row(children: [
          const SizedBox(width: 10),
          // 封面
          StreamBuilder<bool>(
            stream: audioHandler.player.playingStream,
            builder: (_, snap) => Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: song.category == MusicCategory.dj ? AppColors.gradientPrimary : AppColors.gradientAccent,
                ),
                boxShadow: [BoxShadow(color: AppColors.glowPrimary.withValues(alpha: 0.3), blurRadius: 6)],
              ),
              child: Icon(snap.data == true ? Icons.equalizer_rounded : Icons.music_note_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(song.title,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: (song.category == MusicCategory.dj ? AppColors.primary : AppColors.accent).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    song.category == MusicCategory.dj ? 'DJ' : '流行',
                    style: TextStyle(fontSize: 9, color: song.category == MusicCategory.dj ? AppColors.primary : AppColors.accent, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 6),
                Text(audioHandler.eqPresetLabel,
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
              ]),
            ]),
          ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        GradientCircle(
          size: 30, icon: isDJ ? Icons.bolt_rounded : Icons.headphones_rounded, iconSize: 15,
          colors: isDJ ? AppColors.gradientPrimary : AppColors.gradientAccent,
        ),
        const SizedBox(width: 10),
        Text(isDJ ? '🔥 DJ' : '🎵 流行',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Text('$count 首',
            style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.7), fontSize: 12)),
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
  final VoidCallback? onLongPress;
  const SongTile({super.key, required this.song, required this.isPlaying, this.isFavorite = false, required this.onTap, this.onFavorite, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final isDJ = song.category == MusicCategory.dj;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: GlassCard(
        glowing: isPlaying,
        borderColor: isPlaying ? AppColors.primary.withValues(alpha: 0.4) : null,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: isDJ ? AppColors.gradientPrimary : AppColors.gradientAccent,
                    ),
                    boxShadow: isPlaying ? [BoxShadow(color: (isDJ ? AppColors.glowPrimary : AppColors.glowAccent), blurRadius: 6)] : null,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: isPlaying
                      ? _EqualizerIcon(key: ValueKey('eq_${song.filePath}'))
                      : const Icon(Icons.music_note_rounded, color: Colors.white, size: 21),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(song.title,
                      style: TextStyle(
                        color: isPlaying ? AppColors.primary : AppColors.textPrimary,
                        fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 13,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(children: [
                      Text(isDJ ? 'DJ' : '流行',
                        style: TextStyle(fontSize: 11, color: isPlaying ? AppColors.primaryLight : AppColors.textSecondary)),
                      if (song.playCount > 0) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.play_circle_outline, size: 10, color: AppColors.textTertiary),
                        const SizedBox(width: 2),
                        Text('${song.playCount}',
                          style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                      ],
                    ]),
                  ]),
                ),
                if (isPlaying)
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.15),
                    ),
                    child: const Icon(Icons.volume_up_rounded, color: AppColors.primary, size: 13),
                  ),
                if (onFavorite != null)
                  IconButton(
                    icon: Icon(
                      isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: isFavorite ? AppColors.primary : AppColors.textTertiary,
                      size: 20,
                    ),
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

/// 下载气泡
class DownloadBubble extends StatefulWidget {
  final String title;
  final bool isSuccess;
  final String? size;
  final VoidCallback onDismiss;
  const DownloadBubble({super.key, required this.title, required this.isSuccess, this.size, required this.onDismiss});

  @override
  State<DownloadBubble> createState() => _DownloadBubbleState();
}

class _DownloadBubbleState extends State<DownloadBubble> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _scaleAnim = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 3), () { if (mounted) _ctrl.reverse().then((_) => widget.onDismiss()); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: GestureDetector(
          onTap: () => _ctrl.reverse().then((_) => widget.onDismiss()),
          child: Container(
            margin: const EdgeInsets.only(bottom: 80),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: (widget.isSuccess ? AppColors.success : AppColors.error).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: (widget.isSuccess ? AppColors.success : AppColors.error).withValues(alpha: 0.3), blurRadius: 16, spreadRadius: 2),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: Icon(widget.isSuccess ? Icons.check_rounded : Icons.close_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(widget.isSuccess ? '下载完成' : '下载失败',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${widget.title} ${widget.size ?? ""}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),
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
  void initState() { super.initState(); _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => CustomPaint(size: const Size(21, 21), painter: _EqualizerPainter(_controller.value)),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  final double t;
  _EqualizerPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    for (int i = 0; i < 4; i++) {
      final h = 6 + 12 * (0.5 + 0.5 * math.sin(t * math.pi * 2 + i * 1.5));
      canvas.drawLine(Offset(4 + i * 5.0, 20 - h), Offset(4 + i * 5.0, 20), paint);
    }
  }
  @override
  bool shouldRepaint(covariant _EqualizerPainter o) => o.t != t;
}

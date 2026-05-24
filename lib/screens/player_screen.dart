import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/audio_player.dart';
import '../services/lyric_parser.dart';

class PlayerScreen extends StatefulWidget {
  final AudioPlayerService audioService;

  const PlayerScreen({super.key, required this.audioService});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription? _positionSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _showLyrics = false;

  // 均衡器动画条
  late final AnimationController _eqAnimCtrl;
  final List<double> _eqBars = List.generate(12, (_) => 0.2);

  @override
  void initState() {
    super.initState();

    // 监听播放位置，更新歌词
    _positionSub = widget.audioService.player.positionStream.listen((pos) {
      setState(() {
        _position = pos;
        widget.audioService.updateLyricPosition(pos);
      });
    });

    widget.audioService.player.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur ?? Duration.zero);
    });

    // 均衡器动画
    _eqAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(_updateEqBars);
    _eqAnimCtrl.repeat(reverse: true);
  }

  void _updateEqBars() {
    final rng = Random(DateTime.now().millisecondsSinceEpoch ~/ 100);
    final playing = widget.audioService.player.playing;
    final isDJ = widget.audioService.currentSong?.category == MusicCategory.dj;

    setState(() {
      for (int i = 0; i < _eqBars.length; i++) {
        final base = playing ? 0.4 : 0.1;
        final amp = isDJ ? 0.6 : 0.3;
        _eqBars[i] = base + rng.nextDouble() * amp;
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _eqAnimCtrl.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.audioService.currentSong;
    final isDJ = song?.category == MusicCategory.dj;
    final lyrics = widget.audioService.lyrics;
    final lyricIdx = widget.audioService.lyricIndex;

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
              _buildTopBar(isDJ),

              // ── 内容区域（封面 or 歌词） ──
              Expanded(
                child: _showLyrics && lyrics.isNotEmpty
                    ? _buildLyricView(lyrics, lyricIdx, isDJ)
                    : _buildCoverArt(isDJ),
              ),

              // ── 歌曲信息 ──
              _buildSongInfo(song),

              // ── 进度条 ──
              _buildProgressBar(isDJ),

              // ── 播放控制 ──
              _buildControls(isDJ),

              // ── 底部：播放模式 + 歌词切换 ──
              _buildBottomBar(isDJ, lyrics),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isDJ) {
    return Padding(
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
            isDJ ? '🔥 DJ 模式' : '🎵 流行模式',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildCoverArt(bool isDJ) {
    return Center(
      child: StreamBuilder<bool>(
        stream: widget.audioService.player.playingStream,
        builder: (context, snapshot) {
          final playing = snapshot.data ?? false;
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
    );
  }

  Widget _buildLyricView(
      List<LyricLine> lyrics, int currentIdx, bool isDJ) {
    return Column(
      children: [
        // 均衡器可视化
        SizedBox(
          height: 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(_eqBars.length, (i) {
              return Container(
                width: 6,
                height: _eqBars[i] * 70,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: isDJ
                        ? [Colors.orange.shade600, Colors.yellow.shade400]
                        : [Colors.pink.shade400, Colors.blue.shade300],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        // 歌词滚动
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(
                vertical: MediaQuery.of(context).size.height * 0.15),
            itemCount: lyrics.length,
            itemBuilder: (context, index) {
              final isCurrent = index == currentIdx;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    color: isCurrent
                        ? (isDJ ? Colors.orange : Colors.pink)
                        : Colors.white.withValues(alpha: 0.3),
                    fontSize: isCurrent ? 20 : 16,
                    fontWeight:
                        isCurrent ? FontWeight.bold : FontWeight.normal,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                  child: Text(lyrics[index].text),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSongInfo(Song? song) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: Column(
        children: [
          Text(
            song?.title ?? '未选择歌曲',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                song?.category == MusicCategory.dj
                    ? Icons.bolt_rounded
                    : Icons.headphones_rounded,
                color: Colors.white38,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                song?.category == MusicCategory.dj ? 'DJ 劲爆' : '流行歌曲',
                style:
                    TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
              ),
              const SizedBox(width: 12),
              // 播放模式指示
              Text(
                widget.audioService.playModeIcon,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(bool isDJ) {
    final sliderValue = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor:
                  isDJ ? Colors.orange.shade400 : Colors.pink.shade400,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: (isDJ ? Colors.orange : Colors.pink)
                  .withValues(alpha: 0.2),
            ),
            child: Slider(
              value: sliderValue.clamp(0.0, 1.0),
              onChanged: (v) {
                final ms = (v * _duration.inMilliseconds).round();
                widget.audioService.player
                    .seek(Duration(milliseconds: ms));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                ),
                Text(
                  _formatDuration(_duration),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(bool isDJ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 播放模式
          IconButton(
            icon: Text(
              widget.audioService.playModeIcon,
              style: const TextStyle(fontSize: 22),
            ),
            onPressed: () {
              widget.audioService.cyclePlayMode();
              setState(() {});
            },
            tooltip: '切换播放模式',
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous_rounded,
                color: Colors.white, size: 38),
            onPressed: () => widget.audioService.previous(),
          ),
          StreamBuilder<bool>(
            stream: widget.audioService.player.playingStream,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return Container(
                width: 64,
                height: 64,
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
                    size: 34,
                  ),
                  onPressed: widget.audioService.togglePlay,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.skip_next_rounded,
                color: Colors.white, size: 38),
            onPressed: () => widget.audioService.next(),
          ),
          // 歌词切换
          IconButton(
            icon: Icon(
              _showLyrics
                  ? Icons.lyrics_rounded
                  : Icons.lyrics_outlined,
              color: _showLyrics ? Colors.pink : Colors.white38,
              size: 26,
            ),
            onPressed: () =>
                setState(() => _showLyrics = !_showLyrics),
            tooltip: '歌词',
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isDJ, List<LyricLine> lyrics) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 歌词按钮
          _bottomBtn(
            icon: lyrics.isNotEmpty
                ? Icons.closed_caption_rounded
                : Icons.closed_caption_disabled_rounded,
            label: lyrics.isNotEmpty ? '有歌词' : '无歌词',
            active: _showLyrics,
            onTap: lyrics.isNotEmpty
                ? () => setState(() => _showLyrics = !_showLyrics)
                : null,
          ),
          // 均衡器视觉
          _bottomBtn(
            icon: isDJ ? Icons.equalizer_rounded : Icons.equalizer_outlined,
            label: isDJ ? 'DJ音效' : '标准',
            active: isDJ,
            onTap: null,
          ),
          // 歌曲数
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${widget.audioService.queue.length} 首',
              style:
                  TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBtn({
    required IconData icon,
    required String label,
    required bool active,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? Colors.pink.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: active
              ? Border.all(color: Colors.pink.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: active ? Colors.pink : Colors.white38, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.pink : Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

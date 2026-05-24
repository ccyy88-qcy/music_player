import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
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
  bool _showLyrics = true;
  Timer? _sleepUiTimer;

  // 均衡器动画
  late final AnimationController _eqAnimCtrl;
  final List<double> _eqBars = List.generate(16, (_) => 0.15);

  @override
  void initState() {
    super.initState();

    _positionSub = widget.audioService.player.positionStream.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
          widget.audioService.updateLyricPosition(pos);
        });
      }
    });

    widget.audioService.player.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur ?? Duration.zero);
    });

    // 睡眠定时器 UI 刷新
    _sleepUiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.audioService.sleepActive) setState(() {});
    });

    _eqAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addListener(_updateEqBars);
    _eqAnimCtrl.repeat(reverse: true);
  }

  void _updateEqBars() {
    final rng = Random(DateTime.now().millisecondsSinceEpoch ~/ 50);
    final playing = widget.audioService.player.playing;
    final isDJ = widget.audioService.currentSong?.category == MusicCategory.dj;
    final eq = widget.audioService.eqPreset;

    setState(() {
      final bassBoost = eq == EqPreset.djBass || eq == EqPreset.heavyBass;
      for (int i = 0; i < _eqBars.length; i++) {
        final base = playing ? 0.25 : 0.05;
        var amp = isDJ ? 0.55 : 0.3;
        // 低频段（0-4）加重
        if (bassBoost && i < 5) amp *= 1.6;
        if (eq == EqPreset.vocal && i > 4 && i < 10) amp *= 1.3;
        if (eq == EqPreset.classical && i > 8) amp *= 0.6;
        _eqBars[i] = base + rng.nextDouble() * amp;
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _sleepUiTimer?.cancel();
    _eqAnimCtrl.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
                ? [const Color(0xFF2D1B00), const Color(0xFF0F0F1A)]
                : [const Color(0xFF0D1B3E), const Color(0xFF0F0F1A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _topBar(isDJ),
              Expanded(
                child: _showLyrics && lyrics.isNotEmpty
                    ? _lyricView(lyrics, lyricIdx, isDJ)
                    : _coverView(isDJ),
              ),
              _songInfo(song, isDJ),
              _progressBar(isDJ),
              _controls(isDJ),
              _bottomBar(isDJ, lyrics),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── 顶部栏 ──
  Widget _topBar(bool isDJ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white70, size: 32),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          // 睡眠定时器指示
          if (widget.audioService.sleepActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.pink.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bedtime_rounded, color: Colors.pink, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    widget.audioService.sleepTimerLabel,
                    style: const TextStyle(color: Colors.pink, fontSize: 12),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
          Text(
            '${widget.audioService.currentIndex + 1}/${widget.audioService.queue.length}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── 封面 ──
  Widget _coverView(bool isDJ) {
    return Center(
      child: StreamBuilder<bool>(
        stream: widget.audioService.player.playingStream,
        builder: (context, snapshot) {
          final playing = snapshot.data ?? false;
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: playing ? 2 * pi : 0),
            duration: const Duration(seconds: 25),
            builder: (context, value, child) =>
                Transform.rotate(angle: value, child: child),
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isDJ
                      ? [Colors.orange.shade600, Colors.red.shade500, Colors.purple]
                      : [Colors.blue.shade600, Colors.pink.shade400, Colors.purple],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isDJ ? Colors.orange : Colors.blue)
                        .withValues(alpha: 0.35),
                    blurRadius: 50,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const Icon(Icons.music_note_rounded,
                  color: Colors.white, size: 70),
            ),
          );
        },
      ),
    );
  }

  // ── 歌词视图 ──
  Widget _lyricView(List<LyricLine> lyrics, int currentIdx, bool isDJ) {
    return Column(
      children: [
        // 均衡器可视化
        SizedBox(
          height: 70,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_eqBars.length, (i) {
                final t = i / (_eqBars.length - 1);
                final color = Color.lerp(
                  isDJ ? Colors.orange : Colors.pink,
                  isDJ ? Colors.yellow : Colors.blue,
                  t,
                )!;
                return Container(
                  width: 4,
                  height: _eqBars[i] * 60,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [color, color.withValues(alpha: 0.3)],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(
                vertical: MediaQuery.of(context).size.height * 0.12),
            itemCount: lyrics.length,
            itemBuilder: (context, index) {
              final isCurrent = index == currentIdx;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 7),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    color: isCurrent
                        ? (isDJ ? Colors.orange : Colors.pink)
                        : Colors.white.withValues(alpha: 0.25),
                    fontSize: isCurrent ? 21 : 15,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    height: 1.6,
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

  // ── 歌曲信息 ──
  Widget _songInfo(Song? song, bool isDJ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
      child: Column(
        children: [
          Text(
            song?.title ?? '未选择',
            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.audioService.eqPresetLabel,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
              ),
              const SizedBox(width: 8),
              Text(
                widget.audioService.speedLabel,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11),
              ),
              const SizedBox(width: 8),
              Text(
                widget.audioService.playModeLabel,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 进度条 ──
  Widget _progressBar(bool isDJ) {
    final v = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: isDJ ? Colors.orange.shade400 : Colors.pink.shade400,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: (isDJ ? Colors.orange : Colors.pink).withValues(alpha: 0.2),
            ),
            child: Slider(
              value: v.clamp(0.0, 1.0),
              onChanged: (x) => widget.audioService.player
                  .seek(Duration(milliseconds: (x * _duration.inMilliseconds).round())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(_position),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
                Text(_fmt(_duration),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 控制栏 ──
  Widget _controls(bool isDJ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 播放模式
          IconButton(
            icon: const Icon(Icons.repeat_rounded, color: Colors.white38, size: 24),
            onPressed: () {
              widget.audioService.cyclePlayMode();
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous_rounded,
                color: Colors.white, size: 38),
            onPressed: () => widget.audioService.previous(),
          ),
          StreamBuilder<bool>(
            stream: widget.audioService.player.playingStream,
            builder: (context, snapshot) {
              final p = snapshot.data ?? false;
              return Container(
                width: 66,
                height: 66,
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
                          .withValues(alpha: 0.45),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    p ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white, size: 36,
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
          IconButton(
            icon: const Icon(Icons.shuffle_rounded, color: Colors.white38, size: 24),
            onPressed: () => widget.audioService.setPlayMode(PlayMode.shuffle),
          ),
        ],
      ),
    );
  }

  // ── 底部功能栏 ──
  Widget _bottomBar(bool isDJ, List<LyricLine> lyrics) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _chip(
            icon: lyrics.isNotEmpty ? Icons.lyrics_rounded : Icons.lyrics_outlined,
            label: '歌词',
            active: _showLyrics,
            onTap: () => setState(() => _showLyrics = !_showLyrics),
          ),
          _chip(
            icon: Icons.equalizer_rounded,
            label: widget.audioService.eqPresetLabel,
            active: widget.audioService.eqPreset != EqPreset.flat,
            onTap: () {
              widget.audioService.cycleEqPreset();
              setState(() {});
            },
          ),
          _chip(
            icon: Icons.speed_rounded,
            label: widget.audioService.speedLabel,
            active: widget.audioService.speed != 1.0,
            onTap: () {
              widget.audioService.cycleSpeed();
              setState(() {});
            },
          ),
          _chip(
            icon: widget.audioService.sleepActive
                ? Icons.bedtime_rounded
                : Icons.bedtime_outlined,
            label: widget.audioService.sleepTimerLabel,
            active: widget.audioService.sleepActive,
            onTap: () {
              widget.audioService.cycleSleepTimer();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.pink.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: active
              ? Border.all(color: Colors.pink.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: active ? Colors.pink.shade300 : Colors.white38,
                size: 15),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    color: active ? Colors.pink.shade200 : Colors.white38,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

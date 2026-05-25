import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';
import '../services/lyric_parser.dart';
import '../main.dart' show audioHandler, AppColors;

// ─── 浮动音符粒子 ───
class _FloatNote {
  double x, y, size, speed, opacity, rot;
  _FloatNote(this.x, this.y, this.size, this.speed, this.opacity, this.rot);
}

class _PlayerParticles extends StatefulWidget {
  final Widget child;
  const _PlayerParticles({required this.child});
  @override
  State<_PlayerParticles> createState() => _PlayerParticlesState();
}

class _PlayerParticlesState extends State<_PlayerParticles> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  List<_FloatNote> _notes = [];
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _notes = List.generate(12, (_) => _createNote());
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 20))..addListener(_update)..repeat();
  }

  _FloatNote _createNote({bool bottom = false}) {
    return _FloatNote(
      _rng.nextDouble() * 360,
      bottom ? 700 + _rng.nextDouble() * 100 : -20 - _rng.nextDouble() * 50,
      14 + _rng.nextDouble() * 20,
      0.2 + _rng.nextDouble() * 0.4,
      0.06 + _rng.nextDouble() * 0.15,
      _rng.nextDouble() * math.pi * 2,
    );
  }

  void _update() {
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _notes.length; i++) {
        _notes[i].y -= _notes[i].speed;
        _notes[i].x += math.sin(_notes[i].y * 0.03) * 0.5;
        _notes[i].rot += 0.005;
        if (_notes[i].y < -50) _notes[i] = _createNote(bottom: true);
      }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _PlayerNotePainter(_notes, audioHandler.player.playing),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerNotePainter extends CustomPainter {
  final List<_FloatNote> notes;
  final bool playing;
  _PlayerNotePainter(this.notes, this.playing);

  @override
  void paint(Canvas canvas, Size size) {
    if (!playing) return;
    for (final n in notes) {
      final opacity = n.opacity.clamp(0.0, 0.3);
      canvas.save();
      canvas.translate(n.x, n.y);
      canvas.rotate(n.rot);
      final tp = TextPainter(
        text: TextSpan(text: ['♪', '♫', '♩'][n.hashCode.abs() % 3], style: TextStyle(color: AppColors.foxOrange.withValues(alpha: opacity), fontSize: n.size, fontWeight: FontWeight.w100)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PlayerNotePainter o) => true;
}

// ─── 脉冲发光动画 ───
class _PulseGlow extends StatefulWidget {
  final Widget child;
  final bool playing;
  final bool dj;
  const _PulseGlow({required this.child, required this.playing, required this.dj});

  @override
  State<_PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<_PulseGlow> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true); }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final glowIntensity = widget.playing ? 0.5 + _ctrl.value * 0.8 : 0.2;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: (widget.dj ? AppColors.glowOrange : AppColors.glowPurple).withValues(alpha: glowIntensity * 0.6), blurRadius: 40 + _ctrl.value * 40, spreadRadius: 8 + _ctrl.value * 15),
              BoxShadow(color: (widget.dj ? AppColors.foxOrange : AppColors.purple).withValues(alpha: glowIntensity * 0.3), blurRadius: 70, spreadRadius: 20),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription? _posSub;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _showLyrics = true;
  Timer? _sleepUi;

  late final AnimationController _eqCtrl;
  final _eqBars = List.generate(16, (_) => 0.15);
  late final AnimationController _rotateCtrl;
  late final AnimationController _bgGradCtrl;

  @override
  void initState() {
    super.initState();
    _posSub = audioHandler.player.positionStream.listen((p) {
      if (mounted) { _pos = p; audioHandler.updateLyricPosition(p); setState(() {}); }
    });
    audioHandler.player.durationStream.listen((d) { if (mounted) _dur = d ?? Duration.zero; });
    _sleepUi = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted && audioHandler.sleepActive) setState(() {}); });
    _eqCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..addListener(_eq)..repeat(reverse: true);
    _rotateCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _bgGradCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);
  }

  void _eq() {
    final r = math.Random(DateTime.now().millisecondsSinceEpoch ~/ 50);
    final p = audioHandler.player.playing;
    final dj = audioHandler.currentSong?.category == MusicCategory.dj;
    final eq = audioHandler.eqPreset;
    for (int i = 0; i < _eqBars.length; i++) {
      var a = (p ? 0.3 : 0.05) + r.nextDouble() * (dj ? 0.6 : 0.35);
      if ((eq == EqPreset.djBass || eq == EqPreset.heavyBass) && i < 5) a *= 1.6;
      _eqBars[i] = a.clamp(0.0, 1.0);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() { _posSub?.cancel(); _sleepUi?.cancel(); _eqCtrl.dispose(); _rotateCtrl.dispose(); _bgGradCtrl.dispose(); super.dispose(); }

  String _fmt(Duration d) => '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = audioHandler.currentSong;
    final dj = s?.category == MusicCategory.dj;
    final lrc = audioHandler.lyrics;
    final lrcI = audioHandler.lyricIndex;

    return Scaffold(
      body: _PlayerParticles(
        child: AnimatedBuilder(
          animation: _bgGradCtrl,
          builder: (_, __) {
            final t = _bgGradCtrl.value;
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(dj ? const Color(0xFF3D1F00) : const Color(0xFF1A0A3E), dj ? const Color(0xFF5A2D00) : const Color(0xFF2D0050), t)!,
                    AppColors.bg,
                    AppColors.bg,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // 背景阿狸图模糊
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.08,
                      child: Container(
                        decoration: const BoxDecoration(
                          image: DecorationImage(image: AssetImage('assets/images/ali.jpg'), fit: BoxFit.cover),
                        ),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Column(children: [
                      _top(dj),
                      Expanded(child: _showLyrics && lrc.isNotEmpty ? _lrcView(lrc, lrcI, dj) : _albumArt(dj)),
                      _info(s, dj),
                      _progress(dj),
                      _ctrls(dj),
                      _bottom(dj, lrc),
                      const SizedBox(height: 12),
                    ]),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _top(bool dj) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textPrimary, size: 32), onPressed: () => Navigator.pop(context)),
        const Spacer(),
        if (audioHandler.sleepActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.foxOrange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.foxOrange.withValues(alpha: 0.3)),
              boxShadow: [BoxShadow(color: AppColors.glowOrange, blurRadius: 8)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bedtime_rounded, color: AppColors.foxOrange, size: 14),
              const SizedBox(width: 4),
              Text(audioHandler.sleepTimerLabel, style: const TextStyle(color: AppColors.foxOrange, fontSize: 12)),
            ]),
          ),
        const SizedBox(width: 8),
        Text('${audioHandler.currentIndex + 1}/${audioHandler.songQueue.length}',
          style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5), fontSize: 12)),
        const SizedBox(width: 40),
      ]),
    );
  }

  Widget _albumArt(bool dj) {
    return StreamBuilder<bool>(
      stream: audioHandler.player.playingStream,
      builder: (_, snap) {
        final playing = snap.data == true;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 脉冲发光 + 旋转唱片
              _PulseGlow(
                playing: playing, dj: dj,
                child: AnimatedBuilder(
                  animation: _rotateCtrl,
                  builder: (_, __) {
                    final angle = playing ? _rotateCtrl.value * math.pi * 2 : 0.0;
                    return Transform.rotate(
                      angle: angle,
                      child: Container(
                        width: 230, height: 230,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          image: const DecorationImage(image: AssetImage('assets/images/ali.jpg'), fit: BoxFit.cover),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 25, spreadRadius: 8),
                          ],
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: (dj ? AppColors.foxOrange : AppColors.purple).withValues(alpha: 0.4), width: 2),
                          ),
                          child: Center(
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(colors: [AppColors.foxOrange, AppColors.purple]),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8)],
                              ),
                              child: Icon(playing ? Icons.equalizer_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              // 均衡器条
              SizedBox(
                height: 45,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_eqBars.length, (i) => Container(
                    width: 3,
                    height: (_eqBars[i] * 38 + 5).clamp(0.0, 50.0),
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter, end: Alignment.topCenter,
                        colors: [
                          Color.lerp(dj ? AppColors.foxOrange : AppColors.purple, dj ? Colors.yellow : Colors.pink, i / (_eqBars.length - 1))!,
                          Color.lerp(dj ? AppColors.foxOrange : AppColors.purple, dj ? Colors.yellow : Colors.pink, i / (_eqBars.length - 1))!.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                  )),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _lrcView(List<LyricLine> lrc, int cur, bool dj) {
    return Column(children: [
      const SizedBox(height: 12),
      SizedBox(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_eqBars.length, (i) => Container(
            width: 3,
            height: (_eqBars[i] * 35 + 5).clamp(0.0, 50.0),
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [
                  Color.lerp(dj ? AppColors.foxOrange : AppColors.purple, dj ? Colors.yellow : Colors.pink, i / (_eqBars.length - 1))!,
                  Color.lerp(dj ? AppColors.foxOrange : AppColors.purple, dj ? Colors.yellow : Colors.pink, i / (_eqBars.length - 1))!.withValues(alpha: 0.1),
                ],
              ),
            ),
          )),
        ),
      ),
      const SizedBox(height: 20),
      Expanded(
        child: ListView.builder(
          padding: EdgeInsets.symmetric(vertical: MediaQuery.of(context).size.height * 0.1),
          itemCount: lrc.length,
          itemBuilder: (_, i) {
            final isCur = i == cur;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  color: isCur ? (dj ? AppColors.foxOrange : AppColors.purple) : AppColors.textSecondary.withValues(alpha: 0.25),
                  fontSize: isCur ? 21 : 14,
                  fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
                child: Text(lrc[i].text),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _info(Song? s, bool dj) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
      child: Column(children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: dj ? [AppColors.foxOrange, Colors.yellow] : [AppColors.purple, Colors.pink.shade200],
          ).createShader(bounds),
          child: Text(s?.title ?? '未选择',
            style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold),
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _infoTag(audioHandler.eqPresetLabel, dj), const SizedBox(width: 8),
          _infoTag(audioHandler.speedLabel, dj), const SizedBox(width: 8),
          _infoTag(audioHandler.playModeLabel, dj),
        ]),
      ]),
    );
  }

  Widget _infoTag(String label, bool dj) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (dj ? AppColors.foxOrange : AppColors.purple).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (dj ? AppColors.foxOrange : AppColors.purple).withValues(alpha: 0.2)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: dj ? AppColors.foxOrange : AppColors.purple, fontWeight: FontWeight.w600)),
    );
  }

  Widget _progress(bool dj) {
    final v = _dur.inMilliseconds > 0 ? _pos.inMilliseconds / _dur.inMilliseconds : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(children: [
        GestureDetector(
          onTapDown: (d) {
            final newPos = (d.localPosition.dx / (MediaQuery.of(context).size.width - 64) * _dur.inMilliseconds).round();
            audioHandler.seek(Duration(milliseconds: newPos));
          },
          child: Container(
            height: 5,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: AppColors.textSecondary.withValues(alpha: 0.12)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(colors: [dj ? AppColors.foxOrange : AppColors.purple, dj ? Colors.yellow : Colors.pink.shade200]),
                  boxShadow: [BoxShadow(color: AppColors.glowOrange, blurRadius: 6, spreadRadius: 1)],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(_fmt(_pos), style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5), fontSize: 11)),
            Text(_fmt(_dur), style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5), fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  Widget _ctrls(bool dj) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _ctrlBtn(Icons.repeat_rounded, 22, () { audioHandler.cyclePlayMode(); setState(() {}); }),
        _ctrlBtn(Icons.skip_previous_rounded, 34, () => audioHandler.skipToPrevious()),
        StreamBuilder<bool>(
          stream: audioHandler.player.playingStream,
          builder: (_, snap) {
            final p = snap.data == true;
            return Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [AppColors.foxOrange, AppColors.purple]),
                boxShadow: [
                  BoxShadow(color: (dj ? AppColors.glowOrange : AppColors.glowPurple), blurRadius: 30, spreadRadius: 5),
                ],
              ),
              child: IconButton(
                icon: Icon(p ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 38),
                onPressed: audioHandler.togglePlay,
              ),
            );
          },
        ),
        _ctrlBtn(Icons.skip_next_rounded, 34, () => audioHandler.skipToNext()),
        _ctrlBtn(Icons.shuffle_rounded, 22, () => audioHandler.skipToNext()),
      ]),
    );
  }

  Widget _ctrlBtn(IconData icon, double size, VoidCallback onTap) {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: AppColors.glass,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
      ),
      child: IconButton(icon: Icon(icon, color: AppColors.textPrimary.withValues(alpha: 0.8), size: size), onPressed: onTap, padding: EdgeInsets.zero),
    );
  }

  Widget _bottom(bool dj, List<LyricLine> lrc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _chip(Icons.lyrics_rounded, '歌词', _showLyrics, () => setState(() => _showLyrics = !_showLyrics)),
        _chip(Icons.equalizer_rounded, audioHandler.eqPresetLabel, audioHandler.eqPreset != EqPreset.flat, () { audioHandler.cycleEqPreset(); setState(() {}); }),
        _chip(Icons.speed_rounded, audioHandler.speedLabel, audioHandler.speed != 1.0, () { audioHandler.cycleSpeed(); setState(() {}); }),
        _chip(audioHandler.sleepActive ? Icons.bedtime_rounded : Icons.bedtime_outlined, audioHandler.sleepTimerLabel, audioHandler.sleepActive, () { audioHandler.cycleSleepTimer(); setState(() {}); }),
      ]),
    );
  }

  Widget _chip(IconData i, String l, bool a, VoidCallback t) {
    return GestureDetector(
      onTap: t,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: a ? (AppColors.foxOrange.withValues(alpha: 0.15)) : AppColors.glass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: a ? AppColors.foxOrange.withValues(alpha: 0.5) : AppColors.glassBorder),
          boxShadow: a ? [BoxShadow(color: AppColors.glowOrange, blurRadius: 6)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, color: a ? AppColors.foxOrange : AppColors.textSecondary.withValues(alpha: 0.4), size: 15),
          const SizedBox(width: 3),
          Text(l, style: TextStyle(color: a ? AppColors.foxOrange : AppColors.textSecondary.withValues(alpha: 0.4), fontSize: 11, fontWeight: a ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';
import '../services/lyric_parser.dart';
import '../main.dart' show audioHandler, AppColors;

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
    _notes = List.generate(8, (_) => _createNote());
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 20))..addListener(_update)..repeat();
  }

  _FloatNote _createNote({bool bottom = false}) {
    return _FloatNote(
      _rng.nextDouble() * 360,
      bottom ? 700 + _rng.nextDouble() * 100 : -20 - _rng.nextDouble() * 50,
      14 + _rng.nextDouble() * 20,
      0.2 + _rng.nextDouble() * 0.4,
      0.04 + _rng.nextDouble() * 0.1,
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
      canvas.save();
      canvas.translate(n.x, n.y);
      canvas.rotate(n.rot);
      final tp = TextPainter(
        text: TextSpan(text: ['♪', '♫', '♩'][n.hashCode.abs() % 3],
          style: TextStyle(color: AppColors.primary.withValues(alpha: n.opacity), fontSize: n.size, fontWeight: FontWeight.w100)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }
  @override
  bool shouldRepaint(covariant _PlayerNotePainter o) => true;
}

class _PulseGlow extends StatefulWidget {
  final Widget child; final bool playing; final bool dj;
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
    return AnimatedBuilder(animation: _ctrl, builder: (_, child) {
      final i = widget.playing ? 0.5 + _ctrl.value * 0.8 : 0.2;
      return Container(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
          BoxShadow(color: (widget.dj ? AppColors.glowPrimary : AppColors.glowAccent).withValues(alpha: i * 0.6), blurRadius: 40 + _ctrl.value * 40, spreadRadius: 8 + _ctrl.value * 15),
          BoxShadow(color: (widget.dj ? AppColors.primary : AppColors.accent).withValues(alpha: i * 0.3), blurRadius: 70, spreadRadius: 20),
        ]),
        child: child,
      );
    }, child: widget.child);
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with SingleTickerProviderStateMixin {
  StreamSubscription? _posSub;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _showLyrics = true;
  Timer? _sleepUi;
  final ScrollController _lrcScrollCtrl = ScrollController();
  bool _lrcAutoScroll = true;
  int _lastLrcIndex = -1;

  late final AnimationController _eqCtrl;
  final _eqBars = List.generate(16, (_) => 0.15);
  late final AnimationController _rotateCtrl;
  late final AnimationController _bgGradCtrl;

  @override
  void initState() {
    super.initState();
    _posSub = audioHandler.player.positionStream.listen((p) { if (mounted) { _pos = p; setState(() {}); } });
    audioHandler.player.durationStream.listen((d) { if (mounted) _dur = d ?? Duration.zero; });
    _sleepUi = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted && audioHandler.sleepActive) setState(() {}); });
    _eqCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..addListener(_eq)..repeat(reverse: true);
    _rotateCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _bgGradCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
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
  void dispose() { _posSub?.cancel(); _sleepUi?.cancel(); _lrcScrollCtrl.dispose(); _eqCtrl.dispose(); _rotateCtrl.dispose(); _bgGradCtrl.dispose(); super.dispose(); }

  String _fmt(Duration d) => '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  void _scrollToCurrentLrc(int cur, List<LyricLine> lrc) {
    if (!_lrcAutoScroll || cur < 0 || _lastLrcIndex == cur) return;
    _lastLrcIndex = cur;
    final offset = (cur * 60.0) - (MediaQuery.of(context).size.height * 0.1) + 60;
    if (_lrcScrollCtrl.hasClients) {
      _lrcScrollCtrl.animateTo(offset.clamp(0.0, _lrcScrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = audioHandler.currentSong;
    final dj = s?.category == MusicCategory.dj;
    final lrc = audioHandler.lyrics;
    final lrcI = audioHandler.lyricIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _scrollToCurrentLrc(lrcI, lrc); });

    return Scaffold(
      body: _PlayerParticles(
        child: AnimatedBuilder(animation: _bgGradCtrl, builder: (_, __) {
          final t = _bgGradCtrl.value;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [
                  Color.lerp(dj ? const Color(0xFF2A1500) : const Color(0xFF150A2E), dj ? const Color(0xFF3D2000) : const Color(0xFF220040), t)!,
                  AppColors.bg,
                  AppColors.bg,
                ],
              ),
            ),
            child: SafeArea(
              child: Column(children: [
                _top(dj),
                Expanded(child: _showLyrics && lrc.isNotEmpty ? _lrcView(lrc, lrcI, dj) : _albumArt(dj)),
                _info(s, dj),
                _progress(dj),
                _ctrls(dj),
                _bottom(dj, lrc),
                const SizedBox(height: 8),
              ]),
            ),
          );
        }),
      ),
    );
  }

  Widget _top(bool dj) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textPrimary, size: 30), onPressed: () => Navigator.pop(context)),
        const Spacer(),
        if (audioHandler.sleepActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bedtime_rounded, color: AppColors.primary, size: 13),
              const SizedBox(width: 4),
              Text(audioHandler.sleepTimerLabel, style: const TextStyle(color: AppColors.primary, fontSize: 11)),
            ]),
          ),
        const SizedBox(width: 8),
        Text('${audioHandler.currentIndex + 1}/${audioHandler.songQueue.length}',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        const SizedBox(width: 40),
      ]),
    );
  }

  Widget _albumArt(bool dj) {
    return StreamBuilder<bool>(
      stream: audioHandler.player.playingStream,
      builder: (_, snap) {
        final playing = snap.data == true;
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _PulseGlow(playing: playing, dj: dj, child: AnimatedBuilder(animation: _rotateCtrl, builder: (_, __) {
            final angle = playing ? _rotateCtrl.value * math.pi * 2 : 0.0;
            return Transform.rotate(angle: angle, child: Container(
              width: 210, height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: dj ? [const Color(0xFFFF6B35), const Color(0xFFE85D2C)] : [const Color(0xFFA855F7), const Color(0xFF7C3AED)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 25, spreadRadius: 8)],
              ),
              child: Center(child: Text('🦊', style: TextStyle(fontSize: 80))),
            ));
          })),
          const SizedBox(height: 16),
          // EQ bars
          SizedBox(height: 40, child: Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_eqBars.length, (i) => Container(
              width: 3, height: (_eqBars[i] * 35 + 5).clamp(0.0, 50.0),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [
                  Color.lerp(dj ? AppColors.primary : AppColors.accent, dj ? Colors.yellow : Colors.pink, i / (_eqBars.length - 1))!,
                  Color.lerp(dj ? AppColors.primary : AppColors.accent, dj ? Colors.yellow : Colors.pink, i / (_eqBars.length - 1))!.withValues(alpha: 0.1),
                ]),
              ),
            )),
          )),
        ]));
      },
    );
  }

  Widget _lrcView(List<LyricLine> lrc, int cur, bool dj) {
    return Column(children: [
      const SizedBox(height: 8),
      SizedBox(height: 35, child: Row(mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_eqBars.length, (i) => Container(
          width: 3, height: (_eqBars[i] * 30 + 5).clamp(0.0, 50.0),
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [
              Color.lerp(dj ? AppColors.primary : AppColors.accent, dj ? Colors.yellow : Colors.pink, i / (_eqBars.length - 1))!,
              Color.lerp(dj ? AppColors.primary : AppColors.accent, dj ? Colors.yellow : Colors.pink, i / (_eqBars.length - 1))!.withValues(alpha: 0.1),
            ]),
          ),
        )),
      )),
      const SizedBox(height: 12),
      Expanded(
        child: ListView.builder(
          controller: _lrcScrollCtrl,
          padding: EdgeInsets.symmetric(vertical: MediaQuery.of(context).size.height * 0.1),
          itemCount: lrc.length,
          itemBuilder: (_, i) {
            final isCur = i == cur;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 5),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  color: isCur ? (dj ? AppColors.primary : AppColors.accent) : AppColors.textSecondary.withValues(alpha: 0.2),
                  fontSize: isCur ? 20 : 14,
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
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
      child: Column(children: [
        Text(s?.title ?? '未选择',
          style: TextStyle(
            color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold,
            foreground: Paint()..shader = LinearGradient(
              colors: dj ? [AppColors.primary, Colors.yellow] : [AppColors.accent, Colors.pink.shade200],
            ).createShader(const Rect.fromLTWH(0, 0, 200, 30)),
          ),
          maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _infoTag(audioHandler.eqPresetLabel, dj),
          const SizedBox(width: 8),
          _infoTag(audioHandler.speedLabel, dj),
          const SizedBox(width: 8),
          _infoTag(audioHandler.playModeLabel, dj),
        ]),
      ]),
    );
  }

  Widget _infoTag(String label, bool dj) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (dj ? AppColors.primary : AppColors.accent).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (dj ? AppColors.primary : AppColors.accent).withValues(alpha: 0.15)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: dj ? AppColors.primary : AppColors.accent, fontWeight: FontWeight.w600)),
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
            height: 4,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: AppColors.textTertiary.withValues(alpha: 0.15)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(colors: [dj ? AppColors.primary : AppColors.accent, dj ? Colors.yellow : Colors.pink.shade200]),
                  boxShadow: [BoxShadow(color: AppColors.glowPrimary, blurRadius: 4, spreadRadius: 1)],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(_fmt(_pos), style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
            Text(_fmt(_dur), style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  Widget _ctrls(bool dj) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _ctrlBtn(Icons.repeat_rounded, 22, () => _showPlayModePicker(dj)),
        _ctrlBtn(Icons.skip_previous_rounded, 32, () => audioHandler.skipToPrevious()),
        StreamBuilder<bool>(
          stream: audioHandler.player.playingStream,
          builder: (_, snap) {
            final p = snap.data == true;
            return Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: AppColors.gradientMix),
                boxShadow: [BoxShadow(color: (dj ? AppColors.glowPrimary : AppColors.glowAccent), blurRadius: 24, spreadRadius: 4)],
              ),
              child: IconButton(
                icon: Icon(p ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 36),
                onPressed: audioHandler.togglePlay,
              ),
            );
          },
        ),
        _ctrlBtn(Icons.skip_next_rounded, 32, () => audioHandler.skipToNext()),
        _ctrlBtn(Icons.shuffle_rounded, 22, () { audioHandler.cyclePlayMode(); setState(() {}); }),
      ]),
    );
  }

  void _showPlayModePicker(bool dj) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: AppColors.textTertiary, borderRadius: BorderRadius.circular(2))),
            Text('播放模式', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
            const SizedBox(height: 8),
            ...PlayMode.values.map((pm) {
              final icons = ['→', '🔂', '🔁', '🔀'];
              final labels = ['顺序播放', '单曲循环', '列表循环', '随机播放'];
              final idx = pm.index;
              final sel = audioHandler.playMode == pm;
              return ListTile(
                leading: Text(icons[idx], style: const TextStyle(fontSize: 20)),
                title: Text(labels[idx], style: TextStyle(color: sel ? AppColors.primary : AppColors.textPrimary, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                trailing: sel ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () {
                  while (audioHandler.playMode != pm) { audioHandler.cyclePlayMode(); }
                  Navigator.pop(ctx);
                  setState(() {});
                },
              );
            }),
          ]),
        ),
      ),
    );
  }

  Widget _ctrlBtn(IconData icon, double size, VoidCallback onTap) {
    return Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: AppColors.glass,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: IconButton(icon: Icon(icon, color: AppColors.textPrimary.withValues(alpha: 0.8), size: size), onPressed: onTap, padding: EdgeInsets.zero),
    );
  }

  Widget _bottom(bool dj, List<LyricLine> lrc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _chip(Icons.lyrics_rounded, '歌词', _showLyrics, () => setState(() => _showLyrics = !_showLyrics)),
          _chip(Icons.equalizer_rounded, audioHandler.eqPresetLabel, audioHandler.eqPreset != EqPreset.flat, () { audioHandler.cycleEqPreset(); setState(() {}); }),
          _chip(Icons.speed_rounded, audioHandler.speedLabel, audioHandler.speed != 1.0, () { audioHandler.cycleSpeed(); setState(() {}); }),
          _chip(audioHandler.sleepActive ? Icons.bedtime_rounded : Icons.bedtime_outlined, audioHandler.sleepTimerLabel, audioHandler.sleepActive, () { audioHandler.cycleSleepTimer(); setState(() {}); }),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _offsetBtn('←0.2s', () { audioHandler.adjustLyricOffset(-200); setState(() {}); }),
          const SizedBox(width: 4),
          _offsetBtn('←0.1s', () { audioHandler.adjustLyricOffset(-100); setState(() {}); }),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              gradient: audioHandler.lyricOffset == 0 ? null : const LinearGradient(colors: AppColors.gradientMix),
              color: audioHandler.lyricOffset == 0 ? AppColors.glass : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: audioHandler.lyricOffset == 0 ? AppColors.glassBorder : AppColors.primary.withValues(alpha: 0.5)),
            ),
            child: Text(audioHandler.lyricOffsetLabel,
              style: TextStyle(color: audioHandler.lyricOffset == 0 ? AppColors.textTertiary : Colors.white, fontSize: 11, fontWeight: audioHandler.lyricOffset == 0 ? FontWeight.normal : FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          _offsetBtn('+0.1s→', () { audioHandler.adjustLyricOffset(100); setState(() {}); }),
          const SizedBox(width: 4),
          _offsetBtn('+0.2s→', () { audioHandler.adjustLyricOffset(200); setState(() {}); }),
          const SizedBox(width: 4),
          _offsetBtn2(Icons.vertical_align_center_rounded, _lrcAutoScroll ? AppColors.accent : null, () => setState(() => _lrcAutoScroll = !_lrcAutoScroll)),
          if (audioHandler.lyricOffset != 0) ...[
            const SizedBox(width: 4),
            _offsetBtn2(Icons.refresh_rounded, AppColors.error, () { audioHandler.resetLyricOffset(); setState(() {}); }),
          ],
        ]),
      ]),
    );
  }

  Widget _offsetBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.glass, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 10)),
      ),
    );
  }

  Widget _offsetBtn2(IconData icon, Color? color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: color?.withValues(alpha: 0.12) ?? AppColors.glass, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color ?? AppColors.textTertiary, size: 14),
      ),
    );
  }

  Widget _chip(IconData i, String l, bool a, VoidCallback t) {
    return GestureDetector(
      onTap: t,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: a ? (AppColors.primary.withValues(alpha: 0.12)) : AppColors.glass,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: a ? AppColors.primary.withValues(alpha: 0.4) : AppColors.glassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, color: a ? AppColors.primary : AppColors.textTertiary, size: 14),
          const SizedBox(width: 3),
          Text(l, style: TextStyle(color: a ? AppColors.primary : AppColors.textTertiary, fontSize: 11, fontWeight: a ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }
}

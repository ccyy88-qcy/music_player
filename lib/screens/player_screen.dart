import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';
import '../services/lyric_parser.dart';
import '../main.dart' show audioHandler, AppColors;

class _FloatNote {
  double x, y, size, speed, opacity, rot; int type;
  _FloatNote(this.x, this.y, this.size, this.speed, this.opacity, this.rot, this.type);
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with TickerProviderStateMixin {
  StreamSubscription? _posSub;
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _showLyrics = true;
  Timer? _sleepUi;
  final _lrcScroll = ScrollController();
  bool _lrcAuto = true;
  int _lastLrcIdx = -1;

  late final AnimationController _eqCtrl, _rotCtrl, _bgCtrl, _noteCtrl;
  final _eqBars = List.generate(16, (_) => 0.15);
  List<_FloatNote> _notes = [];
  final _rng = math.Random();

  List<Color> get _colors => audioHandler.currentSong?.category == MusicCategory.dj ? AppColors.catDJ : AppColors.catPop;

  @override
  void initState() {
    super.initState();
    _posSub = audioHandler.player.positionStream.listen((p) { if (mounted) { _pos = p; setState(() {}); } });
    audioHandler.player.durationStream.listen((d) { if (mounted) _dur = d ?? Duration.zero; });
    _sleepUi = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted && audioHandler.sleepActive) setState(() {}); });
    _eqCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..addListener(_eqUpdate)..repeat(reverse: true);
    _rotCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
    _noteCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 20))..addListener(_noteUpdate)..repeat();
    _notes = List.generate(10, (_) => _mkNote());
  }

  void _eqUpdate() {
    final r = math.Random(DateTime.now().millisecondsSinceEpoch ~/ 50);
    final p = audioHandler.player.playing;
    final dj = audioHandler.currentSong?.category == MusicCategory.dj;
    for (int i = 0; i < _eqBars.length; i++) {
      _eqBars[i] = ((p ? 0.4 : 0.05) + r.nextDouble() * (dj ? 0.6 : 0.4)).clamp(0.0, 1.0);
    }
    if (mounted) setState(() {});
  }

  void _noteUpdate() {
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _notes.length; i++) {
        _notes[i].y -= _notes[i].speed;
        _notes[i].x += math.sin(_notes[i].y * 0.02) * 0.3;
        if (_notes[i].y < -40) {
          _notes[i] = _mkNote();
          _notes[i].y = 800 + _rng.nextDouble() * 100;
        }
      }
    });
  }

  _FloatNote _mkNote() => _FloatNote(
    _rng.nextDouble() * 400, _rng.nextDouble() * 700 - 100,
    16 + _rng.nextDouble() * 18, 0.15 + _rng.nextDouble() * 0.3,
    0.05 + _rng.nextDouble() * 0.12, _rng.nextDouble() * math.pi * 2,
    _rng.nextInt(3),
  );

  @override
  void dispose() {
    _posSub?.cancel(); _sleepUi?.cancel(); _lrcScroll.dispose();
    _eqCtrl.dispose(); _rotCtrl.dispose(); _bgCtrl.dispose(); _noteCtrl.dispose();
    super.dispose();
  }

  String _fmt(Duration d) => '${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  void _scrollLrc(int cur, List<LyricLine> lrc) {
    if (!_lrcAuto || cur < 0 || _lastLrcIdx == cur) return;
    _lastLrcIdx = cur;
    final off = (cur * 58.0) - (MediaQuery.of(context).size.height * 0.1) + 50;
    if (_lrcScroll.hasClients) _lrcScroll.animateTo(off.clamp(0.0, _lrcScroll.position.maxScrollExtent), duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final s = audioHandler.currentSong;
    final dj = s?.category == MusicCategory.dj;
    final colors = _colors;
    final lrc = audioHandler.lyrics;
    final lrcI = audioHandler.lyricIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _scrollLrc(lrcI, lrc); });

    return Scaffold(
      body: AnimatedBuilder(animation: _bgCtrl, builder: (_, __) {
        final t = _bgCtrl.value;
        final c1 = Color.lerp(colors[0], colors[1], t)!;
        final c2 = Color.lerp(colors[1], colors[2], t)!;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topRight, radius: 1.5,
              colors: [c1.withValues(alpha: 0.25), c2.withValues(alpha: 0.1), AppColors.bg, AppColors.bg],
            ),
          ),
          child: Stack(children: [
            // 浮动音符
            Positioned.fill(child: IgnorePointer(child: CustomPaint(
              painter: _NotePainter(_notes, audioHandler.player.playing, colors),
              size: Size.infinite,
            ))),
            SafeArea(
              child: Column(children: [
                _top(dj, colors),
                Expanded(child: _showLyrics && lrc.isNotEmpty ? _lrcView(lrc, lrcI, dj, colors) : _albumArt(dj, colors, c1, c2)),
                _info(s, dj, colors),
                _progress(dj, colors),
                _ctrls(dj, colors),
                _bottom(dj, colors),
                const SizedBox(height: 8),
              ]),
            ),
          ]),
        );
      }),
    );
  }

  Widget _top(bool dj, List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textPrimary, size: 30), onPressed: () => Navigator.pop(context)),
        const Spacer(),
        if (audioHandler.sleepActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [colors[0].withValues(alpha: 0.15), colors[1].withValues(alpha: 0.08)]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors[0].withValues(alpha: 0.25)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bedtime_rounded, color: colors[0], size: 13),
              const SizedBox(width: 4),
              Text(audioHandler.sleepTimerLabel, style: TextStyle(color: colors[0], fontSize: 11)),
            ]),
          ),
        const SizedBox(width: 8),
        Text('${audioHandler.currentIndex + 1}/${audioHandler.songQueue.length}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(width: 40),
      ]),
    );
  }

  Widget _albumArt(bool dj, List<Color> colors, Color c1, Color c2) {
    final playing = audioHandler.player.playing;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      // 大唱片
      AnimatedBuilder(animation: _rotCtrl, builder: (_, __) {
        final angle = playing ? _rotCtrl.value * math.pi * 2 : 0.0;
        return Transform.rotate(angle: angle, child: Container(
          width: 220, height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [
              BoxShadow(color: c1.withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 8),
              BoxShadow(color: c2.withValues(alpha: 0.2), blurRadius: 60, spreadRadius: 15),
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30, spreadRadius: 5),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.bg.withValues(alpha: 0.3)),
            child: Center(child: Text('🦊', style: TextStyle(fontSize: 85))),
          ),
        ));
      }),
      const SizedBox(height: 20),
      // EQ bars
      SizedBox(height: 42, child: Row(mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_eqBars.length, (i) => Container(
          width: 3, height: (_eqBars[i] * 36 + 5).clamp(0.0, 50.0),
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [
              Color.lerp(colors[i % 3], colors[(i + 1) % 3], i / _eqBars.length)!,
              Color.lerp(colors[i % 3], colors[(i + 1) % 3], i / _eqBars.length)!.withValues(alpha: 0.1),
            ]),
          ),
        )),
      )),
    ]));
  }

  Widget _lrcView(List<LyricLine> lrc, int cur, bool dj, List<Color> colors) {
    return Column(children: [
      const Spacer(flex: 1),
      Expanded(flex: 8, child: ListView.builder(
        controller: _lrcScroll,
        padding: EdgeInsets.symmetric(vertical: MediaQuery.of(context).size.height * 0.15),
        itemCount: lrc.length,
        itemBuilder: (_, i) {
          final isCur = i == cur;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 5),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                color: isCur ? colors[0] : AppColors.textSecondary.withValues(alpha: 0.15),
                fontSize: isCur ? 21 : 14,
                fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
              child: Text(lrc[i].text),
            ),
          );
        },
      )),
      const Spacer(flex: 1),
    ]);
  }

  Widget _info(Song? s, bool dj, List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
      child: Column(children: [
        ShaderMask(
          shaderCallback: (b) => LinearGradient(colors: [colors[0], colors[2]]).createShader(b),
          child: Text(s?.title ?? '未选择',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        ),
        if (s?.artist != null && s!.artist.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(s.artist, style: const TextStyle(color: AppColors.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _tag(audioHandler.eqPresetLabel, colors[0]),
          const SizedBox(width: 8),
          _tag(audioHandler.speedLabel, colors[1]),
          const SizedBox(width: 8),
          _tag(audioHandler.playModeLabel, colors[2]),
        ]),
      ]),
    );
  }

  Widget _tag(String l, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withValues(alpha: 0.15))),
    child: Text(l, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
  );

  Widget _progress(bool dj, List<Color> colors) {
    final v = _dur.inMilliseconds > 0 ? _pos.inMilliseconds / _dur.inMilliseconds : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(children: [
        GestureDetector(
          onTapDown: (d) {
            final np = (d.localPosition.dx / (MediaQuery.of(context).size.width - 64) * _dur.inMilliseconds).round();
            audioHandler.seek(Duration(milliseconds: np));
          },
          child: Container(
            height: 5,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: AppColors.textMuted.withValues(alpha: 0.15)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(colors: [colors[0], colors[2]]),
                  boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1)],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(_fmt(_pos), style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            Text(_fmt(_dur), style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  Widget _ctrls(bool dj, List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _ctrlBtn(Icons.repeat_rounded, 22, colors[0], () => _showModePicker()),
        _ctrlBtn(Icons.skip_previous_rounded, 30, colors[0], () => audioHandler.skipToPrevious()),
        StreamBuilder<bool>(
          stream: audioHandler.player.playingStream,
          builder: (_, snap) {
            final p = snap.data == true;
            return Container(
              width: 70, height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [colors[0], colors[2]], begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: [
                  BoxShadow(color: colors[0].withValues(alpha: 0.4), blurRadius: 28, spreadRadius: 4),
                  BoxShadow(color: colors[2].withValues(alpha: 0.2), blurRadius: 40, spreadRadius: 8),
                ],
              ),
              child: IconButton(
                icon: Icon(p ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 38),
                onPressed: audioHandler.togglePlay,
              ),
            );
          },
        ),
        _ctrlBtn(Icons.skip_next_rounded, 30, colors[0], () => audioHandler.skipToNext()),
        _ctrlBtn(Icons.shuffle_rounded, 22, colors[0], () { audioHandler.cyclePlayMode(); setState(() {}); }),
      ]),
    );
  }

  Widget _ctrlBtn(IconData icon, double size, Color c, VoidCallback onTap) {
    return Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(color: c.withValues(alpha: 0.15)),
      ),
      child: IconButton(icon: Icon(icon, color: AppColors.textPrimary.withValues(alpha: 0.85), size: size), onPressed: onTap, padding: EdgeInsets.zero),
    );
  }

  void _showModePicker() {
    showModalBottomSheet(context: context, backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
        const Text('播放模式', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        ...PlayMode.values.map((pm) {
          final labels = ['顺序播放', '单曲循环', '列表循环', '随机播放'];
          final sel = audioHandler.playMode == pm;
          return ListTile(
            leading: Text(['→', '🔂', '🔁', '🔀'][pm.index], style: const TextStyle(fontSize: 20)),
            title: Text(labels[pm.index], style: TextStyle(color: sel ? AppColors.orange : AppColors.textPrimary, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
            trailing: sel ? const Icon(Icons.check_rounded, color: AppColors.orange) : null,
            onTap: () { while (audioHandler.playMode != pm) audioHandler.cyclePlayMode(); Navigator.pop(ctx); setState(() {}); },
          );
        }),
      ]))),
    );
  }

  Widget _bottom(bool dj, List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _chip(Icons.lyrics_rounded, '歌词', _showLyrics, colors[0], () => setState(() => _showLyrics = !_showLyrics)),
          _chip(Icons.equalizer_rounded, audioHandler.eqPresetLabel, audioHandler.eqPreset != EqPreset.flat, colors[0], () { audioHandler.cycleEqPreset(); setState(() {}); }),
          _chip(Icons.speed_rounded, audioHandler.speedLabel, audioHandler.speed != 1.0, colors[0], () { audioHandler.cycleSpeed(); setState(() {}); }),
          _chip(audioHandler.sleepActive ? Icons.bedtime_rounded : Icons.bedtime_outlined, audioHandler.sleepTimerLabel, audioHandler.sleepActive, colors[0], () { audioHandler.cycleSleepTimer(); setState(() {}); }),
        ]),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _off('←0.2s', () { audioHandler.adjustLyricOffset(-200); setState(() {}); }),
            const SizedBox(width: 4),
            _off('←0.1s', () { audioHandler.adjustLyricOffset(-100); setState(() {}); }),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                gradient: audioHandler.lyricOffset == 0 ? null : LinearGradient(colors: [colors[0], colors[2]]),
                color: audioHandler.lyricOffset == 0 ? AppColors.glass : null,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: audioHandler.lyricOffset == 0 ? AppColors.glassBorder : colors[0].withValues(alpha: 0.5)),
              ),
              child: Text(audioHandler.lyricOffsetLabel,
                style: TextStyle(color: audioHandler.lyricOffset == 0 ? AppColors.textMuted : Colors.white, fontSize: 11, fontWeight: audioHandler.lyricOffset == 0 ? FontWeight.normal : FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            _off('+0.1s→', () { audioHandler.adjustLyricOffset(100); setState(() {}); }),
            const SizedBox(width: 4),
            _off('+0.2s→', () { audioHandler.adjustLyricOffset(200); setState(() {}); }),
            const SizedBox(width: 4),
            _offIcon(Icons.vertical_align_center_rounded, _lrcAuto ? AppColors.accent : null, () => setState(() => _lrcAuto = !_lrcAuto)),
            if (audioHandler.lyricOffset != 0) ...[
              const SizedBox(width: 4),
              _offIcon(Icons.refresh_rounded, AppColors.red, () { audioHandler.resetLyricOffset(); setState(() {}); }),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _off(String l, VoidCallback t) => GestureDetector(onTap: t, child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: AppColors.glass, borderRadius: BorderRadius.circular(8)),
    child: Text(l, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
  ));

  Widget _offIcon(IconData i, Color? c, VoidCallback t) => GestureDetector(onTap: t, child: Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(color: c?.withValues(alpha: 0.12) ?? AppColors.glass, borderRadius: BorderRadius.circular(8)),
    child: Icon(i, color: c ?? AppColors.textMuted, size: 14),
  ));

  Widget _chip(IconData i, String l, bool a, Color c, VoidCallback t) {
    return GestureDetector(
      onTap: t,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: a ? c.withValues(alpha: 0.12) : AppColors.glass,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: a ? c.withValues(alpha: 0.4) : AppColors.glassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, color: a ? c : AppColors.textMuted, size: 14),
          const SizedBox(width: 3),
          Text(l, style: TextStyle(color: a ? c : AppColors.textMuted, fontSize: 11, fontWeight: a ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }
}

class _NotePainter extends CustomPainter {
  final List<_FloatNote> notes; final bool playing; final List<Color> colors;
  _NotePainter(this.notes, this.playing, this.colors);
  @override
  void paint(Canvas canvas, Size size) {
    if (!playing) return;
    for (final n in notes) {
      canvas.save();
      canvas.translate(n.x, n.y);
      canvas.rotate(n.rot);
      final tp = TextPainter(
        text: TextSpan(text: ['♪', '♫', '♩'][n.type], style: TextStyle(
          color: Color.lerp(colors[n.type % colors.length], colors[(n.type + 1) % colors.length], 0.5)!.withValues(alpha: n.opacity),
          fontSize: n.size, fontWeight: FontWeight.w100)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }
  @override
  bool shouldRepaint(covariant _NotePainter o) => true;
}

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';
import '../services/lyric_parser.dart';
import '../main.dart' show audioHandler;

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

  @override
  void initState() {
    super.initState();
    _posSub = audioHandler.player.positionStream.listen((p) {
      if (mounted) { _pos = p; audioHandler.updateLyricPosition(p); setState(() {}); }
    });
    audioHandler.player.durationStream.listen((d) { if (mounted) _dur = d ?? Duration.zero; });
    _sleepUi = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted && audioHandler.sleepActive) setState(() {}); });
    _eqCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..addListener(_eq)..repeat(reverse: true);
  }

  void _eq() {
    final r = Random(DateTime.now().millisecondsSinceEpoch ~/ 50);
    final p = audioHandler.player.playing;
    final dj = audioHandler.currentSong?.category == MusicCategory.dj;
    final eq = audioHandler.eqPreset;
    for (int i = 0; i < _eqBars.length; i++) {
      var a = (p ? 0.25 : 0.05) + r.nextDouble() * (dj ? 0.55 : 0.3);
      if (eq == EqPreset.djBass || eq == EqPreset.heavyBass) { if (i < 5) a *= 1.6; }
      _eqBars[i] = a.clamp(0.0,1.0);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() { _posSub?.cancel(); _sleepUi?.cancel(); _eqCtrl.dispose(); super.dispose(); }

  String _fmt(Duration d) => '${d.inMinutes.remainder(60).toString().padLeft(2,'0')}:${d.inSeconds.remainder(60).toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    final s = audioHandler.currentSong;
    final dj = s?.category == MusicCategory.dj;
    final lrc = audioHandler.lyrics;
    final lrcI = audioHandler.lyricIndex;

    return Scaffold(body: Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: dj ? [const Color(0xFF2D1B00), const Color(0xFF0F0F1A)] : [const Color(0xFF0D1B3E), const Color(0xFF0F0F1A)])),
      child: SafeArea(child: Column(children: [
        _top(dj),
        Expanded(child: _showLyrics && lrc.isNotEmpty ? _lrcView(lrc, lrcI, dj) : _cover(dj)),
        _info(s, dj),
        _progress(dj),
        _ctrls(dj),
        _bottom(dj, lrc),
        const SizedBox(height: 8),
      ])),
    ));
  }

  Widget _top(bool dj) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Row(children: [
    IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 32), onPressed: () => Navigator.pop(context)),
    const Spacer(),
    if (audioHandler.sleepActive) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.pink.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.bedtime_rounded, color: Colors.pink, size: 14), const SizedBox(width: 4), Text(audioHandler.sleepTimerLabel, style: const TextStyle(color: Colors.pink, fontSize: 12))])),
    const SizedBox(width: 8),
    Text('${audioHandler.currentIndex+1}/${audioHandler.songQueue.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
    const SizedBox(width: 48),
  ]));

  Widget _cover(bool dj) => Center(child: StreamBuilder<bool>(stream: audioHandler.player.playingStream, builder: (_, snap) {
    final p = snap.data == true;
    return TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: p ? 2*pi : 0), duration: const Duration(seconds: 25), builder: (_, v, c) => Transform.rotate(angle: v, child: c), child: Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: dj ? [Colors.orange.shade600, Colors.red.shade500, Colors.purple] : [Colors.blue.shade600, Colors.pink.shade400, Colors.purple]), boxShadow: [BoxShadow(color: (dj ? Colors.orange : Colors.blue).withValues(alpha: 0.35), blurRadius: 50, spreadRadius: 8)]), child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 70)));
  }));

  Widget _lrcView(List<LyricLine> lrc, int cur, bool dj) => Column(children: [
    SizedBox(height: 70, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(_eqBars.length, (i) => Container(width: 4, height: _eqBars[i]*60, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color.lerp(dj?Colors.orange:Colors.pink, dj?Colors.yellow:Colors.blue, i/(_eqBars.length-1))!, Color.lerp(dj?Colors.orange:Colors.pink, dj?Colors.yellow:Colors.blue, i/(_eqBars.length-1))!.withValues(alpha: 0.3)]))))))),
    const SizedBox(height: 8),
    Expanded(child: ListView.builder(padding: EdgeInsets.symmetric(vertical: MediaQuery.of(context).size.height*0.12), itemCount: lrc.length, itemBuilder: (_, i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 7), child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 250), style: TextStyle(color: i==cur ? (dj?Colors.orange:Colors.pink) : Colors.white.withValues(alpha: 0.25), fontSize: i==cur ? 21 : 15, fontWeight: i==cur ? FontWeight.bold : FontWeight.normal, height: 1.6), textAlign: TextAlign.center, child: Text(lrc[i].text))))),
  ]);

  Widget _info(Song? s, bool dj) => Padding(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6), child: Column(children: [
    Text(s?.title??'未选择', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
    const SizedBox(height: 4),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(audioHandler.eqPresetLabel, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
      const SizedBox(width: 8),
      Text(audioHandler.speedLabel, style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11)),
      const SizedBox(width: 8),
      Text(audioHandler.playModeLabel, style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11)),
    ]),
  ]));

  Widget _progress(bool dj) {
    final v = _dur.inMilliseconds>0 ? _pos.inMilliseconds/_dur.inMilliseconds : 0.0;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Column(children: [
      SliderTheme(data: SliderThemeData(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7), overlayShape: const RoundSliderOverlayShape(overlayRadius: 14), activeTrackColor: dj?Colors.orange.shade400:Colors.pink.shade400, inactiveTrackColor: Colors.white24, thumbColor: Colors.white, overlayColor: (dj?Colors.orange:Colors.pink).withValues(alpha: 0.2)), child: Slider(value: v.clamp(0.0,1.0), onChanged: (x) => audioHandler.seek(Duration(milliseconds: (x*_dur.inMilliseconds).round())))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_fmt(_pos), style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
        Text(_fmt(_dur), style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
      ])),
    ]));
  }

  Widget _ctrls(bool dj) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    IconButton(icon: const Icon(Icons.repeat_rounded, color: Colors.white38, size: 24), onPressed: () { audioHandler.cyclePlayMode(); setState(() {}); }),
    IconButton(icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 38), onPressed: () => audioHandler.skipToPrevious()),
    StreamBuilder<bool>(stream: audioHandler.player.playingStream, builder: (_, snap) {
      final p = snap.data == true;
      return Container(width: 66, height: 66, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: dj?[Colors.orange,Colors.deepOrange]:[Colors.pink,Colors.purple]), boxShadow: [BoxShadow(color: (dj?Colors.orange:Colors.pink).withValues(alpha: 0.45), blurRadius: 24)]), child: IconButton(icon: Icon(p?Icons.pause_rounded:Icons.play_arrow_rounded, color: Colors.white, size: 36), onPressed: audioHandler.togglePlay));
    }),
    IconButton(icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 38), onPressed: () => audioHandler.skipToNext()),
    IconButton(icon: const Icon(Icons.shuffle_rounded, color: Colors.white38, size: 24), onPressed: () => audioHandler.skipToNext()),
  ]));

  Widget _bottom(bool dj, List<LyricLine> lrc) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    _chip(Icons.lyrics_rounded, '歌词', _showLyrics, () => setState(() => _showLyrics = !_showLyrics)),
    _chip(Icons.equalizer_rounded, audioHandler.eqPresetLabel, audioHandler.eqPreset != EqPreset.flat, () { audioHandler.cycleEqPreset(); setState(() {}); }),
    _chip(Icons.speed_rounded, audioHandler.speedLabel, audioHandler.speed != 1.0, () { audioHandler.cycleSpeed(); setState(() {}); }),
    _chip(audioHandler.sleepActive?Icons.bedtime_rounded:Icons.bedtime_outlined, audioHandler.sleepTimerLabel, audioHandler.sleepActive, () { audioHandler.cycleSleepTimer(); setState(() {}); }),
  ]));

  Widget _chip(IconData i, String l, bool a, VoidCallback t) => GestureDetector(onTap: t, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: a?Colors.pink.withValues(alpha: 0.15):Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(14), border: a?Border.all(color: Colors.pink.withValues(alpha: 0.4)):null), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, color: a?Colors.pink.shade300:Colors.white38, size: 15), const SizedBox(width: 3), Text(l, style: TextStyle(color: a?Colors.pink.shade200:Colors.white38, fontSize: 11))])));
}

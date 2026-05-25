import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';
import '../services/lyric_parser.dart';
import '../main.dart' show audioHandler, AppColors;

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
  }

  void _eq() {
    final r = math.Random(DateTime.now().millisecondsSinceEpoch ~/ 50);
    final p = audioHandler.player.playing;
    final dj = audioHandler.currentSong?.category == MusicCategory.dj;
    final eq = audioHandler.eqPreset;
    for (int i = 0; i < _eqBars.length; i++) {
      var a = (p ? 0.25 : 0.05) + r.nextDouble() * (dj ? 0.55 : 0.3);
      if ((eq == EqPreset.djBass || eq == EqPreset.heavyBass) && i < 5) a *= 1.6;
      _eqBars[i] = a.clamp(0.0, 1.0);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() { _posSub?.cancel(); _sleepUi?.cancel(); _eqCtrl.dispose(); _rotateCtrl.dispose(); super.dispose(); }

  String _fmt(Duration d) => '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = audioHandler.currentSong;
    final dj = s?.category == MusicCategory.dj;
    final lrc = audioHandler.lyrics;
    final lrcI = audioHandler.lyricIndex;

    return Scaffold(
      body: Stack(children: [
        // 背景阿狸图 + 模糊
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              image: const DecorationImage(
                image: AssetImage('assets/images/ali.jpg'),
                fit: BoxFit.cover,
                opacity: 0.12,
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [
                  (dj ? AppColors.foxOrange : AppColors.purple).withValues(alpha: 0.15),
                  AppColors.bg.withValues(alpha: 0.3),
                  AppColors.bg,
                ],
              ),
            ),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
        // 主内容
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
      ]),
    );
  }

  Widget _top(bool dj) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: [
        // 返回按钮
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textPrimary, size: 32),
          onPressed: () => Navigator.pop(context),
        ),
        const Spacer(),
        // 睡眠定时
        if (audioHandler.sleepActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.foxOrange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.foxOrange.withValues(alpha: 0.3)),
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
    return Center(
      child: StreamBuilder<bool>(
        stream: audioHandler.player.playingStream,
        builder: (_, snap) {
          final playing = snap.data == true;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 旋转唱片
              AnimatedBuilder(
                animation: _rotateCtrl,
                builder: (_, __) {
                  // 播放时才旋转，暂停停转
                  final angle = playing ? _rotateCtrl.value * math.pi * 2 : 0.0;
                  return Transform.rotate(
                    angle: angle,
                    child: Container(
                      width: 220, height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: const DecorationImage(
                          image: AssetImage('assets/images/ali.jpg'),
                          fit: BoxFit.cover,
                        ),
                        boxShadow: [
                          BoxShadow(color: (dj ? AppColors.glowOrange : AppColors.glowPurple), blurRadius: 40, spreadRadius: 8),
                          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 5),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: (dj ? AppColors.foxOrange : AppColors.purple).withValues(alpha: 0.5), width: 3),
                        ),
                        child: Center(
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (dj ? AppColors.foxOrange : AppColors.purple).withValues(alpha: 0.8),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8)],
                            ),
                            child: Icon(playing ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                              color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // EQ bars
              SizedBox(
                height: 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_eqBars.length, (i) => Container(
                    width: 3,
                    height: _eqBars[i] * 35 + 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter, end: Alignment.topCenter,
                        colors: [
                          Color.lerp(dj ? AppColors.foxOrange : AppColors.purple, dj ? AppColors.foxLight : Colors.pink, i / (_eqBars.length - 1))!,
                          Color.lerp(dj ? AppColors.foxOrange : AppColors.purple, dj ? AppColors.foxLight : Colors.pink, i / (_eqBars.length - 1))!.withValues(alpha: 0.2),
                        ],
                      ),
                    ),
                  )),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _lrcView(List<LyricLine> lrc, int cur, bool dj) {
    return Column(children: [
      const SizedBox(height: 8),
      // EQ bars
      SizedBox(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_eqBars.length, (i) => Container(
            width: 3,
            height: _eqBars[i] * 35 + 5,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [
                  Color.lerp(dj ? AppColors.foxOrange : AppColors.purple, dj ? AppColors.foxLight : Colors.pink, i / (_eqBars.length - 1))!,
                  Color.lerp(dj ? AppColors.foxOrange : AppColors.purple, dj ? AppColors.foxLight : Colors.pink, i / (_eqBars.length - 1))!.withValues(alpha: 0.2),
                ],
              ),
            ),
          )),
        ),
      ),
      const SizedBox(height: 16),
      // 歌词
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
                  color: isCur ? (dj ? AppColors.foxOrange : AppColors.purple) : AppColors.textSecondary.withValues(alpha: 0.3),
                  fontSize: isCur ? 20 : 14,
                  fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                  height: 1.5,
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
        Text(s?.title ?? '未选择',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
          maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        const SizedBox(height: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (dj ? AppColors.foxOrange : AppColors.purple).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: dj ? AppColors.foxOrange : AppColors.purple, fontWeight: FontWeight.w500)),
    );
  }

  Widget _progress(bool dj) {
    final v = _dur.inMilliseconds > 0 ? _pos.inMilliseconds / _dur.inMilliseconds : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(children: [
        // 自定义进度条
        GestureDetector(
          onTapDown: (d) => audioHandler.seek(Duration(milliseconds: (d.localPosition.dx / (MediaQuery.of(context).size.width - 64) * _dur.inMilliseconds).round())),
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: AppColors.textSecondary.withValues(alpha: 0.15),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: const LinearGradient(colors: [AppColors.foxOrange, AppColors.purple]),
                  boxShadow: [BoxShadow(color: AppColors.glowOrange, blurRadius: 4)],
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
        // 播放模式
        _ctrlBtn(Icons.repeat_rounded, 24, AppColors.textSecondary, () { audioHandler.cyclePlayMode(); setState(() {}); }),
        // 上一首
        _ctrlBtn(Icons.skip_previous_rounded, 36, AppColors.textPrimary, () => audioHandler.skipToPrevious()),
        // 播放/暂停
        StreamBuilder<bool>(
          stream: audioHandler.player.playingStream,
          builder: (_, snap) {
            final p = snap.data == true;
            return Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [AppColors.foxOrange, AppColors.purple]),
                boxShadow: [BoxShadow(color: (dj ? AppColors.glowOrange : AppColors.glowPurple), blurRadius: 24, spreadRadius: 4)],
              ),
              child: IconButton(
                icon: Icon(p ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 36),
                onPressed: audioHandler.togglePlay,
              ),
            );
          },
        ),
        // 下一首
        _ctrlBtn(Icons.skip_next_rounded, 36, AppColors.textPrimary, () => audioHandler.skipToNext()),
        // 随机
        _ctrlBtn(Icons.shuffle_rounded, 24, AppColors.textSecondary, () => audioHandler.skipToNext()),
      ]),
    );
  }

  Widget _ctrlBtn(IconData icon, double size, Color color, VoidCallback onTap) {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: AppColors.glass,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: size),
        onPressed: onTap,
        padding: EdgeInsets.zero,
      ),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: a ? AppColors.glowOrange.withValues(alpha: 0.15) : AppColors.glass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: a ? AppColors.foxOrange.withValues(alpha: 0.4) : AppColors.glassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, color: a ? AppColors.foxOrange : AppColors.textSecondary.withValues(alpha: 0.4), size: 15),
          const SizedBox(width: 3),
          Text(l, style: TextStyle(color: a ? AppColors.foxOrange : AppColors.textSecondary.withValues(alpha: 0.4), fontSize: 11)),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';
import 'screens/home_screen.dart';

late AudioPlayerHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 audio_service（通知栏 + MediaSession + 前台服务）
  // 超时或异常时降级为纯 just_audio
  try {
    audioHandler = await AudioService.init(
      builder: () => AudioPlayerHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.alee.music_player.audio',
        androidNotificationChannelName: '狸音乐',
      ),
    ).timeout(const Duration(seconds: 5));
  } catch (_) {
    audioHandler = AudioPlayerHandler();
  }

  // 请求忽略电池优化（原生 MethodChannel，静默失败）
  try { const MethodChannel('com.alee.music_player/service').invokeMethod('requestIgnoreBatteryOptimizations'); } catch (_) {}

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
  );
  runApp(const MusicPlayerApp());
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '狸音乐',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink, brightness: Brightness.dark),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      ),
      home: const HomeScreen(),
    );
  }
}

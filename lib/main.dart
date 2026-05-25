import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'services/audio_handler.dart';
import 'screens/home_screen.dart';

late AudioPlayerHandler audioHandler;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'music_player_channel',
      channelName: '狸音乐播放',
      channelDescription: '音乐播放后台服务',
      iconData: null,
    ),
    requestNotificationPermission: true,
  );
  audioHandler = AudioPlayerHandler();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
  );
  _requestBatteryOptimization();
  runApp(const MusicPlayerApp());
}

/// 请求忽略电池优化（防止后台被杀）
void _requestBatteryOptimization() {
  const channel = MethodChannel('com.alee.music_player/battery');
  channel.invokeMethod('requestIgnoreBatteryOptimizations');
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

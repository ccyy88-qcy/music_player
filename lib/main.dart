import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'services/audio_handler.dart';
import 'screens/home_screen.dart';

late AudioPlayerHandler audioHandler;
const _batteryChannel = MethodChannel('com.alee.music_player/battery');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 初始化前台服务框架
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'music_player_channel',
      channelName: '狸音乐播放',
      channelDescription: '后台音乐播放服务',
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
  );

  // 2. 请求忽略电池优化（静默失败不影响启动）
  _requestBatteryOptimization();

  // 3. 初始化音频引擎
  audioHandler = AudioPlayerHandler();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
  );

  runApp(const MusicPlayerApp());
}

/// 通过原生 MethodChannel 请求忽略电池优化
Future<void> _requestBatteryOptimization() async {
  try {
    // 先检查是否已忽略
    final isIgnoring = await _batteryChannel
        .invokeMethod<bool>('isIgnoringBatteryOptimizations')
        .then((v) => v ?? true);
    if (isIgnoring) return;

    // 未忽略则弹出系统设置页
    await _batteryChannel
        .invokeMethod('requestIgnoreBatteryOptimizations')
        .timeout(const Duration(seconds: 3));
  } catch (_) {
    // MethodChannel 未注册时静默忽略（首次安装或旧版本）
  }
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

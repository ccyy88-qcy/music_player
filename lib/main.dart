import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/audio_handler.dart';
import 'screens/home_screen.dart';

late AudioPlayerHandler audioHandler;
const _channel = MethodChannel('com.alee.music_player/service');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  audioHandler = AudioPlayerHandler();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
  );
  _requestBatteryOptimization();
  runApp(const MusicPlayerApp());
}

Future<void> _requestBatteryOptimization() async {
  try {
    final ok = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations').then((v) => v ?? true);
    if (!ok) await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  } catch (_) {}
}

void notifyForeground(String title, String artist, bool playing) {
  _channel.invokeMethod('updateNotification', {'title': title, 'artist': artist, 'playing': playing});
}

void stopForeground() {
  _channel.invokeMethod('stopForegroundService');
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

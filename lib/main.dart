import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/audio_handler.dart';
import 'screens/home_screen.dart';

late AudioPlayerHandler audioHandler;

// 狸音乐设计系统
class AppColors {
  static const foxOrange = Color(0xFFFF6B35);
  static const foxLight = Color(0xFFFF8C42);
  static const foxDark = Color(0xFFE85D2C);
  static const purple = Color(0xFFA855F7);
  static const purpleDark = Color(0xFF7C3AED);
  static const bg = Color(0xFF0A0A12);
  static const surface = Color(0xFF1A1A2E);
  static const surfaceLight = Color(0xFF252540);
  static const glass = Color(0x1AFFFFFF);
  static const glassBorder = Color(0x33FFFFFF);
  static const textPrimary = Color(0xFFF0F0F5);
  static const textSecondary = Color(0xFF9090A0);
  static const glowOrange = Color(0x66FF6B35);
  static const glowPurple = Color(0x66A855F7);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  audioHandler = AudioPlayerHandler();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
  );
  _requestBatteryOpt();
  runApp(const MusicPlayerApp());
}

void _requestBatteryOpt() {
  const MethodChannel('com.alee.music_player/service').invokeMethod('requestBattery');
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '狸音乐',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.foxOrange,
          secondary: AppColors.purple,
          surface: AppColors.surface,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: -0.5),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          bodyLarge: TextStyle(fontSize: 14, color: AppColors.textPrimary),
          bodyMedium: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.glassBorder)),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.glassBorder, space: 0, thickness: 0.5),
      ),
      home: const HomeScreen(),
    );
  }
}

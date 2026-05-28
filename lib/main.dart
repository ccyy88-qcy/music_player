import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/audio_handler.dart';
import 'screens/home_screen.dart';

late AudioPlayerHandler audioHandler;

class AppColors {
  // 主色
  static const orange = Color(0xFFFF6B35);
  static const orangeLight = Color(0xFFFF8C42);
  static const purple = Color(0xFFA855F7);
  static const purpleLight = Color(0xFFC084FC);
  static const pink = Color(0xFFEC4899);
  static const blue = Color(0xFF3B82F6);
  static const cyan = Color(0xFF06B6D4);
  static const green = Color(0xFF22C55E);
  static const yellow = Color(0xFFEAB308);
  static const red = Color(0xFFEF4444);

  // 背景
  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF121218);
  static const surfaceLight = Color(0xFF1A1A24);
  static const surfaceCard = Color(0xFF16161E);

  // 文字
  static const textPrimary = Color(0xFFF0F0F5);
  static const textSecondary = Color(0xFF88889A);
  static const textMuted = Color(0xFF555566);
  static const accent = Color(0xFFA855F7);
  static const primary = Color(0xFFFF6B35);
  static const primaryLight = Color(0xFFFF8C42);
  static const textTertiary = Color(0xFF555566);

  // 装饰
  static const glass = Color(0x0AFFFFFF);
  static const glassBorder = Color(0x15FFFFFF);
  static const divider = Color(0x12FFFFFF);

  // 分类色
  static const catDJ = [orange, red, yellow];
  static const catPop = [purple, pink, blue];
  static const catFav = [yellow, orange, pink];
  static const catOnline = [cyan, blue, purple];
}

// 辅助方法
Color _lerp(List<Color> colors, double t) {
  if (colors.isEmpty) return colors.first;
  if (t <= 0) return colors.first;
  if (t >= 1) return colors.last;
  final segment = (colors.length - 1) * t;
  final idx = segment.floor();
  final localT = segment - idx;
  return Color.lerp(colors[idx], colors[idx + 1], localT)!;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  audioHandler = AudioPlayerHandler();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0A0F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
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
          primary: AppColors.orange,
          secondary: AppColors.purple,
          surface: AppColors.surface,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5),
          headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          bodyLarge: TextStyle(fontSize: 14, color: AppColors.textPrimary),
          bodyMedium: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          bodySmall: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surfaceCard,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

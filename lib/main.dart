import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/audio_handler.dart';
import 'screens/home_screen.dart';

late AudioPlayerHandler audioHandler;

class AppColors {
  static const primary = Color(0xFFFF6B35);
  static const primaryLight = Color(0xFFFF8C42);
  static const accent = Color(0xFFA855F7);
  static const accentLight = Color(0xFFC084FC);
  static const bg = Color(0xFF0D0D14);
  static const surface = Color(0xFF16161F);
  static const surfaceLight = Color(0xFF1E1E2A);
  static const surfaceCard = Color(0xFF1A1A26);
  static const glass = Color(0x0DFFFFFF);
  static const glassBorder = Color(0x18FFFFFF);
  static const textPrimary = Color(0xFFEEEEF4);
  static const textSecondary = Color(0xFF88889A);
  static const textTertiary = Color(0xFF555566);
  static const glowPrimary = Color(0x40FF6B35);
  static const glowAccent = Color(0x30A855F7);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const divider = Color(0x1AFFFFFF);

  static const gradientPrimary = [primary, Color(0xFFE85D2C)];
  static const gradientAccent = [accent, Color(0xFF7C3AED)];
  static const gradientMix = [primary, accent];
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  audioHandler = AudioPlayerHandler();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0D14),
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
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.5),
          titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          bodyLarge: TextStyle(fontSize: 14, color: AppColors.textPrimary),
          bodyMedium: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          bodySmall: TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surfaceCard,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.glassBorder)),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.divider, space: 0, thickness: 0.5),
      ),
      home: const HomeScreen(),
    );
  }
}

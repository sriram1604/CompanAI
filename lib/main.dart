import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'dart:developer';
import 'config/feature_flags.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'overlay_main.dart';
import 'theme/app_theme.dart';

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        canvasColor: Colors.transparent,
        scaffoldBackgroundColor: Colors.transparent,
        cardColor: Colors.white,
        dialogTheme: const DialogThemeData(backgroundColor: Colors.transparent),
        primaryColor: const Color(0xFF4F46E5),
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF4F46E5),
          surface: Colors.white,
          onSurface: Color(0xFF1E293B),
          onPrimary: Colors.white,
        ),
      ),
      builder: (context, child) {
        return Container(color: Colors.transparent, child: child);
      },
      home: const OverlayApp(),
    ),
  );
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void Function(String task)? onOverlayTask;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (FeatureFlags.floatingOverlayEnabled) {
    FlutterOverlayWindow.overlayListener.listen((event) {
      log("Main app received from overlay: $event");
      if (event is String && event.trim().isNotEmpty) {
        if (onOverlayTask != null) {
          onOverlayTask!(event.trim());
        } else {
          log("Warning: overlay task received but no handler registered yet");
        }
      }
    });
  }

  final prefs = await SharedPreferences.getInstance();
  final themeStr = prefs.getString('themeMode');
  if (themeStr == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else {
    themeNotifier.value = ThemeMode.light;
  }

  final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

  runApp(PrivateAgentApp(onboardingCompleted: onboardingCompleted));
}

class PrivateAgentApp extends StatelessWidget {
  final bool onboardingCompleted;
  const PrivateAgentApp({super.key, required this.onboardingCompleted});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode currentMode, child) {
        return MaterialApp(
          title: 'CompanAI',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: onboardingCompleted
              ? const HomeScreen()
              : const OnboardingScreen(),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../services/app_store.dart';
import '../services/alert_count_service.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../screens/splash_screen.dart';
import '../screens/settings_screen.dart';
import 'aquatic_scene.dart';

class AquaWatchApp extends StatefulWidget {
  const AquaWatchApp({super.key, required this.store, required this.home});

  final AppStore store;
  final Widget home;

  static Future<void> changeMode(BuildContext context, bool simulation) =>
      context
          .findAncestorStateOfType<_AquaWatchAppState>()!
          .changeMode(simulation);

  @override
  State<AquaWatchApp> createState() => _AquaWatchAppState();
}

class _AquaWatchAppState extends State<AquaWatchApp> {
  late AppStore _store = widget.store;
  late Widget _home = widget.home;
  bool _changing = false;

  Future<void> changeMode(bool simulation) async {
    if (_changing || simulation == _store.simulation) return;
    _changing = true;
    final previous = _store;
    final next = AppStore(simulation: simulation);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('simulation_mode', simulation);
      await next.init();
      previous.stopReadings();
      NotificationService.instance.dispose();
      AlertCountService.instance.dispose();
      await SyncService.instance.restart(simMode: simulation);
      if (!mounted) {
        next.dispose();
        return;
      }
      setState(() {
        _store = next;
        _home = simulation ? const SettingsScreen() : const SplashScreen();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    } finally {
      _changing = false;
    }
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppStore>.value(
      key: ValueKey(_store.simulation),
      value: _store,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: AppAppearance.mode,
        builder: (context, mode, _) => MaterialApp(
          title: 'Liponhay AquaWatch',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          builder: (context, child) {
            final palette = AppTheme.of(context);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: palette.header,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
                systemNavigationBarColor: palette.surface,
                systemNavigationBarIconBrightness:
                    palette.brightness == Brightness.light
                        ? Brightness.dark
                        : Brightness.light,
              ),
              child: AquaticBackground(child: child ?? const SizedBox.shrink()),
            );
          },
          home: _home,
        ),
      ),
    );
  }
}

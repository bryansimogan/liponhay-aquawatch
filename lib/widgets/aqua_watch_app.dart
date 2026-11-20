import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/app_store.dart';
import 'aquatic_scene.dart';

class AquaWatchApp extends StatefulWidget {
  const AquaWatchApp({super.key, required this.store, required this.home});

  final AppStore store;
  final Widget home;

  @override
  State<AquaWatchApp> createState() => _AquaWatchAppState();
}

class _AquaWatchAppState extends State<AquaWatchApp> {
  late final AppStore _store = widget.store;
  late final Widget _home = widget.home;

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

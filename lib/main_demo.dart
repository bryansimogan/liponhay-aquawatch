import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'services/app_store.dart';
import 'widgets/aqua_watch_app.dart';

/// Offline presentation entry point. The live APK uses main.dart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initializeDateFormatting();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('simulation_mode', true);
  await AppAppearance.load();

  final store = AppStore(simulation: true);
  await store.init();
  runApp(AquaWatchApp(store: store, home: const DashboardScreen()));
}

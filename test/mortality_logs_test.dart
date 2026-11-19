import 'dart:convert';

import 'package:fish_farm_app/app_theme.dart';
import 'package:fish_farm_app/models/mortality_record.dart';
import 'package:fish_farm_app/models/mortality_analysis.dart';
import 'package:fish_farm_app/screens/mortality_screen.dart';
import 'package:fish_farm_app/services/app_store.dart';
import 'package:fish_farm_app/services/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'aqua_language': 'en'});
    await initializeDateFormatting();
  });

  testWidgets(
      'a saved missing-reading snapshot stays frozen when newer readings arrive',
      (tester) async {
    final reportedAt = DateTime.now();
    final analysis =
        MortalityAnalysis.evaluate([], eventAt: reportedAt, species: 'Tilapia');
    final record = MortalityRecord(
        id: 'missing-evidence',
        date: reportedAt.toIso8601String(),
        pondId: 'pond1',
        species: 'Tilapia',
        count: 2,
        possibleCause: '',
        timestamp: reportedAt.millisecondsSinceEpoch,
        analysis: analysis);
    SharedPreferences.setMockInitialValues({
      'aqua_language': 'en',
      'demo_mortality_pond1': jsonEncode([
        {'id': record.id, ...record.toMap()}
      ]),
    });
    final store = AppStore(simulation: true);
    addTearDown(store.dispose);
    addTearDown(() => appLang = 'tl');
    await store.init();
    store.stopReadings();
    store.simProblem('ph', critical: true);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: const MortalityScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 fish · Pond 1'));
    await tester.pumpAndSettle();
    expect(find.text('Insufficient Data to Determine Suspected Cause'),
        findsWidgets);
    expect(
        find.text(
            'No usable reading was found within 30 minutes of the recorded event.'),
        findsOneWidget);
    expect(find.textContaining('10.50'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'mortality form saves remarks, preserves evidence on edit, and confirms deletion',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(simulation: true);
    addTearDown(store.dispose);
    addTearDown(() => appLang = 'tl');
    await store.init();
    store.stopReadings();
    store.simProblem('o', critical: true);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: const MortalityScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '3');
    await tester.enterText(
        find.byType(TextField).at(1), 'Fish gasping at surface');
    await tester.tap(find.text('Save Record'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mortality-details')), findsOneWidget);
    expect(find.text('3 fish died'), findsOneWidget);
    expect(find.text('HOW WAS THIS CAUSE FOUND?'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
    expect(find.text('Fish gasping at surface'), findsWidgets);
    final prefs = await SharedPreferences.getInstance();
    final saved = (jsonDecode(prefs.getString('demo_mortality_pond1')!) as List)
        .single as Map;
    final original = MortalityRecord.fromMap(saved['id'] as String, saved);
    expect(original.count, 3);
    expect(original.analysis!.reading!.dissolvedOxygen, 1.2);
    expect(store.mortality.single.n, 3);
    store.lang = 'tl';
    await tester.pumpAndSettle();
    expect(find.text('PAANO NATUKOY ANG SANHI?'), findsOneWidget);
    expect(find.text('Fish gasping at surface'), findsWidgets);
    store.lang = 'en';
    await tester.pumpAndSettle();
    Navigator.of(
            tester.element(find.byKey(const ValueKey('mortality-details'))))
        .pop();
    await tester.pumpAndSettle();
    store.simAction('fixo');
    await tester.tap(find.byTooltip('Edit record'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '5');
    await tester.enterText(find.byType(TextField).at(1), 'Aerator checked');
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    final edited =
        (jsonDecode(prefs.getString('demo_mortality_pond1')!) as List).single
            as Map;
    expect(edited['count'], 5);
    expect(edited['notes'], 'Aerator checked');
    expect(edited['date'], saved['date']);
    expect(edited['timestamp'], saved['timestamp']);
    expect(edited['water_analysis'], saved['water_analysis']);
    expect(store.mortality.single.n, 5);
    await tester.tap(find.byTooltip('Delete record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.mortality.single.n, 5);
    await tester.tap(find.byTooltip('Delete record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(jsonDecode(prefs.getString('demo_mortality_pond1')!), isEmpty);
    expect(store.mortality, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

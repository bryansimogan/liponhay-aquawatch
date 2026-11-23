import 'package:fish_farm_app/app_theme.dart';
import 'package:fish_farm_app/models/incident.dart';
import 'package:fish_farm_app/models/mortality_record.dart';
import 'package:fish_farm_app/screens/manage_screen.dart';
import 'package:fish_farm_app/services/app_store.dart';
import 'package:fish_farm_app/services/firebase_service.dart';
import 'package:fish_farm_app/services/i18n.dart';
import 'package:fish_farm_app/widgets/stocking_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingStockingService extends FirebaseService {
  @override
  Future<void> saveStocking(String pondId, Stocking value) async =>
      throw StateError('Write rejected');
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'aqua_language': 'en'});
    await initializeDateFormatting();
  });

  test('a fresh live installation has no fabricated stock count', () async {
    final store = AppStore(simulation: false);
    addTearDown(store.dispose);
    await store.init();
    expect(store.stock.n, 0);
    expect(store.aliveCount, 0);
  });

  test('legacy demo stock and harvest never migrate into a fresh live store',
      () async {
    SharedPreferences.setMockInitialValues({
      'simulation_mode': true,
      'aqua_store_v1': '{"stock":{"n":1000,"area":250,"date":"2026-09-20"},'
          '"harv":[{"id":1,"t":1795050000000,"n":100,"kg":20}]}',
    });
    final store = AppStore(simulation: false);
    addTearDown(store.dispose);
    await store.init();
    expect(store.stock.n, 0);
    expect(store.harvest, isEmpty);
    expect(store.mortality, isEmpty);
  });

  test('a rejected live save preserves the last known stock', () async {
    final store = AppStore(simulation: false);
    addTearDown(store.dispose);
    await store.init();
    store.stock = const Stocking(n: 100, area: 50, date: '2026-11-19');
    await expectLater(
        store.saveStocking(const Stocking(n: 200, area: 75, date: '2026-11-19'),
            firebase: _FailingStockingService()),
        throwsStateError);
    expect(store.stock.n, 100);
    expect(store.stock.area, 50);
  });

  test('an old local mortality summary cannot deduct fish after upgrade',
      () async {
    SharedPreferences.setMockInitialValues({
      'aqua_store_live_v1':
          '{"stock":{"n":1000,"area":250,"date":"2026-11-20"},'
              '"mort":[{"n":7,"c":"Old sample","t":1795412888000}],'
              '"harv":[{"id":1,"t":1795412888000,"n":20,"kg":8.6}]}',
    });
    final store = AppStore(simulation: false);
    addTearDown(store.dispose);
    await store.init();
    expect(store.stock.n, 1000);
    expect(store.mortality, isEmpty);
    expect(store.aliveCount, 980);
  });

  testWidgets(
      'separate Stocking button saves inputs and recalculates alive fish',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(simulation: true);
    addTearDown(store.dispose);
    addTearDown(() => appLang = 'tl');
    await store.init();
    store.stopReadings();
    store.harvest.clear();
    store.replaceMortalityRecords('pond1', [
      MortalityRecord(
          id: 'one',
          date: '2026-11-19',
          pondId: 'pond1',
          species: 'Tilapia',
          count: 3,
          possibleCause: '',
          timestamp: 1795050000000)
    ]);
    final originalDate = store.stock.date;
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
            theme: AppTheme.darkTheme, home: const ManageScreen())));
    await tester.pumpAndSettle();
    expect(
        find.ancestor(
            of: find.text('Fingerlings alive'), matching: find.byType(InkWell)),
        findsNothing);
    await tester.ensureVisible(find.text('Stocking'));
    await tester.tap(find.text('Stocking'));
    await tester.pumpAndSettle();
    expect(find.byType(StockingSheet), findsOneWidget);
    expect(find.text('Fingerlings stocked'), findsOneWidget);
    expect(find.text('Pond area (m²)'), findsOneWidget);
    expect(find.text('Date stocked'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '500');
    await tester.enterText(find.byType(TextFormField).at(1), '250.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.stock.n, 500);
    expect(store.stock.area, 250.5);
    expect(store.stock.date, originalDate);
    expect(store.mortality.single.n, 3);
    expect(store.aliveCount, 497);
    expect(find.byType(StockingSheet), findsNothing);
    final restored = AppStore(simulation: true);
    addTearDown(restored.dispose);
    await restored.init();
    restored.stopReadings();
    expect(restored.stock.toMap(), store.stock.toMap());
    expect(restored.aliveCount, 497);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid pond area keeps the saved stock intact', (tester) async {
    final store = AppStore(simulation: true);
    addTearDown(store.dispose);
    addTearDown(() => appLang = 'tl');
    await store.init();
    store.stopReadings();
    final saved = store.stock.toMap();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: StockingSheet()))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a pond area greater than zero.'), findsOneWidget);
    expect(store.stock.toMap(), saved);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

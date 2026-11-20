import 'dart:async';
import 'dart:io';
import 'package:fish_farm_app/app_theme.dart';
import 'package:fish_farm_app/models/incident.dart';
import 'package:fish_farm_app/screens/reports_screen.dart';
import 'package:fish_farm_app/services/app_store.dart';
import 'package:fish_farm_app/services/i18n.dart';
import 'package:fish_farm_app/services/report_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppStore store;
  final start = DateTime(2026, 11, 20).millisecondsSinceEpoch;
  final end = DateTime(2026, 11, 21).millisecondsSinceEpoch;
  FarmReport capture() => FarmReport.capture(store,
      start: start,
      end: end,
      period: 'November 20, 2026',
      generatedAt: DateTime(2026, 11, 20, 14, 30));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appLang = 'en';
    store = AppStore(simulation: false);
    store.stock = const Stocking(n: 1000, area: 250.5, date: '2026-09-20');
  });
  tearDown(() {
    store.dispose();
    appLang = 'tl';
  });

  test('period boundaries, action timestamps and cycle totals match saved data',
      () {
    store.mortality.addAll([
      MortLog(n: 3, cause: 'Low dissolved oxygen', t: start),
      MortLog(n: 2, cause: 'High pH', t: end - 1),
      MortLog(n: 7, cause: 'Outside selected period', t: end),
    ]);
    store.harvest.addAll([
      HarvestRecord(id: 1, t: start, n: 20, kg: 10, price: 100),
      HarvestRecord(id: 2, t: start - 1, n: 30, kg: 15),
    ]);
    store.incidents.add(Incident(
        id: 1,
        p: 'o',
        title: 'Earlier incident',
        val: '2.5 mg/L',
        ts: start - 10000,
        rem: [
          IncidentRemark(t: start, action: 'Aerator started'),
          IncidentRemark(t: end, action: 'Outside action')
        ]));
    final report = capture();
    final overview = Map.fromEntries(
        report.sections.first.rows.map((r) => MapEntry(r[0], r[1])));
    expect(overview['Fish died'], '5');
    expect(overview['Harvested fish'], '20');
    expect(overview['Harvest value'], '₱1,000.00');
    expect(report.sections[1].rows, isEmpty);
    expect(report.sections[2].rows.single[1], 'Aerator started');
    expect(report.sections[3].rows.length, 2);
    expect(report.text, isNot(contains('Outside selected period')));
    expect(report.text, isNot(contains('Outside action')));
    final cycle = Map.fromEntries(
        report.sections.last.rows.map((r) => MapEntry(r[0], r[1])));
    expect(cycle['Fish remaining'], '938');
    expect(cycle['Total fish died'], '12');
    expect(cycle['Total harvested fish'], '50');
    // A print job holds the captured figures even when later readings arrive.
    store.mortality.clear();
    appLang = 'tl';
    expect(report.text, contains('Fish died | 5'));
    expect(report.text, contains('Aerator started'));
  });

  test('offline PDF renders currency, empty sections, long notes and many rows',
      () async {
    for (var n = 0; n < 130; n++) {
      store.mortality.add(MortLog(
          n: n % 3 + 1,
          cause: 'Suspected low dissolved oxygen · event ${n + 1}',
          snap: 'DO 2.61 mg/L · pH 7.98 · 29.8 °C',
          t: start + n * 60000));
    }
    store.harvest
        .add(HarvestRecord(id: 1, t: start, n: 100, kg: 45.5, price: 120));
    store.incidents.add(Incident(
        id: 1,
        p: 'o',
        title: 'Low dissolved oxygen',
        val: '2.61 mg/L',
        ts: start,
        st: 'resolved',
        actAt: start + 60000,
        closedAt: start + 660000,
        rem: [
          IncidentRemark(
              t: start + 60000,
              action: List.filled(80, 'Checked aerator and water circulation.')
                  .join(' '))
        ]));
    final bytes = await ReportService.buildPdf(capture());
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(10000));
    final qa = Platform.environment['AQUAWATCH_REPORT_QA'];
    if (qa != null) {
      await Directory(qa).create(recursive: true);
      await File('$qa/report-many.pdf').writeAsBytes(bytes);
    }
    store.mortality.clear();
    store.incidents.clear();
    store.harvest.clear();
    appLang = 'tl';
    final empty = await ReportService.buildPdf(capture());
    expect(String.fromCharCodes(empty.take(5)), '%PDF-');
    if (qa != null) await File('$qa/report-empty-tl.pdf').writeAsBytes(empty);
  });

  testWidgets('printer uses selected day/week/month and recovers after failure',
      (tester) async {
    tester.view.physicalSize = const Size(360, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final jobs = <FarmReport>[];
    Completer<bool>? pending;
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: ReportsScreen(
              printReport: (report) {
                jobs.add(report);
                pending = Completer<bool>();
                return pending!.future;
              },
            ))));
    await tester.pumpAndSettle();
    for (final mode in ['Day', 'Week', 'Month']) {
      await tester.tap(find.widgetWithText(ChoiceChip, mode));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Print report'));
      await tester.pump();
      final button = tester.widget<IconButton>(find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Print report'));
      expect(button.onPressed, isNull);
      if (mode == 'Month') {
        pending!.completeError(StateError('Printer unavailable'));
      } else {
        pending!.complete(false); // User cancels the Android dialog.
      }
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<IconButton>(find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Print report'))
              .onPressed,
          isNotNull);
    }
    expect(jobs.length, 3);
    expect(jobs[0].period, isNot(jobs[1].period));
    expect(jobs[1].period, isNot(jobs[2].period));
    expect(find.text('Unable to print the report. Please try again.'),
        findsOneWidget);
    expect(find.byTooltip('Copy report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

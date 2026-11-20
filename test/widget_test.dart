// Tests for the pieces that don't require a live Firebase app.
//
// The screens themselves construct FirebaseService, so they need
// Firebase.initializeApp() and are exercised by running the app instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fish_farm_app/app_theme.dart';
import 'package:fish_farm_app/models/alert_content.dart';
import 'package:fish_farm_app/models/alert_record.dart';
import 'package:fish_farm_app/models/app_notification.dart';
import 'package:fish_farm_app/models/gsm_config.dart';
import 'package:fish_farm_app/models/mortality_record.dart';
import 'package:fish_farm_app/models/sensor_data.dart';
import 'package:fish_farm_app/models/water_quality.dart';
import 'package:fish_farm_app/services/i18n.dart';
import 'package:fish_farm_app/services/offline_cache_service.dart';
import 'package:fish_farm_app/services/sync_service.dart';
import 'package:fish_farm_app/widgets/app_bottom_nav.dart';
import 'package:fish_farm_app/widgets/app_header.dart';
import 'package:fish_farm_app/widgets/expandable_notice.dart';
import 'package:fish_farm_app/widgets/reveal.dart';
import 'package:fish_farm_app/widgets/sync_status.dart';
import 'package:fish_farm_app/widgets/water_quality_status_chart.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: child),
    );

void main() {
  group('AquaWatch redesign', () {
    testWidgets(
        'water quality chart shows all three readings on a small screen',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final chart = WaterQualityStatusChart(
        ph: ParamReading.classify(WaterParam.ph, 7.24),
        temperature: ParamReading.classify(WaterParam.temperature, 34.4),
        oxygen: ParamReading.classify(WaterParam.dissolvedOxygen, 1.93),
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: chart),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('7.24'), findsOneWidget);
      expect(find.text('34.4'), findsOneWidget);
      expect(find.text('1.93'), findsOneWidget);
      expect(find.text('Critical'), findsOneWidget);
    });

    testWidgets('notice reveals its details without leaving the list',
        (tester) async {
      await tester.pumpWidget(_wrap(const ExpandableNotice(
        title: 'Low oxygen',
        timestamp: 'Nov 16, 9:00 AM',
        icon: Icons.warning_amber_rounded,
        accent: AppTheme.amber,
        unread: true,
        details: Text('Pond 1 · 2.24 mg/L'),
      )));
      expect(find.text('Pond 1 · 2.24 mg/L'), findsNothing);
      await tester.tap(find.text('Low oxygen'));
      await tester.pumpAndSettle();
      expect(find.text('Pond 1 · 2.24 mg/L'), findsOneWidget);
    });
  });

  group('offline cache', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('keeps the latest dashboard reading and requested history window',
        () async {
      final now = DateTime.now();
      final old = SensorData(
        ph: 7,
        temperature: 28,
        dissolvedOxygen: 6,
        timestamp: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      );
      final latest = SensorData(
        ph: 6.2,
        temperature: 29,
        dissolvedOxygen: 5.5,
        timestamp: now.millisecondsSinceEpoch,
      );

      await OfflineCacheService.saveCurrent('pond1', latest);
      await OfflineCacheService.saveHistory('pond1', [old, latest]);

      expect((await OfflineCacheService.current('pond1'))!.ph, 6.2);
      final today = await OfflineCacheService.history(
        'pond1',
        since: now.subtract(const Duration(hours: 24)),
      );
      expect(today.map((reading) => reading.timestamp), [latest.timestamp]);
    });

    test('keeps mortality records and alerts with their ids', () async {
      final mortality = MortalityRecord(
        id: 'mortality-1',
        date: '2026-10-04',
        pondId: 'pond1',
        species: 'Tilapia',
        count: 3,
        possibleCause: 'Low oxygen',
        timestamp: 1234567890000,
      );
      final alert = AlertRecord(
        id: 'alert-1',
        parameter: 'pH',
        value: 6.1,
        severity: 'warning',
        condition: 'Acidic',
        timestamp: 1234567890001,
        pondId: 'pond1',
      );

      await OfflineCacheService.saveMortality('pond1', [mortality]);
      await OfflineCacheService.saveAlerts([alert]);

      expect((await OfflineCacheService.mortality('pond1')).single.id,
          'mortality-1');
      expect((await OfflineCacheService.alerts()).single.id, 'alert-1');
    });
  });

  group('notification inbox', () {
    test('history and alert destinations survive local persistence', () {
      for (final type in AppNotificationType.values) {
        final original = AppNotification(
          id: 'item-${type.name}',
          type: type,
          title: 'Update',
          body: 'Pond 1',
          timestamp: 1234567890000,
        );
        final restored = AppNotification.fromMap(original.toMap());
        expect(restored.id, original.id);
        expect(restored.type, type);
        expect(restored.read, isFalse);
      }
    });

    test('a notification can be marked read without changing its route', () {
      const original = AppNotification(
        id: 'history-1',
        type: AppNotificationType.history,
        title: 'New history reading',
        body: 'Pond 1',
        timestamp: 1234567890000,
      );
      final read = original.copyWith(read: true);
      expect(read.read, isTrue);
      expect(read.type, AppNotificationType.history);
    });

    test('promo notification keeps its Settings route after persistence', () {
      const original = AppNotification(
        id: 'promo-2026-10-01-7-3-days-left',
        type: AppNotificationType.promo,
        title: 'SIM promo expires in 3 days',
        body: 'GIGA · Renew before expiry.',
        timestamp: 123,
      );

      final restored = AppNotification.fromMap(original.toMap());
      expect(restored.type, AppNotificationType.promo);
      expect(restored.title, original.title);
    });
  });

  group('animations', () {
    testWidgets('CountUpText lands on the target value', (tester) async {
      await tester.pumpWidget(_wrap(const CountUpText(23)));
      await tester.pumpAndSettle();
      expect(find.text('23'), findsOneWidget);
    });

    testWidgets('CountUpDecimal lands on the target value', (tester) async {
      await tester.pumpWidget(_wrap(const CountUpDecimal(7.24, decimals: 2)));
      await tester.pumpAndSettle();
      expect(find.text('7.24'), findsOneWidget);
    });

    testWidgets('Reveal shows its child after animating', (tester) async {
      await tester.pumpWidget(_wrap(const Reveal(child: Text('hello'))));
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('Reveal honours its stagger delay', (tester) async {
      await tester
          .pumpWidget(_wrap(const Reveal(delayMs: 200, child: Text('late'))));

      // Scope to the Opacity that Reveal itself wraps around the child —
      // MaterialApp and Scaffold contribute their own.
      final revealOpacity = find.ancestor(
        of: find.text('late'),
        matching: find.descendant(
          of: find.byType(Reveal),
          matching: find.byType(Opacity),
        ),
      );

      // Still fully transparent before the delay elapses.
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<Opacity>(revealOpacity).opacity, 0.0);

      // The stagger is a timer, so no frame is scheduled until it fires —
      // pumpAndSettle alone would return early. Advance past it first.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(revealOpacity).opacity, 1.0);
    });
  });

  group('water quality thresholds', () {
    test('pH is classified against the 6.5-8.5 safe range', () {
      expect(ParamReading.classify(WaterParam.ph, 7.2).level, 'safe');
      expect(ParamReading.classify(WaterParam.ph, 6.0).level, 'warning');
      expect(ParamReading.classify(WaterParam.ph, 9.0).level, 'warning');
      expect(ParamReading.classify(WaterParam.ph, 3.5).level, 'critical');
      expect(ParamReading.classify(WaterParam.ph, 10.5).level, 'critical');
    });

    test('temperature is classified against the 25-32C safe range', () {
      expect(ParamReading.classify(WaterParam.temperature, 28.0).level, 'safe');
      expect(
          ParamReading.classify(WaterParam.temperature, 23.0).level, 'warning');
      expect(
          ParamReading.classify(WaterParam.temperature, 34.0).level, 'warning');
      expect(ParamReading.classify(WaterParam.temperature, 18.0).level,
          'critical');
      expect(ParamReading.classify(WaterParam.temperature, 37.0).level,
          'critical');
    });

    test('dissolved oxygen is classified against the >5 mg/L safe range', () {
      expect(
          ParamReading.classify(WaterParam.dissolvedOxygen, 6.5).level, 'safe');
      expect(ParamReading.classify(WaterParam.dissolvedOxygen, 4.0).level,
          'warning');
      expect(ParamReading.classify(WaterParam.dissolvedOxygen, 1.5).level,
          'critical');
    });

    test('safe readings carry no advice, unsafe ones do', () {
      expect(ParamReading.classify(WaterParam.ph, 7.2).advice, isNull);
      expect(
          ParamReading.classify(WaterParam.ph, 5.0).advice, contains('lime'));
      expect(ParamReading.classify(WaterParam.dissolvedOxygen, 2.5).advice,
          contains('aerator'));
    });

    test('every mortality cause offers a next step', () {
      for (final cause in MortalityCause.options.where(
        (cause) => cause != MortalityCause.other,
      )) {
        expect(MortalityCause.adviceFor(cause), isNotEmpty);
      }
      expect(MortalityCause.adviceFor(MortalityCause.other), isEmpty);
    });

    test('mortality causes use Filipino labels and preserve an Other reason',
        () {
      expect(MortalityCause.options, contains('Mababang oxygen'));
      expect(MortalityCause.options, isNot(contains('Unknown / Other')));
      expect(MortalityCause.options, contains('Overfeeding'));
      expect(MortalityCause.options, contains('Dumi ng isda'));
      expect(
        MortalityCause.options,
        contains('Predator (hal. daga, ibon, atbp.)'),
      );
      expect(MortalityCause.options.last, 'Other');
      expect(
        MortalityCause.storedValue('Other', 'Nasira ang lambat'),
        'Other: Nasira ang lambat',
      );
      expect(
        MortalityCause.otherReasonFor('Other: Nasira ang lambat'),
        'Nasira ang lambat',
      );
      expect(
        MortalityCause.adviceFor('Other: Nasira ang lambat'),
        isEmpty,
      );
      expect(MortalityCause.isOther('Other: Nasira ang lambat'), isTrue);
      expect(MortalityCause.isOther('Overfeeding'), isFalse);
      expect(MortalityCause.displayName('Low oxygen'), 'Mababang oxygen');
    });
  });

  group('sync status', () {
    test('relativeLabel describes each elapsed span', () {
      final now = DateTime.now();
      expect(SyncService.relativeLabel(null), 'never');
      expect(SyncService.relativeLabel(now), 'just now');
      expect(
          SyncService.relativeLabel(now.subtract(const Duration(minutes: 12))),
          '12 mins ago');
      expect(
          SyncService.relativeLabel(now.subtract(const Duration(minutes: 1))),
          '1 min ago');
      expect(SyncService.relativeLabel(now.subtract(const Duration(hours: 3))),
          '3 hours ago');
      expect(SyncService.relativeLabel(now.subtract(const Duration(days: 2))),
          '2 days ago');
    });

    test('invalid device timestamps never invent a fresh sync', () {
      final sync = SyncService();
      for (final timestamp in [
        0,
        18827,
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch
      ]) {
        sync.markDeviceSeen(timestamp);
        expect(sync.lastSynced.value, isNull);
        expect(sync.online.value, isFalse);
      }
      sync.dispose();
    });

    test('a valid stale timestamp preserves its actual age', () {
      final sync = SyncService();
      sync.markDeviceSeen(DateTime.now()
          .subtract(const Duration(minutes: 12))
          .millisecondsSinceEpoch);
      expect(SyncService.relativeLabel(sync.lastSynced.value), '12 mins ago');
      expect(sync.online.value, isFalse);
      sync.dispose();
    });

    test('relativeLabel never prints an absurd age', () {
      final ancient = DateTime.fromMillisecondsSinceEpoch(0);
      expect(SyncService.relativeLabel(ancient), 'over a year ago');
      final future = DateTime.now().add(const Duration(minutes: 5));
      expect(SyncService.relativeLabel(future), 'just now');
    });

    testWidgets('pill requires both phone and controller for Online and Synced',
        (tester) async {
      // Both up.
      SyncService.instance.phoneOnline.value = true;
      SyncService.instance.online.value = true;
      await tester.pumpWidget(_wrap(const SyncPill()));
      await tester.pumpAndSettle();
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Synced'), findsOneWidget);

      // Phone fine, controller quiet: the second chip becomes the age of the
      // last reading, because "offline" would not say whose.
      SyncService.instance.online.value = false;
      SyncService.instance.lastSynced.value =
          DateTime.now().subtract(const Duration(minutes: 12));
      await tester.pumpAndSettle();
      expect(find.text('Online'), findsNothing);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Last sync 12 mins ago'), findsOneWidget);

      // Phone has no data or WiFi.
      SyncService.instance.phoneOnline.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
    });

    testWidgets('banner names which link dropped', (tester) async {
      SyncService.instance.phoneOnline.value = true;
      SyncService.instance.online.value = true;
      SyncService.instance.lastSynced.value =
          DateTime.now().subtract(const Duration(minutes: 12));

      await tester.pumpWidget(_wrap(const SyncBanner()));
      await tester.pumpAndSettle();
      expect(find.textContaining('LAST READING'), findsNothing);
      expect(find.textContaining('NO CONNECTION'), findsNothing);

      // Controller quiet — a trip to the pond.
      SyncService.instance.online.value = false;
      await tester.pumpAndSettle();
      expect(find.textContaining('CONTROLLER QUIET'), findsOneWidget);
      expect(find.textContaining('12 MINS AGO'), findsOneWidget);

      // Phone unreachable — load or WiFi, which the reader can fix.
      SyncService.instance.phoneOnline.value = false;
      await tester.pumpAndSettle();
      expect(find.textContaining('NO CONNECTION'), findsOneWidget);
      expect(find.textContaining('CONTROLLER QUIET'), findsNothing);
    });
  });

  group('chrome', () {
    testWidgets('header shows the brand and notification count',
        (tester) async {
      await tester.pumpWidget(_wrap(
        AppHeader(
          selectedPondId: 'pond1',
          onPondChanged: (_) {},
          notificationCount: 4,
        ),
      ));
      await tester.pumpAndSettle();

      // The header carries the farm name alone now; "AquaWatch" was a second
      // brand on top of it and has been dropped.
      expect(find.text('Liponhay Fish Farm'), findsOneWidget);
      expect(find.text('AquaWatch'), findsNothing);
      expect(find.text('4'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);
    });

    testWidgets('pond selector is hidden while there is only one pond',
        (tester) async {
      // The farm has one instrumented pond, so a picker would offer a single
      // option and do nothing. Adding a second Pond entry should bring it
      // back without any other change — that is what this pins down.
      expect(Pond.hasChoice, isFalse);

      await tester.pumpWidget(_wrap(
        AppHeader(
          selectedPondId: 'pond1',
          onPondChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pond 1 — Tilapia'), findsNothing);
    });

    test('an alert stamped before the clock was set has no known time', () {
      AlertRecord withStamp(int ms) => AlertRecord.fromMap('a1', {
            'parameter': 'pH',
            'value': 5.9,
            'severity': 'warning',
            'condition': 'Acidic',
            'timestamp': ms,
            'pond_id': 'pond1',
          });

      // What the controller writes before NTP lands, and what every record
      // written by the older firmware carries. Rendering these as a date puts
      // them in January 1970.
      expect(withStamp(0).hasKnownTime, isFalse);
      expect(withStamp(18827).hasKnownTime, isFalse);

      expect(
        withStamp(DateTime.now().millisecondsSinceEpoch).hasKnownTime,
        isTrue,
      );
    });

    testWidgets('bottom nav renders all six tabs', (tester) async {
      appLang = 'en';
      await tester.pumpWidget(_wrap(const AppBottomNav(currentIndex: 0)));
      await tester.pumpAndSettle();

      for (final label in [
        'Dashboard',
        'History',
        'Mortality',
        'Manage',
        'Alerts',
        'Settings',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    });

    testWidgets('selected Alerts tab uses the filled exclamation icon',
        (tester) async {
      appLang = 'en';
      // Alerts is now the 5th tab (index 4) after the new Manage tab.
      await tester.pumpWidget(_wrap(const AppBottomNav(currentIndex: 4)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    });
  });

  group('alert content', () {
    test('a safe reading has nothing to explain', () {
      final safe = ParamReading.classify(WaterParam.ph, 7.2);
      expect(AlertContent.forReading(safe), isNull);
    });

    test('a breach carries explanation, detailed actions, and follow-up', () {
      final low = ParamReading.classify(WaterParam.dissolvedOxygen, 1.5);
      final e = AlertContent.forReading(low)!;
      expect(e.emoji, '🚨'); // critical
      for (final part in [
        e.title,
        e.whatsHappening,
        e.why,
        e.consequence,
        e.whatToDo,
        e.recommendation,
      ]) {
        expect(part.trim(), isNotEmpty);
      }
      // The actual value is stated in the "what happened" line.
      expect(e.whatsHappening, contains('1.5'));
      expect(e.actionSteps.length, greaterThanOrEqualTo(3));
      expect(e.actionSteps.every((step) => step.trim().isNotEmpty), isTrue);
      expect(e.followUp.trim(), isNotEmpty);
    });

    test('every warning and critical direction has detailed steps', () {
      final readings = [
        ParamReading.classify(WaterParam.ph, 3.5),
        ParamReading.classify(WaterParam.ph, 6.0),
        ParamReading.classify(WaterParam.ph, 9.0),
        ParamReading.classify(WaterParam.ph, 10.5),
        ParamReading.classify(WaterParam.temperature, 19),
        ParamReading.classify(WaterParam.temperature, 24),
        ParamReading.classify(WaterParam.temperature, 33),
        ParamReading.classify(WaterParam.temperature, 36),
        ParamReading.classify(WaterParam.dissolvedOxygen, 4),
        ParamReading.classify(WaterParam.dissolvedOxygen, 1.5),
      ];

      for (final reading in readings) {
        final detail = AlertContent.forReading(reading)!;
        expect(detail.actionSteps.length, greaterThanOrEqualTo(3));
        expect(detail.followUp, isNotEmpty);
      }
    });

    test('pH low and pH high explain different problems', () {
      final acidic =
          AlertContent.forReading(ParamReading.classify(WaterParam.ph, 5.0))!;
      final alkaline =
          AlertContent.forReading(ParamReading.classify(WaterParam.ph, 9.5))!;
      expect(acidic.title.toLowerCase(), contains('acidic'));
      expect(alkaline.title.toLowerCase(), contains('alkaline'));
      expect(acidic.recommendation, isNot(alkaline.recommendation));
    });

    test('SMS text is human-readable, not just a code', () {
      final sms = AlertContent.smsText(
          ParamReading.classify(WaterParam.dissolvedOxygen, 1.5));
      expect(sms, contains('CRITICAL'));
      expect(sms, contains('Action:'));
      // Longer than the old "CRITICAL: DO LOW" one-liner.
      expect(sms.length, greaterThan(60));
    });
  });

  group('mortality period', () {
    MortalityRecord on(String date) => MortalityRecord(
          id: date,
          date: date,
          pondId: 'pond1',
          species: 'Tilapia',
          count: 3,
          possibleCause: 'Low oxygen',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

    test('year and month come from the incident date, not a bare name', () {
      final r = on('2026-09-18');
      expect(r.year, 2026);
      expect(r.month, 9);
    });

    test('the same month in different years is a separate period', () {
      expect(on('2026-09-01').inPeriod(2026, 9), isTrue);
      expect(on('2027-09-01').inPeriod(2026, 9), isFalse);
      expect(on('2026-09-01').inPeriod(2027, 9), isFalse);
    });
  });

  group('gsm promo expiry', () {
    test('no promo means no reminder', () {
      const g = GsmConfig();
      expect(g.isEmpty, isTrue);
      expect(g.daysLeft, isNull);
      expect(g.expiryStatus, 'none');
    });

    test('a name + duration starts the countdown from today', () {
      final g = GsmConfig.promo(name: 'GIGA Unli', days: 7);
      expect(g.promoName, 'GIGA Unli');
      expect(g.durationDays, 7);
      expect(g.daysLeft, 7);
      expect(g.expiryStatus, 'ok');
      expect(g.expiryLabel, contains('7 days'));
    });

    test('within three days is urgent-or-soon and worded that way', () {
      final soon = GsmConfig.promo(name: 'p', days: 3);
      expect(soon.expiryStatus, 'soon');

      final tomorrow = GsmConfig.promo(name: 'p', days: 1);
      expect(tomorrow.expiryStatus, 'urgent');
      expect(tomorrow.expiryLabel, contains('tomorrow'));
    });

    test('a promo whose days have run out reads as expired', () {
      // Started three days ago, ran one day → lapsed two days ago.
      final g = GsmConfig.promo(
        name: 'p',
        days: 1,
        start: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(g.expiryStatus, 'expired');
      expect(g.expiryLabel.toLowerCase(), contains('expired'));
    });
  });
}

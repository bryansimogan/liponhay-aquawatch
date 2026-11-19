import 'package:fish_farm_app/models/app_notification.dart';
import 'package:fish_farm_app/models/mortality_analysis.dart';
import 'package:fish_farm_app/models/mortality_record.dart';
import 'package:fish_farm_app/models/notification_copy.dart';
import 'package:fish_farm_app/models/sensor_data.dart';
import 'package:fish_farm_app/services/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final event = DateTime(2026, 11, 17, 10, 32);

  MortalityReading sample(Duration offset,
          {double? ph = 7,
          double? temp = 28,
          double? oxygen = 6,
          double? ammonia}) =>
      MortalityReading(
        ph: ph,
        temperature: temp,
        dissolvedOxygen: oxygen,
        ammoniaNh3: ammonia,
        timestamp: event.add(offset).millisecondsSinceEpoch,
      );

  MortalityAnalysis evaluate(List<MortalityReading> readings) =>
      MortalityAnalysis.evaluate(readings, eventAt: event, species: 'Tilapia');

  test('selects the closest sample at or before the actual event', () {
    final nearest = sample(const Duration(minutes: -2), oxygen: 1.5);
    final result = evaluate([
      sample(const Duration(minutes: -31), ph: 12),
      sample(const Duration(minutes: -18), ph: 9.2),
      sample(const Duration(seconds: 10), oxygen: 18),
      nearest,
    ]);

    expect(result.sampleCount, 3);
    expect(result.reading, nearest);
    expect(result.findings.single.factor, MortalityFactor.lowOxygen);
    expect(result.findings.single.criticalCount, 1);
    expect(result.findings.single.threshold, 5);
  });

  test('reports simultaneous high DO, measured ammonia, pH and temperature',
      () {
    final result = evaluate([
      sample(Duration.zero, ph: 9.2, temp: 36, oxygen: 10, ammonia: 0.13),
    ]);

    expect(
        result.findings.map((finding) => finding.factor),
        containsAll([
          MortalityFactor.highOxygen,
          MortalityFactor.highAmmonia,
          MortalityFactor.highPh,
          MortalityFactor.highTemperature,
        ]));
    expect(MortalityAnalysis.highOxygenLimit(30), closeTo(8.3, .1));
    expect(MortalityAnalysis.highOxygenLimit(10), greaterThan(10));
    expect(evaluate([sample(Duration.zero, temp: 28, oxygen: 8)]).findings,
        isEmpty);
  });

  test('handles distant, after-event, incomplete and normal readings', () {
    final distant = evaluate([sample(const Duration(minutes: -31), ph: 12)]);
    final after = evaluate([sample(const Duration(minutes: 1), oxygen: 1)]);
    final incomplete = evaluate([sample(Duration.zero, ph: null, temp: null)]);
    final abnormalPartial = evaluate([
      sample(Duration.zero, ph: null, temp: null, oxygen: 2),
    ]);
    final withinRange = evaluate([sample(Duration.zero)]);

    expect(distant.reading!.ph, 12);
    expect(distant.readingOutdated, isTrue);
    expect(distant.findings, isEmpty);
    expect(distant.insufficient, isTrue);
    expect(after.readingAfterEvent, isTrue);
    expect(after.insufficient, isTrue);
    expect(after.findings, isEmpty);
    expect(incomplete.insufficient, isTrue);
    expect(abnormalPartial.findings.single.factor, MortalityFactor.lowOxygen);
    expect(withinRange.insufficient, isFalse);
    expect(withinRange.findings, isEmpty);
  });

  test('accepts explicit measured NH3 without inferring it from TAN or pH', () {
    final row = {
      'timestamp': event.millisecondsSinceEpoch,
      'ph': 9.2,
      'temperature': 28,
      'dissolved_oxygen': 6,
      'ammonia': 10,
      'tan': 10,
    };
    final ambiguous = MortalityReading.fromMap(row)!;
    expect(ambiguous.ammoniaNh3, isNull);
    expect(
        evaluate([ambiguous]).findings.single.factor, MortalityFactor.highPh);

    row['ammonia_nh3_mg_l'] = 0.12;
    final explicit = SensorData.tryFromHistoryMap(row)!;
    expect(MortalityReading.fromSensor(explicit)!.ammoniaNh3, .12);
  });

  test('preserves saved event date and evidence and recognizes date-only logs',
      () {
    final analysis = evaluate([sample(Duration.zero, ph: 4.2, temp: 37)]);
    final record = MortalityRecord(
      id: 'one',
      date: '2026-11-17',
      pondId: 'pond1',
      species: 'Tilapia',
      count: 3,
      possibleCause: 'High temperature',
      timestamp: event.millisecondsSinceEpoch,
      analysis: analysis,
    );
    final saved = record.toMap();
    final restored = MortalityRecord.fromMap(record.id, saved);
    expect(restored.date, record.date);
    expect(restored.eventAt, event);
    expect(restored.count, 3);
    expect(restored.analysis!.usesEventMatch, isTrue);
    expect(restored.analysis!.reading!.ph, 4.2);
    expect(restored.analysis!.findings.first.factor,
        MortalityFactor.highTemperature);
    final earlierDate = MortalityRecord.fromMap(record.id, {
      ...saved,
      'date': '2026-11-15',
    });
    expect(earlierDate.date, '2026-11-15');
    expect(earlierDate.eventAt, isNull);
    saved.remove('water_analysis');
    saved.remove('timestamp');
    final legacy = MortalityRecord.fromMap(record.id, saved);
    expect(legacy.analysis, isNull);
    expect(legacy.eventAt, isNull);
  });

  test('localizes saved history and demo notes after switching language', () {
    final previous = appLang;
    addTearDown(() => appLang = previous);
    const history = AppNotification(
      id: 'history-1',
      type: AppNotificationType.history,
      title: 'New history reading',
      body: 'Pond 1 · pH 7.12, Temp 29.5 °C, DO 6.00 mg/L',
      timestamp: 1,
    );
    const demo = AppNotification(
      id: 'demo-1',
      type: AppNotificationType.history,
      title: 'Naresolba · na-verify na ligtas',
      body:
          '9.20 → 7.99. Na-verify matapos ang 10 minutong ligtas na readings.',
      timestamp: 1,
    );

    appLang = 'tl';
    expect(history.localizedTitle, 'Bagong reading sa kasaysayan');
    expect(history.localizedBody,
        contains('Palaisdaan 1 · pH 7.12, Temperatura 29.5'));
    appLang = 'en';
    expect(history.localizedTitle, history.title);
    expect(demo.localizedTitle, 'Resolved · verified safe');
    expect(demo.localizedBody, contains('Verified after 10 minutes'));
  });
}

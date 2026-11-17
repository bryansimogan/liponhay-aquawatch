import 'dart:async';

import 'package:fish_farm_app/models/sensor_data.dart';
import 'package:fish_farm_app/services/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('demo recovery restarts after a relapse and resolves at ten minutes',
      () async {
    final store = AppStore(
      simulation: true,
      clock: () => DateTime(2026, 11, 16, 9),
    );
    addTearDown(store.dispose);
    await store.init();

    store.simProblem('ph');
    final incident = store.openIncidents.single;
    expect(store.currentReading.ph, 9.2);
    expect(incident.isVerifying, isFalse);

    store.simAction('fixph');
    expect(store.currentReading.ph, 7.99);
    expect(incident.isVerifying, isTrue);
    expect(store.allSafe, isFalse);

    store.simAdvance(const Duration(minutes: 9, seconds: 59));
    expect(incident.isOpen, isTrue);
    store.simProblem('ph');
    expect(incident.safeSince, isNull);

    store.simAction('fixph');
    store.simAdvance(const Duration(minutes: 9, seconds: 59));
    expect(incident.isOpen, isTrue);
    store.simAdvance(const Duration(seconds: 1));
    expect(incident.st, 'resolved');
    expect(incident.closedAt! - incident.safeSince!, 600000);
    expect(store.allSafe, isTrue);
  });

  test('demo remains unsafe when its response window ends', () async {
    final store = AppStore(simulation: true);
    addTearDown(store.dispose);
    await store.init();

    store.simProblem('o', critical: true);
    final incident = store.openIncidents.single;
    store.simAdvance(const Duration(hours: 3));
    expect(incident.st, 'unresolved');
    expect(store.openIncidents, isEmpty);
    expect(store.allSafe, isFalse);
    store.simAdvance(const Duration(seconds: 2));
    expect(store.openIncidents, isEmpty);
  });

  test('live verification restarts after a missing-reading gap', () async {
    var now = DateTime(2026, 11, 16, 9);
    final readings = StreamController<SensorData?>(sync: true);
    addTearDown(readings.close);
    final store = AppStore(simulation: false, clock: () => now);
    addTearDown(store.dispose);
    await store.init();
    store.connectLive(readings: readings.stream);

    void sample(double ph, {int seconds = 0}) {
      now = now.add(Duration(seconds: seconds));
      readings.add(SensorData(
        ph: ph,
        temperature: 29,
        dissolvedOxygen: 6,
        timestamp: now.millisecondsSinceEpoch,
      ));
    }

    sample(9.2);
    final incident = store.openIncidents.single;
    sample(7.9, seconds: 1);
    final beforeGap = incident.safeSince;
    sample(7.9, seconds: 120);
    expect(incident.safeSince, isNot(beforeGap));

    for (var i = 0; i < 19; i++) {
      sample(7.9, seconds: 30);
    }
    sample(7.9, seconds: 29);
    expect(incident.isVerifying, isTrue);
    expect(store.allSafe, isFalse);
    sample(7.9, seconds: 1);
    expect(incident.st, 'resolved');
    expect(store.allSafe, isTrue);
  });
}

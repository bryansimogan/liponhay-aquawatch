import 'dart:async';

import 'package:fish_farm_app/models/management_logs.dart';
import 'package:fish_farm_app/models/incident.dart';
import 'package:fish_farm_app/models/mortality_record.dart';
import 'package:fish_farm_app/models/sensor_data.dart';
import 'package:fish_farm_app/services/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final start = DateTime(2026, 11, 19, 9).millisecondsSinceEpoch;
  SensorData sample(int seconds, {double ph = 7, double oxygen = 6}) =>
      SensorData(
          ph: ph,
          temperature: 28,
          dissolvedOxygen: oxygen,
          timestamp: start + seconds * 1000);

  test('deduplicates replayed samples and escalates the existing incident', () {
    final first = ManagementLogs().receive(sample(0, oxygen: 3));
    final original = first.incidents.single;
    final replay =
        ManagementLogs.fromMap(first.toMap()).receive(sample(0, oxygen: 3));
    expect(replay.incidents.length, 1);
    final critical = replay.receive(sample(30, oxygen: 1));
    expect(critical.incidents.single.id, original.id);
    expect(critical.incidents.single.ts, start);
    expect(critical.incidents.single.val, '3.00 mg/L');
    expect(critical.incidents.single.latestValue, 1);
    expect(critical.incidents.single.lvl, 'crit');
    expect(first.incidents.single.latestValue, 3);
  });

  test('recovery survives serialization and requires ten continuous minutes',
      () {
    var state = ManagementLogs().receive(sample(0, ph: 9.2));
    state = state.receive(sample(30));
    final since = state.incidents.single.safeSince;
    state = ManagementLogs.fromMap(state.toMap());
    for (var seconds = 60; seconds < 630; seconds += 30) {
      state = state.receive(sample(seconds));
      expect(state.incidents.single.isOpen, isTrue);
    }
    state = state.receive(sample(630));
    expect(state.incidents.single.st, 'resolved');
    expect(state.incidents.single.closedAt! - since!, 600000);
  });

  test('data gaps and a relapse restart verification', () {
    var state = ManagementLogs().receive(sample(0, ph: 9.2));
    state = state.receive(sample(30));
    state = state.receive(sample(150));
    expect(state.incidents.single.safeSince, start + 150000);
    state = state.receive(sample(180, ph: 9.2));
    expect(state.incidents.single.safeSince, isNull);
    state = state.receive(sample(210));
    expect(state.incidents.single.safeSince, start + 210000);
  });

  test('an overdue condition stays one incident through verified recovery', () {
    var state = ManagementLogs().receive(sample(0, oxygen: 1));
    final id = state.incidents.single.id;
    state = state.receive(sample(3600, oxygen: 1));
    expect(state.incidents.single.st, 'unresolved');
    state = state.receive(sample(3630, oxygen: 1));
    expect(state.incidents.length, 1);
    expect(state.incidents.single.latestAt, start + 3630000);
    state = state.receive(sample(3660));
    expect(state.incidents.single.isVerifying, isTrue);
    for (var seconds = 3690; seconds <= 4260; seconds += 30) {
      state = state.receive(sample(seconds));
    }
    expect(state.incidents.single.id, id);
    expect(state.incidents.single.st, 'resolved');
    state = state.receive(sample(4290, oxygen: 1));
    expect(state.incidents.length, 2);
    expect(state.incidents.where((i) => i.isOpen).length, 1);
  });

  test('keeps independent incidents and the latest unsafe direction', () {
    var state = ManagementLogs().receive(sample(0, ph: 9.2, oxygen: 1));
    expect(state.incidents.map((i) => i.p), unorderedEquals(['ph', 'o']));
    state = state.receive(sample(30, ph: 5.8));
    state = state.receive(sample(60));
    final ph = state.incidents.singleWhere((i) => i.p == 'ph');
    expect(ph.problemValue, 5.8);
    expect(ph.val, '9.20');
    expect(ph.isVerifying, isTrue);
  });

  test('mortality insert, edit, and deletion update the same farm totals',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(simulation: false);
    addTearDown(store.dispose);
    await store.init();
    MortalityRecord record(int count) => MortalityRecord(
        id: 'one',
        date: '2026-11-19',
        pondId: 'pond1',
        species: 'Tilapia',
        count: count,
        possibleCause: '',
        timestamp: start);
    store.stock = const Stocking(n: 1000, area: 250, date: '2026-11-19');
    final alive = store.aliveCount;
    store.replaceMortalityRecords('pond1', [record(3)]);
    expect(store.aliveCount, alive - 3);
    store.replaceMortalityRecords('pond1', [record(5)]);
    expect(store.aliveCount, alive - 5);
    store.replaceMortalityRecords('pond1', []);
    expect(store.aliveCount, alive);
  });

  test('unsafe readings and mortality from a previous batch do not lower stock',
      () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.fromMillisecondsSinceEpoch(start);
    final store = AppStore(simulation: false, clock: () => now);
    addTearDown(store.dispose);
    await store.init();
    store.stock = const Stocking(n: 1000, area: 250, date: '2026-11-19');
    // This was reported today, but the fish died before the current stocking.
    final old = MortalityRecord(
        id: 'old',
        date: '2026-11-18',
        pondId: 'pond1',
        species: 'Tilapia',
        count: 50,
        possibleCause: 'High pH',
        timestamp: start);
    store.replaceMortalityRecords('pond1', [old]);
    final readings = StreamController<SensorData?>(sync: true);
    store.connectLive(readings: readings.stream);
    readings.add(sample(0, ph: 10.5, oxygen: 1));
    expect(store.openIncidents, isNotEmpty);
    expect(store.mortality.single.n, 50);
    expect(store.cycleDeaths, 0);
    expect(store.aliveCount, 1000);
    await readings.close();
  });
}

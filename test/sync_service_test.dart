import 'dart:async';

import 'package:fish_farm_app/models/sensor_data.dart';
import 'package:fish_farm_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'connectivity checks tolerate a failure and recover independently',
      (tester) async {
    final link = StreamController<bool>(sync: true);
    final internet = StreamController<bool>(sync: true);
    final sync = SyncService();
    await sync.start(connections: link.stream, internetChecks: internet.stream);
    try {
      internet.add(true);
      link.add(true);
      internet.add(false);
      link.add(false);
      await tester.pump(const Duration(seconds: 2));
      expect(sync.phoneOnline.value, isTrue);
      expect(sync.serverOnline.value, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(sync.phoneOnline.value, isTrue);
      expect(sync.serverOnline.value, isFalse);
      internet.add(false);
      expect(sync.phoneOnline.value, isFalse);
      internet.add(true);
      link.add(true);
      expect(sync.phoneOnline.value, isTrue);
      expect(sync.serverOnline.value, isTrue);
      expect(sync.online.value, isFalse);
    } finally {
      sync.dispose();
      unawaited(link.close());
      unawaited(internet.close());
    }
  });

  testWidgets(
      'history can outrun current, retries recover, and stale data expires',
      (tester) async {
    var now = DateTime.utc(2026, 11, 23, 8, 30);
    SensorData sample({int age = 0, double ph = 7}) => SensorData(
        ph: ph,
        temperature: 29,
        dissolvedOxygen: 6,
        timestamp: now.subtract(Duration(seconds: age)).millisecondsSinceEpoch);
    final link = StreamController<bool>.broadcast(sync: true);
    final current = StreamController<SensorData?>.broadcast(sync: true);
    final history = StreamController<List<SensorData>>.broadcast(sync: true);
    var subscriptions = 0;
    final sync = SyncService(clock: () => now);
    await sync.start(
        connections: link.stream,
        currentReadings: () {
          subscriptions++;
          return current.stream;
        },
        historyReadings: () => history.stream);
    try {
      link.add(true);
      final old = sample(age: 3600);
      current.add(old);
      expect(sync.ageLabel.value, '1 hour ago');
      expect(sync.online.value, isFalse);
      final fresh = sample(age: 10, ph: 8.8);
      history.add([fresh]);
      expect(sync.latestReading.value, fresh);
      expect(sync.ageLabel.value, '10 s ago');
      expect(sync.online.value, isTrue);
      current.add(old);
      current.addError(StateError('Transient read failure'));
      expect(sync.online.value, isTrue);
      expect(sync.latestReading.value, fresh);
      await tester.pump(const Duration(seconds: 5));
      expect(subscriptions, 2);
      now = now.add(const Duration(seconds: 110));
      await tester.pump(const Duration(seconds: 1));
      expect(sync.online.value, isFalse);
      expect(sync.ageLabel.value, '2 mins ago');
      history.add([fresh]);
      expect(sync.online.value, isFalse);
      current.add(sample());
      expect(sync.online.value, isTrue);
      expect(sync.ageLabel.value, 'just now');
    } finally {
      sync.dispose();
      unawaited(link.close());
      unawaited(current.close());
      unawaited(history.close());
    }
  });

  testWidgets('server clock offset can validate a reading after it arrives',
      (tester) async {
    final now = DateTime.utc(2026, 11, 23);
    final link = StreamController<bool>.broadcast(sync: true);
    final clock = StreamController<Duration>.broadcast(sync: true);
    final current = StreamController<SensorData?>.broadcast(sync: true);
    final sync = SyncService(clock: () => now);
    await sync.start(
        connections: link.stream,
        serverTimeOffsets: clock.stream,
        currentReadings: () => current.stream);
    try {
      link.add(true);
      final timestamp =
          now.add(const Duration(hours: 1)).millisecondsSinceEpoch;
      current.add(SensorData(
          ph: 7, temperature: 29, dissolvedOxygen: 6, timestamp: timestamp));
      expect(sync.online.value, isFalse);
      expect(sync.lastSynced.value, isNull);
      clock.add(const Duration(hours: 1));
      expect(sync.online.value, isTrue);
      expect(sync.lastSynced.value!.millisecondsSinceEpoch, timestamp);
    } finally {
      sync.dispose();
      unawaited(link.close());
      unawaited(clock.close());
      unawaited(current.close());
    }
  });

  test('UTC seconds and history keys normalize to epoch milliseconds', () {
    final ms = DateTime.utc(2026, 11, 23, 8, 30).millisecondsSinceEpoch;
    final map = {'ph': 7.1, 'temperature': 29, 'dissolved_oxygen': 6.0};
    expect(
        SensorData.tryFromHistoryMap({...map, 'timestamp': '${ms ~/ 1000}'})
            ?.timestamp,
        ms);
    expect(
        SensorData.tryFromHistoryMap({...map, 'timestamp': 0}, key: '$ms')
            ?.timestamp,
        ms);
    expect(SensorData.tryFromHistoryMap({...map, 'timestamp': 18000}), isNull);
    expect(SensorData.tryFromHistoryMap({'ph': 7.2, 'timestamp': ms}), isNull);
  });
}

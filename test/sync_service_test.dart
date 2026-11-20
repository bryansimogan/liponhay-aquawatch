import 'dart:async';
import 'package:fish_farm_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late SyncService sync;
  late StreamController<bool> connection;
  late StreamController<bool> network;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 20, 14);
    sync = SyncService(clock: () => now);
    connection = StreamController<bool>(sync: true);
    network = StreamController<bool>(sync: true);
    await sync.start(
        connections: connection.stream, networkAvailability: network.stream);
  });
  tearDown(() async {
    sync.dispose();
    await connection.close();
    await network.close();
  });
  void connect() {
    network.add(true);
    connection.add(true);
  }

  test('starts offline and a phone connection alone cannot claim Synced', () {
    expect(sync.online.value, isFalse);
    expect(sync.phoneOnline.value, isFalse);
    connect();
    expect(sync.phoneOnline.value, isTrue);
    expect(sync.online.value, isFalse);
    expect(sync.lastSynced.value, isNull);
    sync.markDeviceSeen(now.millisecondsSinceEpoch);
    expect(sync.online.value, isTrue);
  });

  test('no network immediately clears status; replay cannot restore it', () {
    connect();
    final timestamp = now.millisecondsSinceEpoch;
    sync.markDeviceSeen(timestamp);
    network.add(false);
    expect(sync.phoneOnline.value, isFalse);
    expect(sync.online.value, isFalse);
    sync.markDeviceSeen(timestamp);
    network.add(true);
    sync.markDeviceSeen(timestamp);
    expect(sync.online.value, isFalse);
    now = now.add(const Duration(seconds: 1));
    sync.markDeviceSeen(now.millisecondsSinceEpoch);
    expect(sync.online.value, isTrue);
  });

  test('Firebase disconnect and errors override an available WiFi interface',
      () {
    connect();
    sync.markDeviceSeen(now.millisecondsSinceEpoch);
    connection.add(false);
    expect(sync.online.value, isFalse);
    expect(sync.phoneOnline.value, isFalse);
    connection.add(true);
    expect(sync.online.value, isFalse);
    now = now.add(const Duration(seconds: 1));
    sync.markDeviceSeen(now.millisecondsSinceEpoch);
    expect(sync.online.value, isTrue);
    connection.addError(StateError('Unreachable database'));
    expect(sync.online.value, isFalse);
    expect(sync.phoneOnline.value, isFalse);
  });

  test(
      'duplicate cached readings do not extend the controller freshness window',
      () {
    connect();
    final timestamp = now.millisecondsSinceEpoch;
    sync.markDeviceSeen(timestamp);
    now = now.add(const Duration(seconds: 59));
    sync.markDeviceSeen(timestamp);
    expect(sync.online.value, isTrue);
    now = now.add(const Duration(seconds: 2));
    sync.refresh();
    expect(sync.online.value, isFalse);
    expect(sync.lastSynced.value!.millisecondsSinceEpoch, timestamp);
    sync.markDeviceSeen(timestamp + 1);
    expect(sync.online.value, isFalse);
    sync.markDeviceSeen(now.millisecondsSinceEpoch);
    expect(sync.online.value, isTrue);
  });

  test('old, future, pre-NTP and out-of-order timestamps cannot fake sync', () {
    connect();
    sync.markDeviceSeen(
        now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch);
    expect(sync.online.value, isFalse);
    for (final invalid in [
      0,
      15000,
      now.add(const Duration(hours: 1)).millisecondsSinceEpoch
    ]) {
      sync.markDeviceSeen(invalid);
      expect(sync.online.value, isFalse);
    }
    sync.markDeviceSeen(now.millisecondsSinceEpoch);
    final latest = sync.lastSynced.value;
    sync.markDeviceSeen(
        now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch);
    expect(sync.lastSynced.value, latest);
  });

  test('restores cached age without treating the same cached reading as live',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_synced_at', now.millisecondsSinceEpoch);
    final restored = SyncService(clock: () => now);
    final c = StreamController<bool>(sync: true);
    final n = StreamController<bool>(sync: true);
    await restored.start(connections: c.stream, networkAvailability: n.stream);
    c.add(true);
    n.add(true);
    restored.markDeviceSeen(now.millisecondsSinceEpoch);
    expect(restored.lastSynced.value, now);
    expect(restored.online.value, isFalse);
    now = now.add(const Duration(seconds: 1));
    restored.markDeviceSeen(now.millisecondsSinceEpoch);
    expect(restored.online.value, isTrue);
    restored.dispose();
    await c.close();
    await n.close();
  });
}

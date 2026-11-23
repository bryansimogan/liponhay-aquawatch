import 'package:fish_farm_app/models/alert_record.dart';
import 'package:fish_farm_app/models/app_notification.dart';
import 'package:fish_farm_app/models/management_logs.dart';
import 'package:fish_farm_app/models/sensor_data.dart';
import 'package:fish_farm_app/services/sync_service.dart';
import 'package:fish_farm_app/services/water_alert_feed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final time = DateTime.utc(2026, 11, 23, 8, 30);
  SensorData reading(int seconds, {double ph = 8.9, double oxygen = 1.5}) =>
      SensorData(
          ph: ph,
          temperature: 29.8,
          dissolvedOxygen: oxygen,
          timestamp:
              time.add(Duration(seconds: seconds)).millisecondsSinceEpoch);

  test(
      'current and history replay create one alert per unsafe parameter and time',
      () async {
    SharedPreferences.setMockInitialValues({
      'offline_v1_alerts': '[{"id":"sim_alert_0","value":9.2}]',
    });
    final sync = SyncService(clock: () => time);
    final feed = WaterAlertFeed(sync: sync);
    addTearDown(feed.dispose);
    sync.latestReading.value = reading(-10);
    await feed.start();
    expect(feed.items.value, isEmpty);
    final first = reading(0);
    sync.receivedReading.value = first;
    sync.recentHistory.value = [first, first];
    expect(feed.items.value, hasLength(2));
    expect(feed.items.value.map((a) => a.severity),
        unorderedEquals(['warning', 'critical']));
    expect(feed.items.value.map((a) => a.timestamp).toSet(), {first.timestamp});
    final next = reading(1, ph: 10.5, oxygen: 5.7);
    sync.receivedReading.value = next;
    sync.recentHistory.value = [first, next];
    expect(feed.items.value, hasLength(3));
    expect(feed.items.value.map((a) => a.id).toSet(), hasLength(3));
    await feed.clear();
    sync.recentHistory.value = [first, next];
    expect(feed.items.value, isEmpty);
    sync.receivedReading.value = reading(2);
    expect(feed.items.value, hasLength(2));
  });

  test('management and inbox use the same warning after a critical reading',
      () {
    final critical = reading(0, ph: 10.5, oxygen: 6);
    final sample = reading(1, oxygen: 6);
    final state = ManagementLogs().receive(critical).receive(sample);
    final alert = AlertRecord.forReading(sample).single;
    final incident = state.incidents.single;
    final notification = AppNotification.fromWaterAlert(alert);
    expect(incident.latestAlert?.id, alert.id);
    expect(incident.latestAlert?.value, 8.9);
    expect(incident.latestAlert?.severity, 'warning');
    expect(incident.latestAlert?.condition, alert.condition);
    expect(notification.id, alert.id);
    expect(notification.timestamp, sample.timestamp);
    expect(notification.severity, 'warning');
    expect(notification.body, '8.90 · Alkaline');
    expect(alert.dateTime.hour, 16);
  });
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_record.dart';
import '../models/sensor_data.dart';
import 'offline_cache_service.dart';
import 'sync_service.dart';

/// A single alert feed for both Alerts and Notifications. Replaying a reading
/// from current, history, or the offline cache cannot create another event.
class WaterAlertFeed {
  WaterAlertFeed({SyncService? sync}) : _sync = sync ?? SyncService.instance;
  static final instance = WaterAlertFeed();
  static const _clearedKey = 'water_alerts_cleared_through_v2';
  static const _limit = 500;
  final SyncService _sync;
  final items = ValueNotifier<List<AlertRecord>>(const []);
  final _events = <String, AlertRecord>{};
  int _clearedThrough = 0;
  Timer? _saveTimer;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final prefs = await SharedPreferences.getInstance();
    _clearedThrough = prefs.getInt(_clearedKey) ?? 0;
    for (final alert in await OfflineCacheService.alerts()) {
      if (alert.timestamp > _clearedThrough && alert.id.startsWith('water-')) {
        _events[alert.id] = alert;
      }
    }
    if (!_started) return;
    _sync.receivedReading.addListener(_onCurrent);
    _sync.recentHistory.addListener(_onHistory);
    _onHistory();
  }

  void _onCurrent() {
    final current = _sync.receivedReading.value;
    if (current != null && _merge(current)) _publish();
  }

  void _onHistory() {
    var changed = false;
    final current = _sync.receivedReading.value;
    for (final sample in _sync.recentHistory.value) {
      if (sample.timestamp != current?.timestamp && _merge(sample))
        changed = true;
    }
    if (current != null && _merge(current)) changed = true;
    if (changed || items.value.isEmpty) _publish();
  }

  bool _merge(SensorData sample) {
    if (sample.timestamp <= _clearedThrough) return false;
    final alerts = AlertRecord.forReading(sample);
    var changed = false;
    for (final alert in alerts) {
      final old = _events[alert.id];
      if (old?.value == alert.value &&
          old?.severity == alert.severity &&
          old?.condition == alert.condition) continue;
      _events[alert.id] = alert;
      changed = true;
    }
    return changed;
  }

  void _publish() {
    final sorted = _events.values.toList()
      ..sort((a, b) {
        final time = b.timestamp.compareTo(a.timestamp);
        return time == 0 ? a.id.compareTo(b.id) : time;
      });
    final kept = sorted.take(_limit).toList(growable: false);
    for (final extra in sorted.skip(_limit)) {
      _events.remove(extra.id);
    }
    items.value = kept;
    _saveTimer ??= Timer(const Duration(seconds: 2), () {
      _saveTimer = null;
      unawaited(OfflineCacheService.saveAlerts(items.value)
          .catchError((Object _) {}));
    });
  }

  Future<void> clear() async {
    final now = _sync.serverNow.millisecondsSinceEpoch;
    final newest = items.value.firstOrNull?.timestamp ?? 0;
    final through = newest > now ? newest : now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_clearedKey, through);
    _clearedThrough = through;
    _events.removeWhere((_, alert) => alert.timestamp <= through);
    _publish();
    await OfflineCacheService.saveAlerts(items.value);
  }

  void dispose() {
    _started = false;
    _sync.receivedReading.removeListener(_onCurrent);
    _sync.recentHistory.removeListener(_onHistory);
    _saveTimer?.cancel();
  }
}

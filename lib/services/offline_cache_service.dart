import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_record.dart';
import '../models/mortality_record.dart';
import '../models/sensor_data.dart';

/// Small on-device snapshot store used when the phone cannot reach Firebase.
///
/// Firebase remains the source of truth. These values are only the last data
/// successfully downloaded by this phone, so every online response replaces
/// or extends the matching snapshot.
class OfflineCacheService {
  OfflineCacheService._();

  static const _prefix = 'offline_v1';

  static String _currentKey(String pondId) => '${_prefix}_current_$pondId';
  static String _historyKey(String pondId) => '${_prefix}_history_$pondId';
  static String _mortalityKey(String pondId) => '${_prefix}_mortality_$pondId';
  static const _alertsKey = '${_prefix}_alerts';
  static const _recipientKey = '${_prefix}_sms_recipient';

  static Future<void> saveCurrent(String pondId, SensorData reading) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentKey(pondId), jsonEncode(reading.toMap()));
  }

  static Future<SensorData?> current(String pondId) async {
    try {
      final raw = (await SharedPreferences.getInstance())
          .getString(_currentKey(pondId));
      if (raw == null) return null;
      return SensorData.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Merge history windows so visiting Today, Week, and a picked month builds
  /// one useful offline archive instead of each request erasing the previous.
  static Future<void> saveHistory(
      String pondId, List<SensorData> readings) async {
    final existing = await history(pondId);
    final byTimestamp = <int, SensorData>{
      for (final reading in existing) reading.timestamp: reading,
      for (final reading in readings) reading.timestamp: reading,
    };
    final merged = byTimestamp.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // SharedPreferences is appropriate for a compact offline snapshot, not an
    // unlimited database. Keep the newest 2,000 sampled readings.
    final kept =
        merged.length > 2000 ? merged.sublist(merged.length - 2000) : merged;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey(pondId),
      jsonEncode(kept.map((reading) => reading.toMap()).toList()),
    );
  }

  static Future<List<SensorData>> history(
    String pondId, {
    DateTime? since,
    DateTime? until,
    int? limit,
  }) async {
    try {
      final raw = (await SharedPreferences.getInstance())
          .getString(_historyKey(pondId));
      if (raw == null) return [];
      var readings = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map>()
          .map(SensorData.tryFromHistoryMap)
          .whereType<SensorData>()
          .where((reading) =>
              (since == null ||
                  reading.timestamp >= since.millisecondsSinceEpoch) &&
              (until == null ||
                  reading.timestamp <= until.millisecondsSinceEpoch))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (limit != null && readings.length > limit) {
        readings = readings.sublist(readings.length - limit);
      }
      return readings;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMortality(
      String pondId, List<MortalityRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _mortalityKey(pondId),
      jsonEncode(records
          .map((record) => {'id': record.id, ...record.toMap()})
          .toList()),
    );
  }

  static Future<List<MortalityRecord>> mortality(String pondId) async {
    try {
      final raw = (await SharedPreferences.getInstance())
          .getString(_mortalityKey(pondId));
      if (raw == null) return [];
      return (jsonDecode(raw) as List<dynamic>).map((item) {
        final map = item as Map<String, dynamic>;
        return MortalityRecord.fromMap(map['id'] as String, map);
      }).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAlerts(List<AlertRecord> alerts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _alertsKey,
      jsonEncode(
          alerts.map((alert) => {'id': alert.id, ...alert.toMap()}).toList()),
    );
  }

  static Future<List<AlertRecord>> alerts() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_alertsKey);
      if (raw == null) return [];
      return (jsonDecode(raw) as List<dynamic>).map((item) {
        final map = item as Map<String, dynamic>;
        return AlertRecord.fromMap(map['id'] as String, map);
      }).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_alertsKey);
  }

  static Future<void> saveSmsRecipient(String recipient) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recipientKey, recipient);
  }

  static Future<String?> smsRecipient() async =>
      (await SharedPreferences.getInstance()).getString(_recipientKey);
}

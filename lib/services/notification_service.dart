import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_record.dart';
import '../models/app_notification.dart';
import '../models/gsm_config.dart';
import '../models/sensor_data.dart';
import 'firebase_service.dart';
import 'water_alert_feed.dart';

/// In-app notification inbox for new History records, Alerts, and SIM promo
/// expiration reminders.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _itemsKey = 'app_notifications_v1';
  static const _historyCursorKey = 'notification_history_cursor_v1';

  final ValueNotifier<List<AppNotification>> items =
      ValueNotifier<List<AppNotification>>(const []);
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  FirebaseService? _firebase;
  StreamSubscription<SensorData>? _historySub;
  final _alertFeed = WaterAlertFeed.instance;
  StreamSubscription<GsmConfig>? _gsmSub;
  Timer? _promoTimer;
  Timer? _saveTimer;
  GsmConfig _gsm = const GsmConfig();
  bool _started = false;
  int _historyCursor = 0;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _restore();
    await _alertFeed.start();

    _firebase ??= FirebaseService();
    _historySub = _firebase!.latestHistoryStream('pond1').listen(
          _onHistory,
          onError: (_) {},
        );
    _alertFeed.items.addListener(_syncAlerts);
    _syncAlerts();
    _gsmSub = _firebase!.gsmConfigStream().listen(
      (config) {
        _gsm = config;
        _checkPromoExpiry();
      },
      onError: (_) {},
    );
    _promoTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _checkPromoExpiry(),
    );
  }

  void _checkPromoExpiry() {
    final days = _gsm.daysLeft;
    if (days == null || days > 3) return;

    final reminderKey = days < 0 ? 'expired' : '$days-days-left';
    final title = days < 0
        ? 'SIM promo expired'
        : days == 0
            ? 'SIM promo expires today'
            : days == 1
                ? 'SIM promo expires tomorrow'
                : 'SIM promo expires in $days days';
    final action = days < 0
        ? 'Renew it now to keep SMS alerts working.'
        : 'Renew it before expiry to avoid interrupted SMS alerts.';

    _add(AppNotification(
      id: 'promo-${_gsm.startDate}-${_gsm.durationDays}-$reminderKey',
      type: AppNotificationType.promo,
      title: title,
      body:
          '${_gsm.promoName.isEmpty ? "SIM promo" : _gsm.promoName} · $action',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void _onHistory(SensorData reading) {
    // The first snapshot establishes the baseline on a new installation; it
    // is not a new event that happened while the app was watching.
    if (_historyCursor == 0) {
      _historyCursor = reading.timestamp;
      _persist();
      return;
    }
    if (reading.timestamp <= _historyCursor) return;
    _historyCursor = reading.timestamp;
    if (reading.parameters.any((parameter) => !parameter.isSafe)) {
      _persist();
      return;
    }
    _add(AppNotification(
      id: 'history-${reading.timestamp}',
      type: AppNotificationType.history,
      title: 'New history reading',
      body: 'Pond 1 · pH ${reading.ph.toStringAsFixed(2)}, '
          'Temp ${reading.temperature.toStringAsFixed(1)} °C, '
          'DO ${reading.dissolvedOxygen.toStringAsFixed(2)} mg/L',
      timestamp: reading.timestamp,
    ));
  }

  void _syncAlerts() {
    final previous = {for (final item in items.value) item.id: item};
    _publish([
      ...items.value.where((item) => item.type != AppNotificationType.alert),
      for (final alert in _alertFeed.items.value)
        AppNotification.fromWaterAlert(
          alert,
          read: previous[alert.id]?.read ?? false,
        ),
    ]);
  }

  bool isAlertUnread(AlertRecord alert) =>
      items.value.any((item) => item.id == alert.id && !item.read);

  Future<void> markAlertsRead() async {
    items.value = [
      for (final item in items.value)
        item.type == AppNotificationType.alert
            ? item.copyWith(read: true)
            : item,
    ];
    _updateCount();
    await _persist();
  }

  void _add(AppNotification notification) {
    if (items.value.any((item) => item.id == notification.id)) return;
    _publish([notification, ...items.value]);
  }

  void _publish(List<AppNotification> next) {
    next.sort((a, b) {
      final time = b.timestamp.compareTo(a.timestamp);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
    var other = 0;
    items.value = [
      for (final item in next)
        if (item.type == AppNotificationType.alert || other++ < 100) item,
    ];
    _updateCount();
    _saveTimer ??= Timer(const Duration(seconds: 2), () {
      _saveTimer = null;
      _persist();
    });
  }

  Future<void> markRead(String id) async {
    items.value = [
      for (final item in items.value)
        item.id == id ? item.copyWith(read: true) : item,
    ];
    _updateCount();
    await _persist();
  }

  Future<void> markAllRead() async {
    items.value = [for (final item in items.value) item.copyWith(read: true)];
    _updateCount();
    await _persist();
  }

  Future<void> clear() async {
    items.value = const [];
    _updateCount();
    await _persist();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _historyCursor = prefs.getInt(_historyCursorKey) ?? 0;
      final raw = prefs.getString(_itemsKey);
      if (raw != null) {
        items.value = (jsonDecode(raw) as List<dynamic>)
            .map((item) =>
                AppNotification.fromMap(Map<String, dynamic>.from(item as Map)))
            .where((item) =>
                item.type != AppNotificationType.alert ||
                item.id.startsWith('water-'))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
    } catch (_) {
      items.value = const [];
    }
    _updateCount();
  }

  void _updateCount() {
    unreadCount.value = items.value.where((item) => !item.read).length;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_historyCursorKey, _historyCursor);
      await prefs.setString(
        _itemsKey,
        jsonEncode(items.value.map((item) => item.toMap()).toList()),
      );
    } catch (_) {}
  }

  void dispose() {
    _historySub?.cancel();
    _alertFeed.items.removeListener(_syncAlerts);
    _gsmSub?.cancel();
    _promoTimer?.cancel();
    _saveTimer?.cancel();
    _started = false;
  }
}

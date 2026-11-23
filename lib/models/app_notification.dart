import 'alert_record.dart';

enum AppNotificationType { history, alert, promo }

/// One in-app notification shown from the header bell.
class AppNotification {
  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final int timestamp;
  final String? severity;
  final bool read;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.severity,
    this.read = false,
  });

  factory AppNotification.fromWaterAlert(AlertRecord alert,
          {bool read = false}) =>
      AppNotification(
        id: alert.id,
        type: AppNotificationType.alert,
        title: '${alert.severityLabel} alert · ${alert.parameterLabel}',
        body: '${alert.formattedValue} · ${alert.condition}',
        timestamp: alert.timestamp,
        severity: alert.severity,
        read: read,
      );

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        timestamp: timestamp,
        severity: severity,
        read: read ?? this.read,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'timestamp': timestamp,
        if (severity != null) 'severity': severity,
        'read': read,
      };

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
        id: map['id'] as String,
        type: switch (map['type']) {
          'history' => AppNotificationType.history,
          'promo' => AppNotificationType.promo,
          _ => AppNotificationType.alert,
        },
        title: map['title'] as String? ?? 'Update',
        body: map['body'] as String? ?? '',
        timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
        severity: map['severity'] as String?,
        read: map['read'] as bool? ?? false,
      );
}

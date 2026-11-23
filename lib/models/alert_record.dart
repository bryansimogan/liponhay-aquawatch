import 'sensor_data.dart';
import 'water_quality.dart';

/// One unsafe measurement, identified by pond, parameter and sample time.
class AlertRecord {
  final String id;
  final String parameter; // "pH", "temperature", "dissolved_oxygen"
  final double value;
  final String severity; // "warning" or "critical"
  final String condition;
  final int timestamp;
  final String pondId;

  AlertRecord({
    required this.id,
    required this.parameter,
    required this.value,
    required this.severity,
    required this.condition,
    required this.timestamp,
    required this.pondId,
  });

  static List<AlertRecord> forReading(SensorData sample,
          {String pondId = 'pond1'}) =>
      [
        for (final reading in sample.parameters)
          if (!reading.isSafe)
            fromParameter(reading, sample.timestamp, pondId: pondId),
      ];

  static AlertRecord fromParameter(ParamReading reading, int timestamp,
          {String pondId = 'pond1'}) =>
      AlertRecord(
        id: 'water-$pondId-${reading.param.name}-$timestamp',
        parameter: switch (reading.param) {
          WaterParam.ph => 'pH',
          WaterParam.temperature => 'temperature',
          WaterParam.dissolvedOxygen => 'dissolved_oxygen',
        },
        value: reading.value,
        severity: reading.level,
        condition: reading.condition,
        timestamp: timestamp,
        pondId: pondId,
      );

  String get parameterLabel => switch (parameter) {
        'pH' => 'pH',
        'temperature' => 'Temperature',
        'dissolved_oxygen' => 'Dissolved oxygen',
        _ => parameter,
      };

  String get formattedValue => switch (parameter) {
        'temperature' => '${value.toStringAsFixed(1)} °C',
        'dissolved_oxygen' => '${value.toStringAsFixed(2)} mg/L',
        _ => value.toStringAsFixed(2),
      };

  String get severityLabel => severity == 'critical' ? 'Critical' : 'Warning';

  factory AlertRecord.fromMap(String id, Map<dynamic, dynamic> map) {
    return AlertRecord(
      id: id,
      parameter: (map['parameter'] as String?) ?? '',
      value: (map['value'] as num?)?.toDouble() ?? 0.0,
      severity: (map['severity'] as String?) ?? 'warning',
      condition: (map['condition'] as String?) ?? '',
      timestamp: SensorData.timestampMilliseconds(map['timestamp']) ?? 0,
      pondId: (map['pond_id'] as String?) ?? 'pond1',
    );
  }

  Map<String, dynamic> toMap() => {
        'parameter': parameter,
        'value': value,
        'severity': severity,
        'condition': condition,
        'timestamp': timestamp,
        'pond_id': pondId,
      };

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
          .add(const Duration(hours: 8));

  /// Whether [timestamp] is a real wall-clock time.
  ///
  /// The controller stamps its own readings, and until its clock is set from
  /// NTP it has nothing to stamp them with. Records written in that window —
  /// and every record written before the firmware used real time at all —
  /// carry a value near zero, which renders as 1 January 1970. Showing that
  /// date claims the alert happened at a moment it plainly did not, so the
  /// screen says the time is unknown instead.
  bool get hasKnownTime => timestamp > DateTime(2020).millisecondsSinceEpoch;
}

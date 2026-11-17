/// Model representing a single sensor reading from one pond.
class SensorData {
  final double ph;
  final double temperature;
  final double dissolvedOxygen;
  final int timestamp;
  final double? ammoniaNh3;
  String status; // "normal", "warning", "critical"

  SensorData({
    required this.ph,
    required this.temperature,
    required this.dissolvedOxygen,
    required this.timestamp,
    this.ammoniaNh3,
    this.status = 'normal',
  });

  factory SensorData.fromMap(Map<dynamic, dynamic> map) {
    return SensorData(
      ph: (map['ph'] as num?)?.toDouble() ?? 7.0,
      temperature: (map['temperature'] as num?)?.toDouble() ?? 28.0,
      dissolvedOxygen: (map['dissolved_oxygen'] as num?)?.toDouble() ?? 6.0,
      timestamp: (map['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      status: (map['status'] as String?) ?? 'normal',
      ammoniaNh3: _measuredAmmonia(map),
    );
  }

  /// History must carry measured values and a timestamp.
  static SensorData? tryFromHistoryMap(Map<dynamic, dynamic> map) {
    final ph = map['ph'];
    final temperature = map['temperature'];
    final oxygen = map['dissolved_oxygen'];
    final time = map['timestamp'];
    if (ph is! num ||
        !ph.isFinite ||
        temperature is! num ||
        !temperature.isFinite ||
        oxygen is! num ||
        !oxygen.isFinite ||
        time is! num ||
        !time.isFinite ||
        time <= 0) {
      return null;
    }
    return SensorData(
      ph: ph.toDouble(),
      temperature: temperature.toDouble(),
      dissolvedOxygen: oxygen.toDouble(),
      timestamp: time.toInt(),
      ammoniaNh3: _measuredAmmonia(map),
      status: map['status'] is String ? map['status'] as String : 'normal',
    );
  }

  static double? _measuredAmmonia(Map<dynamic, dynamic> map) {
    final value = map['ammonia_nh3_mg_l'] ?? map['nh3_mg_l'];
    return value is num && value.isFinite && value >= 0
        ? value.toDouble()
        : null;
  }

  Map<String, dynamic> toMap() {
    return {
      'ph': ph,
      'temperature': temperature,
      'dissolved_oxygen': dissolvedOxygen,
      'timestamp': timestamp,
      if (ammoniaNh3 != null) 'ammonia_nh3_mg_l': ammoniaNh3,
      'status': status,
    };
  }

  /// Returns a DateTime from the stored timestamp
  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  /// Determine overall status based on thresholds from the manuscript:
  ///   pH 6.5-8.5, Temp 25-32°C, DO > 5 mg/L
  String computeStatus() {
    // Critical checks
    if (ph < 4 ||
        ph > 10 ||
        temperature < 20 ||
        temperature > 35 ||
        dissolvedOxygen < 2) {
      return 'critical';
    }
    // Warning checks
    if (ph < 6.5 ||
        ph > 8.5 ||
        temperature < 25 ||
        temperature > 32 ||
        dissolvedOxygen < 5) {
      return 'warning';
    }
    return 'normal';
  }
}

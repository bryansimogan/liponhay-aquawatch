import 'water_quality.dart';

/// Model representing a single sensor reading from one pond.
class SensorData {
  static final minEpochMilliseconds = DateTime.utc(2020).millisecondsSinceEpoch;
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

  /// History must carry measured values and a timestamp.
  static SensorData? tryFromHistoryMap(Map<dynamic, dynamic> map,
      {String? key}) {
    final ph = map['ph'];
    final temperature = map['temperature'];
    final oxygen = map['dissolved_oxygen'];
    final time =
        timestampMilliseconds(map['timestamp']) ?? timestampMilliseconds(key);
    if (ph is! num ||
        !ph.isFinite ||
        temperature is! num ||
        !temperature.isFinite ||
        oxygen is! num ||
        !oxygen.isFinite ||
        time == null) {
      return null;
    }
    return SensorData(
      ph: ph.toDouble(),
      temperature: temperature.toDouble(),
      dissolvedOxygen: oxygen.toDouble(),
      timestamp: time,
      ammoniaNh3: _measuredAmmonia(map),
      status: map['status'] is String ? map['status'] as String : 'normal',
    );
  }

  /// Firmware uses UTC epoch time. Accept seconds and numeric history keys
  /// without interpreting either as the phone's local time.
  static int? timestampMilliseconds(Object? value) {
    final number = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (number == null || !number.isFinite || number <= 0) return null;
    final millis = (number < 100000000000 ? number * 1000 : number).toInt();
    return millis >= minEpochMilliseconds && millis < 4102444800000
        ? millis
        : null;
  }

  List<ParamReading> get parameters => [
        ParamReading.classify(WaterParam.ph, ph),
        ParamReading.classify(WaterParam.temperature, temperature),
        ParamReading.classify(WaterParam.dissolvedOxygen, dissolvedOxygen),
      ];

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

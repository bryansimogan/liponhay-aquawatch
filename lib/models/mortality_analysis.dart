import 'dart:math' as math;

import 'sensor_data.dart';
import 'water_quality.dart';

enum MortalityFactor {
  lowOxygen(
      'Low Dissolved Oxygen', 'Mababang dissolved oxygen', 'mg/L', 2, true),
  highOxygen(
      'High Dissolved Oxygen', 'Mataas na dissolved oxygen', 'mg/L', 2, false),
  highAmmonia('High Ammonia', 'Mataas na ammonia', 'mg/L NH₃', 3, false),
  highTemperature('High Temperature', 'Mataas na temperatura', '°C', 1, false),
  lowTemperature('Low Temperature', 'Mababang temperatura', '°C', 1, true),
  highPh('High pH', 'Mataas na pH', '', 2, false),
  lowPh('Low pH', 'Mababang pH', '', 2, true);

  const MortalityFactor(
      this.english, this.tagalog, this.unit, this.decimals, this.lower);

  final String english;
  final String tagalog;
  final String unit;
  final int decimals;
  final bool lower;

  String format(double value) =>
      '${value.toStringAsFixed(decimals)}${unit.isEmpty ? '' : ' $unit'}';
}

/// A measured sample, including any available subset of the sensor channels.
class MortalityReading {
  const MortalityReading({
    required this.timestamp,
    this.ph,
    this.temperature,
    this.dissolvedOxygen,
    this.ammoniaNh3,
  });

  final int timestamp;
  final double? ph;
  final double? temperature;
  final double? dissolvedOxygen;
  final double? ammoniaNh3;

  bool get hasMonitoredParameters =>
      ph != null && temperature != null && dissolvedOxygen != null;

  static MortalityReading? fromMap(Map<dynamic, dynamic> row) {
    double? measured(Object? value) =>
        value is num && value.isFinite ? value.toDouble() : null;

    final time = measured(row['timestamp']);
    if (time == null || time < 1) return null;
    final reportedAmmonia =
        measured(row['ammonia_nh3_mg_l']) ?? measured(row['nh3_mg_l']);
    final reading = MortalityReading(
      timestamp: time.toInt(),
      ph: measured(row['ph']),
      temperature: measured(row['temperature']),
      dissolvedOxygen: measured(row['dissolved_oxygen']),
      // These field names specify measured un-ionized NH3 in mg/L.
      ammoniaNh3: reportedAmmonia != null && reportedAmmonia >= 0
          ? reportedAmmonia
          : null,
    );
    return reading.ph == null &&
            reading.temperature == null &&
            reading.dissolvedOxygen == null &&
            reading.ammoniaNh3 == null
        ? null
        : reading;
  }

  static MortalityReading? fromSensor(SensorData sample) =>
      fromMap(sample.toMap());

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp,
        if (ph != null) 'ph': ph,
        if (temperature != null) 'temperature': temperature,
        if (dissolvedOxygen != null) 'dissolved_oxygen': dissolvedOxygen,
        if (ammoniaNh3 != null) 'ammonia_nh3_mg_l': ammoniaNh3,
      };
}

class MortalityFinding {
  const MortalityFinding({
    required this.factor,
    required this.count,
    required this.criticalCount,
    required this.extreme,
    required this.lastSeen,
    this.threshold,
  });

  final MortalityFactor factor;
  final int count;
  final int criticalCount;
  final double extreme;
  final int lastSeen;
  final double? threshold;

  Map<String, dynamic> toMap() => {
        'factor': factor.name,
        'count': count,
        'critical_count': criticalCount,
        'extreme': extreme,
        'last_seen': lastSeen,
        if (threshold != null) 'threshold': threshold,
      };

  static MortalityFinding? fromMap(Map<dynamic, dynamic> map) {
    final factor = MortalityFactor.values.asNameMap()[map['factor']];
    final extreme = map['extreme'];
    if (factor == null || extreme is! num || !extreme.isFinite) return null;
    return MortalityFinding(
      factor: factor,
      count: (map['count'] as num?)?.toInt() ?? 0,
      criticalCount: (map['critical_count'] as num?)?.toInt() ?? 0,
      extreme: extreme.toDouble(),
      lastSeen: (map['last_seen'] as num?)?.toInt() ?? 0,
      threshold: (map['threshold'] as num?)?.toDouble(),
    );
  }
}

/// The closest eligible water-quality sample for one mortality event.
class MortalityAnalysis {
  static const maxGap = Duration(minutes: 30);
  static const _matchMethod = 'event_nearest_v1';

  // Benson & Krause freshwater oxygen solubility at standard pressure, USGS
  // WQ 2011.03: https://water.usgs.gov/water-resources/memos/documents/WQ.2011.03.pdf
  // 110% is a screening trigger for this app. It is not a toxicity threshold.
  static const highOxygenScreeningRatio = 1.10;
  // FAO Nile tilapia reference: NH3 below 0.1 mg/L.
  static const ammoniaLimit = 0.1;

  const MortalityAnalysis({
    required this.sampleCount,
    required this.firstReading,
    required this.lastReading,
    required this.findings,
    this.eventTimestamp,
    this.reading,
    this.hasSpeciesProfile = true,
  });

  final int sampleCount;
  final int? firstReading;
  final int? lastReading;
  final List<MortalityFinding> findings;
  final int? eventTimestamp;
  final MortalityReading? reading;
  final bool hasSpeciesProfile;

  bool get usesEventMatch => eventTimestamp != null;
  bool get readingAfterEvent =>
      reading != null &&
      eventTimestamp != null &&
      reading!.timestamp > eventTimestamp!;
  bool get insufficient =>
      reading == null ||
      readingAfterEvent ||
      !hasSpeciesProfile ||
      (findings.isEmpty && !reading!.hasMonitoredParameters);

  static MortalityAnalysis evaluate(
    Iterable<MortalityReading> readings, {
    required DateTime eventAt,
    required String species,
  }) {
    final event = eventAt.millisecondsSinceEpoch;
    final radius = maxGap.inMilliseconds;
    final candidates = <int, MortalityReading>{};
    MortalityReading? before;
    MortalityReading? after;
    for (final sample in readings) {
      final offset = sample.timestamp - event;
      if (offset.abs() > radius) continue;
      candidates[sample.timestamp] = sample;
      if (offset <= 0) {
        if (before == null || sample.timestamp >= before.timestamp)
          before = sample;
      } else if (after == null || sample.timestamp <= after.timestamp) {
        after = sample;
      }
    }
    final timestamps = candidates.keys.toList()..sort();
    final hasSpeciesProfile = species.toLowerCase().contains('tilapia');
    final findings = before != null && hasSpeciesProfile
        ? _tilapiaFindings(before)
        : <MortalityFinding>[];
    return MortalityAnalysis(
      sampleCount: candidates.length,
      firstReading: timestamps.firstOrNull,
      lastReading: timestamps.lastOrNull,
      findings: findings,
      eventTimestamp: event,
      reading: before ?? after,
      hasSpeciesProfile: hasSpeciesProfile,
    );
  }

  static List<MortalityFinding> _tilapiaFindings(MortalityReading sample) {
    final findings = <MortalityFinding>[];

    void add(MortalityFactor factor, double value, double limit,
        {bool critical = false}) {
      findings.add(MortalityFinding(
        factor: factor,
        count: 1,
        criticalCount: critical ? 1 : 0,
        extreme: value,
        lastSeen: sample.timestamp,
        threshold: limit,
      ));
    }

    void classify(WaterParam parameter, double? value, MortalityFactor low,
        MortalityFactor high, double min, double max) {
      if (value == null) return;
      final reading = ParamReading.classify(parameter, value);
      if (!reading.isSafe) {
        final lower = value < min;
        add(lower ? low : high, value, lower ? min : max,
            critical: reading.level == 'critical');
      }
    }

    classify(WaterParam.ph, sample.ph, MortalityFactor.lowPh,
        MortalityFactor.highPh, 6.5, 8.5);
    classify(
        WaterParam.temperature,
        sample.temperature,
        MortalityFactor.lowTemperature,
        MortalityFactor.highTemperature,
        25,
        32);
    final oxygen = sample.dissolvedOxygen;
    final oxygenLimit = highOxygenLimit(sample.temperature);
    if (oxygen != null) {
      if (oxygen < 5) {
        add(MortalityFactor.lowOxygen, oxygen, 5,
            critical: ParamReading.classify(WaterParam.dissolvedOxygen, oxygen)
                    .level ==
                'critical');
      } else if (oxygenLimit != null && oxygen >= oxygenLimit) {
        add(MortalityFactor.highOxygen, oxygen, oxygenLimit);
      }
    }
    final ammonia = sample.ammoniaNh3;
    if (ammonia != null && ammonia >= ammoniaLimit) {
      add(MortalityFactor.highAmmonia, ammonia, ammoniaLimit);
    }

    return findings..sort(_compareFindings);
  }

  static double? highOxygenLimit(double? temperature) {
    if (temperature == null || temperature < 0 || temperature > 40) return null;
    final kelvin = temperature + 273.15;
    final inverse = 1 / kelvin;
    final exponent = -139.34411 +
        inverse *
            (157570.1 +
                inverse *
                    (-66423080 +
                        inverse * (12438000000 - 862194900000 * inverse)));
    return math.exp(exponent) * highOxygenScreeningRatio;
  }

  static int _compareFindings(MortalityFinding a, MortalityFinding b) {
    final severity = b.criticalCount.compareTo(a.criticalCount);
    if (severity != 0) return severity;
    final frequency = b.count.compareTo(a.count);
    if (frequency != 0) return frequency;
    final recency = b.lastSeen.compareTo(a.lastSeen);
    return recency == 0 ? a.factor.index.compareTo(b.factor.index) : recency;
  }

  Map<String, dynamic> toMap() => {
        'sample_count': sampleCount,
        if (firstReading != null) 'first_reading': firstReading,
        if (lastReading != null) 'last_reading': lastReading,
        if (usesEventMatch) ...{
          'method': _matchMethod,
          'event_timestamp': eventTimestamp,
        },
        if (reading != null) 'matched_reading': reading!.toMap(),
        if (!hasSpeciesProfile) 'profile_supported': false,
        if (findings.isNotEmpty)
          'findings': {
            for (final finding in findings)
              finding.factor.name: finding.toMap(),
          },
      };

  factory MortalityAnalysis.fromMap(Map<dynamic, dynamic> map) {
    final recordedFindings = map['findings'];
    final recordedReading = map['matched_reading'];
    return MortalityAnalysis(
      sampleCount: (map['sample_count'] as num?)?.toInt() ?? 0,
      firstReading: (map['first_reading'] as num?)?.toInt(),
      lastReading: (map['last_reading'] as num?)?.toInt(),
      eventTimestamp: map['method'] == _matchMethod
          ? (map['event_timestamp'] as num?)?.toInt()
          : null,
      hasSpeciesProfile: map['profile_supported'] != false,
      reading: recordedReading is Map
          ? MortalityReading.fromMap(recordedReading)
          : null,
      findings: [
        if (recordedFindings is Map)
          for (final item in recordedFindings.values)
            if (item is Map)
              if (MortalityFinding.fromMap(item) case final finding?) finding,
      ]..sort(_compareFindings),
    );
  }
}

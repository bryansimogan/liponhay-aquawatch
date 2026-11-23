import '../data/response_content.dart';
import '../services/i18n.dart';
import 'incident.dart';
import 'sensor_data.dart';
import 'water_quality.dart';

/// Persisted response-center state. Advancing the same timestamp is idempotent.
class ManagementLogs {
  static const verificationPeriod = Duration(minutes: 10);
  static const maxVerificationGap = Duration(seconds: 60);

  ManagementLogs({List<Incident>? incidents, this.lastReadingAt = 0})
      : incidents = incidents ?? [];

  final List<Incident> incidents;
  final int lastReadingAt;

  factory ManagementLogs.fromMap(Map<dynamic, dynamic> map) {
    final records = map['incidents'];
    return ManagementLogs(
      lastReadingAt: (map['last_reading_at'] as num?)?.toInt() ?? 0,
      incidents: [
        if (records is Map)
          for (final row in records.values)
            if (row is Map) Incident.fromMap(row),
      ]..sort((a, b) => b.ts.compareTo(a.ts)),
    );
  }

  Map<String, dynamic> toMap() => {
        'last_reading_at': lastReadingAt,
        'incidents': {
          for (final incident in incidents) '${incident.id}': incident.toMap()
        },
      };

  ManagementLogs receive(SensorData sample, {bool allowDemoTimeJump = false}) {
    if (sample.timestamp < lastReadingAt ||
        (!allowDemoTimeJump && sample.timestamp == lastReadingAt) ||
        SensorData.tryFromHistoryMap(sample.toMap()) == null) {
      return this;
    }
    final records = [for (final i in incidents) Incident.fromMap(i.toMap())];
    final gap = !allowDemoTimeJump &&
        lastReadingAt > 0 &&
        sample.timestamp - lastReadingAt > maxVerificationGap.inMilliseconds;
    final values = {
      'ph': sample.ph,
      't': sample.temperature,
      'o': sample.dissolvedOxygen
    };
    final parameters = {
      'ph': WaterParam.ph,
      't': WaterParam.temperature,
      'o': WaterParam.dissolvedOxygen
    };

    for (final p in values.keys) {
      final value = values[p]!;
      final reading = ParamReading.classify(parameters[p]!, value);
      final level = reading.isSafe
          ? 'ok'
          : reading.level == 'critical'
              ? 'crit'
              : 'warn';
      final matching = records.where((i) => i.p == p).toList()
        ..sort((a, b) => b.ts.compareTo(a.ts));
      var incident = matching.where((i) => i.isOpen).firstOrNull;
      if (incident == null && matching.firstOrNull?.st == 'unresolved') {
        incident = matching.first;
        incident.latestValue = value;
        incident.latestAt = sample.timestamp;
        if (!reading.isSafe) {
          if (level == 'crit') incident.lvl = 'crit';
          incident.lastUnsafeValue = value;
          incident.lastUnsafeAt = sample.timestamp;
          incident.title = paramTitle(p, value);
          continue;
        }
        incident.closedAt = null;
      }
      if (incident == null) {
        if (reading.isSafe) continue;
        incident = Incident(
          id: sample.timestamp * 10 + const ['o', 'ph', 't'].indexOf(p),
          p: p,
          title: paramTitle(p, value),
          val: formatReading(p, value),
          ts: sample.timestamp,
          lvl: level,
          sms: allowDemoTimeJump,
          d0: distance(p, value),
          latestValue: value,
          latestAt: sample.timestamp,
        );
        records.insert(0, incident);
      }
      incident.latestValue = value;
      incident.latestAt = sample.timestamp;
      if (gap) incident.safeSince = null;
      if (level == 'crit') incident.lvl = 'crit';

      if (!incident.act) {
        incident.d0 ??= distance(p, value);
        if (distance(p, value) <= incident.d0! - improvementDelta[p]!) {
          incident.imp += 1;
          if (incident.imp >= 2) {
            incident.act = true;
            incident.actAt = sample.timestamp;
            incident.st = 'progress';
            incident.rem.add(IncidentRemark(
              t: sample.timestamp,
              action: autoActionFor(p),
              note: L('Detected from the sensor readings',
                  'Natukoy mula sa mga reading ng sensor'),
            ));
          }
        } else {
          incident.imp = 0;
        }
      }

      if (reading.isSafe) {
        if (incident.safeSince == null) {
          incident.safeSince = sample.timestamp;
          incident.st = 'progress';
          incident.rem.add(IncidentRemark(
            t: sample.timestamp,
            note: L('The reading must stay in range for 10 minutes.',
                'Kailangang manatiling ligtas ang reading sa loob ng 10 minuto.'),
          ));
        } else if (sample.timestamp - incident.safeSince! >=
            verificationPeriod.inMilliseconds) {
          incident.st = 'resolved';
          incident.closedAt = sample.timestamp;
          incident.after = formatReading(p, value);
          incident.self = !incident.act;
          incident.rem.add(IncidentRemark(
            t: sample.timestamp,
            note: L('Verified after 10 minutes of safe readings.',
                'Na-verify matapos ang 10 minutong ligtas na readings.'),
          ));
        }
      } else {
        incident.lastUnsafeValue = value;
        incident.lastUnsafeAt = sample.timestamp;
        incident.title = paramTitle(p, value);
        if (incident.safeSince != null) {
          incident.safeSince = null;
          incident.st = incident.act ? 'progress' : 'open';
          incident.rem.add(IncidentRemark(
            t: sample.timestamp,
            note: L('Unsafe again · verification reset',
                'Hindi ligtas muli · na-reset ang pag-verify'),
          ));
        }
        final deadline =
            incident.ts + paramMeta[p]!.window(incident.lvl)[1] * 60000;
        if (sample.timestamp >= deadline) {
          incident.st = 'unresolved';
          incident.closedAt = sample.timestamp;
          incident.rem.add(IncidentRemark(
            t: sample.timestamp,
            note: L('The reading was still unsafe after the response window.',
                'Hindi pa rin ligtas ang reading matapos ang itinakdang oras.'),
          ));
        }
      }
    }
    return ManagementLogs(incidents: records, lastReadingAt: sample.timestamp);
  }
}

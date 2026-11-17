import 'dart:async';
import 'dart:math';
import '../models/sensor_data.dart';
import '../models/mortality_record.dart';
import '../models/alert_record.dart';
import '../models/water_quality.dart';

/// Generates realistic simulated sensor data for testing WITHOUT real hardware.
///
/// In simulation mode, the app creates realistic-looking water quality readings
/// that fluctuate naturally around safe thresholds, occasionally spiking into
/// warning/critical ranges so you can verify the alert system works.
class SimulationService {
  final Random _rng = Random();
  StreamController<SensorData>? _controller;
  Timer? _timer;

  // Simulated current values (they drift smoothly)
  double _ph = 7.2;
  double _temp = 28.0;
  double _do = 6.5;

  // Occasional spike state
  bool _spiking = false;
  int _spikeCountdown = 0;

  /// Start generating simulated data for a given pond every [intervalMs].
  Stream<SensorData> startSimulation({
    required String pondId,
    int intervalMs = 5000,
  }) {
    _controller = StreamController<SensorData>.broadcast();
    _ph = 7.0 + _rng.nextDouble() * 1.0;   // 7.0 - 8.0
    _temp = 26.0 + _rng.nextDouble() * 4.0; // 26 - 30
    _do = 5.5 + _rng.nextDouble() * 2.5;    // 5.5 - 8.0

    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _updateValues();
      final data = SensorData(
        ph: double.parse(_ph.toStringAsFixed(2)),
        temperature: double.parse(_temp.toStringAsFixed(1)),
        dissolvedOxygen: double.parse(_do.toStringAsFixed(2)),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        status: 'normal',
      );
      // Compute real status from thresholds
      data.status = data.computeStatus();
      _controller?.add(data);
    });
    return _controller!.stream;
  }

  void _updateValues() {
    // Random walk with small step
    _ph += (_rng.nextDouble() - 0.5) * 0.3;
    _temp += (_rng.nextDouble() - 0.5) * 0.8;
    _do += (_rng.nextDouble() - 0.5) * 0.4;

    // Occasional spike into warning/critical zone
    if (!_spiking && _rng.nextInt(100) < 5) {
      // 5% chance per tick to start a spike
      _spiking = true;
      _spikeCountdown = _rng.nextInt(3) + 2; // spike for 2-4 readings
    }
    if (_spiking) {
      _spikeCountdown--;
      if (_spikeCountdown <= 0) {
        _spiking = false;
      } else {
        // Push one parameter into danger zone
        final spikeParam = _rng.nextInt(3);
        switch (spikeParam) {
          case 0: // pH spike
            _ph += _rng.nextBool() ? _rng.nextDouble() * 3 : -_rng.nextDouble() * 3;
            break;
          case 1: // Temperature spike
            _temp += _rng.nextBool() ? _rng.nextDouble() * 6 : -_rng.nextDouble() * 6;
            break;
          case 2: // DO spike (downward)
            _do -= _rng.nextDouble() * 4;
            break;
        }
      }
    }

    // Clamp to physically reasonable ranges
    _ph = _ph.clamp(0.0, 14.0);
    _temp = _temp.clamp(10.0, 45.0);
    _do = _do.clamp(0.0, 14.0);
  }

  /// Generate fake historical data (backfill N entries).
  List<SensorData> generateHistory(String pondId, {int count = 30}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final List<SensorData> history = [];
    double ph = 7.2;
    double temp = 28.0;
    double doVal = 6.5;

    for (int i = count - 1; i >= 0; i--) {
      ph += (_rng.nextDouble() - 0.5) * 0.4;
      temp += (_rng.nextDouble() - 0.5) * 1.0;
      doVal += (_rng.nextDouble() - 0.5) * 0.5;

      ph = ph.clamp(4.0, 11.0);
      temp = temp.clamp(18.0, 38.0);
      doVal = doVal.clamp(1.0, 10.0);

      final data = SensorData(
        ph: double.parse(ph.toStringAsFixed(2)),
        temperature: double.parse(temp.toStringAsFixed(1)),
        dissolvedOxygen: double.parse(doVal.toStringAsFixed(2)),
        timestamp: now - (i * 30000), // 30 seconds apart
      );
      data.status = data.computeStatus();
      history.add(data);
    }
    return history;
  }

  /// Generate sample mortality records for demo.
  List<MortalityRecord> generateMortalityRecords(String pondId,
      {int count = 4}) {
    final now = DateTime.now();
    const notes = [
      'Found near aerator, low DO recorded that morning',
      'Noticed during morning feeding',
      '',
      'Water looked cloudy the day before',
      '',
    ];
    final List<MortalityRecord> records = [];
    for (int i = 0; i < count; i++) {
      final date = now.subtract(Duration(days: i * 3 + 1));
      records.add(MortalityRecord(
        id: 'sim_mort_$i',
        date: '${date.year}-${date.month.toString().padLeft(2, '0')}'
            '-${date.day.toString().padLeft(2, '0')}',
        pondId: pondId,
        species: MortalityRecord.speciesForPond(pondId),
        count: _rng.nextInt(6) + 1,
        possibleCause:
            MortalityCause.options[_rng.nextInt(MortalityCause.options.length)],
        notes: notes[_rng.nextInt(notes.length)],
        timestamp: date.millisecondsSinceEpoch,
      ));
    }
    return records;
  }

  /// Generate sample alert records for demo.
  List<AlertRecord> generateAlerts({int count = 8}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final params = ['pH', 'temperature', 'dissolved_oxygen'];
    final conditions = [
      'Strongly Acidic', 'Acidic', 'Alkaline', 'Strongly Alkaline',
      'Cold stress', 'Warm stress', 'Too hot',
      'Severe depletion', 'Low oxygen',
    ];
    final List<AlertRecord> alerts = [];
    for (int i = 0; i < count; i++) {
      final param = params[i % params.length];
      double val;
      switch (param) {
        case 'pH':
          val = i % 2 == 0 ? 3.5 + _rng.nextDouble() : 9.5 + _rng.nextDouble();
          break;
        case 'temperature':
          val = i % 2 == 0 ? 15.0 + _rng.nextDouble() * 5 : 36.0 + _rng.nextDouble() * 4;
          break;
        default:
          val = 1.0 + _rng.nextDouble() * 2;
      }
      alerts.add(AlertRecord(
        id: 'sim_alert_$i',
        parameter: param,
        value: double.parse(val.toStringAsFixed(2)),
        severity: i % 3 == 0 ? 'critical' : 'warning',
        condition: conditions[i % conditions.length],
        timestamp: now - (i * 600000), // 10 min apart
        pondId: 'pond${(i % 3) + 1}',
      ));
    }
    return alerts;
  }

  void stop() {
    _timer?.cancel();
    _controller?.close();
  }
}

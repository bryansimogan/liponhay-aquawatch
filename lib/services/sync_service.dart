import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/sensor_data.dart';
import 'firebase_service.dart';
import 'offline_cache_service.dart';

/// Observes the phone's internet, the database session and the pond separately.
class SyncService with WidgetsBindingObserver {
  SyncService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  static final SyncService instance = SyncService();
  static const deviceStaleAfter = Duration(milliseconds: 120000);
  static const _pollInterval = Duration(seconds: 5);
  static const _maxClockLead = Duration(minutes: 5);
  static const _internetChannel = MethodChannel('aquawatch/internet');
  final DateTime Function() _clock;
  final phoneOnline = ValueNotifier<bool?>(null);
  final serverOnline = ValueNotifier<bool?>(null);
  final online = ValueNotifier<bool>(false);
  final lastSynced = ValueNotifier<DateTime?>(null);
  final latestReading = ValueNotifier<SensorData?>(null);
  final receivedReading = ValueNotifier<SensorData?>(null);
  final recentHistory = ValueNotifier<List<SensorData>>(const []);
  final ageLabel = ValueNotifier<String>('never');

  StreamSubscription<bool>? _connection;
  StreamSubscription<bool>? _network;
  StreamSubscription<Duration>? _offsets;
  StreamSubscription<SensorData?>? _current;
  StreamSubscription<List<SensorData>>? _history;
  Timer? _tick;
  Timer? _serverGrace;
  Timer? _retry;
  bool _started = false;
  bool _hasSession = false;
  bool _checkingInternet = false;
  bool _pollInFlight = false;
  int _internetMisses = 0;
  int _ticks = 0;
  int _generation = 0;
  bool _production = false;
  Duration _offset = Duration.zero;
  int? _confirmedTimestamp;
  DateTime? _confirmedAt;
  DateTime? _confirmedServerAt;
  SensorData? _pendingCurrent;
  List<SensorData> _pendingHistory = const [];
  Future<List<SensorData>> Function()? _pollReadings;
  DateTime get serverNow => _clock().add(_offset);

  Future<void> start({
    Stream<bool>? connections,
    Stream<bool>? internetChecks,
    Stream<Duration>? serverTimeOffsets,
    Stream<SensorData?> Function()? currentReadings,
    Stream<List<SensorData>> Function()? historyReadings,
    Future<List<SensorData>> Function()? pollReadings,
  }) async {
    if (_started) return;
    _started = true;
    final generation = ++_generation;
    _production = connections == null;
    final database = _production ? FirebaseDatabase.instance : null;
    final firebase = FirebaseService();
    _pollReadings = pollReadings ??
        (_production ? () => firebase.pollHardwareReadings('pond1') : null);
    if (_production) {
      final cached = await OfflineCacheService.current('pond1');
      if (!_started || generation != _generation) return;
      if (cached != null && _plausible(cached.timestamp)) {
        latestReading.value = cached;
        lastSynced.value = cached.dateTime;
      }
      WidgetsBinding.instance.addObserver(this);
      unawaited(_checkInternet());
    }
    _network = internetChecks?.listen(_internetResult, onError: (Object _) {});
    _offsets = (serverTimeOffsets ??
            database?.ref('.info/serverTimeOffset').onValue.map((event) =>
                Duration(
                    milliseconds:
                        (event.snapshot.value as num?)?.toInt() ?? 0)))
        ?.listen((offset) {
      _offset = offset;
      _acceptHistory();
      final reading = _pendingCurrent;
      if (reading != null) _receive(reading);
      refresh();
    }, onError: (Object _) {});

    final current = currentReadings ??
        (_production ? () => firebase.currentReadingStream('pond1') : null);
    final history = historyReadings ??
        (_production
            ? () => firebase.recentHardwareHistoryStream('pond1')
            : null);

    void subscribe() {
      if (!_started || generation != _generation) return;
      void retry() {
        if (!_started || generation != _generation || _retry?.isActive == true)
          return;
        _retry = Timer(_pollInterval, subscribe);
      }

      unawaited(_current?.cancel());
      unawaited(_history?.cancel());
      _current = current?.call().listen((reading) {
        if (reading != null) {
          _pendingCurrent = reading;
          _receive(reading);
        }
      }, onError: (Object _) => retry(), onDone: retry);
      _history = history?.call().listen((readings) {
        _pendingHistory = readings;
        _acceptHistory();
      }, onError: (Object _) => retry(), onDone: retry);
    }

    _connection = (connections ??
            database!
                .ref('.info/connected')
                .onValue
                .map((e) => e.snapshot.value == true))
        .listen((connected) {
      _hasSession = connected;
      _serverGrace?.cancel();
      if (connected) {
        serverOnline.value = true;
        if (_retry?.isActive == true) {
          _retry!.cancel();
          subscribe();
        }
        // A snapshot can arrive immediately before Firebase announces its session.
        final reading = _pendingCurrent;
        if (reading != null) _receive(reading);
        _acceptHistory();
        unawaited(refreshNow());
      } else {
        _serverGrace = Timer(const Duration(seconds: 5), () {
          serverOnline.value = false;
        });
      }
      refresh();
    }, onError: (Object _) {
      // Keep the previous status until the SDK reports the connection state.
    });

    subscribe();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (++_ticks % _pollInterval.inSeconds == 0) {
        if (_production) unawaited(_checkInternet());
        final lastReceipt = _confirmedAt;
        if (lastReceipt == null ||
            _clock().difference(lastReceipt) >= _pollInterval) {
          unawaited(_pollNewest());
        }
      }
      refresh();
    });
    refresh();
  }

  void _acceptHistory() {
    final valid =
        _pendingHistory.where((r) => _plausible(r.timestamp)).toList();
    if (valid.isNotEmpty) _receive(valid.last);
    if (_hasSession) recentHistory.value = valid;
  }

  void _receive(SensorData reading) {
    if (!_hasSession || !_plausible(reading.timestamp)) return;
    final previous = latestReading.value;
    if (previous != null &&
        _plausible(previous.timestamp) &&
        reading.timestamp < previous.timestamp &&
        !(previous.timestamp > serverNow.millisecondsSinceEpoch &&
            _confirmedTimestamp == null)) return;

    _confirm(reading.timestamp);
    if (previous?.timestamp != reading.timestamp ||
        receivedReading.value == null) {
      lastSynced.value = reading.dateTime;
      latestReading.value = reading;
      if (_production) {
        unawaited(OfflineCacheService.saveCurrent('pond1', reading)
            .catchError((Object _) {}));
      }
    }
    receivedReading.value = latestReading.value;
    refresh();
  }

  void _confirm(int timestamp) {
    if (timestamp == _confirmedTimestamp) return;
    _confirmedTimestamp = timestamp;
    _confirmedAt = _clock();
    _confirmedServerAt = serverNow;
  }

  bool _plausible(int timestamp) =>
      timestamp >= SensorData.minEpochMilliseconds &&
      timestamp <= serverNow.add(_maxClockLead).millisecondsSinceEpoch;

  void _internetResult(bool reachable) {
    if (reachable) {
      _internetMisses = 0;
      phoneOnline.value = true;
    } else if (++_internetMisses >= 2) {
      phoneOnline.value = false;
    }
  }

  Future<void> _checkInternet() async {
    if (_checkingInternet) return;
    _checkingInternet = true;
    final generation = _generation;
    try {
      final reachable =
          await _internetChannel.invokeMethod<bool>('isValidated');
      if (_started && generation == _generation && reachable != null) {
        _internetResult(reachable);
      }
    } on PlatformException {
      // A failed check does not establish that the phone is offline.
    } on MissingPluginException {
      // Firebase session status remains available on platforms without this probe.
    } finally {
      _checkingInternet = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refreshNow());
  }

  Future<void> refreshNow() async {
    if (!_started) return;
    refresh();
    await Future.wait([
      if (_production) _checkInternet(),
      _pollNewest(),
    ]);
  }

  Future<void> _pollNewest() async {
    final poll = _pollReadings;
    if (!_hasSession || !_started || _pollInFlight || poll == null) return;
    final generation = _generation;
    _pollInFlight = true;
    try {
      final readings = await poll();
      if (!_started || generation != _generation || !_hasSession) return;
      SensorData? newest;
      for (final reading in readings) {
        if (_plausible(reading.timestamp) &&
            (newest == null || reading.timestamp > newest.timestamp)) {
          newest = reading;
        }
      }
      if (newest != null) _receive(newest);
    } catch (_) {
      // The live subscription and freshness timer keep running after a read failure.
    } finally {
      _pollInFlight = false;
    }
  }

  void refresh() {
    final last = lastSynced.value;
    final time = _confirmedAt;
    final receivedAt = _confirmedServerAt;
    final observed = last != null &&
            receivedAt != null &&
            _confirmedTimestamp == last.millisecondsSinceEpoch &&
            last.isAfter(receivedAt)
        ? receivedAt
        : last;
    ageLabel.value = relativeLabel(observed, now: serverNow);
    online.value = last != null &&
        last.millisecondsSinceEpoch == _confirmedTimestamp &&
        _plausible(last.millisecondsSinceEpoch) &&
        serverNow.difference(last) < deviceStaleAfter &&
        time != null &&
        !_clock().difference(time).isNegative &&
        _clock().difference(time) < deviceStaleAfter;
  }

  static String relativeLabel(DateTime? time, {DateTime? now}) {
    if (time == null) return 'never';
    final age = (now ?? DateTime.now()).difference(time);
    if (age.inSeconds < 5) return 'just now';
    if (age.inSeconds < 60) return '${age.inSeconds} s ago';
    if (age.inMinutes < 60) {
      return '${age.inMinutes} ${age.inMinutes == 1 ? 'min' : 'mins'} ago';
    }
    if (age.inHours < 24) {
      return '${age.inHours} ${age.inHours == 1 ? 'hour' : 'hours'} ago';
    }
    if (age.inDays > 365) return 'over a year ago';
    return '${age.inDays} ${age.inDays == 1 ? 'day' : 'days'} ago';
  }

  void dispose() {
    _started = false;
    _generation++;
    _tick?.cancel();
    _serverGrace?.cancel();
    _retry?.cancel();
    unawaited(_connection?.cancel());
    unawaited(_network?.cancel());
    unawaited(_offsets?.cancel());
    unawaited(_current?.cancel());
    unawaited(_history?.cancel());
    if (_production) WidgetsBinding.instance.removeObserver(this);
  }
}

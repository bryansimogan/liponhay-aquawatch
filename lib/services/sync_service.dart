import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Requires the phone's database link AND advancing, recent ESP32 readings.
/// Neither a network interface nor a cached Firebase event proves device life.
class SyncService with WidgetsBindingObserver {
  SyncService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  static final SyncService instance = SyncService();
  static const deviceStaleAfter = Duration(seconds: 60);
  static const _maxDeviceClockLead = Duration(minutes: 5);
  static const _lastSyncedKey = 'last_synced_at';
  static final _minPlausibleMs = DateTime.utc(2020).millisecondsSinceEpoch;
  final DateTime Function() _clock;
  final online = ValueNotifier<bool>(false);
  final phoneOnline = ValueNotifier<bool>(false);
  final lastSynced = ValueNotifier<DateTime?>(null);
  StreamSubscription<bool>? _connSub;
  StreamSubscription<bool>? _networkSub;
  StreamSubscription<Duration>? _serverTimeSub;
  StreamSubscription<int?>? _deviceSub;
  Timer? _staleCheck;
  bool _started = false;
  bool _firebaseConnected = false;
  bool? _networkAvailable;
  bool _observingLifecycle = false;
  int _generation = 0;
  int _networkRevision = 0;
  int _lastDeviceTimestampMs = 0;
  DateTime? _lastDeviceContact;
  Duration _serverTimeOffset = Duration.zero;
  DateTime get _serverNow => _clock().add(_serverTimeOffset);

  /// Streams can be supplied for deterministic connection/freshness tests.
  Future<void> start({
    Stream<bool>? connections,
    Stream<bool>? networkAvailability,
    Stream<int?>? deviceTimestamps,
    Stream<Duration>? serverTimeOffsets,
  }) async {
    if (_started) return;
    _started = true;
    final generation = ++_generation;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getInt(_lastSyncedKey);
      if (!_started || generation != _generation) return;
      if (cached != null &&
          _plausible(cached) &&
          cached > (lastSynced.value?.millisecondsSinceEpoch ?? 0)) {
        lastSynced.value = DateTime.fromMillisecondsSinceEpoch(cached);
        _lastDeviceTimestampMs = cached;
      }
    } catch (_) {/* Cache must never prevent connection tracking. */}
    if (!_started || generation != _generation) return;

    final database = connections == null ? FirebaseDatabase.instance : null;
    final network = networkAvailability ??
        Connectivity().onConnectivityChanged.map(_hasNetwork);
    _networkSub = network.listen((available) {
      _networkRevision++;
      _networkAvailable = available;
      if (!available) invalidateDevice();
      _recompute();
    }, onError: (_) {
      _networkRevision++;
      _recompute();
    });
    _connSub = (connections ??
            database!
                .ref('.info/connected')
                .onValue
                .map((event) => event.snapshot.value == true))
        .listen((connected) {
      _firebaseConnected = connected;
      if (!connected) invalidateDevice();
      _recompute();
    }, onError: (_) {
      _firebaseConnected = false;
      invalidateDevice();
    });
    _serverTimeSub = (serverTimeOffsets ??
            database?.ref('.info/serverTimeOffset').onValue.map((event) =>
                Duration(
                    milliseconds:
                        (event.snapshot.value as num?)?.toInt() ?? 0)))
        ?.listen((offset) {
      _serverTimeOffset = offset;
      _recompute();
    }, onError: (Object _) {});
    // Watch the timestamp directly, even while another tab is open. Sensor
    // validation and disk writes on the reading stream cannot delay presence.
    _deviceSub = (deviceTimestamps ??
            database?.ref('ponds/pond1/current/timestamp').onValue.map((event) {
              final value = event.snapshot.value;
              return value is num && value.isFinite ? value.toInt() : null;
            }))
        ?.listen((timestamp) {
      if (timestamp == null) {
        invalidateDevice();
      } else {
        markDeviceSeen(timestamp);
      }
    }, onError: (Object _) => invalidateDevice(), onDone: invalidateDevice);
    if (networkAvailability == null) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
      unawaited(_checkNetwork(generation));
    }
    _staleCheck = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    _recompute();
  }

  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((value) => value != ConnectivityResult.none);

  Future<void> _checkNetwork(int generation) async {
    final revision = ++_networkRevision;
    try {
      final results = await Connectivity().checkConnectivity();
      if (!_started ||
          generation != _generation ||
          revision != _networkRevision) {
        return;
      }
      _networkAvailable = _hasNetwork(results);
    } catch (_) {
      if (!_started ||
          generation != _generation ||
          revision != _networkRevision) {
        return;
      }
      // Keep the previous network observation. Firebase still reports
      // whether the database is reachable if the platform check fails.
    }
    if (_networkAvailable == false) invalidateDevice();
    _recompute();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _started) {
      // Android can suspend connectivity broadcasts in the background.
      _recompute();
      unawaited(_checkNetwork(_generation));
    }
  }

  bool _plausible(int timestamp) =>
      timestamp >= _minPlausibleMs &&
      timestamp <= _serverNow.add(_maxDeviceClockLead).millisecondsSinceEpoch;

  void markDeviceSeen(int timestamp) {
    if (!_plausible(timestamp)) {
      invalidateDevice();
      return;
    }
    if (timestamp == _lastDeviceTimestampMs) return;
    final seen = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final age = _serverNow.difference(seen);
    final previous = lastSynced.value;
    if (timestamp < _lastDeviceTimestampMs &&
        (age >= deviceStaleAfter ||
            (previous != null &&
                _plausible(_lastDeviceTimestampMs) &&
                !_serverNow.isAfter(previous.add(deviceStaleAfter))))) {
      return;
    }
    _lastDeviceTimestampMs = timestamp;
    lastSynced.value = seen;
    unawaited(SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt(_lastSyncedKey, timestamp))
        .catchError((_) => false));
    // Connection and data events can arrive in either order on reconnect.
    // Retain fresh evidence and let the combined status gate its display.
    _lastDeviceContact = age < deviceStaleAfter ? _clock() : null;
    _recompute();
  }

  void invalidateDevice() {
    _lastDeviceContact = null;
    _recompute();
  }

  /// Also used when resuming and by tests that advance the injected clock.
  void refresh() => _recompute();

  void _recompute() {
    final connected = _networkAvailable != false && _firebaseConnected;
    final now = _clock();
    final contact = _lastDeviceContact;
    final sample = lastSynced.value;
    final fresh = contact != null &&
        sample != null &&
        !now.difference(contact).isNegative &&
        now.difference(contact) < deviceStaleAfter &&
        _serverNow.difference(sample) < deviceStaleAfter &&
        _plausible(sample.millisecondsSinceEpoch);
    // Clear device first so no intermediate UI rebuild can claim a sync.
    online.value = connected && fresh;
    phoneOnline.value = connected;
  }

  void dispose() {
    _started = false;
    _generation++;
    unawaited(_connSub?.cancel());
    unawaited(_networkSub?.cancel());
    unawaited(_serverTimeSub?.cancel());
    unawaited(_deviceSub?.cancel());
    _staleCheck?.cancel();
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    _observingLifecycle = false;
    _firebaseConnected = false;
    _networkAvailable = null;
    invalidateDevice();
  }

  /// "just now", "12 mins ago", "3 hours ago", "2 days ago".
  static String relativeLabel(DateTime? time) {
    if (time == null) return 'never';
    final diff = DateTime.now().difference(time);
    // A device or phone clock that is slightly ahead makes the difference
    // negative; that is still "just now", never a negative age.
    if (diff.isNegative) return 'just now';
    // A defensive cap: with the timestamp guards above this should never fire,
    // but no path can ever print "27000 days ago" again.
    if (diff.inDays > 365) return 'over a year ago';
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes.clamp(1, 59);
      return '$m ${m == 1 ? "min" : "mins"} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ${h == 1 ? "hour" : "hours"} ago';
    }
    final d = diff.inDays;
    return '$d ${d == 1 ? "day" : "days"} ago';
  }
}

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
  static const _lastSyncedKey = 'last_synced_at';
  static final _minPlausibleMs = DateTime.utc(2020).millisecondsSinceEpoch;
  final DateTime Function() _clock;
  final online = ValueNotifier<bool>(false);
  final phoneOnline = ValueNotifier<bool>(false);
  final lastSynced = ValueNotifier<DateTime?>(null);
  StreamSubscription<bool>? _connSub;
  StreamSubscription<bool>? _networkSub;
  Timer? _staleCheck;
  bool _started = false;
  bool _firebaseConnected = false;
  bool _networkAvailable = false;
  bool _observingLifecycle = false;
  int _generation = 0;
  int _networkRevision = 0;
  int _lastDeviceTimestampMs = 0;
  DateTime? _lastDeviceContact;

  /// Streams can be supplied for deterministic connection/freshness tests.
  Future<void> start(
      {Stream<bool>? connections, Stream<bool>? networkAvailability}) async {
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

    final network = networkAvailability ??
        Connectivity().onConnectivityChanged.map(_hasNetwork);
    _networkSub = network.listen((available) {
      _networkRevision++;
      _networkAvailable = available;
      if (!available) invalidateDevice();
      _recompute();
    }, onError: (_) {
      _networkRevision++;
      _networkAvailable = false;
      invalidateDevice();
    });
    _connSub = (connections ??
            FirebaseDatabase.instance
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
    final revision = _networkRevision;
    try {
      final results = await Connectivity().checkConnectivity();
      if (!_started ||
          generation != _generation ||
          revision != _networkRevision) return;
      _networkAvailable = _hasNetwork(results);
    } catch (_) {
      if (!_started ||
          generation != _generation ||
          revision != _networkRevision) return;
      _networkAvailable = false;
    }
    if (!_networkAvailable) invalidateDevice();
    _recompute();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _started) {
      // Android can suspend connectivity broadcasts in the background.
      _networkAvailable = false;
      invalidateDevice();
      unawaited(_checkNetwork(_generation));
    }
  }

  bool _plausible(int timestamp) =>
      timestamp >= _minPlausibleMs &&
      timestamp <=
          _clock().add(const Duration(seconds: 5)).millisecondsSinceEpoch;

  void markDeviceSeen(int timestamp) {
    if (!_plausible(timestamp)) {
      invalidateDevice();
      return;
    }
    // Multiple subscribers and offline cache replays must not renew contact.
    if (timestamp <= _lastDeviceTimestampMs) return;
    _lastDeviceTimestampMs = timestamp;
    final seen = DateTime.fromMillisecondsSinceEpoch(timestamp);
    lastSynced.value = seen;
    unawaited(SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt(_lastSyncedKey, timestamp))
        .catchError((_) => false));
    final age = _clock().difference(seen);
    if (_firebaseConnected && _networkAvailable && age <= deviceStaleAfter) {
      _lastDeviceContact = _clock();
    } else {
      _lastDeviceContact = null;
    }
    _recompute();
  }

  void invalidateDevice() {
    _lastDeviceContact = null;
    _recompute();
  }

  /// Also used when resuming and by tests that advance the injected clock.
  void refresh() => _recompute();

  void _recompute() {
    final connected = _networkAvailable && _firebaseConnected;
    final now = _clock();
    final contact = _lastDeviceContact;
    final sample = lastSynced.value;
    final fresh = contact != null &&
        sample != null &&
        !now.difference(contact).isNegative &&
        now.difference(contact) <= deviceStaleAfter &&
        now.difference(sample) <= deviceStaleAfter &&
        sample.difference(now) <= const Duration(seconds: 5);
    // Clear device first so no intermediate UI rebuild can claim a sync.
    online.value = connected && fresh;
    phoneOnline.value = connected;
  }

  void dispose() {
    _started = false;
    _generation++;
    unawaited(_connSub?.cancel());
    unawaited(_networkSub?.cancel());
    _staleCheck?.cancel();
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    _observingLifecycle = false;
    _firebaseConnected = false;
    _networkAvailable = false;
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

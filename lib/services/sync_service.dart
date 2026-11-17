import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the ESP32 itself is actually online, not just whether the
/// phone has a connection to Firebase.
///
/// The "current" reading node only gets overwritten by the device when it
/// truly has a network link — while offline the ESP32 just buffers readings
/// in memory (see the sketch's `dataBuffer`), so the node's `timestamp` stops
/// advancing the moment the device drops. That makes it a reliable proxy for
/// device liveness: if `.info/connected` is fine (the phone has internet) but
/// that timestamp is stale, the ESP32 — not the app — is the one offline, and
/// this must still report "Offline" rather than trusting the cached data.
///
/// Widgets listen via [online] and [lastSynced]; both are [ValueNotifier]s
/// so a `ValueListenableBuilder` rebuilds only the small status chip.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _lastSyncedKey = 'last_synced_at';

  /// Timestamps before this are not real wall-clock time.
  ///
  /// The ESP32 stamps a reading with epoch milliseconds only once its clock is
  /// NTP-set. Before that it sends 0 (or, on older firmware, a tiny
  /// millis()-based value) — as a date that is 1970, which the age label
  /// rendered as "27000 days ago" and which pinned the device permanently
  /// "offline". Anything earlier than 2020 is treated as no real time.
  static final int _minPlausibleMs = DateTime.utc(2020).millisecondsSinceEpoch;

  /// How long without a fresh reading before the device counts as offline.
  ///
  /// Judged from when the app last RECEIVED an update, not the device's own
  /// timestamp — a controller whose NTP clock lags the phone by a few seconds
  /// was being flagged "quiet" while it was really pushing fine. The window is
  /// The current firmware publishes about once a second, but one emergency
  /// SMS can occupy the SIM800L for up to 36 seconds and a slow Firebase
  /// request can take 15 seconds. This covers one legitimate alert cycle.
  static const deviceStaleAfter = Duration(seconds: 60);

  /// True while the ESP32 is both reachable AND has reported recently
  /// (simulation always reports true — there's no device to lose).
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  /// True while THIS PHONE can reach the database.
  ///
  /// Separate from [online] on purpose: they fail for different reasons and
  /// call for different actions. The phone loses its link when WiFi drops or
  /// a prepaid SIM runs out of data — something the person holding it can
  /// fix. The device goes quiet when the controller at the pond loses power
  /// or WiFi — something only a trip to the pond can fix. One chip saying
  /// "Offline" for both left no way to tell which had happened.
  final ValueNotifier<bool> phoneOnline = ValueNotifier<bool>(true);

  /// Timestamp of the last reading actually taken by the device (from its
  /// own `timestamp` field), not when the phone happened to receive it —
  /// so a buffered reading that arrives late still shows its real age.
  final ValueNotifier<DateTime?> lastSynced = ValueNotifier<DateTime?>(null);

  StreamSubscription<DatabaseEvent>? _connSub;
  Timer? _staleCheck;
  bool _started = false;
  bool _simMode = true;
  bool _firebaseConnected = false;

  /// Receipt time of the last LIVE controller event. This is intentionally
  /// separate from both sensor values and the ESP32's wall clock.
  DateTime? _lastDeviceContact;

  /// Begins tracking. Safe to call more than once — repeat calls are ignored,
  /// so use [restart] when the data source changes.
  Future<void> start({required bool simMode}) async {
    if (_started) return;
    _started = true;
    _simMode = simMode;

    // Restore the last known sync time so an offline cold start can still
    // say "last synced 12 mins ago" instead of showing nothing.
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedMs = prefs.getInt(_lastSyncedKey);
      // Ignore a cached value that predates 2020 — a bad timestamp saved by an
      // older build must not resurface as "27000 days ago" on cold start.
      if (storedMs != null && storedMs >= _minPlausibleMs) {
        lastSynced.value = DateTime.fromMillisecondsSinceEpoch(storedMs);
      }
    } catch (_) {
      // No cached timestamp available — the label just reads "never" until
      // the first sync lands.
    }

    if (simMode) {
      online.value = true;
      phoneOnline.value = true;
      markSynced();
    } else {
      try {
        _connSub = FirebaseDatabase.instance
            .ref('.info/connected')
            .onValue
            .listen((event) {
          _firebaseConnected = event.snapshot.value == true;
          _recompute();
        }, onError: (_) {
          _firebaseConnected = false;
          _recompute();
        });
      } catch (_) {
        _firebaseConnected = false;
      }
      // The device going quiet doesn't fire any Firebase event on its own —
      // nothing else would notice the reading has gone stale — so poll for
      // that separately from whatever triggers `.info/connected` or a new
      // reading.
      _staleCheck = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _recompute(),
      );
      _recompute();
    }
  }

  /// Re-subscribes for a new data source. Call this after the simulation-mode
  /// toggle changes, otherwise the status keeps reflecting the old source —
  /// simulation always reports connected, so a real outage would go unnoticed.
  Future<void> restart({required bool simMode}) async {
    final subscription = _connSub;
    _connSub = null;
    unawaited(subscription?.cancel().catchError((Object _) {}));
    _staleCheck?.cancel();
    _staleCheck = null;
    _started = false;
    _firebaseConnected = false;
    _lastDeviceContact = null;
    lastSynced.value = null;
    // Simulation has no link to lose; real mode is unknown until the
    // `.info/connected` listener and the next reading report in.
    online.value = simMode;
    phoneOnline.value = simMode;
    await start(simMode: simMode);
  }

  /// Records that data just arrived, timestamped by the phone's own clock.
  /// Used by simulation mode, where there's no device clock to defer to.
  void markSynced() {
    final now = DateTime.now();
    lastSynced.value = now;
    if (!_simMode) _persist(now.millisecondsSinceEpoch);
    _recompute();
  }

  /// Records a reading actually taken by the ESP32, timestamped by the
  /// device's own clock (NTP-synced) rather than when the phone received it.
  /// A reading buffered while offline and flushed later still shows its true
  /// age instead of looking live just because it arrived this second.
  void markDeviceSeen(int deviceTimestampMs) {
    final now = DateTime.now();
    _lastDeviceContact = now;
    final latestPlausible =
        now.add(const Duration(minutes: 5)).millisecondsSinceEpoch;

    // Firebase immediately emits the last stored value, even when the ESP32
    // is already off. Preserve a valid device timestamp so that cached value
    // cannot turn into a fake new sync. Pre-NTP (1970) and implausibly future
    // timestamps fall back to receipt time so older firmware remains usable.
    final seen = deviceTimestampMs >= _minPlausibleMs &&
            deviceTimestampMs <= latestPlausible
        ? DateTime.fromMillisecondsSinceEpoch(deviceTimestampMs)
        : now;
    lastSynced.value = seen;
    _persist(seen.millisecondsSinceEpoch);
    _recompute();
  }

  void _persist(int epochMs) {
    // Caching the timestamp is a convenience for the next cold start; if the
    // write fails the in-memory value is still correct, so never let it throw.
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_lastSyncedKey, epochMs))
        .catchError((_) => false);
  }

  void _recompute() {
    if (_simMode) {
      phoneOnline.value = true;
      online.value = true;
      return;
    }
    phoneOnline.value = _firebaseConnected;

    // Firebase can stay connected after the ESP32 is powered off. Only call
    // the controller synced while an actual device reading is still fresh;
    // otherwise the UI shows the age of the last sync instead of "Synced".
    final contact = _lastDeviceContact;
    final fresh = contact != null &&
        DateTime.now().difference(contact) <= deviceStaleAfter;
    online.value = _firebaseConnected && fresh;
  }

  /// Only for the demo build's offline/online showcase.
  void setOnline(bool value) {
    online.value = value;
    phoneOnline.value = value;
    if (value) markSynced();
  }

  void dispose() {
    _connSub?.cancel();
    _staleCheck?.cancel();
    _started = false;
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

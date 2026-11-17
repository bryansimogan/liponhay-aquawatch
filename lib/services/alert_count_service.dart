import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_record.dart';
import 'firebase_service.dart';
import 'simulation_service.dart';

/// The number on the header's bell, held in one place.
///
/// Each screen used to work this out for itself, and only the Dashboard
/// actually did — so the badge showed a count there and vanished the moment
/// you opened History or Mortality. The alerts had not gone anywhere; the
/// other headers simply had nothing to show.
///
/// One subscription now feeds every header. Navigating changes which screen
/// is drawn, not what the badge knows.
class AlertCountService {
  AlertCountService._();
  static final AlertCountService instance = AlertCountService._();

  final ValueNotifier<int> count = ValueNotifier<int>(0);

  // Built on first use, not in the field initialiser. AppHeader reads this
  // singleton on every screen, and constructing FirebaseService touches
  // FirebaseDatabase.instance — which throws if Firebase has not been
  // initialised yet. Lazily means the header is safe to build anywhere,
  // including in a widget test with no Firebase at all.
  FirebaseService? _firebase;
  final SimulationService _sim = SimulationService();

  StreamSubscription? _sub;
  bool _started = false;

  /// Alerts at or before this time have been read; the badge counts only newer
  /// ones. "Mark all read" pushes this to now, so the badge clears without
  /// deleting anything. Persisted so it survives a restart.
  static const _readAtKey = 'alerts_read_at';
  int _readAtMs = 0;

  /// The last list received, kept so the count can be recomputed the moment
  /// "read all" moves the read cursor, without waiting for the next stream tick.
  List<AlertRecord> _latest = const [];

  /// Begins tracking. Repeat calls are ignored, so the first screen to open
  /// starts it and the rest simply read the value; use [restart] when the
  /// data source changes.
  void start({required bool simMode}) {
    if (_started) return;
    _started = true;
    _listen(simMode);
  }

  /// Re-subscribes against a different data source, for the simulation
  /// toggle in Settings.
  void restart({required bool simMode}) {
    _sub?.cancel();
    _sub = null;
    _started = true;
    _listen(simMode);
  }

  void _listen(bool simMode) async {
    // Load the read cursor before counting, so the badge starts at the right
    // number instead of flashing the full total then dropping.
    try {
      final prefs = await SharedPreferences.getInstance();
      _readAtMs = prefs.getInt(_readAtKey) ?? 0;
    } catch (_) {
      _readAtMs = 0;
    }

    if (simMode) {
      _latest = _sim.generateAlerts();
      count.value = _unread(_latest);
      return;
    }

    try {
      _firebase ??= FirebaseService();
      _sub = _firebase!.alertsStream().listen(
        (list) {
          _latest = list;
          count.value = _unread(list);
        },
        // A read failure leaves the previous count alone rather than
        // dropping the badge to zero, which would read as "all clear".
        onError: (_) {},
      );
    } catch (_) {
      // Same reasoning: keep whatever was last known.
    }
  }

  /// How many alerts are newer than the read cursor.
  int _unread(List<AlertRecord> list) =>
      list.where((a) => a.timestamp > _readAtMs).length;

  /// Marks every current alert as read: the badge clears, but the alerts stay
  /// in the list. Anything that arrives later counts again.
  Future<void> markAllRead() async {
    _readAtMs = DateTime.now().millisecondsSinceEpoch;
    count.value = _unread(_latest);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_readAtKey, _readAtMs);
    } catch (_) {
      // In-memory value already applied; persistence is a convenience.
    }
  }

  /// Whether a given alert is still unread, for the per-row "new" dot.
  bool isUnread(AlertRecord a) => a.timestamp > _readAtMs;

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/incident.dart';
import '../models/gsm_config.dart';
import '../models/app_notification.dart';
import '../models/sensor_data.dart';
import '../models/mortality_analysis.dart';
import '../models/water_quality.dart';
import '../data/response_content.dart';
import 'firebase_service.dart';
import 'i18n.dart';
import 'sync_service.dart';

/// A locally-logged fish death, used by the response centre and reports. Kept
/// separate from the Firebase [MortalityRecord] so the ported features work
/// fully offline for the demo and defense.
class MortLog {
  final int n;
  final String cause;
  final int t;

  /// Snapshot of the readings when logged, e.g. "DO 2.57 mg/L · pH 7.99 · 29.8 °C".
  final String snap;

  const MortLog(
      {required this.n, required this.cause, required this.t, this.snap = ''});

  Map<String, dynamic> toMap() => {'n': n, 'c': cause, 't': t, 'r': snap};
  factory MortLog.fromMap(Map<dynamic, dynamic> m) => MortLog(
        n: (m['n'] as num?)?.toInt() ?? 0,
        cause: (m['c'] as String?) ?? '',
        t: (m['t'] as num?)?.toInt() ?? 0,
        snap: (m['r'] as String?) ?? '',
      );
}

/// Central application store, ported from the AquaWatch prototype's `S` state
/// plus its live simulation + incident state machine.
///
/// Owns the live readings (pH, temperature, dissolved oxygen), drives them with
/// a simulation the demo panel can steer, opens and verifies incidents, and
/// keeps the owner-entered data (harvest, stocking, promo, mortality, language)
/// persisted to [SharedPreferences].
class AppStore extends ChangeNotifier {
  AppStore({required this.simulation, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const verificationPeriod = Duration(minutes: 10);
  final DateTime Function() _clock;
  Duration _demoOffset = Duration.zero;
  int get nowMs => _clock().add(_demoOffset).millisecondsSinceEpoch;

  final bool simulation;
  static const _demoPrefsKey = 'aqua_store_v1';
  static const _livePrefsKey = 'aqua_store_live_v1';
  static const _languageKey = 'aqua_language';
  String get _prefsKey => simulation ? _demoPrefsKey : _livePrefsKey;

  // ─── Live readings ──────────────────────────────────────────────
  double ph = 7.99;
  double temp = 29.8;
  double doxy = 6.4;
  int _demoLastReading = 0;
  final _demoReadings = ListQueue<SensorData>();
  Iterable<SensorData> get demoReadings => _demoReadings;
  Timer? _scenario;
  String? demoStage;
  int? _demoPromoExpiry;

  String? get demoPromoStatus {
    final expiry = _demoPromoExpiry;
    if (expiry == null) return null;
    final left = expiry - nowMs;
    if (left <= 0)
      return L('Demo SIM promo expired', 'Expired na ang demo SIM promo');
    final minutes = (left / 60000).ceil();
    return L('Demo SIM promo: ${minutes ~/ 60} h ${minutes % 60} min left',
        'Demo SIM promo: ${minutes ~/ 60} oras ${minutes % 60} minutong natitira');
  }

  void simPromo(Duration expiresIn) {
    if (!simulation) return;
    _demoPromoExpiry = nowMs + expiresIn.inMilliseconds;
    _note(AppNotificationType.promo, L('Demo SIM promo', 'Demo SIM promo'),
        demoPromoStatus!);
    _save();
    notifyListeners();
  }

  SensorData get currentReading => SensorData(
        ph: ph,
        temperature: temp,
        dissolvedOxygen: doxy,
        timestamp: simulation ? _demoLastReading : _lastTimestamp,
      );

  // ─── Owner / incident data ──────────────────────────────────────
  final List<Incident> incidents = [];
  final List<HarvestRecord> harvest = [];
  final List<MortLog> mortality = [];
  final List<AppNotification> notes = [];
  Stocking stock = const Stocking(n: 1000, area: 250, date: '2026-09-20');
  GsmConfig promo = const GsmConfig();

  final _unresolvedParameters = <String>{};
  Timer? _tick;
  Timer? _readingExpiry;
  StreamSubscription<SensorData?>? _liveReadings;
  int _lastTimestamp = 0;
  bool _readingFresh = false;
  bool get hasCurrentReading => simulation || _readingFresh;

  // ─── Lifecycle ──────────────────────────────────────────────────
  Future<void> init() async {
    await _load();
    final prefs = await SharedPreferences.getInstance();
    final selectedLanguage = prefs.getString(_languageKey);
    if (selectedLanguage == 'en' || selectedLanguage == 'tl') {
      appLang = selectedLanguage!;
    }
    if (simulation) {
      _demoLastReading = nowMs;
      _demoReadings.add(currentReading);
      _tick ??= Timer.periodic(
        const Duration(milliseconds: 1800),
        (_) => _sampleDemo(),
      );
    }
  }

  /// Starts after the live app has opened its Firebase session.
  void connectLive({Stream<SensorData?>? readings}) {
    if (simulation || _liveReadings != null) return;
    final stream = readings ?? FirebaseService().currentReadingStream('pond1');
    _liveReadings = stream.listen(
      _onLiveReading,
      onError: (Object _) => _onLiveReading(null),
    );
  }

  void _onLiveReading(SensorData? reading) {
    if (reading == null) {
      _expireReading();
      return;
    }
    final now = _clock();
    final maxAge = SyncService.deviceStaleAfter;
    final age = now.difference(reading.dateTime);
    if (reading.timestamp <= _lastTimestamp ||
        age > maxAge ||
        age < const Duration(minutes: -5)) {
      return;
    }

    if (_lastTimestamp > 0 &&
        reading.timestamp - _lastTimestamp > maxAge.inMilliseconds) {
      _resetVerification();
    }
    _lastTimestamp = reading.timestamp;
    _readingFresh = true;
    _readingExpiry?.cancel();
    _readingExpiry =
        Timer(age.isNegative ? maxAge : maxAge - age, _expireReading);
    SyncService.instance.markDeviceSeen(reading.timestamp);
    ph = reading.ph;
    temp = reading.temperature;
    doxy = reading.dissolvedOxygen;
    _checkReadings(reading.timestamp);
  }

  void _expireReading() {
    if (!_readingFresh) return;
    _readingFresh = false;
    _resetVerification();
    notifyListeners();
  }

  void stopReadings() {
    _tick?.cancel();
    _scenario?.cancel();
    _readingExpiry?.cancel();
    final subscription = _liveReadings;
    _liveReadings = null;
    unawaited(subscription?.cancel().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scenario?.cancel();
    _readingExpiry?.cancel();
    _liveReadings?.cancel();
    super.dispose();
  }

  // ─── Language ───────────────────────────────────────────────────
  String get lang => appLang;
  set lang(String v) {
    final selected = v == 'en' ? 'en' : 'tl';
    appLang = selected;
    unawaited(SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_languageKey, selected))
        .catchError((Object _) => false));
    _save();
    notifyListeners();
  }

  /// Convenience passthrough so widgets can write `store.tr('A','B')`.
  String tr(String en, String tl) => L(en, tl);

  // ─── Readings helpers ───────────────────────────────────────────
  double reading(String p) => switch (p) { 'ph' => ph, 't' => temp, _ => doxy };

  WaterParam _wp(String p) => switch (p) {
        'ph' => WaterParam.ph,
        't' => WaterParam.temperature,
        _ => WaterParam.dissolvedOxygen,
      };

  /// 'ok' | 'warn' | 'crit' for a parameter's current reading.
  String level(String p) {
    final lv = ParamReading.classify(_wp(p), reading(p)).level;
    return switch (lv) { 'safe' => 'ok', 'warning' => 'warn', _ => 'crit' };
  }

  bool get allSafe =>
      hasCurrentReading &&
      openIncidents.isEmpty &&
      level('ph') == 'ok' &&
      level('t') == 'ok' &&
      level('o') == 'ok';

  List<Incident> get openIncidents => incidents.where((i) => i.isOpen).toList();

  int get aliveCount {
    final lost = mortality.fold<int>(0, (a, b) => a + b.n);
    final harv = harvest.fold<int>(0, (a, b) => a + b.n);
    return max(0, stock.n - lost - harv);
  }

  void simProblem(String key, {bool critical = false}) {
    if (!simulation) return;
    switch (key) {
      case 'ph':
        ph = critical ? 10.5 : 9.2;
      case 'pl':
        ph = critical ? 3.8 : 5.8;
      case 't':
        temp = critical ? 36.5 : 33.5;
      case 'tc':
        temp = critical ? 18.5 : 22.5;
      case 'o':
        doxy = critical ? 1.2 : 2.6;
    }
    _sampleDemo();
  }

  void simAction(String key) {
    if (!simulation) return;
    switch (key) {
      case 'fixo':
        doxy = 6.4;
      case 'fixph':
        ph = 7.99;
      case 'fixt':
        temp = 29.8;
    }
    _sampleDemo();
  }

  void simReset() {
    if (!simulation) return;
    _scenario?.cancel();
    demoStage = null;
    ph = 7.99;
    temp = 29.8;
    doxy = 6.4;
    _sampleDemo();
  }

  void simAdvance(Duration elapsed) {
    if (!simulation) return;
    _demoOffset += elapsed;
    _sampleDemo();
  }

  void simScenario(String key) {
    if (!simulation) return;
    simReset();
    final (problem, recovery) = switch (key) {
      'ph' => ('ph', 'fixph'),
      't' => ('t', 'fixt'),
      _ => ('o', 'fixo'),
    };
    final unresolved = key == 'unresolved';
    demoStage =
        L('1/3 Abnormal reading detected', '1/3 May abnormal na reading');
    simProblem(problem, critical: unresolved);
    _scenario = Timer(const Duration(seconds: 12), () {
      if (unresolved) {
        demoStage = L('3/3 Still unsafe after the response window (demo time)',
            '3/3 Hindi pa rin ligtas matapos ang takdang oras (demo)');
        simAdvance(const Duration(hours: 3));
        return;
      }
      demoStage = L('2/3 Back in range. The 10-minute check has started.',
          '2/3 Bumalik sa ligtas na saklaw. Nagsimula ang 10-minutong pag-verify.');
      simAction(recovery);
      _scenario = Timer(const Duration(seconds: 20), () {
        demoStage = L('3/3 Advanced the demo clock by 10 minutes.',
            '3/3 Inabante ang oras ng demo nang 10 minuto.');
        simAdvance(verificationPeriod);
      });
    });
  }

  void _sampleDemo() {
    _demoLastReading = nowMs;
    if (_demoReadings.isNotEmpty &&
        _demoReadings.last.timestamp == _demoLastReading) {
      _demoReadings.removeLast();
    }
    _demoReadings.add(currentReading);
    final cutoff = _demoLastReading - MortalityAnalysis.maxGap.inMilliseconds;
    while (_demoReadings.first.timestamp < cutoff) {
      _demoReadings.removeFirst();
    }
    SyncService.instance.markSynced();
    _checkReadings(_demoLastReading);
  }

  void _checkReadings(int sampledAt) {
    for (final p in const ['ph', 't', 'o']) {
      if (level(p) == 'ok') {
        _unresolvedParameters.remove(p);
      } else if (!_unresolvedParameters.contains(p)) {
        _openIncident(p, sampledAt);
      }
    }
    _verify(sampledAt);
    notifyListeners();
  }

  // ─── Incident machine ───────────────────────────────────────────
  void _openIncident(String p, int sampledAt) {
    if (incidents.any((i) => i.p == p && i.isOpen)) return;
    final v = reading(p);
    final lvl = level(p);
    final title = paramTitle(p, v);
    final w = windowText(paramMeta[p]!.window(lvl));
    incidents.insert(
      0,
      Incident(
        id: sampledAt + const ['o', 'ph', 't'].indexOf(p),
        p: p,
        d0: distance(p, v),
        title: title,
        val: formatReading(p, v),
        ts: sampledAt,
        lvl: lvl,
        sms: simulation,
      ),
    );
    _note(
      AppNotificationType.alert,
      title,
      '${paramMeta[p]!.label} is ${formatReading(p, v)} in Pond 1. '
      '${L('Act within', 'Kumilos sa loob ng')} $w.',
    );
    _save();
  }

  void _autoAction(Incident i, int sampledAt) {
    final name = autoActionFor(i.p);
    i.rem.add(IncidentRemark(
      t: sampledAt,
      action: name,
      note: L('Detected from the sensor readings',
          'Natukoy mula sa mga reading ng sensor'),
    ));
    i.act = true;
    i.st = 'progress';
    i.actAt = sampledAt;
    _note(
      AppNotificationType.history,
      L('Action taken', 'Nagawa na ang aksyon'),
      '$name — ${i.title} (${i.val}).',
    );
  }

  void _resetVerification() {
    final active = openIncidents.where((i) => i.isVerifying).toList();
    if (active.isEmpty) return;
    for (final i in active) {
      i.safeSince = null;
    }
    _save();
  }

  void _verify(int sampledAt) {
    var changed = false;
    for (final i in incidents) {
      if (!i.isOpen) continue;
      final p = i.p;
      final lv = level(p);

      if (lv == 'crit' && i.lvl == 'warn') {
        i.lvl = 'crit';
        changed = true;
      }

      if (!i.act) {
        i.d0 ??= distance(p, reading(p));
        final delta = improvementDelta[p]!;
        if (distance(p, reading(p)) <= i.d0! - delta) {
          i.imp += 1;
          if (i.imp >= 2) {
            _autoAction(i, sampledAt);
            changed = true;
          }
        } else {
          i.imp = 0;
        }
      }

      if (lv == 'ok') {
        final since = i.safeSince;
        if (since == null) {
          i.safeSince = sampledAt;
          changed = true;
          _note(
            AppNotificationType.history,
            L('Back in range · verifying',
                'Bumalik sa ligtas na saklaw · bine-verify'),
            L('The reading must stay in range for 10 minutes.',
                'Kailangang manatiling ligtas ang reading sa loob ng 10 minuto.'),
          );
        } else if (sampledAt - since >= verificationPeriod.inMilliseconds) {
          i.st = 'resolved';
          i.closedAt = sampledAt;
          i.after = formatReading(p, reading(p));
          i.self = !i.act;
          changed = true;
          final msg = '${i.val} → ${i.after}. ${L(
            'Verified after 10 minutes of safe readings.',
            'Na-verify matapos ang 10 minutong ligtas na readings.',
          )}';
          i.rem.add(IncidentRemark(t: sampledAt, note: msg));
          _note(
            AppNotificationType.history,
            L('Resolved · verified safe', 'Naresolba · na-verify na ligtas'),
            msg,
          );
        }
      } else {
        if (i.isVerifying) {
          i.safeSince = null;
          changed = true;
          _note(
            AppNotificationType.alert,
            L('Unsafe again · verification reset',
                'Hindi ligtas muli · na-reset ang pag-verify'),
            paramMeta[p]!.label,
          );
        }
        final latest = paramMeta[p]!.window(i.lvl)[1] * 60000;
        if (sampledAt > i.ts + latest) {
          i.st = 'unresolved';
          _unresolvedParameters.add(p);
          i.closedAt = sampledAt;
          changed = true;
          final msg =
              '${paramMeta[p]!.label} ${L('is still', 'ay nananatiling')} '
              '${formatReading(p, reading(p))} ${L('after the response window', 'matapos ang itinakdang oras')}.';
          i.rem.add(IncidentRemark(
              t: sampledAt,
              note: '${L('Not resolved', 'Hindi naresolba')}: $msg'));
          _note(AppNotificationType.alert, L('Not resolved', 'Hindi naresolba'),
              msg);
        }
      }
    }
    if (changed) _save();
  }

  // ─── Owner actions ──────────────────────────────────────────────
  void logMortality(int n) {
    final sc = _suspectedCause();
    mortality.insert(
        0,
        MortLog(
            n: n,
            cause: sc,
            t: DateTime.now().millisecondsSinceEpoch,
            snap:
                'DO ${doxy.toStringAsFixed(2)} mg/L · pH ${ph.toStringAsFixed(2)} · ${temp.toStringAsFixed(1)} °C'));
    _note(AppNotificationType.alert, L('Fish died', 'Namatay na isda'),
        '$n ${L('fish died', 'isda ang namatay')}. ${L('Suspected cause', 'Posibleng sanhi')}: $sc.');
    _save();
    notifyListeners();
  }

  String _suspectedCause() {
    final out = <String>[];
    for (final p in const ['o', 't', 'ph']) {
      if (level(p) != 'ok') {
        out.add(
            '${paramTitle(p, reading(p))} (${levelName(level(p))} · ${formatReading(p, reading(p))})');
      }
    }
    return out.isEmpty
        ? L('No abnormal water reading — possible disease or infection',
            'Normal ang tubig — posibleng sakit o impeksiyon')
        : out.join(' + ');
  }

  void addHarvest(HarvestRecord h) {
    harvest.insert(0, h);
    _note(
        AppNotificationType.history,
        L('Harvest logged', 'Naitala ang harvest'),
        '${h.n} ${L('fish', 'isda')} · ${h.kg.toStringAsFixed(1)} kg');
    _save();
    notifyListeners();
  }

  void removeHarvest(int id) {
    harvest.removeWhere((h) => h.id == id);
    _save();
    notifyListeners();
  }

  void setPromo(GsmConfig p) {
    promo = p;
    _save();
    notifyListeners();
  }

  void markNoteRead(String id) {
    final index = notes.indexWhere((note) => note.id == id && !note.read);
    if (index < 0) return;
    notes[index] = notes[index].copyWith(read: true);
    _save();
    notifyListeners();
  }

  void markNotesSeen() {
    for (var i = 0; i < notes.length; i++) {
      if (!notes[i].read) notes[i] = notes[i].copyWith(read: true);
    }
    _save();
    notifyListeners();
  }

  int get unseenNotes => notes.where((n) => !n.read).length;

  void _note(AppNotificationType type, String title, String body) {
    notes.insert(
      0,
      AppNotification(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        title: title,
        body: body,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (notes.length > 60) notes.removeRange(60, notes.length);
  }

  // ─── Persistence ────────────────────────────────────────────────
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'lang': appLang,
        'inc': incidents.map((i) => i.toMap()).toList(),
        'harv': harvest.map((h) => h.toMap()).toList(),
        'mort': mortality.map((m) => m.toMap()).toList(),
        'notes': notes.map((n) => n.toMap()).toList(),
        'stock': stock.toMap(),
        'promo': promo.toMap(),
      };
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (_) {/* best-effort */}
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) {
        if (simulation) {
          _seed();
        } else {
          // The old store generated incidents and mortality records from demo
          // data. Carry over the operator's language, stocking, and harvest.
          final previous = prefs.getString(_demoPrefsKey);
          if (previous != null) {
            final old = jsonDecode(previous) as Map<String, dynamic>;
            _loadFarmDetails(old);
          }
        }
        return;
      }
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _loadFarmDetails(m);
      incidents
        ..clear()
        ..addAll(
            ((m['inc'] as List?) ?? []).map((e) => Incident.fromMap(e as Map)));
      for (final incident in openIncidents) {
        incident.safeSince = null;
      }
      mortality
        ..clear()
        ..addAll(
            ((m['mort'] as List?) ?? []).map((e) => MortLog.fromMap(e as Map)));
      notes
        ..clear()
        ..addAll(((m['notes'] as List?) ?? [])
            .map((e) => AppNotification.fromMap(Map<String, dynamic>.from(e))));
      if (m['promo'] != null) promo = GsmConfig.fromMap(m['promo'] as Map);
    } catch (_) {
      if (simulation) _seed();
    }
  }

  void _loadFarmDetails(Map<String, dynamic> data) {
    appLang = (data['lang'] as String?) == 'en' ? 'en' : 'tl';
    harvest
      ..clear()
      ..addAll(((data['harv'] as List?) ?? [])
          .map((entry) => HarvestRecord.fromMap(entry as Map)));
    if (data['stock'] != null) stock = Stocking.fromMap(data['stock'] as Map);
  }

  /// First-run seed so the response centre and reports are not empty.
  void _seed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    stock = Stocking(n: 1000, area: 250, date: '${DateTime.now().year}-09-20');
    promo = GsmConfig.promo(name: 'AllNetSurf10', days: 1);
    mortality
      ..clear()
      ..add(MortLog(
          n: 3,
          cause: L('Disease / infection', 'Sakit / impeksiyon'),
          t: now - 6 * 3600000,
          snap: 'DO 2.57 mg/L · pH 7.99 · 29.8 °C'));
    // One already-resolved high-pH incident so history/reports read true.
    incidents
      ..clear()
      ..add(Incident(
        id: now - 7200000,
        p: 'ph',
        title: L('High pH', 'Mataas na pH'),
        val: '8.90',
        ts: now - 7200000,
        lvl: 'warn',
        st: 'resolved',
        act: true,
        actAt: now - 6900000,
        closedAt: now - 6240000,
        after: '8.10',
        rem: [
          IncidentRemark(
              t: now - 6900000,
              action:
                  L('Partial water change', 'Bahagyang pagpapalit ng tubig')),
          IncidentRemark(
              t: now - 6240000,
              note: L('Auto-verified: pH 8.90 → 8.10 after the action.',
                  'Awtomatikong na-verify: pH 8.90 → 8.10 matapos ang aksyon.')),
        ],
      ));
  }
}

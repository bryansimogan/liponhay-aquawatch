import 'package:firebase_database/firebase_database.dart';
import '../models/sensor_data.dart';
import '../models/mortality_record.dart';
import '../models/mortality_analysis.dart';
import '../models/gsm_config.dart';
import '../models/incident.dart';
import '../models/management_logs.dart';
import 'offline_cache_service.dart';
import 'sync_service.dart';

/// Service layer for all Firebase Realtime Database operations.
class FirebaseService {
  FirebaseService({DatabaseReference? database}) : _database = database;

  final DatabaseReference? _database;
  DatabaseReference get _db => _database ?? FirebaseDatabase.instance.ref();

  // ---- SENSOR DATA ----

  /// Get a real-time stream of the CURRENT reading for a specific pond.
  Stream<SensorData?> currentReadingStream(String pondId) =>
      _db.child('ponds').child(pondId).child('current').onValue.map((event) {
        final data = event.snapshot.value;
        return data is Map ? SensorData.tryFromHistoryMap(data) : null;
      });

  /// The firmware's history keys are epoch timestamps. Watch the recent tail
  /// so a stalled current node cannot hide newer measured readings.
  Stream<List<SensorData>> recentHardwareHistoryStream(String pondId) => _db
      .child('ponds/$pondId/history')
      .orderByKey()
      .limitToLast(200)
      .onValue
      .map((event) => [
            for (final child in event.snapshot.children)
              if (child.value case final Map row)
                if (SensorData.tryFromHistoryMap(row, key: child.key)
                    case final reading?)
                  reading,
          ]..sort((a, b) => a.timestamp.compareTo(b.timestamp)));

  /// Emits only the newest saved History row and then every newer row.
  Stream<SensorData> latestHistoryStream(String pondId) => _db
      .child('ponds')
      .child(pondId)
      .child('history')
      .orderByChild('timestamp')
      .limitToLast(1)
      .onChildAdded
      .map((event) => event.snapshot.value is Map
          ? SensorData.tryFromHistoryMap(event.snapshot.value as Map,
              key: event.snapshot.key)
          : null)
      .where((reading) => reading != null)
      .cast<SensorData>();

  /// Get a one-time snapshot of the current reading.
  Future<SensorData?> getCurrentReading(String pondId) async {
    final cached = await OfflineCacheService.current(pondId);
    if (cached != null) return cached;
    final snap = await _db.child('ponds').child(pondId).child('current').get();
    if (snap.value == null) return null;
    final value = snap.value;
    final reading = value is Map ? SensorData.tryFromHistoryMap(value) : null;
    if (reading != null) await OfflineCacheService.saveCurrent(pondId, reading);
    return reading;
  }

  /// Get historical readings for a pond.
  ///
  /// Pass [since] to bound the window; without it this returns the most recent
  /// [limit] readings whenever they happened. The History screen's range picker
  /// needs the window, because "Today" and "This Month" asking only for
  /// different point counts returned the same recent readings either way — the
  /// picker looked like it worked and changed nothing.
  Future<List<SensorData>> getHistory(
    String pondId, {
    int? limit = 50,
    DateTime? since,
    DateTime? until,
  }) async {
    // Once the connection monitor knows this phone is offline, avoid waiting
    // for a Firebase timeout and open the saved history immediately.
    if (SyncService.instance.serverOnline.value == false) {
      return OfflineCacheService.history(
        pondId,
        since: since,
        until: until,
        limit: limit,
      );
    }

    var query = _historyQuery(pondId, since: since, until: until);
    if (limit != null) query = query.limitToLast(limit);

    try {
      final snap = await query.get().timeout(const Duration(seconds: 6));
      if (snap.value == null) return [];
      final entries = [
        for (final child in snap.children)
          if (child.value case final Map row)
            if (SensorData.tryFromHistoryMap(row) case final SensorData reading)
              reading,
      ];
      entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      await OfflineCacheService.saveHistory(pondId, entries);
      return entries;
    } catch (_) {
      return OfflineCacheService.history(
        pondId,
        since: since,
        until: until,
        limit: limit,
      );
    }
  }

  Query _historyQuery(String pondId, {DateTime? since, DateTime? until}) {
    var query = _db
        .child('ponds')
        .child(pondId)
        .child('history')
        .orderByChild('timestamp');
    if (since != null)
      query = query.startAt(since.millisecondsSinceEpoch.toDouble());
    if (until != null)
      query = query.endAt(until.millisecondsSinceEpoch.toDouble());
    return query;
  }

  Future<List<MortalityReading>> getMortalityHistory(String pondId,
      {required DateTime since, required DateTime until}) async {
    if (SyncService.instance.serverOnline.value != false) {
      try {
        final snapshot = await _historyQuery(pondId, since: since, until: until)
            .get()
            .timeout(const Duration(seconds: 6));
        return [
          for (final child in snapshot.children)
            if (child.value case final Map row)
              if (MortalityReading.fromMap(row)
                  case final MortalityReading reading)
                reading,
        ];
      } catch (_) {
        // Cached readings remain bounded to the event's time window.
      }
    }
    final cached =
        await OfflineCacheService.history(pondId, since: since, until: until);
    return cached
        .map(MortalityReading.fromSensor)
        .whereType<MortalityReading>()
        .toList();
  }

  /// Capture the current device row as well as the event's saved history.
  /// Parse raw rows so missing sensor channels never acquire default values.
  Future<List<MortalityReading>> getMortalityReadings(String pondId,
      {required DateTime eventAt}) async {
    final history = await getMortalityHistory(pondId,
        since: eventAt.subtract(MortalityAnalysis.maxGap), until: eventAt);
    MortalityReading? current;
    if (SyncService.instance.serverOnline.value != false) {
      try {
        final snapshot = await _db
            .child('ponds/$pondId/current')
            .get()
            .timeout(const Duration(seconds: 6));
        if (snapshot.value case final Map row) {
          current = MortalityReading.fromMap(row);
        }
      } catch (_) {
        // A cached sample retains its original device timestamp.
      }
    }
    if (current == null) {
      final cached = await OfflineCacheService.current(pondId);
      if (cached != null) current = MortalityReading.fromSensor(cached);
    }
    return [...history, if (current != null) current];
  }

  Stream<ManagementLogs> managementLogsStream(String pondId) => _db
      .child('ponds/$pondId/management_logs')
      .onValue
      .map((event) => ManagementLogs.fromMap(event.snapshot.value is Map
          ? event.snapshot.value as Map
          : const {}));

  /// The transaction also deduplicates a reading processed by two phones.
  Future<void> recordManagementReading(String pondId, SensorData reading,
      {required List<Incident> initialIncidents}) async {
    await _db.child('ponds/$pondId/management_logs').runTransaction((value) {
      final state = value is Map
          ? ManagementLogs.fromMap(value)
          : ManagementLogs(incidents: initialIncidents);
      if (reading.timestamp <= state.lastReadingAt) return Transaction.abort();
      return Transaction.success(state.receive(reading).toMap());
    }, applyLocally: false);
  }

  String newMortalityId(String pondId) =>
      _db.child('ponds').child(pondId).child('mortality').push().key!;

  Stream<Stocking?> stockingStream(String pondId) => _db
      .child('ponds/$pondId/stocking')
      .onValue
      .map((event) => event.snapshot.value is Map
          ? Stocking.tryFromMap(event.snapshot.value as Map)
          : null);

  Future<void> saveStocking(String pondId, Stocking value) async {
    if (!value.isValid) throw ArgumentError('Invalid stocking information.');
    final result = await _db.child('ponds/$pondId/stocking').runTransaction(
        (current) => Transaction.success({
              if (current is Map) ...Map<String, dynamic>.from(current),
              ...value.toMap(),
            }),
        applyLocally: false);
    if (!result.committed) throw StateError('Stocking was not saved.');
  }

  // ---- FISH MORTALITY ----

  /// Add a mortality record.
  Future<void> addMortalityRecord(MortalityRecord record) async {
    if (record.count <= 0) throw ArgumentError('Enter a positive fish count.');
    final result = await _db
        .child('ponds')
        .child(record.pondId)
        .child('mortality')
        .child(record.id)
        .runTransaction((current) {
      if (current == null) return Transaction.success(record.toMap());
      if (current is Map &&
          current['count'] == record.count &&
          (current['notes'] ?? '') == record.notes) {
        return Transaction.success(current);
      }
      return Transaction.abort();
    }, applyLocally: false);
    if (!result.committed) throw StateError('Mortality record was not saved.');
  }

  /// Update the count while preserving the reported date and evidence.
  Future<void> updateMortalityCount({
    required String pondId,
    required String recordId,
    required int count,
    String? notes,
  }) async {
    if (count <= 0) throw ArgumentError('Enter a positive fish count.');
    final reference =
        _db.child('ponds').child(pondId).child('mortality').child(recordId);
    final saved = await reference.get();
    if (!saved.exists) throw StateError('The mortality record was deleted.');
    final result = await reference.runTransaction((value) {
      if (value is! Map) return Transaction.abort();
      return Transaction.success({
        ...Map<String, dynamic>.from(value),
        'count': count,
        if (notes != null) 'notes': notes,
      });
    }, applyLocally: false);
    if (!result.committed) {
      throw StateError('The mortality record was deleted during the edit.');
    }
  }

  /// Re-files a record under a different pond in one atomic update.
  Future<void> moveMortalityRecord(
    MortalityRecord record, {
    required String fromPondId,
  }) async {
    if (fromPondId == record.pondId) {
      await addMortalityRecord(record);
      return;
    }
    await _db.update({
      'ponds/${record.pondId}/mortality/${record.id}': record.toMap(),
      'ponds/$fromPondId/mortality/${record.id}': null,
    });
  }

  /// Removes a mortality record.
  Future<void> deleteMortalityRecord({
    required String pondId,
    required String recordId,
  }) async {
    await _db
        .child('ponds')
        .child(pondId)
        .child('mortality')
        .child(recordId)
        .remove();
  }

  /// Stream all mortality records for a pond.
  Stream<List<MortalityRecord>> mortalityStream(String pondId) async* {
    final cached = await OfflineCacheService.mortality(pondId);
    if (cached.isNotEmpty) yield cached;

    final remote = _db
        .child('ponds')
        .child(pondId)
        .child('mortality')
        .onValue
        .map((event) {
      if (event.snapshot.value == null) return <MortalityRecord>[];
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      return map.entries
          .map((e) => MortalityRecord.fromMap(e.key, e.value))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
    await for (final records in remote) {
      // An offline Firebase client can emit an empty local snapshot even
      // though our explicit cache contains records. Do not let that temporary
      // empty value erase the last known data.
      if (records.isEmpty &&
          cached.isNotEmpty &&
          SyncService.instance.serverOnline.value == false) {
        continue;
      }
      await OfflineCacheService.saveMortality(pondId, records);
      yield records;
    }
  }

  // ---- SETTINGS ----

  /// Save SMS recipient phone number.
  Future<void> setSmsRecipient(String phone) async {
    await _db.child('settings').child('sms_recipient').set(phone);
    await OfflineCacheService.saveSmsRecipient(phone);
  }

  /// Read SMS recipient phone number.
  Future<String> getSmsRecipient() async {
    try {
      final snap = await _db
          .child('settings')
          .child('sms_recipient')
          .get()
          .timeout(const Duration(seconds: 4));
      final recipient = snap.value as String? ?? '+63XXXXXXXXXX';
      await OfflineCacheService.saveSmsRecipient(recipient);
      return recipient;
    } catch (_) {
      return await OfflineCacheService.smsRecipient() ?? '+63XXXXXXXXXX';
    }
  }

  // ---- GSM / SIM CONFIG ----

  /// Read the SIM's load / promo details.
  Future<GsmConfig> getGsmConfig() async {
    final snap = await _db.child('settings').child('gsm').get();
    if (snap.value == null) return const GsmConfig();
    return GsmConfig.fromMap(Map<dynamic, dynamic>.from(snap.value as Map));
  }

  /// Live stream of the SIM config, so an edit on another device is reflected
  /// without a manual reload.
  Stream<GsmConfig> gsmConfigStream() {
    return _db.child('settings').child('gsm').onValue.map((event) {
      if (event.snapshot.value == null) return const GsmConfig();
      return GsmConfig.fromMap(
          Map<dynamic, dynamic>.from(event.snapshot.value as Map));
    });
  }

  /// Save the SIM's load / promo details.
  Future<void> setGsmConfig(GsmConfig config) async {
    await _db.child('settings').child('gsm').set(config.toMap());
  }
}

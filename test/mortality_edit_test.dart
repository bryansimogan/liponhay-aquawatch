import 'package:firebase_database/firebase_database.dart';
import 'package:fish_farm_app/models/incident.dart';
import 'package:fish_farm_app/models/mortality_record.dart';
import 'package:fish_farm_app/services/firebase_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Snapshot extends Fake implements DataSnapshot {
  _Snapshot(this.exists);
  @override
  final bool exists;
}

class _Result extends Fake implements TransactionResult {
  _Result(this.committed);
  @override
  final bool committed;
}

class _Reference extends Fake implements DatabaseReference {
  _Reference(this.data, {this.deleteAfterRead = false});
  Object? data;
  final bool deleteAfterRead;
  int transactions = 0;
  bool? lastApplyLocally;

  @override
  DatabaseReference child(String path) => this;

  @override
  Future<DataSnapshot> get() async {
    final snapshot = _Snapshot(data != null);
    if (deleteAfterRead) data = null;
    return snapshot;
  }

  @override
  Future<TransactionResult> runTransaction(
      Transaction Function(Object?) handler,
      {bool applyLocally = true}) async {
    transactions++;
    lastApplyLocally = applyLocally;
    final result = handler(data);
    if (!result.aborted) data = result.value;
    return _Result(!result.aborted);
  }
}

void main() {
  Map<String, Object> original() => {
        'date': '2026-11-19',
        'timestamp': 1795050000000,
        'count': 3,
        'notes': 'Original observation',
        'water_analysis': {
          'matched_reading': {'ph': 9.2}
        },
        'additional_metadata': 'Preserve this field',
      };

  test('stocking saves actual counts, fractional area and date atomically',
      () async {
    final reference = _Reference({'additional_metadata': 'keep'});
    final stock = Stocking(n: 600, area: 250.5, date: '2026-11-19');
    await FirebaseService(database: reference).saveStocking('pond1', stock);
    expect(reference.data, {...stock.toMap(), 'additional_metadata': 'keep'});
    expect(reference.transactions, 1);
    expect(Stocking.tryFromMap(reference.data as Map)!.area, 250.5);
  });

  test('invalid stocking values cannot be written to the database', () async {
    final reference = _Reference(null);
    await expectLater(
        FirebaseService(database: reference)
            .saveStocking('pond1', const Stocking(n: -1, area: 0, date: '')),
        throwsArgumentError);
    expect(reference.data, isNull);
    expect(reference.transactions, 0);
    expect(Stocking.tryFromMap({'date': '2026-11-19'}), isNull);
  });

  test('editing count and remarks preserves the original evidence and metadata',
      () async {
    final saved = original();
    final reference = _Reference(saved);
    final service = FirebaseService(database: reference);
    await service.updateMortalityCount(
        pondId: 'pond1', recordId: 'one', count: 5, notes: 'Aerator checked');
    final result = reference.data as Map;
    expect(result['count'], 5);
    expect(result['notes'], 'Aerator checked');
    expect(result['date'], saved['date']);
    expect(result['timestamp'], saved['timestamp']);
    expect(result['water_analysis'], saved['water_analysis']);
    expect(result['additional_metadata'], saved['additional_metadata']);
    expect(saved['count'], 3);
  });

  test(
      'a new positive count is published after commit and a retry keeps one record',
      () async {
    final reference = _Reference(null);
    final service = FirebaseService(database: reference);
    final record = MortalityRecord(
        id: 'one',
        date: '2026-11-19',
        pondId: 'pond1',
        species: 'Tilapia',
        count: 3,
        possibleCause: '',
        timestamp: 1795050000000);
    await service.addMortalityRecord(record);
    expect(reference.lastApplyLocally, isFalse);
    expect(reference.data, record.toMap());
    final saved = reference.data;
    await service.addMortalityRecord(record);
    expect(identical(reference.data, saved), isTrue);
  });

  test('count-only callers retain saved remarks', () async {
    final reference = _Reference(original());
    await FirebaseService(database: reference)
        .updateMortalityCount(pondId: 'pond1', recordId: 'one', count: 4);
    expect((reference.data as Map)['notes'], 'Original observation');
  });

  test('an edit cannot recreate a record deleted before the edit', () async {
    final reference = _Reference(null);
    await expectLater(
        FirebaseService(database: reference)
            .updateMortalityCount(pondId: 'pond1', recordId: 'one', count: 5),
        throwsStateError);
    expect(reference.data, isNull);
    expect(reference.transactions, 0);
  });

  test('an edit cannot recreate a record deleted during the transaction',
      () async {
    final reference = _Reference(original(), deleteAfterRead: true);
    await expectLater(
        FirebaseService(database: reference)
            .updateMortalityCount(pondId: 'pond1', recordId: 'one', count: 5),
        throwsStateError);
    expect(reference.data, isNull);
    expect(reference.transactions, 1);
  });
}

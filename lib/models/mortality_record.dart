import 'mortality_analysis.dart';

/// Model for fish mortality records entered by the farm operator.
class MortalityRecord {
  final String id;
  final String date;
  final String pondId;
  final String species;
  final int count;

  /// Legacy suspected cause, retained for older records and clients.
  final String possibleCause;

  /// Free-text detail the operator adds. Optional.
  final String notes;

  final int timestamp;
  final MortalityAnalysis? analysis;

  MortalityRecord({
    required this.id,
    required this.date,
    required this.pondId,
    required this.species,
    required this.count,
    required this.possibleCause,
    this.notes = '',
    required this.timestamp,
    this.analysis,
  });

  factory MortalityRecord.fromMap(String id, Map<dynamic, dynamic> map) {
    return MortalityRecord(
      id: id,
      date: (map['date'] as String?) ?? '',
      pondId: (map['pond_id'] as String?) ?? 'pond1',
      species: (map['species'] as String?) ?? 'Tilapia',
      count: (map['count'] as num?)?.toInt() ?? 0,
      possibleCause: (map['possible_cause'] as String?) ?? '',
      notes: (map['notes'] as String?) ?? '',
      analysis: map['water_analysis'] is Map
          ? MortalityAnalysis.fromMap(map['water_analysis'] as Map)
          : null,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'pond_id': pondId,
      'species': species,
      'count': count,
      'possible_cause': possibleCause,
      'notes': notes,
      'timestamp': timestamp,
      if (analysis != null) 'water_analysis': analysis!.toMap(),
    };
  }

  /// The species stocked in a given pond.
  ///
  /// The farm raises Tilapia only. This stays a function of the pond rather
  /// than a constant so a second species needs one line here and nothing at
  /// the call sites.
  static String speciesForPond(String pondId) => 'Tilapia';

  /// The date the incident belongs to, for monthly grouping.
  ///
  /// Uses the operator-picked [date] — "when the fish died" — falling back to
  /// [timestamp] (when it was logged) if the date is missing or malformed. The
  /// year and month are derived from this rather than stored, so no field can
  /// disagree with the date and there is nothing to migrate: a September 2026
  /// record and a September 2027 record separate on their own because the year
  /// is read off a real DateTime, never off the bare month name.
  DateTime get when {
    final parsed = DateTime.tryParse(date);
    if (parsed != null) return parsed;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// A date-only legacy entry can use its saved time only on the same day.
  DateTime? get eventAt {
    final day = DateTime.tryParse(date)?.toLocal();
    if (day != null && RegExp(r'[T ]\d{2}:\d{2}').hasMatch(date)) return day;
    if (timestamp <= 0) return null;
    final saved = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (day != null &&
        (day.year != saved.year ||
            day.month != saved.month ||
            day.day != saved.day)) {
      return null;
    }
    return saved;
  }

  int get year => when.year;
  int get month => when.month;

  /// True when this record falls in the given calendar month.
  bool inPeriod(int year, int month) =>
      this.year == year && this.month == month;
}

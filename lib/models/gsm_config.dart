/// The promo on the SIM inside the SIM800L, kept as simply as possible.
///
/// The device sends the SMS alerts; a prepaid SIM whose unli promo has lapsed
/// sends nothing, silently. So the operator enters just two things — the promo
/// name and how many days it runs — and the app counts down on its own from the
/// day it was set. No manual expiry date, no bookkeeping.
///
/// Plain configuration, no Flutter import, so it can be unit-tested on its own.
class GsmConfig {
  final String promoName;

  /// How many days the promo lasts (e.g. an unli-30 is 30).
  final int durationDays;

  /// The day the promo was activated, ISO yyyy-MM-dd. Defaults to the day it
  /// was entered; the expiry is derived from this plus [durationDays].
  final String startDate;

  const GsmConfig({
    this.promoName = '',
    this.durationDays = 0,
    this.startDate = '',
  });

  /// Build a promo that starts today (or [start]) and runs [days] days. This is
  /// the only way the app creates one — the operator never types a date.
  factory GsmConfig.promo({
    required String name,
    required int days,
    DateTime? start,
  }) {
    final s = start ?? DateTime.now();
    return GsmConfig(
      promoName: name,
      durationDays: days,
      startDate: _iso(DateTime(s.year, s.month, s.day)),
    );
  }

  factory GsmConfig.fromMap(Map<dynamic, dynamic> map) {
    return GsmConfig(
      promoName: (map['promo_name'] as String?)?.trim() ?? '',
      durationDays: (map['duration_days'] as num?)?.toInt() ?? 0,
      startDate: (map['start_date'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'promo_name': promoName,
        'duration_days': durationDays,
        'start_date': startDate,
        // Stored for readability on the database side; the app always derives
        // it, so a stale value here is never trusted.
        'expiry_date': _iso(expiry),
      };

  bool get isEmpty => promoName.isEmpty && durationDays <= 0;

  DateTime get _start {
    final d = DateTime.tryParse(startDate);
    final s = d ?? DateTime.now();
    return DateTime(s.year, s.month, s.day);
  }

  /// The last day the promo is valid — start plus its duration.
  DateTime get expiry => _start.add(Duration(days: durationDays));

  /// Whole days from today until the promo lapses. Negative once it has passed.
  /// Computed live from [DateTime.now], so the countdown is never stale.
  int? get daysLeft {
    if (isEmpty) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return expiry.difference(today).inDays;
  }

  /// 'none' | 'ok' | 'soon' | 'urgent' | 'expired' — drives the badge colour.
  String get expiryStatus {
    final d = daysLeft;
    if (d == null) return 'none';
    if (d < 0) return 'expired';
    if (d == 0 || d == 1) return 'urgent';
    if (d <= 3) return 'soon';
    return 'ok';
  }

  /// The reminder line, worded for the time remaining. Recomputed on read.
  String get expiryLabel {
    final d = daysLeft;
    if (d == null) return 'No promo set';
    if (d < 0) {
      final ago = -d;
      return ago == 1
          ? '🚨 Promo expired yesterday'
          : '🚨 Promo expired $ago days ago';
    }
    if (d == 0) return '⚠️ Promo expires today';
    if (d == 1) return '⚠️ Promo expires tomorrow';
    if (d <= 3) return '⚠️ Promo expires in $d days';
    return 'Promo expires in $d days';
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

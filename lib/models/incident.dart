/// Water-quality incident and the owner's response to it, ported from the
/// AquaWatch HTML prototype's incident state machine (`S.inc`).
///
/// An incident opens when a parameter leaves its safe range, runs through
/// open → progress (action taken) → resolved | unresolved, and carries a
/// timeline of remarks ([IncidentRemark]) the way the prototype did.
library;

/// One line in an incident's timeline: an owner action, a logged fish death,
/// or an automatic verification note.
class IncidentRemark {
  final int t;

  /// A named corrective action, when this remark records one.
  final String? action;

  /// Number of fish logged dead against this incident, when applicable.
  final int? died;

  /// Suspected cause stored with a death remark.
  final String? cause;

  /// Free note (auto-verification result, detection note, …).
  final String note;

  const IncidentRemark({
    required this.t,
    this.action,
    this.died,
    this.cause,
    this.note = '',
  });

  Map<String, dynamic> toMap() => {
        't': t,
        if (action != null) 'a': action,
        if (died != null) 'died': died,
        if (cause != null) 'c': cause,
        if (note.isNotEmpty) 'x': note,
      };

  factory IncidentRemark.fromMap(Map<dynamic, dynamic> m) => IncidentRemark(
        t: (m['t'] as num?)?.toInt() ?? 0,
        action: m['a'] as String?,
        died: (m['died'] as num?)?.toInt(),
        cause: m['c'] as String?,
        note: (m['x'] as String?) ?? '',
      );
}

class Incident {
  final int id;

  /// Parameter key: 'ph' | 't' | 'o'.
  final String p;

  /// Human title captured at open time, e.g. "High pH", "Low dissolved oxygen".
  String title;

  /// Formatted reading at open time, e.g. "8.90", "2.57 mg/L".
  String val;

  /// When the incident opened (epoch ms).
  final int ts;

  /// 'warn' | 'crit' — can escalate while open.
  String lvl;

  /// 'open' | 'progress' | 'resolved' | 'unresolved'.
  String st;

  /// SMS was sent to the owner.
  bool sms;

  /// A corrective action has been taken.
  bool act;

  /// When the action was taken (epoch ms), if any.
  int? actAt;

  /// Timeline of remarks.
  List<IncidentRemark> rem;

  /// When the incident closed (resolved or unresolved).
  int? closedAt;

  /// Baseline distance-outside-range at open, used to detect improvement.
  double? d0;

  /// Consecutive readings showing improvement (toward auto-detecting action).
  int imp;

  /// Timestamp of the first reading in the current uninterrupted safe period.
  int? safeSince;

  /// Resolved without any logged action (recovered on its own).
  bool self;

  /// Reading value once resolved.
  String? after;

  double? latestValue;
  int? latestAt;
  double? lastUnsafeValue;

  double get problemValue =>
      lastUnsafeValue ?? double.tryParse(val.split(' ').first) ?? 0;

  Incident({
    required this.id,
    required this.p,
    required this.title,
    required this.val,
    required this.ts,
    this.lvl = 'warn',
    this.st = 'open',
    this.sms = true,
    this.act = false,
    this.actAt,
    List<IncidentRemark>? rem,
    this.closedAt,
    this.d0,
    this.imp = 0,
    this.safeSince,
    this.self = false,
    this.after,
    this.latestValue,
    this.latestAt,
    this.lastUnsafeValue,
  }) : rem = rem ?? [];

  bool get isOpen => st == 'open' || st == 'progress';
  bool get isVerifying => isOpen && safeSince != null;

  void updateFrom(Incident latest) {
    title = latest.title;
    val = latest.val;
    lvl = latest.lvl;
    st = latest.st;
    sms = latest.sms;
    act = latest.act;
    actAt = latest.actAt;
    rem = latest.rem;
    closedAt = latest.closedAt;
    d0 = latest.d0;
    imp = latest.imp;
    safeSince = latest.safeSince;
    self = latest.self;
    after = latest.after;
    latestValue = latest.latestValue;
    latestAt = latest.latestAt;
    lastUnsafeValue = latest.lastUnsafeValue;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'p': p,
        'title': title,
        'val': val,
        'ts': ts,
        'lvl': lvl,
        'st': st,
        'sms': sms,
        'act': act,
        'actAt': actAt,
        'rem': rem.map((r) => r.toMap()).toList(),
        'closedAt': closedAt,
        'd0': d0,
        'imp': imp,
        'safeSince': safeSince,
        'self': self,
        'after': after,
        'latest_value': latestValue,
        'latest_at': latestAt,
        'last_unsafe_value': lastUnsafeValue,
      };

  factory Incident.fromMap(Map<dynamic, dynamic> m) => Incident(
        id: (m['id'] as num).toInt(),
        p: m['p'] as String,
        title: (m['title'] as String?) ?? '',
        val: (m['val'] as String?) ?? '',
        ts: (m['ts'] as num?)?.toInt() ?? 0,
        lvl: (m['lvl'] as String?) ?? 'warn',
        st: (m['st'] as String?) ?? 'open',
        sms: m['sms'] as bool? ?? true,
        act: m['act'] as bool? ?? false,
        actAt: (m['actAt'] as num?)?.toInt(),
        rem: ((m['rem'] as List?) ?? [])
            .map((e) => IncidentRemark.fromMap(e as Map))
            .toList(),
        closedAt: (m['closedAt'] as num?)?.toInt(),
        d0: (m['d0'] as num?)?.toDouble(),
        imp: (m['imp'] as num?)?.toInt() ?? 0,
        safeSince: (m['safeSince'] as num?)?.toInt(),
        self: m['self'] as bool? ?? false,
        after: m['after'] as String?,
        latestValue: (m['latest_value'] as num?)?.toDouble(),
        latestAt: (m['latest_at'] as num?)?.toInt(),
        lastUnsafeValue: (m['last_unsafe_value'] as num?)?.toDouble(),
      );
}

/// One harvest event, ported from the prototype's `S.harv`.
class HarvestRecord {
  final int id;

  /// Epoch ms of the harvest.
  final int t;

  /// Number of fish harvested.
  final int n;

  /// Total weight in kilograms.
  final double kg;

  /// Selling price per kilogram in pesos (0 if not recorded).
  final double price;

  /// Final harvest (whole pond) vs. a partial harvest.
  final bool fin;

  /// Buyer / remarks, optional.
  final String buyer;

  const HarvestRecord({
    required this.id,
    required this.t,
    required this.n,
    required this.kg,
    this.price = 0,
    this.fin = false,
    this.buyer = '',
  });

  /// Average size per fish in grams.
  double get avgGrams => n > 0 ? kg / n * 1000 : 0;

  /// Total value in pesos.
  double get value => kg * price;

  Map<String, dynamic> toMap() => {
        'id': id,
        't': t,
        'n': n,
        'kg': kg,
        'price': price,
        'fin': fin,
        'buyer': buyer,
      };

  factory HarvestRecord.fromMap(Map<dynamic, dynamic> m) => HarvestRecord(
        id: (m['id'] as num).toInt(),
        t: (m['t'] as num?)?.toInt() ?? 0,
        n: (m['n'] as num?)?.toInt() ?? 0,
        kg: (m['kg'] as num?)?.toDouble() ?? 0,
        price: (m['price'] as num?)?.toDouble() ?? 0,
        fin: m['fin'] as bool? ?? false,
        buyer: (m['buyer'] as String?) ?? '',
      );
}

/// Stocking record for the pond — how many fingerlings, pond area, date.
class Stocking {
  final int n;
  final int area;
  final String date;

  const Stocking({this.n = 1000, this.area = 250, this.date = ''});

  Map<String, dynamic> toMap() => {'n': n, 'area': area, 'date': date};

  factory Stocking.fromMap(Map<dynamic, dynamic> m) => Stocking(
        n: (m['n'] as num?)?.toInt() ?? 1000,
        area: (m['area'] as num?)?.toInt() ?? 250,
        date: (m['date'] as String?) ?? '',
      );
}

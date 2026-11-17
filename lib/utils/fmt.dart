/// Small formatting helpers shared by the response-centre, harvest and report
/// screens — ported from the prototype's fd / dur / clock / peso helpers.
library;

import 'package:intl/intl.dart';
import '../services/i18n.dart';

/// "Oct 4 · 4:41 PM" style stamp.
String fd(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateFormat('MMM d · h:mm a').format(d);
}

/// "4:41 PM"
String timeStr(int ms) =>
    DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));

/// "Oct 4, 2026"
String dMed(int ms) =>
    DateFormat('MMM d, y').format(DateTime.fromMillisecondsSinceEpoch(ms));

/// A coarse duration in minutes/hours, e.g. "12 min", "2 h 10 min".
String dur(int ms) {
  final m = (ms / 60000).round().clamp(1, 1 << 30);
  if (m < 60) return '$m ${L('min', 'min')}';
  return '${m ~/ 60} ${L('h', 'oras')} ${m % 60} min';
}

/// Count-down clock "HH:MM:SS" from a millisecond span.
String clock(int ms) {
  final t = (ms < 0 ? 0 : ms) ~/ 1000;
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(t ~/ 3600)}:${two((t ~/ 60) % 60)}:${two(t % 60)}';
}

/// ISO yyyy-MM-dd.
String iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// "₱1,250.00"
String peso(num v) =>
    '₱${NumberFormat('#,##0.00', 'en_PH').format(v)}';

/// Thousands-grouped integer.
String grp(num v) => NumberFormat('#,##0', 'en_PH').format(v);

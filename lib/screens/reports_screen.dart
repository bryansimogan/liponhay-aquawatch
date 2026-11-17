import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/incident.dart';
import '../services/app_store.dart';
import '../services/i18n.dart';
import '../utils/fmt.dart';
import '../widgets/reveal.dart';

/// Summary of Reports — ported from the prototype's `sumPanel` / `repData` /
/// `printReport`. Pick a day, week or month and read a production report:
/// incidents, owner actions, mortality, harvest and a cycle-to-date summary.
/// "Copy report" puts a plain-text version on the clipboard (stands in for the
/// prototype's browser print; a true PDF export can be added with a package).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _Mode { day, week, month }

class _ReportsScreenState extends State<ReportsScreen> {
  _Mode _mode = _Mode.day;
  DateTime _anchor = DateTime.now();

  // ─── Range maths ─────────────────────────────────────────────────
  (int, int, String) _range() {
    switch (_mode) {
      case _Mode.day:
        final a = DateTime(_anchor.year, _anchor.month, _anchor.day);
        final b = a.add(const Duration(days: 1));
        return (
          a.millisecondsSinceEpoch,
          b.millisecondsSinceEpoch,
          DateFormat('MMMM d, y').format(a)
        );
      case _Mode.week:
        var a = DateTime(_anchor.year, _anchor.month, _anchor.day);
        a = a.subtract(Duration(days: (a.weekday + 6) % 7)); // back to Monday
        final b = a.add(const Duration(days: 7));
        final e = b.subtract(const Duration(days: 1));
        final f = DateFormat('MMM d');
        return (
          a.millisecondsSinceEpoch,
          b.millisecondsSinceEpoch,
          '${f.format(a)} – ${f.format(e)}, ${e.year}'
        );
      case _Mode.month:
        final a = DateTime(_anchor.year, _anchor.month, 1);
        final b = DateTime(_anchor.year, _anchor.month + 1, 1);
        return (
          a.millisecondsSinceEpoch,
          b.millisecondsSinceEpoch,
          DateFormat('MMMM y').format(a)
        );
    }
  }

  void _shift(int dir) {
    setState(() {
      switch (_mode) {
        case _Mode.day:
          _anchor = _anchor.add(Duration(days: dir));
        case _Mode.week:
          _anchor = _anchor.add(Duration(days: 7 * dir));
        case _Mode.month:
          _anchor = DateTime(_anchor.year, _anchor.month + dir, 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>();
    final (r0, r1, label) = _range();
    bool inRange(int t) => t >= r0 && t < r1;

    final incidents = s.incidents.where((i) => inRange(i.ts)).toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));
    final resolved = incidents.where((i) => i.st == 'resolved').toList();
    final unresolved = incidents.where((i) => i.st == 'unresolved').toList();
    final mort = s.mortality.where((m) => inRange(m.t)).toList()
      ..sort((a, b) => b.t.compareTo(a.t));
    final harv = s.harvest.where((h) => inRange(h.t)).toList()
      ..sort((a, b) => b.t.compareTo(a.t));

    final actions = <(Incident, IncidentRemark)>[];
    for (final i in s.incidents) {
      for (final r in i.rem) {
        if ((r.action != null || r.died != null) && inRange(r.t)) {
          actions.add((i, r));
        }
      }
    }
    actions.sort((a, b) => b.$2.t.compareTo(a.$2.t));

    final resp = incidents.where((i) => i.actAt != null).toList();
    final rec = resolved.where((i) => i.actAt != null && i.closedAt != null);
    final avgResp = resp.isEmpty
        ? '—'
        : dur((resp.fold<int>(0, (a, i) => a + (i.actAt! - i.ts)) / resp.length)
            .round());
    final avgRec = rec.isEmpty
        ? '—'
        : dur((rec.fold<int>(0, (a, i) => a + (i.closedAt! - i.actAt!)) /
                rec.length)
            .round());
    final fishDied = mort.fold<int>(0, (a, b) => a + b.n);
    final harvN = harv.fold<int>(0, (a, b) => a + b.n);
    final harvKg = harv.fold<double>(0, (a, b) => a + b.kg);
    final harvVal = harv.fold<double>(0, (a, b) => a + b.value);

    final now = DateTime.now().millisecondsSinceEpoch;
    final (periodLabel, periodColor) = r0 > now
        ? (L('Upcoming', 'Paparating'), const Color(0xFF3B9BD6))
        : r1 <= now
            ? (L('Past', 'Nakaraan'), AppTheme.of(context).coral)
            : (L('Present', 'Kasalukuyan'), AppTheme.of(context).aqua);

    return Scaffold(
      backgroundColor: AppTheme.of(context).bg,
      appBar: AppBar(
        title: Text(L('Summary of Reports', 'Buod ng mga Ulat')),
        backgroundColor: AppTheme.of(context).header,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: L('Copy report', 'Kopyahin ang ulat'),
            onPressed: () => _copyReport(
                s, label, incidents, resolved, unresolved, actions, mort, harv),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Text('Pond 1 · Tilapia',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.of(context).inkSoft)),
          const SizedBox(height: 10),
          _modeChips(),
          const SizedBox(height: 10),
          _rangeBar(label),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.of(context).ink)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: periodColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999)),
                child: Text(periodLabel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: periodColor)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Reveal(
            child: _statCard([
              (
                '${incidents.length}',
                L('INCIDENTS', 'INSIDENTE'),
                AppTheme.of(context).ink
              ),
              (
                '${resolved.length}',
                L('RESOLVED', 'NARESOLBA'),
                AppTheme.of(context).aqua
              ),
              (
                '${unresolved.length}',
                L('NOT RESOLVED', 'HINDI NARESOLBA'),
                AppTheme.of(context).coral
              ),
            ], [
              (avgResp, L('AVG RESPONSE', 'KARANIWANG TUGON')),
              (avgRec, L('AVG RECOVERY', 'KARANIWANG PAGBAWI')),
              ('$fishDied', L('FISH DIED', 'NAMATAY')),
            ]),
          ),
          const SizedBox(height: 12),
          _section(L('HARVEST', 'HARVEST (PAG-ANI)')),
          _harvestSummary(harvN, harvKg, harvVal),
          if (harv.isNotEmpty)
            for (final h in harv)
              _kv(dMed(h.t),
                  '${grp(h.n)} ${L('fish', 'isda')} · ${h.kg.toStringAsFixed(1)} kg${h.price > 0 ? ' · ${peso(h.value)}' : ''}'),
          const SizedBox(height: 4),
          _section(L('WATER INCIDENTS', 'MGA INSIDENTE SA TUBIG')),
          if (incidents.isEmpty)
            _empty(L('No incidents in this period.',
                'Walang insidente sa panahong ito.'))
          else
            for (final i in incidents)
              _kv('${fd(i.ts)} · ${i.title}', '${i.val} · ${_outcome(i)}'),
          const SizedBox(height: 4),
          _section(L('ACTIONS BY OWNER', 'MGA AKSYON NG MAY-ARI')),
          if (actions.isEmpty)
            _empty(r0 > now
                ? L('This period has not started yet.',
                    'Hindi pa nagsisimula ang panahong ito.')
                : L('No actions were logged in this period.',
                    'Walang naitalang aksyon sa panahong ito.'))
          else
            for (final (i, r) in actions)
              _kv('${fd(r.t)} · ${r.action ?? '${L('Fish died', 'Namatay')}: ${r.died}'}',
                  '${i.title} (${i.val})'),
          const SizedBox(height: 4),
          _section(L('FISH MORTALITY', 'PAGKAMATAY NG ISDA')),
          if (mort.isEmpty)
            _empty(L('None recorded.', 'Walang naitala.'))
          else
            for (final m in mort)
              _kv('${fd(m.t)} · ${m.n} ${L('fish', 'isda')}',
                  '${L('Cause', 'Sanhi')}: ${m.cause}'),
          const SizedBox(height: 4),
          _section(L('PRODUCTION SUMMARY (CYCLE TO DATE)',
              'BUOD NG PRODUKSIYON (HANGGANG NGAYON)')),
          _productionSummary(s),
        ],
      ),
    );
  }

  String _outcome(Incident i) => switch (i.st) {
        'resolved' => i.self
            ? L('Recovered on its own', 'Kusang bumalik')
            : '${L('Resolved', 'Naresolba')}: ${i.val} → ${i.after ?? '—'}',
        'unresolved' => L('Not resolved', 'Hindi naresolba'),
        _ => L('Monitoring', 'Binabantayan'),
      };

  // ─── Pieces ──────────────────────────────────────────────────────
  Widget _modeChips() {
    Widget chip(_Mode m, String label) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(label),
              selected: _mode == m,
              onSelected: (_) => setState(() => _mode = m),
            ),
          ),
        );
    return Row(
      children: [
        chip(_Mode.day, L('Day', 'Araw')),
        chip(_Mode.week, L('Week', 'Linggo')),
        chip(_Mode.month, L('Month', 'Buwan')),
      ],
    );
  }

  Widget _rangeBar(String label) {
    return Row(
      children: [
        IconButton(
            onPressed: () => _shift(-1),
            icon: Icon(Icons.chevron_left_rounded,
                color: AppTheme.of(context).deep)),
        Expanded(
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.of(context).ink)),
        ),
        IconButton(
            onPressed: () => _shift(1),
            icon: Icon(Icons.chevron_right_rounded,
                color: AppTheme.of(context).deep)),
        TextButton(
          onPressed: () => setState(() => _anchor = DateTime.now()),
          child: Text(L('Today', 'Ngayon')),
        ),
      ],
    );
  }

  Widget _statCard(
      List<(String, String, Color)> top, List<(String, String)> bottom) {
    Widget cell(String big, String label, Color c) => Expanded(
          child: Column(
            children: [
              Text(big,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700, color: c)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10, color: AppTheme.of(context).inkSoft)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.of(context).card(),
      child: Column(
        children: [
          Row(children: [for (final t in top) cell(t.$1, t.$2, t.$3)]),
          const Divider(height: 24),
          Row(children: [
            for (final b in bottom) cell(b.$1, b.$2, AppTheme.of(context).ink)
          ]),
        ],
      ),
    );
  }

  Widget _harvestSummary(int n, double kg, double val) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.of(context).card(radius: 16),
      child: Row(
        children: [
          _mini('${grp(n)}', L('fish', 'isda')),
          _mini('${kg.toStringAsFixed(1)} kg', L('weight', 'timbang')),
          _mini(peso(val), L('value', 'halaga')),
        ],
      ),
    );
  }

  Widget _mini(String big, String label) => Expanded(
        child: Column(
          children: [
            Text(big,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.of(context).ink)),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: AppTheme.of(context).inkSoft)),
          ],
        ),
      );

  Widget _productionSummary(AppStore s) {
    final lost = s.mortality.fold<int>(0, (a, b) => a + b.n);
    final harvN = s.harvest.fold<int>(0, (a, b) => a + b.n);
    final harvKg = s.harvest.fold<double>(0, (a, b) => a + b.kg);
    final harvVal = s.harvest.fold<double>(0, (a, b) => a + b.value);
    final surv =
        s.stock.n > 0 ? ((s.stock.n - lost) / s.stock.n * 100).round() : 0;
    final rows = [
      (L('Fingerlings stocked', 'Na-stock na fingerlings'), grp(s.stock.n)),
      (L('Total fish died', 'Kabuuang namatay'), grp(lost)),
      (L('Total fish harvested', 'Kabuuang na-harvest'), grp(harvN)),
      (L('Fish remaining in pond', 'Natitirang isda'), grp(s.aliveCount)),
      (L('Survival rate', 'Survival rate'), '$surv%'),
      (
        L('Total harvest weight', 'Kabuuang timbang'),
        '${harvKg.toStringAsFixed(1)} kg'
      ),
      (L('Total harvest value', 'Kabuuang halaga'), peso(harvVal)),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: AppTheme.of(context).card(radius: 16),
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                      child: Text(r.$1,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.of(context).inkSoft))),
                  Text(r.$2,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.of(context).ink)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(t,
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: AppTheme.of(context).inkSoft)),
      );

  Widget _kv(String left, String right) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.of(context).card(radius: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(left,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.of(context).ink)),
              const SizedBox(height: 2),
              Text(right,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppTheme.of(context).inkSoft)),
            ],
          ),
        ),
      );

  Widget _empty(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style:
                TextStyle(fontSize: 12.5, color: AppTheme.of(context).inkSoft)),
      );

  // ─── Copy as text ────────────────────────────────────────────────
  void _copyReport(
    AppStore s,
    String label,
    List<Incident> incidents,
    List<Incident> resolved,
    List<Incident> unresolved,
    List<(Incident, IncidentRemark)> actions,
    List<MortLog> mort,
    List<HarvestRecord> harv,
  ) {
    final b = StringBuffer();
    b.writeln('LIPONHAY FISH FARM — AquaWatch Report');
    b.writeln('Pond 1 · Tilapia');
    b.writeln('Period: $label');
    b.writeln('Generated: ${fd(DateTime.now().millisecondsSinceEpoch)}');
    b.writeln('');
    b.writeln('SUMMARY');
    b.writeln('  Incidents: ${incidents.length}');
    b.writeln('  Resolved: ${resolved.length}');
    b.writeln('  Not resolved: ${unresolved.length}');
    b.writeln('  Fish died: ${mort.fold<int>(0, (a, m) => a + m.n)}');
    b.writeln(
        '  Harvested: ${grp(harv.fold<int>(0, (a, h) => a + h.n))} fish · ${harv.fold<double>(0, (a, h) => a + h.kg).toStringAsFixed(1)} kg');
    b.writeln('');
    b.writeln('WATER INCIDENTS');
    if (incidents.isEmpty) b.writeln('  (none)');
    for (final i in incidents) {
      b.writeln('  ${fd(i.ts)} · ${i.title} · ${i.val} · ${_outcome(i)}');
    }
    b.writeln('');
    b.writeln('ACTIONS BY OWNER');
    if (actions.isEmpty) b.writeln('  (none)');
    for (final (i, r) in actions) {
      b.writeln(
          '  ${fd(r.t)} · ${r.action ?? 'Fish died: ${r.died}'} · ${i.title} (${i.val})');
    }
    b.writeln('');
    b.writeln('FISH MORTALITY');
    if (mort.isEmpty) b.writeln('  (none)');
    for (final m in mort) {
      b.writeln('  ${fd(m.t)} · ${m.n} fish · ${m.cause}');
    }
    b.writeln('');
    b.writeln('HARVEST');
    if (harv.isEmpty) b.writeln('  (none)');
    for (final h in harv) {
      b.writeln(
          '  ${dMed(h.t)} · ${grp(h.n)} fish · ${h.kg.toStringAsFixed(1)} kg · ${peso(h.value)}');
    }
    Clipboard.setData(ClipboardData(text: b.toString()));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L(
            'Report copied to clipboard.', 'Nakopya ang ulat sa clipboard.'))));
  }
}

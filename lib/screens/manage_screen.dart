import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../data/response_content.dart';
import '../models/incident.dart';
import '../models/notification_copy.dart';
import '../services/app_store.dart';
import '../services/i18n.dart';
import '../utils/fmt.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_header.dart';
import '../widgets/reveal.dart';
import '../widgets/stocking_sheet.dart';
import 'harvest_screen.dart';

/// Management / Response Centre — ported from the AquaWatch prototype's
/// `manage()` view. Shows only what needs action: a safe-readings strip,
/// feeding advice, a countdown tile per open incident with a risk breakdown,
/// the action state, survival stats, the incident list and the harvest entry.
class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key});

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Per-second tick so the countdowns move smoothly between store updates.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>();
    final open = s.openIncidents;

    return Scaffold(
      backgroundColor: AppTheme.of(context).bg,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              children: [
                _headerRow(open.length, s),
                const SizedBox(height: 12),
                if (s.managementSyncFailed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(L(
                      'Management logs could not sync to Firebase. Check the connection and database access.',
                      'Hindi ma-sync sa Firebase ang management logs. Suriin ang koneksyon at access sa database.',
                    )),
                  ),
                if (s.hasCurrentReading)
                  Reveal(child: _safeStrip(s))
                else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppTheme.of(context).card(),
                    child: Text(L(
                      'Waiting for a current reading from the ESP32.',
                      'Hinihintay ang bagong reading mula sa ESP32.',
                    )),
                  ),
                const SizedBox(height: 12),
                if (open.isNotEmpty) ...[
                  Reveal(delayMs: 40, child: _feedingCard(open)),
                  const SizedBox(height: 12),
                ],
                if (open.isNotEmpty) ...[
                  _incidentGrid(s, open),
                  const SizedBox(height: 12),
                ],
                Reveal(delayMs: 120, child: _statsRow(s)),
                const SizedBox(height: 12),
                Reveal(delayMs: 150, child: _showIncidentsCard(s)),
                const SizedBox(height: 12),
                _linkCard(
                    Icons.set_meal_outlined,
                    AppTheme.of(context).aqua.withValues(alpha: .15),
                    AppTheme.of(context).aqua,
                    L('Stocking', 'Pag-stock ng isda'),
                    '${grp(s.stock.n)} ${L('fingerlings stocked', 'na-stock na fingerlings')}',
                    () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: AppTheme.of(context).bg,
                        builder: (_) => const StockingSheet())),
                const SizedBox(height: 12),
                Reveal(delayMs: 180, child: _harvestCard(s)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  // ─── Header row ──────────────────────────────────────────────────
  Widget _headerRow(int openCount, AppStore store) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  context.read<AppStore>().simulation
                      ? L('Demo Mode · Response centre',
                          'Demo Mode · Sentro ng Pagtugon')
                      : L('Response centre', 'Sentro ng Pagtugon'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.of(context).inkSoft)),
              Text(L('Management', 'Pamamahala'),
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.of(context).ink)),
            ],
          ),
        ),
        if (openCount > 0 || store.hasCurrentReading)
          _pill(
            openCount > 0
                ? '$openCount ${L('open', 'bukas')}'
                : store.allSafe
                    ? L('All clear', 'Ayos lahat')
                    : L('Still unsafe', 'Hindi pa ligtas'),
            store.allSafe
                ? AppTheme.of(context).aqua
                : AppTheme.of(context).amber,
          ),
      ],
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      );

  // ─── Safe strip ──────────────────────────────────────────────────
  Widget _safeStrip(AppStore s) {
    const names = {'ph': 'pH', 't': 'Temp', 'o': 'DO'};
    final open = s.openIncidents;
    final safe = ['ph', 't', 'o']
        .where((p) => s.level(p) == 'ok' && !open.any((i) => i.p == p))
        .toList();
    final allOk = s.allSafe;
    final verifying =
        open.any((i) => i.isVerifying) && open.every((i) => i.isVerifying);
    final title = allOk
        ? L('All readings are safe', 'Ligtas ang lahat ng reading')
        : verifying
            ? L('Verifying recovered readings',
                'Bine-verify ang bumalik sa normal')
            : safe.isNotEmpty
                ? L('Safe readings', 'Mga ligtas na reading')
                : L('Needs action', 'Kailangan ng aksyon');
    final sub = allOk
        ? L('Live values are on the Dashboard. This page only shows what needs action.',
            'Nasa Dashboard ang mga live na value. Ito ay para lang sa kailangang aksyunan.')
        : verifying
            ? L('The recovered readings must stay safe for 10 minutes.',
                'Kailangang manatiling ligtas ang readings sa loob ng 10 minuto.')
            : safe.isNotEmpty
                ? safe.map((p) => names[p]).join(' · ')
                : L('Take an action below.', 'Kumilos sa ibaba.');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.of(context).card(),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: (allOk
                        ? AppTheme.of(context).aqua
                        : AppTheme.of(context).amber)
                    .withOpacity(0.18),
                shape: BoxShape.circle),
            child: Icon(
                allOk ? Icons.check_rounded : Icons.warning_amber_rounded,
                size: 18,
                color: allOk
                    ? AppTheme.of(context).aqua
                    : AppTheme.of(context).amber),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.of(context).ink)),
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppTheme.of(context).inkSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Feeding advice ──────────────────────────────────────────────
  Widget _feedingCard(List<Incident> open) {
    const names = {'ph': 'pH', 't': 'Temp', 'o': 'DO'};
    final stop = open.any((i) => feed[riskKey(i.p, _val(i))]!.stop);
    final crit = open.any((i) => i.lvl == 'crit');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (crit ? AppTheme.of(context).coral : AppTheme.of(context).amber)
            .withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color:
                (crit ? AppTheme.of(context).coral : AppTheme.of(context).amber)
                    .withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: AppTheme.of(context).amber.withOpacity(0.2),
                shape: BoxShape.circle),
            child: Icon(Icons.set_meal_rounded,
                size: 18, color: AppTheme.of(context).amber),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    stop
                        ? L('Stop feeding for now',
                            'Ihinto muna ang pagpapakain')
                        : L('Cut back on feeding', 'Bawasan ang pagpapakain'),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.of(context).ink)),
                const SizedBox(height: 6),
                for (final i in open)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: AppTheme.of(context).inkSoft),
                        children: [
                          TextSpan(
                              text: '${names[i.p]}  ',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.of(context).ink)),
                          TextSpan(text: feed[riskKey(i.p, _val(i))]!.text),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _val(Incident i) => i.problemValue;

  Widget _incidentGrid(AppStore store, List<Incident> open) {
    final ordered = [
      for (final parameter in const ['ph', 't', 'o'])
        ...open.where((incident) => incident.p == parameter),
    ];
    final needsAction = ordered.where((i) => !i.isVerifying).toList()
      ..sort((a, b) =>
          (b.lvl == 'crit' ? 1 : 0).compareTo(a.lvl == 'crit' ? 1 : 0));

    return LayoutBuilder(builder: (context, constraints) {
      final full = constraints.maxWidth;
      final column = full >= 300 ? (full - 12) / 2 : full;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (index, incident) in ordered.indexed)
            SizedBox(
              width: needsAction.isEmpty &&
                      ordered.length.isOdd &&
                      index == ordered.length - 1
                  ? full
                  : column,
              child: _problemTile(store, incident),
            ),
          if (needsAction.isNotEmpty)
            SizedBox(
              width: ordered.length.isEven ? full : column,
              child: _actionTile(needsAction.first),
            ),
        ],
      );
    });
  }

  Widget _problemTile(AppStore store, Incident i) {
    final palette = AppTheme.of(context);
    final verifying = i.isVerifying;
    final color = verifying
        ? palette.aqua
        : i.lvl == 'crit'
            ? palette.coral
            : palette.amber;
    final (left, fraction) = _incidentTimer(i, store.nowMs);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showIncidentDetail(i),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(minHeight: 172),
          padding: const EdgeInsets.all(13),
          decoration: palette.card(borderColor: color.withValues(alpha: .42)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 36,
                    child: CircularProgressIndicator(
                      value: fraction,
                      color: color,
                      backgroundColor: color.withValues(alpha: .15),
                      strokeWidth: 4,
                    ),
                  ),
                  _pill(
                      verifying
                          ? L('Verifying', 'Bine-verify')
                          : levelName(i.lvl),
                      color),
                ],
              ),
              const SizedBox(height: 8),
              Text(paramMeta[i.p]!.label,
                  style: TextStyle(fontSize: 12, color: palette.inkSoft)),
              Text(
                verifying || left > 0
                    ? clock(left < 0 ? 0 : left)
                    : L('Overdue', 'Lampas na'),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: palette.ink),
              ),
              Text(
                verifying
                    ? L('In range · confirming',
                        'Nasa ligtas na saklaw · kinukumpirma')
                    : L('Sensor is rechecking', 'Muling binabasa ng sensor'),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color),
              ),
              const SizedBox(height: 5),
              Text(
                risk[riskKey(i.p, _val(i))]!.s,
                style: TextStyle(
                    fontSize: 10.5, height: 1.35, color: palette.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTile(Incident incident) {
    const bg = Color(0xFFA73327);
    const icon = Icons.warning_amber_rounded;
    final title = L('RECOMMENDED ACTION', 'MUNGKAHING AKSYON');
    final sub = hintFor(incident.p);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 172),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: [
          Icon(icon, size: 30, color: Colors.white),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Colors.white.withOpacity(0.9))),
        ],
      ),
    );
  }

  // ─── Stats row ───────────────────────────────────────────────────
  Widget _statsRow(AppStore s) {
    final alive = s.aliveCount;
    final pct = (s.stock.n > 0)
        ? ((s.stock.n - s.mortality.fold<int>(0, (a, b) => a + b.n)) /
                s.stock.n *
                100)
            .round()
            .clamp(0, 100)
        : 0;
    final recovered = s.incidents
        .where((i) => i.st == 'resolved' && i.closedAt != null)
        .toList();
    final avg = recovered.isEmpty
        ? '—'
        : dur((recovered.fold<int>(0, (sum, i) => sum + i.closedAt! - i.ts) /
                recovered.length)
            .round());
    final lost = s.mortality.fold<int>(0, (a, b) => a + b.n);

    return Row(
      children: [
        Expanded(
          child: _statCard(
            '${grp(alive)}',
            '/ ${grp(s.stock.n)}',
            L('Fingerlings alive', 'Buhay na fingerlings'),
            '$pct% ${L('survival', 'survival')}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            avg,
            '',
            L('Avg recovery', 'Karaniwang pagbawi'),
            '$lost ${L('fish lost', 'isda ang nawala')}',
          ),
        ),
      ],
    );
  }

  Widget _statCard(String big, String small, String label, String msg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.of(context).card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 12, color: AppTheme.of(context).inkSoft)),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.of(context).ink),
              children: [
                TextSpan(text: big),
                if (small.isNotEmpty)
                  TextSpan(
                      text: ' $small',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.of(context).inkSoft)),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(msg,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.of(context).aqua)),
        ],
      ),
    );
  }

  // ─── Show incidents + harvest cards ──────────────────────────────
  Widget _linkCard(IconData icon, Color iconBg, Color iconColor, String title,
      String sub, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.of(context).card(),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.of(context).ink)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.of(context).inkSoft)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.of(context).deep),
          ],
        ),
      ),
    );
  }

  Widget _showIncidentsCard(AppStore s) {
    final open = s.openIncidents.length;
    return _linkCard(
      Icons.error_outline_rounded,
      AppTheme.of(context).deep.withOpacity(0.08),
      AppTheme.of(context).deep,
      L('Show incidents', 'Ipakita ang mga insidente'),
      '${s.incidents.length} ${L('total', 'kabuuan')} · $open ${L('open', 'bukas')}',
      () => _showIncidentList(s),
    );
  }

  Widget _harvestCard(AppStore s) {
    final n = s.harvest.fold<int>(0, (a, b) => a + b.n);
    final kg = s.harvest.fold<double>(0, (a, b) => a + b.kg);
    return _linkCard(
      Icons.shopping_basket_rounded,
      AppTheme.of(context).aqua.withOpacity(0.15),
      AppTheme.of(context).aqua,
      L('Harvest', 'Harvest (Pag-ani)'),
      '$n ${L('fish', 'isda')} · ${kg.toStringAsFixed(1)} kg',
      () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const HarvestScreen())),
    );
  }

  // ─── Incident list sheet ─────────────────────────────────────────
  void _showIncidentList(AppStore s) {
    final list = [...s.incidents]..sort((a, b) => b.ts.compareTo(a.ts));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.of(context).bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            _grab(),
            Text(L('Incidents', 'Mga Insidente'),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.of(context).ink)),
            Text(
                '${list.length} ${L('total · tap one for details', 'kabuuan · pindutin para sa detalye')}',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.of(context).inkSoft)),
            const SizedBox(height: 12),
            if (list.isEmpty)
              Text(L('No incidents yet.', 'Wala pang insidente.'),
                  style: TextStyle(color: AppTheme.of(context).inkSoft)),
            for (final i in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _incidentRow(i, pop: () => Navigator.pop(ctx)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _incidentRow(Incident i, {VoidCallback? pop}) {
    final (label, color) = i.isVerifying
        ? (L('Verifying', 'Bine-verify'), AppTheme.of(context).aqua)
        : _statusChip(i.st);
    return InkWell(
      onTap: () {
        pop?.call();
        _showIncidentDetail(i);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.of(context).card(radius: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: (i.lvl == 'crit'
                          ? AppTheme.of(context).coral
                          : AppTheme.of(context).amber)
                      .withOpacity(0.18),
                  shape: BoxShape.circle),
              child: Icon(Icons.warning_amber_rounded,
                  size: 18,
                  color: i.lvl == 'crit'
                      ? AppTheme.of(context).coral
                      : AppTheme.of(context).amber),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(paramTitle(i.p, i.problemValue),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.of(context).ink)),
                  Text('${formatReading(i.p, i.problemValue)} · ${fd(i.ts)}',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.of(context).inkSoft)),
                ],
              ),
            ),
            _pill(label, color),
          ],
        ),
      ),
    );
  }

  (String, Color) _statusChip(String st) => switch (st) {
        'open' => (L('Take action', 'Kumilos'), AppTheme.of(context).coral),
        'progress' => (
            L('Action taken', 'Nagawa ang aksyon'),
            AppTheme.of(context).deep
          ),
        'resolved' => (L('Resolved', 'Naresolba'), AppTheme.of(context).aqua),
        _ => (L('Not resolved', 'Hindi naresolba'), AppTheme.of(context).coral),
      };

  // ─── Incident detail sheet ───────────────────────────────────────
  void _showIncidentDetail(Incident i) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.of(context).bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _IncidentDetailSheet(incidentId: i.id),
    );
  }

  Widget _grab() => Center(
        child: Container(
          width: 40,
          height: 5,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
              color: AppTheme.of(context).border,
              borderRadius: BorderRadius.circular(5)),
        ),
      );
}

/// Live-updating incident detail: countdown, step tracker, risk breakdown,
/// feeding advice, timeline and the final verdict.
class _IncidentDetailSheet extends StatefulWidget {
  final int incidentId;
  const _IncidentDetailSheet({required this.incidentId});

  @override
  State<_IncidentDetailSheet> createState() => _IncidentDetailSheetState();
}

class _IncidentDetailSheetState extends State<_IncidentDetailSheet> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>();
    final i = s.incidents.where((x) => x.id == widget.incidentId).firstOrNull;
    if (i == null) return const SizedBox.shrink();
    final rk = riskKey(i.p, i.problemValue);
    final open = i.isOpen;
    final crit = i.lvl == 'crit';
    final accent =
        crit ? AppTheme.of(context).coral : AppTheme.of(context).amber;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.96,
      builder: (ctx, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                  color: AppTheme.of(context).border,
                  borderRadius: BorderRadius.circular(5)),
            ),
          ),
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: accent.withOpacity(0.18), shape: BoxShape.circle),
                child:
                    Icon(Icons.warning_amber_rounded, size: 20, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${paramTitle(i.p, i.problemValue)} · ${formatReading(i.p, i.problemValue)}',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.of(context).ink)),
                    Text('${fd(i.ts)} · ${levelName(i.lvl)}',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.of(context).inkSoft)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (i.latestValue != null && i.latestAt != null)
            Text(
                '${L('Latest recorded reading', 'Pinakabagong naitalang reading')} · '
                '${formatReading(i.p, i.latestValue!)} · ${fd(i.latestAt!)}',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.of(context).inkSoft)),
          if (open) _incidentCountdown(context, s, i),
          const SizedBox(height: 16),
          _steps(context, i, s.simulation),
          const SizedBox(height: 16),
          _riskBlock(context, rk, crit),
          const SizedBox(height: 16),
          if (open) _indicator(context, i) else _verdict(context, i),
          if (i.rem.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(L('Timeline', 'Takbo ng pangyayari'),
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.of(context).inkSoft)),
            const SizedBox(height: 8),
            for (final r in i.rem) _remarkRow(context, r),
          ],
        ],
      ),
    );
  }

  Widget _steps(BuildContext context, Incident i, bool simulation) {
    Widget step(String label, bool on) => Expanded(
          child: Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: on
                      ? AppTheme.of(context).aqua
                      : AppTheme.of(context).surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: on
                          ? AppTheme.of(context).aqua
                          : AppTheme.of(context).inkSoft,
                      width: 2),
                ),
              ),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10.5,
                      color: on
                          ? AppTheme.of(context).ink
                          : AppTheme.of(context).inkSoft)),
            ],
          ),
        );
    return Row(
      children: [
        step(L('Detected', 'Natukoy'), true),
        if (i.sms)
          step(
              simulation
                  ? L('SIMULATED SMS', 'SIMULATED NA SMS')
                  : L('SMS sent', 'Naipadala ang SMS'),
              true),
        step(
            L('Verifying', 'Bine-verify'), i.isVerifying || i.st == 'resolved'),
        step(
            i.st == 'unresolved'
                ? L('Not resolved', 'Hindi naresolba')
                : L('Verified', 'Na-verify'),
            !i.isOpen),
      ],
    );
  }

  Widget _riskBlock(BuildContext context, String rk, bool crit) {
    final r = risk[rk]!;
    final steps = doNow[rk]!.map((e) => L(e[0], e[1])).toList();
    final accent =
        crit ? AppTheme.of(context).coral : AppTheme.of(context).amber;
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(t,
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.of(context).inkSoft)),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.t,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.of(context).ink)),
                    Text(r.s,
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.of(context).inkSoft)),
                  ],
                ),
              ),
            ],
          ),
          label(L('POSSIBLE CAUSES', 'POSIBLENG SANHI')),
          for (final c in r.causeList) _bullet(context, c),
          label(L('IF NOT ACTED ON IN TIME', 'KUNG HINDI MAAGAPAN')),
          for (var k = 0; k < r.effectList.length; k++)
            _numbered(context, k + 1, r.effectList[k], accent),
          label(L('WHAT TO DO NOW', 'ANO ANG GAGAWIN NGAYON')),
          for (final step in steps) _check(context, step),
          const SizedBox(height: 10),
          Text(
            crit
                ? L('This is critical. Act now.',
                    'Kritikal na ito. Kumilos na ngayon.')
                : L('Act before it becomes critical.',
                    'Kumilos bago ito maging kritikal.'),
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: accent),
          ),
        ],
      ),
    );
  }

  Widget _bullet(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 7, right: 9),
                decoration: BoxDecoration(
                    color: AppTheme.of(context).inkSoft,
                    shape: BoxShape.circle)),
            Expanded(
                child: Text(t,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppTheme.of(context).ink))),
          ],
        ),
      );

  Widget _numbered(BuildContext context, int n, String t, Color accent) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(right: 9),
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: Center(
                  child: Text('$n',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.of(context).onPrimary))),
            ),
            Expanded(
                child: Text(t,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppTheme.of(context).ink))),
          ],
        ),
      );

  Widget _check(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_rounded,
                size: 16, color: AppTheme.of(context).aqua),
            const SizedBox(width: 9),
            Expanded(
                child: Text(t,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppTheme.of(context).ink))),
          ],
        ),
      );

  Widget _incidentCountdown(BuildContext context, AppStore store, Incident i) {
    final palette = AppTheme.of(context);
    final verifying = i.isVerifying;
    final color = verifying ? palette.aqua : palette.amber;
    final (left, fraction) = _incidentTimer(i, store.nowMs);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: palette.tintedCard(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            verifying
                ? L('10-minute safety verification', '10-minutong pag-verify')
                : L('Recommended response window',
                    'Inirerekomendang oras ng pagtugon'),
            style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink),
          ),
          const SizedBox(height: 6),
          Text(
            verifying || left > 0
                ? clock(left < 0 ? 0 : left)
                : L('Overdue', 'Lampas na'),
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: fraction, color: color),
          if (verifying) ...[
            const SizedBox(height: 8),
            Text(L('Any unsafe reading restarts the check.',
                'Magsisimula ulit ang pag-check kapag may reading na hindi ligtas.')),
          ],
        ],
      ),
    );
  }

  Widget _indicator(BuildContext context, Incident i) {
    final palette = AppTheme.of(context);
    final color = i.isVerifying ? palette.aqua : palette.coral;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: palette.tintedCard(color),
      child: Text(
        i.isVerifying
            ? L('The reading is in range. Keep following the recommendations while the sensor verifies it.',
                'Nasa ligtas na saklaw ang reading. Sundin pa rin ang mga rekomendasyon habang bine-verify ito.')
            : L('Waiting for a safe reading. The 10-minute check begins when the reading returns to range.',
                'Hinihintay ang ligtas na reading. Magsisimula ang 10-minutong pag-verify kapag bumalik ito sa ligtas na saklaw.'),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _verdict(BuildContext context, Incident i) {
    final resolved = i.st == 'resolved';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            (resolved ? AppTheme.of(context).aqua : AppTheme.of(context).coral)
                .withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(resolved ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 18,
              color: resolved
                  ? AppTheme.of(context).aqua
                  : AppTheme.of(context).coral),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              resolved
                  ? '${L('Verified by sensor', 'Na-verify ng sensor')}: ${i.val} → ${i.after ?? '—'}'
                      '${i.self ? L(' · recovered on its own', ' · kusang bumalik') : ''}'
                  : L('Not resolved. The reading was still unsafe after the response window.',
                      'Hindi naresolba. Hindi pa rin ligtas matapos ang itinakdang oras.'),
              style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: resolved
                      ? AppTheme.of(context).aqua
                      : AppTheme.of(context).coral),
            ),
          ),
        ],
      ),
    );
  }

  Widget _remarkRow(BuildContext context, IncidentRemark r) {
    final text = r.action != null
        ? '${L('Action', 'Aksyon')}: ${localizeSystemMessage(r.action!)}${r.note.isNotEmpty ? ' — ${localizeSystemMessage(r.note)}' : ''}'
        : r.died != null
            ? '${L('Fish died', 'Namatay na isda')}: ${r.died}'
            : localizeSystemMessage(r.note);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fd(r.t),
              style:
                  TextStyle(fontSize: 11, color: AppTheme.of(context).inkSoft)),
          Text(text,
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: AppTheme.of(context).ink)),
        ],
      ),
    );
  }
}

/// Countdown for either the recommendation or the uninterrupted recovery check.
(int, double) _incidentTimer(Incident incident, int now) {
  final since = incident.safeSince ?? incident.ts;
  final duration = incident.isVerifying
      ? AppStore.verificationPeriod.inMilliseconds
      : paramMeta[incident.p]!.window(incident.lvl)[0] * 60000;
  final left = since + duration - now;
  return (left, duration > 0 ? (left / duration).clamp(0.0, 1.0) : 0.0);
}

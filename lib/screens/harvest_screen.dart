import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/incident.dart';
import '../services/app_store.dart';
import '../services/i18n.dart';
import '../utils/fmt.dart';
import '../widgets/reveal.dart';

/// Harvest (pag-ani) — ported from the prototype's harvest panel + timing
/// guide. Tracks the culture day, shows the 90/120/180-day guide, records each
/// harvest, and computes average size and peso value.
class HarvestScreen extends StatelessWidget {
  const HarvestScreen({super.key});

  // Culture-day guide milestones (days).
  static const _hg = [90, 120, 180];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>();
    final records = [...s.harvest]..sort((a, b) => b.t.compareTo(a.t));
    final n = records.fold<int>(0, (a, b) => a + b.n);
    final kg = records.fold<double>(0, (a, b) => a + b.kg);
    final value = records.fold<double>(0, (a, b) => a + b.value);
    final avg = n > 0 ? kg / n * 1000 : 0;

    return Scaffold(
      backgroundColor: AppTheme.of(context).bg,
      appBar: AppBar(
        title: Text(L('Harvest', 'Harvest (Pag-ani)')),
        backgroundColor: AppTheme.of(context).header,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Reveal(child: _cultureCard(context, s)),
          const SizedBox(height: 12),
          Reveal(
              delayMs: 40,
              child: _statsCard(context, s, n, kg, value, avg.toDouble())),
          const SizedBox(height: 12),
          Reveal(
            delayMs: 80,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _logHarvest(context, s),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(L('Log harvest', 'I-log ang harvest')),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(L('HARVEST RECORDS', 'MGA TALA NG HARVEST'),
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.of(context).inkSoft)),
          const SizedBox(height: 8),
          if (records.isEmpty)
            Text(L('No harvest logged yet.', 'Wala pang naka-log na harvest.'),
                style: TextStyle(color: AppTheme.of(context).inkSoft))
          else
            for (final h in records)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _recordRow(context, s, h),
              ),
        ],
      ),
    );
  }

  int? _cultureDay(AppStore s) {
    final d = DateTime.tryParse(s.stock.date);
    if (d == null) return null;
    return DateTime.now().difference(d).inDays.clamp(0, 1 << 30);
  }

  Widget _cultureCard(BuildContext context, AppStore s) {
    final d = _cultureDay(s);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.of(context).card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: AppTheme.of(context).deep.withOpacity(0.08),
                    shape: BoxShape.circle),
                child: Icon(Icons.schedule_rounded,
                    size: 20, color: AppTheme.of(context).deep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        d == null
                            ? '—'
                            : '${L('Day', 'Araw')} $d ${L('of culture', 'ng pag-aalaga')}',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.of(context).ink)),
                    Text(
                        '${L('Stocked', 'Na-stock')}: ${s.stock.date} · ${grp(s.stock.n)} fingerlings',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.of(context).inkSoft)),
                  ],
                ),
              ),
            ],
          ),
          if (d != null) ...[
            const SizedBox(height: 14),
            _guide(context, d),
          ],
        ],
      ),
    );
  }

  Widget _guide(BuildContext context, int d) {
    final stage = _stage(context, d);
    final pct = (d / _hg[2] * 100).clamp(0, 100).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: stage.$2.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999)),
              child: Text(stage.$1,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: stage.$2)),
            ),
            Text(L('Estimated guide', 'Tinatayang gabay'),
                style: TextStyle(
                    fontSize: 11, color: AppTheme.of(context).inkSoft)),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          Widget tick(int day) => Positioned(
                left: (day / _hg[2] * w).clamp(0, w - 2),
                child: Container(
                    width: 2,
                    height: 14,
                    color: AppTheme.of(context).ink.withOpacity(0.35)),
              );
          return SizedBox(
            height: 14,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 3,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                        color: AppTheme.of(context).border,
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                Positioned(
                  top: 3,
                  left: 0,
                  child: Container(
                    height: 8,
                    width: pct / 100 * w,
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          AppTheme.of(context).aqua,
                          AppTheme.of(context).deep
                        ]),
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                tick(_hg[0]),
                tick(_hg[1]),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0',
                style: TextStyle(
                    fontSize: 10, color: AppTheme.of(context).inkSoft)),
            Text('${_hg[0]}',
                style: TextStyle(
                    fontSize: 10, color: AppTheme.of(context).inkSoft)),
            Text('${_hg[1]}',
                style: TextStyle(
                    fontSize: 10, color: AppTheme.of(context).inkSoft)),
            Text('${_hg[2]} ${L('days', 'araw')}',
                style: TextStyle(
                    fontSize: 10, color: AppTheme.of(context).inkSoft)),
          ],
        ),
        const SizedBox(height: 10),
        Text(stage.$3,
            style: TextStyle(
                fontSize: 12.5, height: 1.5, color: AppTheme.of(context).ink)),
      ],
    );
  }

  /// Returns (badge, color, message) for the culture day.
  (String, Color, String) _stage(BuildContext context, int d) {
    if (d < _hg[0]) {
      return (
        L('Still growing', 'Lumalaki pa'),
        AppTheme.of(context).aqua,
        L('Too early to harvest. Start sampling at day ${_hg[0]} (${_hg[0] - d} days to go).',
            'Maaga pa. Magsimulang mag-sampling sa Araw ${_hg[0]} (${_hg[0] - d} araw pa).')
      );
    }
    if (d < _hg[1]) {
      return (
        L('Start sampling', 'Simulan ang sampling'),
        const Color(0xFF3B9BD6),
        L('Weigh a sample every 2 weeks to see how fast the fish are growing.',
            'Magtimbang ng sample kada 2 linggo para makita kung gaano kabilis lumaki.')
      );
    }
    if (d <= _hg[2]) {
      return (
        L('Harvest window', 'Puwede nang mag-harvest'),
        AppTheme.of(context).amber,
        L('Most tilapia reach market size now. Harvest when the average is about 250 g or more.',
            'Karaniwang market size na. Mag-harvest kapag mga 250 g pataas ang average.')
      );
    }
    return (
      L('Past the usual time', 'Lampas na sa karaniwan'),
      AppTheme.of(context).coral,
      L('Feed cost keeps rising while growth slows. Weigh a sample and plan the harvest soon.',
          'Tumataas ang gastos sa pakain habang bumabagal ang paglaki. Magtimbang at planuhin na ang harvest.')
    );
  }

  Widget _statsCard(BuildContext context, AppStore s, int n, double kg,
      double value, double avg) {
    Widget stat(String big, String label) => Expanded(
          child: Column(
            children: [
              Text(big,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.of(context).ink)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10.5, color: AppTheme.of(context).inkSoft)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.of(context).card(),
      child: Column(
        children: [
          Row(
            children: [
              stat(grp(n), L('HARVESTED', 'NA-HARVEST')),
              stat(kg.toStringAsFixed(1), 'KG'),
              stat(grp(s.aliveCount), L('IN POND', 'SA POND')),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              stat(avg > 0 ? '${avg.toStringAsFixed(0)} g' : '—',
                  L('AVG SIZE', 'KARANIWANG LAKI')),
              stat(peso(value), L('TOTAL VALUE', 'KABUUANG HALAGA')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recordRow(BuildContext context, AppStore s, HarvestRecord h) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.of(context).card(radius: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: AppTheme.of(context).aqua.withOpacity(0.15),
                shape: BoxShape.circle),
            child: Icon(Icons.shopping_basket_rounded,
                size: 20, color: AppTheme.of(context).aqua),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${grp(h.n)} ${L('fish', 'isda')} · ${h.kg.toStringAsFixed(1)} kg',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.of(context).ink)),
                Text(
                    '${dMed(h.t)} · ${h.fin ? L('Final harvest', 'Huling harvest') : L('Partial harvest', 'Bahagyang harvest')}',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.of(context).inkSoft)),
                Text(
                    '${L('Avg size', 'Karaniwang laki')}: ${h.avgGrams.toStringAsFixed(0)} g${h.price > 0 ? ' · ${peso(h.value)}' : ''}',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.of(context).inkSoft)),
                if (h.buyer.isNotEmpty)
                  Text('${L('Buyer / remarks', 'Bumili / tala')}: ${h.buyer}',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.of(context).inkSoft)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                size: 20, color: AppTheme.of(context).coral),
            onPressed: () => s.removeHarvest(h.id),
          ),
        ],
      ),
    );
  }

  Future<void> _logHarvest(BuildContext context, AppStore s) async {
    var isFinal = false;
    final dateCtl = TextEditingController(text: iso(DateTime.now()));
    final nCtl = TextEditingController();
    final kgCtl = TextEditingController();
    final priceCtl = TextEditingController();
    final buyerCtl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppTheme.of(context).bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L('Log harvest', 'I-log ang harvest'),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.of(context).ink)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: Text(L('Partial', 'Bahagya')),
                        selected: !isFinal,
                        onSelected: (_) => setSheet(() => isFinal = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: Text(L('Final', 'Huli')),
                        selected: isFinal,
                        onSelected: (_) => setSheet(() => isFinal = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _field(dateCtl, L('Date (yyyy-mm-dd)', 'Petsa (yyyy-mm-dd)')),
                _field(nCtl, L('Number of fish', 'Bilang ng isda'),
                    number: true),
                _field(kgCtl, L('Total weight (kg)', 'Kabuuang timbang (kg)'),
                    number: true),
                _field(
                    priceCtl,
                    L('Price per kg (₱, optional)',
                        'Presyo kada kilo (₱, opsyonal)'),
                    number: true),
                _field(
                    buyerCtl,
                    L('Buyer / remarks (optional)',
                        'Bumili / tala (opsyonal)')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(L('Cancel', 'Kanselahin')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(L('Save', 'I-save')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok != true) return;
    final n = int.tryParse(nCtl.text.trim()) ?? 0;
    final kg = double.tryParse(kgCtl.text.trim()) ?? 0;
    final price = double.tryParse(priceCtl.text.trim()) ?? 0;
    if (n < 1 || kg <= 0) {
      _toast(
          context,
          L('Enter the number of fish and the total weight.',
              'Ilagay ang bilang ng isda at ang kabuuang timbang.'));
      return;
    }
    if (n > s.aliveCount) {
      _toast(
          context,
          L('Only about ${grp(s.aliveCount)} fish are left in the pond.',
              'Mga ${grp(s.aliveCount)} na lang ang isda sa pond.'));
      return;
    }
    final parsed = DateTime.tryParse(dateCtl.text.trim());
    final t = parsed == null
        ? DateTime.now().millisecondsSinceEpoch
        : DateTime(parsed.year, parsed.month, parsed.day, 12)
            .millisecondsSinceEpoch;
    s.addHarvest(HarvestRecord(
      id: DateTime.now().millisecondsSinceEpoch,
      t: t,
      n: n,
      kg: kg,
      price: price < 0 ? 0 : price,
      fin: isFinal,
      buyer: buyerCtl.text.trim(),
    ));
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        ),
      );

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

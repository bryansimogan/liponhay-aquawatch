import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/incident.dart';
import '../services/app_store.dart';
import '../services/i18n.dart';

class StockingSheet extends StatefulWidget {
  const StockingSheet({super.key});

  @override
  State<StockingSheet> createState() => _StockingSheetState();
}

class _StockingSheetState extends State<StockingSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _count;
  late final TextEditingController _area;
  late final TextEditingController _date;
  late DateTime _stockedAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final stock = context.read<AppStore>().stock;
    _count = TextEditingController(text: '${stock.n}');
    _area = TextEditingController(text: stock.area > 0 ? '${stock.area}' : '');
    _stockedAt = DateTime.tryParse(stock.date) ?? DateTime.now();
    _date = TextEditingController();
  }

  @override
  void dispose() {
    _count.dispose();
    _area.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
        context: context,
        initialDate: _stockedAt.isAfter(today) ? today : _stockedAt,
        firstDate: DateTime(1900),
        lastDate: today);
    if (picked != null && mounted) setState(() => _stockedAt = picked);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final stock = Stocking(
        n: int.parse(_count.text.trim()),
        area: num.parse(_area.text.trim()),
        date: DateFormat('yyyy-MM-dd').format(_stockedAt));
    final store = context.read<AppStore>();
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await store.saveStocking(stock).timeout(const Duration(seconds: 12));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = L(
              'Could not confirm the save. Check your connection and try again.',
              'Hindi nakumpirma ang pag-save. Suriin ang koneksyon at subukang muli.');
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.select<AppStore, String>((store) => store.lang);
    final palette = AppTheme.of(context);
    _date.text = DateFormat.yMMMd(appDateLocale).format(_stockedAt);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 22, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L('Stocking', 'Pag-stock ng isda'),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: palette.ink)),
                const SizedBox(height: 20),
                TextFormField(
                    controller: _count,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                        labelText: L(
                            'Fingerlings stocked', 'Na-stock na fingerlings')),
                    validator: (text) =>
                        int.tryParse(text?.trim() ?? '') == null
                            ? L('Enter the number of stocked fish.',
                                'Ilagay ang bilang ng na-stock na isda.')
                            : null),
                const SizedBox(height: 18),
                TextFormField(
                    controller: _area,
                    enabled: !_saving,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText:
                            L('Pond area (m²)', 'Lawak ng palaisdaan (m²)')),
                    validator: (text) {
                      final value = num.tryParse(text?.trim() ?? '');
                      return value == null || !value.isFinite || value <= 0
                          ? L('Enter a pond area greater than zero.',
                              'Maglagay ng lawak na mas mataas sa zero.')
                          : null;
                    }),
                const SizedBox(height: 18),
                TextFormField(
                    controller: _date,
                    readOnly: true,
                    enabled: !_saving,
                    onTap: _saving ? null : _pickDate,
                    decoration: InputDecoration(
                        labelText: L('Date stocked', 'Petsa ng pag-stock'),
                        suffixIcon: const Icon(Icons.calendar_today_outlined,
                            size: 18)),
                    validator: (_) => DateUtils.dateOnly(_stockedAt)
                            .isAfter(DateUtils.dateOnly(DateTime.now()))
                        ? L('Choose today or an earlier date.',
                            'Pumili ng petsa ngayon o mas maaga.')
                        : null),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(_error!,
                          style: TextStyle(color: palette.coral))),
                const SizedBox(height: 24),
                Row(children: [
                  FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(L('Save', 'I-save'))),
                  const SizedBox(width: 12),
                  OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46)),
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: Text(L('Cancel', 'Kanselahin'))),
                ]),
              ],
            )),
      ),
    );
  }
}

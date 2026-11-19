import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../models/mortality_record.dart';
import '../models/mortality_analysis.dart';
import '../services/firebase_service.dart';
import '../services/app_store.dart';
import '../services/i18n.dart';
import '../services/offline_cache_service.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_header.dart';
import '../widgets/fish_icon.dart';
import '../widgets/loading_emblem.dart';
import '../widgets/paged_list.dart';
import '../widgets/reveal.dart';

/// Fish mortality log, one calendar month at a time.
///
/// The screen keeps every record streaming in the background but only ever
/// shows the selected period, so the list can never become the flat wall of
/// entries it used to be. The period defaults to the current month and rolls
/// over on its own — a record filed on 1 October lands in October because the
/// month is read off its date, never stored as a bare name.
class MortalityScreen extends StatefulWidget {
  const MortalityScreen({super.key});

  @override
  State<MortalityScreen> createState() => _MortalityScreenState();
}

class _MortalityScreenState extends State<MortalityScreen> {
  final FirebaseService _firebase = FirebaseService();
  late final AppStore _store;
  StreamSubscription<List<MortalityRecord>>? _subscription;

  String _pondId = 'pond1';
  bool get _simMode => _store.simulation;
  String _demoKey(String pondId) => 'demo_mortality_$pondId';
  bool _loading = true;

  /// Every record for the pond. Filtered to [_selectedYear]/[_selectedMonth]
  /// for display — the full set stays here so switching months is instant and
  /// the summary can be recomputed without another read.
  List<MortalityRecord> _records = [];

  /// The active period. Starts on the current month and, because it is only
  /// ever seeded from DateTime.now(), the "current" period follows the real
  /// calendar with no manual rollover.
  late int _selectedYear;
  late int _selectedMonth;

  // ── Form state ──
  bool _formOpen = false;
  bool _saving = false;

  /// Id of the record currently being deleted, so only its row shows a spinner.
  String? _deletingId;

  /// Set when editing; null when adding a new record.
  MortalityRecord? _editing;

  final _countController = TextEditingController();
  final _notesController = TextEditingController();
  String? _pendingId;
  DateTime? _reportedAt;
  MortalityAnalysis? _pendingAnalysis;
  final _resolvedAnalyses = <String, MortalityAnalysis>{};

  @override
  void initState() {
    super.initState();
    _store = context.read<AppStore>();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _load();
  }

  Future<void> _load() async {
    final pondId = _pondId;
    unawaited(_subscription?.cancel());
    setState(() => _loading = true);
    var initial = <MortalityRecord>[];
    if (_simMode) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_demoKey(pondId));
      if (raw != null) {
        try {
          initial = (jsonDecode(raw) as List)
              .whereType<Map>()
              .map((row) => MortalityRecord.fromMap(row['id'] as String, row))
              .toList();
        } on FormatException {
          initial = [];
        } on TypeError {
          initial = [];
        }
      }
    } else {
      initial = await OfflineCacheService.mortality(pondId);
    }
    if (!mounted || pondId != _pondId) return;
    setState(() {
      _records = initial;
      _loading = false;
    });
    _store.replaceMortalityRecords(pondId, initial);
    if (_simMode) return;
    _subscription = _firebase.mortalityStream(pondId).listen((records) {
      if (mounted && pondId == _pondId) {
        setState(() => _records = records);
        _store.replaceMortalityRecords(pondId, records);
      }
    }, onError: (Object _) {});
  }

  Future<void> _saveDemo(String pondId, List<MortalityRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _demoKey(pondId),
      jsonEncode([
        for (final record in records) {'id': record.id, ...record.toMap()},
      ]),
    );
    if (mounted && _pondId == pondId) setState(() => _records = records);
    _store.replaceMortalityRecords(pondId, records);
  }

  /// Records in the active period, newest first.
  List<MortalityRecord> get _visible {
    final list = _records
        .where((r) => r.inPeriod(_selectedYear, _selectedMonth))
        .toList()
      ..sort((a, b) {
        final dateOrder = b.when.compareTo(a.when);
        return dateOrder == 0 ? b.timestamp.compareTo(a.timestamp) : dateOrder;
      });
    return list;
  }

  int get _periodDeaths => _visible.fold(0, (sum, r) => sum + r.count);

  bool get _isCurrentPeriod {
    final now = DateTime.now();
    return _selectedYear == now.year && _selectedMonth == now.month;
  }

  String get _periodLabel => DateFormat(
        'MMMM yyyy',
        appDateLocale,
      ).format(DateTime(_selectedYear, _selectedMonth));

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _countController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Period navigation ──

  void _shiftPeriod(int months) {
    final next = DateTime(_selectedYear, _selectedMonth + months);
    // Never step past the current month — future months hold nothing.
    final now = DateTime(DateTime.now().year, DateTime.now().month);
    if (next.isAfter(now)) return;
    setState(() {
      _selectedYear = next.year;
      _selectedMonth = next.month;
    });
  }

  Future<void> _pickPeriod() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: AppTheme.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PeriodPicker(year: _selectedYear, month: _selectedMonth),
    );
    if (mounted && picked != null) {
      setState(() {
        _selectedYear = picked.year;
        _selectedMonth = picked.month;
      });
    }
  }

  // ── Form actions ──

  void _openForm({MortalityRecord? existing}) {
    if (_saving || _deletingId != null) return;
    setState(() {
      _editing = existing;
      _formOpen = true;
      _pendingId = null;
      _reportedAt = null;
      _pendingAnalysis = null;
      _countController.text = existing == null ? '' : '${existing.count}';
      _notesController.text = existing?.notes ?? '';
    });
  }

  void _closeForm() {
    setState(() {
      _formOpen = false;
      _editing = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final count = int.tryParse(_countController.text.trim()) ?? 0;
    if (count <= 0) {
      _toast(
        L('Enter how many fish died.', 'Ilagay kung ilang isda ang namatay.'),
      );
      return;
    }
    final existing = _editing;
    final pondId = existing?.pondId ?? _pondId;
    final reportedAt = _reportedAt ??= _simMode
        ? DateTime.fromMillisecondsSinceEpoch(_store.nowMs)
        : DateTime.now();
    final species = existing?.species ?? MortalityRecord.speciesForPond(pondId);

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    late MortalityRecord record;
    try {
      final id = existing?.id ??
          (_pendingId ??= _simMode
              ? DateTime.now().microsecondsSinceEpoch.toString()
              : _firebase.newMortalityId(pondId));
      var analysis = existing?.analysis ?? _pendingAnalysis;
      if (existing == null && analysis == null) {
        analysis = await _analyze(pondId, species, reportedAt);
        _pendingAnalysis = analysis;
      }
      record = MortalityRecord(
        id: id,
        date: existing?.date ?? DateFormat('yyyy-MM-dd').format(reportedAt),
        pondId: pondId,
        species: species,
        count: count,
        possibleCause: existing?.possibleCause ??
            (analysis!.findings.isEmpty
                ? ''
                : analysis.findings.first.factor.english),
        notes: _notesController.text.trim(),
        timestamp: existing?.timestamp ?? reportedAt.millisecondsSinceEpoch,
        analysis: analysis,
      );

      if (_simMode) {
        await _saveDemo(pondId, [
          record,
          ..._records.where((previous) => previous.id != record.id),
        ]);
      } else {
        final write = existing == null
            ? _firebase.addMortalityRecord(record)
            : _firebase.updateMortalityCount(
                pondId: record.pondId,
                recordId: record.id,
                count: record.count,
                notes: record.notes,
              );
        await write.timeout(const Duration(seconds: 12));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _toast(
          L(
            'Could not confirm the save. Please try again.',
            'Hindi nakumpirma ang pag-save. Pakisubukan ulit.',
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _selectedYear = record.year;
      _selectedMonth = record.month;
    });
    _closeForm();
    _toast(
      existing != null
          ? L('Mortality record updated.', 'Na-update ang tala.')
          : L(
              'Mortality record saved.',
              'Na-save ang tala ng namatay na isda.',
            ),
    );
    if (existing == null) await _showRecordDetails(record);
  }

  Future<MortalityAnalysis> _analyze(
    String pondId,
    String species,
    DateTime eventAt,
  ) async {
    final captured = !_simMode && pondId == 'pond1' && _store.hasCurrentReading
        ? MortalityReading.fromSensor(_store.currentReading)
        : null;
    final readings = _simMode
        ? _store.demoReadings
            .map(MortalityReading.fromSensor)
            .whereType<MortalityReading>()
        : await _firebase.getMortalityReadings(pondId, eventAt: eventAt);
    return MortalityAnalysis.evaluate([
      if (captured != null) captured,
      ...readings,
    ], eventAt: eventAt, species: species);
  }

  Future<MortalityAnalysis?> _analysisFor(MortalityRecord record) async {
    final eventAt = record.eventAt;
    if (eventAt == null) return null;
    final saved = _resolvedAnalyses[record.id] ?? record.analysis;
    if (saved != null && saved.usesEventMatch) {
      return saved;
    }
    final analysis = await _analyze(record.pondId, record.species, eventAt);
    if (mounted) setState(() => _resolvedAnalyses[record.id] = analysis);
    return analysis;
  }

  Future<void> _confirmDelete(MortalityRecord r) async {
    if (_deletingId != null || _saving) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L('Delete this record?', 'Burahin ang tala na ito?')),
        content: Text(
          '${r.count} ${L('fish', 'isda')} · ${_cause(r)}\n'
          '${_prettyDate(r.date)}\n\n'
          '${L('This cannot be undone.', 'Hindi na ito maibabalik.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L('Cancel', 'Kanselahin')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.of(context).coral,
            ),
            child: Text(L('Delete', 'Burahin')),
          ),
        ],
      ),
    );
    if (!mounted || ok != true || _deletingId != null || _saving) return;

    setState(() => _deletingId = r.id);
    try {
      if (_simMode) {
        await _saveDemo(r.pondId, _records.where((x) => x.id != r.id).toList());
      } else {
        await _firebase
            .deleteMortalityRecord(pondId: r.pondId, recordId: r.id)
            .timeout(const Duration(seconds: 12));
      }
    } catch (_) {
      if (mounted)
        _toast(
          L(
            'Could not delete the record. Please try again.',
            'Hindi nabura ang tala. Pakisubukan ulit.',
          ),
        );
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    context.select<AppStore, String>((store) => store.lang);
    final visible = _visible;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          AppHeader(
            selectedPondId: _pondId,
            onPondChanged: _saving
                ? null
                : (id) {
                    _closeForm();
                    setState(() => _pondId = id);
                    _load();
                  },
          ),
          Expanded(
            child: _loading
                ? const EmblemLoader()
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Column(
                          children: [
                            Reveal(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      L(
                                        'Fish Mortality',
                                        'Tala ng Namatay na Isda',
                                      ),
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.of(context).ink,
                                      ),
                                    ),
                                  ),
                                  _LogButton(
                                    open: _formOpen,
                                    onTap: _saving
                                        ? null
                                        : () => _formOpen
                                            ? _closeForm()
                                            : _openForm(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Reveal(delayMs: 40, child: _periodCard(visible)),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _formOpen
                            ? SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                child: _buildForm(),
                              )
                            : Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: PagedList(
                                  perPage: 4,
                                  items: [
                                    for (final r in visible) _recordCard(r),
                                  ],
                                  empty: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 40,
                                        horizontal: 20,
                                      ),
                                      decoration: AppTheme.of(context).card(),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          FishIcon(
                                            size: 34,
                                            color: AppTheme.of(
                                              context,
                                            ).inkSoft.withOpacity(0.35),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            L(
                                              'No records for $_periodLabel',
                                              'Walang tala para sa $_periodLabel',
                                            ),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.of(context).ink,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _isCurrentPeriod
                                                ? L(
                                                    'Tap Log to record a loss.',
                                                    'Pindutin ang Itala para magdagdag ng tala.',
                                                  )
                                                : L(
                                                    'Nothing was logged this month.',
                                                    'Walang naitala ngayong buwan.',
                                                  ),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.of(
                                                context,
                                              ).inkSoft,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }

  /// The period selector plus this month's totals — section 4's summary.
  Widget _periodCard(List<MortalityRecord> visible) {
    final now = DateTime.now();
    final atCurrent = _selectedYear == now.year && _selectedMonth == now.month;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: AppTheme.of(context).card(),
      child: Column(
        children: [
          Row(
            children: [
              _PeriodArrow(
                icon: Icons.chevron_left_rounded,
                onTap: () => _shiftPeriod(-1),
              ),
              Expanded(
                child: InkWell(
                  onTap: _pickPeriod,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _periodLabel,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.of(context).ink,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              Icons.expand_more_rounded,
                              size: 17,
                              color: AppTheme.of(context).inkSoft,
                            ),
                          ],
                        ),
                        if (atCurrent) ...[
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.of(
                                context,
                              ).deep.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              L('ACTIVE PERIOD', 'KASALUKUYANG BUWAN'),
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: AppTheme.of(context).deep,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              _PeriodArrow(
                icon: Icons.chevron_right_rounded,
                // Disabled at the current month — there is no future to show.
                onTap: atCurrent ? null : () => _shiftPeriod(1),
              ),
            ],
          ),
          Divider(height: 1, color: AppTheme.of(context).border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: _summaryStat(
                    '$_periodDeaths',
                    L('FISH LOST', 'NAMATAY NA ISDA'),
                    AppTheme.of(context).coral,
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: AppTheme.of(context).border,
                ),
                Expanded(
                  child: _summaryStat(
                    '${visible.length}',
                    L(visible.length == 1 ? 'RECORD' : 'RECORDS', 'TALA'),
                    AppTheme.of(context).deep,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppTheme.of(context).inkSoft,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    final isEditing = _editing != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.of(context).card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isEditing
                      ? L('Edit Record', 'I-edit ang Tala')
                      : L('New Mortality Record', 'Bagong Tala'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.of(context).ink,
                  ),
                ),
              ),
              IconButton(
                onPressed: _saving ? null : _closeForm,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppTheme.of(context).inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _countController,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: L(
                'Number of fish that died',
                'Bilang ng namatay na isda',
              ),
              hintText: L('e.g. 3', 'hal. 3'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            enabled: !_saving,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: L('Remarks or observations (optional)',
                  'Mga tala o obserbasyon (opsyonal)'),
            ),
          ),
          if (!isEditing) ...[
            const SizedBox(height: 10),
            Text(
              _simMode
                  ? L(
                      'Matches demo readings to the report time.',
                      'Hahanapin ang demo reading na pinakamalapit sa oras ng pag-uulat.',
                    )
                  : L(
                      'Matches recorded ESP32 readings to the report time.',
                      'Hahanapin ang ESP32 reading na pinakamalapit sa oras ng pag-uulat.',
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _closeForm,
                  child: Text(L('Cancel', 'Kanselahin')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  // Disabled while saving — the guard in _save is the real
                  // duplicate defence, this makes it visible.
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          isEditing ? Icons.check_rounded : Icons.save_rounded,
                          size: 16,
                        ),
                  label: Text(
                    _saving
                        ? L('Working…', 'Pinoproseso…')
                        : (isEditing
                            ? L('Update', 'I-update')
                            : L('Save Record', 'I-save ang Tala')),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _cause(MortalityRecord record) {
    final analysis = _resolvedAnalyses[record.id] ?? record.analysis;
    if (analysis?.usesEventMatch == true) return _suspectedCause(analysis);
    return L(
        'Open to check event readings', 'Buksan para makita ang mga reading');
  }

  String _suspectedCause(MortalityAnalysis? analysis) {
    if (analysis == null || analysis.insufficient) {
      return L(
        'Insufficient Data to Determine Suspected Cause',
        'Kulang ang datos para matukoy ang pinaghihinalaang sanhi',
      );
    }
    if (analysis.findings.isEmpty) {
      return L('No abnormal measured readings',
          'Walang abnormal sa mga nasukat na reading');
    }
    return analysis.findings
        .map((finding) => L(finding.factor.english, finding.factor.tagalog))
        .join(' · ');
  }

  String _dateTime(int value) => DateFormat.yMMMd(appDateLocale)
      .add_jm()
      .format(DateTime.fromMillisecondsSinceEpoch(value));

  Widget _sectionHeading(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 12),
        child: Text(title,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: .7,
                color: AppTheme.of(context).inkSoft)),
      );

  Widget _analysisCard(List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.of(context)
            .card(borderColor: AppTheme.of(context).border, radius: 22),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _checkLine(String text, {bool warning = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                  warning ? Icons.info_outline_rounded : Icons.check_rounded,
                  size: 19,
                  color: warning
                      ? AppTheme.of(context).amber
                      : AppTheme.of(context).aqua)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.55,
                      color: AppTheme.of(context).ink))),
        ]),
      );

  Widget _analysisDetails(MortalityAnalysis? analysis, MortalityRecord record) {
    final reading = analysis?.reading;
    final findings = analysis?.findings ?? const <MortalityFinding>[];
    final missing = L('Not recorded', 'Walang naitalang reading');
    String measured(double? value, MortalityFactor factor) =>
        value == null ? missing : factor.format(value);
    final valid = analysis != null && !analysis.insufficient;
    final summary = !valid || findings.isEmpty
        ? _suspectedCause(analysis)
        : findings.map((finding) {
            final severity = finding.criticalCount > 0
                ? L('Critical', 'Kritikal')
                : L('Warning', 'Babala');
            return '${L(finding.factor.english, finding.factor.tagalog)} '
                '($severity · ${finding.factor.format(finding.extreme)})';
          }).join(' + ');
    final checklist = <Widget>[];
    if (analysis == null) {
      checklist.add(_checkLine(
          L('The original record has a date only. A reading cannot be matched to an exact event time.',
              'Petsa lang ang nasa orihinal na tala. Kailangan ang oras para maitugma ang reading.'),
          warning: true));
    } else if (reading == null) {
      checklist.add(_checkLine(
          L('No usable reading was found within 30 minutes of the recorded event.',
              'Walang magagamit na reading sa loob ng 30 minuto mula sa nakatalang oras.'),
          warning: true));
    } else if (analysis.readingAfterEvent) {
      checklist.add(_checkLine(
          L('The available reading was taken after the event. A reading from the time of the event or shortly before is needed to suggest a cause.',
              'Pagkatapos ng insidente nakuha ang reading. Kailangan ang reading noong insidente o ilang minuto bago ito para makapagmungkahi ng sanhi.'),
          warning: true));
    } else if (analysis.readingOutdated) {
      checklist.add(_checkLine(
          L('The latest available reading is more than 30 minutes older than this report. It is preserved here, but a fresh reading is needed to estimate a suspected cause.',
              'Mahigit 30 minuto nang luma ang pinakabagong reading kumpara sa ulat. Naka-save ito rito, pero kailangan ng sariwang reading para matantiya ang posibleng sanhi.'),
          warning: true));
    } else if (!analysis.hasSpeciesProfile) {
      checklist.add(_checkLine(
          L('A water quality profile for this species is needed to assess these readings.',
              'Kailangan ang mga limitasyon sa kalidad ng tubig para sa species na ito upang masuri ang readings.'),
          warning: true));
    } else {
      checklist.add(_checkLine(record.analysis?.usesEventMatch == true
          ? L('When this mortality was logged, the app saved the available sensor readings with the record. These saved values are shown in “Readings when logged” above.',
              'Nang itala ang namatay na isda, na-save kasama ng tala ang mga available na sensor reading. Nasa “Mga reading noong itinala” sa itaas ang mga na-save na halaga.')
          : L('The closest recorded reading at or before this event was matched to its original date and time.',
              'Itinugma sa orihinal na petsa at oras ng insidente ang pinakamalapit na naitalang reading noong insidente o bago ito.')));
      checklist.add(_checkLine(L(
          'It compares the readings with the tilapia monitoring ranges. pH 6.5–8.5, temperature 25–32 °C, and dissolved oxygen 5.0 mg/L and above.',
          'Inihahambing ang readings sa saklaw para sa tilapia. pH 6.5–8.5, temperatura 25–32 °C, at dissolved oxygen na 5.0 mg/L pataas.')));
      if (!reading.hasMonitoredParameters) {
        checklist.add(_checkLine(
            L('This snapshot is incomplete. Only the measured parameters can be assessed.',
                'Kulang ang snapshot na ito. Ang mga parameter lang na nasukat ang maaaring suriin.'),
            warning: true));
      }
      for (final finding in findings) {
        checklist.add(_checkLine('${_findingExplanation(finding, reading)} '
            '${_healthEffect(finding.factor)}'));
      }
      if (findings.length > 1) {
        checklist.add(_checkLine(L(
            'Critical problems are listed first, followed by warnings. Multiple abnormal readings are shown together as possible contributing causes.',
            'Nauuna ang mga kritikal na problema, kasunod ang mga babala. Sama-samang ipinapakita ang mga abnormal na reading bilang mga posibleng salik.')));
      }
      if (findings.isEmpty && reading.hasMonitoredParameters) {
        checklist.add(_checkLine(L(
            'The recorded parameters were within their monitoring limits. Disease, infection, handling stress, or other factors require a separate investigation.',
            'Nasa saklaw ang mga naitalang parameter. Kailangan ng hiwalay na pagsusuri para sa sakit, impeksiyon, stress sa paghawak, o iba pang salik.')));
      }
    }
    checklist.add(_checkLine(
        L('These findings are suspected causes based on the recorded evidence. If deaths continue, ask a fisheries technician to examine the fish and water.',
            'Mga pinaghihinalaang sanhi ang mga ito batay sa naitalang ebidensya. Kung patuloy ang pagkamatay, ipasuri ang isda at tubig sa fisheries technician.'),
        warning: true));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _analysisCard([
        Text(L('Suspected cause', 'Pinaghihinalaang sanhi'),
            style:
                TextStyle(fontSize: 13, color: AppTheme.of(context).inkSoft)),
        const SizedBox(height: 7),
        Text(summary,
            style: TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: AppTheme.of(context).ink)),
        const SizedBox(height: 12),
        Text(
            reading == null
                ? L('Readings unavailable', 'Walang available na reading')
                : '${L('Readings when logged', 'Mga reading noong itinala')} · '
                    'DO ${measured(reading.dissolvedOxygen, MortalityFactor.lowOxygen)} · '
                    'pH ${measured(reading.ph, MortalityFactor.lowPh)} · '
                    '${measured(reading.temperature, MortalityFactor.lowTemperature)}'
                    '${reading.ammoniaNh3 == null ? '' : ' · NH₃ ${MortalityFactor.highAmmonia.format(reading.ammoniaNh3!)}'}',
            style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: AppTheme.of(context).inkSoft)),
        if (reading != null) ...[
          const SizedBox(height: 5),
          Text(
              '${L('Recorded at', 'Oras ng reading')} · ${_dateTime(reading.timestamp)}',
              style:
                  TextStyle(fontSize: 11, color: AppTheme.of(context).inkSoft)),
        ],
      ]),
      _sectionHeading(
          L('HOW WAS THIS CAUSE FOUND?', 'PAANO NATUKOY ANG SANHI?')),
      _analysisCard(checklist),
      _sectionHeading(
          L('HOW TO LESSEN IT NEXT TIME', 'PAANO MABABAWASAN SA SUSUNOD')),
      if (findings.isEmpty)
        _analysisCard([
          Text(L('Further checks', 'Karagdagang pagsusuri'),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.of(context).ink)),
          const SizedBox(height: 12),
          _checkLine(L(
              'Record the time of losses and any unusual fish behavior.',
              'Itala ang oras ng pagkamatay at anumang kakaibang kilos ng isda.')),
          _checkLine(L(
              'Take a fresh water sample and verify the sensor readings.',
              'Kumuha ng sariwang sample ng tubig at kumpirmahin ang sensor readings.')),
          _checkLine(L('If losses continue, consult a fisheries technician.',
              'Kung patuloy ang pagkamatay, kumonsulta sa fisheries technician.')),
        ])
      else
        for (final finding in findings) ...[
          _analysisCard([
            Text(L(finding.factor.english, finding.factor.tagalog),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.of(context).ink)),
            const SizedBox(height: 10),
            Text(_healthEffect(finding.factor),
                style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: AppTheme.of(context).inkSoft)),
            const SizedBox(height: 16),
            for (final tip in _prevention(finding.factor)) _checkLine(tip),
          ]),
          const SizedBox(height: 12),
        ],
    ]);
  }

  String _findingExplanation(
      MortalityFinding finding, MortalityReading reading) {
    final factor = finding.factor;
    final value = factor.format(finding.extreme);
    final label = L(factor.english, factor.tagalog);
    final threshold = finding.threshold;
    if (threshold == null) return '$label · $value';
    final limit = factor.format(threshold);
    if (factor == MortalityFactor.highOxygen) {
      return L(
        '$label · $value meets the $limit screening trigger at ${reading.temperature?.toStringAsFixed(1) ?? '—'} °C, based on estimated freshwater oxygen saturation at sea level.',
        '$label · Umabot ang $value sa $limit na antas para sa pagsusuri sa ${reading.temperature?.toStringAsFixed(1) ?? '—'} °C, batay sa tinatayang oxygen saturation ng freshwater sa sea level.',
      );
    }
    if (factor == MortalityFactor.highAmmonia) {
      return L(
          '$label · Measured NH₃ was $value. The tilapia reference is below $limit.',
          '$label · $value ang nasukat na NH₃. Ang gabay para sa tilapia ay mas mababa sa $limit.');
    }
    final severity = finding.criticalCount > 0
        ? L('Critical', 'Kritikal')
        : L('Warning', 'Babala');
    final direction = factor.lower
        ? L('below', 'mas mababa sa')
        : L('above', 'mas mataas sa');
    return L(
      '$label · $value is $direction the $limit monitoring limit ($severity).',
      '$label · Ang $value ay $direction limitasyong $limit ($severity).',
    );
  }

  String _healthEffect(MortalityFactor factor) => switch (factor) {
        MortalityFactor.lowOxygen => L(
            'Low oxygen can cause gasping, stress, and suffocation.',
            'Maaaring magdulot ng paghabol ng hangin, stress, at pagkamatay ang kakulangan ng oxygen.'),
        MortalityFactor.highOxygen => L(
            'An elevated oxygen reading warrants checking gas saturation and meter calibration.',
            'Kailangang suriin ang gas saturation at calibration ng meter kapag mataas ang oxygen reading.'),
        MortalityFactor.highAmmonia => L(
            'Un-ionized ammonia can damage gills and interfere with breathing.',
            'Maaaring makasira ng hasang at makaapekto sa paghinga ang un-ionized ammonia.'),
        MortalityFactor.highTemperature => L(
            'Warm water raises oxygen demand while holding less oxygen.',
            'Tumataas ang pangangailangan ng isda sa oxygen habang mas kaunti ang oxygen sa mainit na tubig.'),
        MortalityFactor.lowTemperature => L(
            'Cold water can suppress feeding and weaken the fish’s stress response.',
            'Maaaring humina ang pagkain at kakayahang makayanan ang stress kapag malamig ang tubig.'),
        MortalityFactor.highPh => L(
            'High pH can irritate the gills and increase the toxic fraction of any ammonia present.',
            'Maaaring mairita ang hasang at tumaas ang nakalalasong bahagi ng ammonia kapag mataas ang pH.'),
        MortalityFactor.lowPh => L(
            'Acidic water can irritate the gills and disrupt the fish’s salt balance.',
            'Maaaring mairita ang hasang at maapektuhan ang balanse ng asin sa katawan ng isda kapag acidic ang tubig.'),
      };

  List<String> _prevention(MortalityFactor factor) => switch (factor) {
        MortalityFactor.lowOxygen => [
            L('Keep the aerator and backup power ready. Check oxygen before sunrise and maintain adequate aeration overnight.',
                'Ihanda ang aerator at backup power. Sukatin ang oxygen bago sumikat ang araw at tiyaking sapat ang aeration sa gabi.'),
            L('Avoid overfeeding and remove leftover feed before it breaks down and consumes oxygen.',
                'Iwasan ang sobrang pakain at alisin ang tirang pagkain bago ito mabulok at kumonsumo ng oxygen.'),
            L('Reduce feeding while dissolved oxygen is low, especially during cloudy conditions.',
                'Bawasan ang pakain habang mababa ang dissolved oxygen, lalo na kapag maulap.'),
            L('Keep stocking density within the capacity of the pond and aeration equipment.',
                'Iayon ang dami ng isda sa kayang suportahan ng pond at ng aeration equipment.'),
          ],
        MortalityFactor.highOxygen => [
            L('Verify the reading with a calibrated meter at several depths.',
                'Kumpirmahin ang reading gamit ang calibrated meter sa iba’t ibang lalim.'),
            L('Track afternoon oxygen peaks.',
                'Bantayan ang pagtaas ng oxygen sa hapon.'),
            L('Ask a technician to check total dissolved gases if high readings persist.',
                'Ipasuri sa technician ang kabuuang dissolved gases kung patuloy na mataas ang reading.'),
          ],
        MortalityFactor.highAmmonia => [
            L('Retest ammonia together with pH and temperature.',
                'Sukatin muli ang ammonia kasama ng pH at temperatura.'),
            L('Reduce feeding while levels remain high and remove excess feed.',
                'Bawasan muna ang pakain habang mataas ang reading at alisin ang sobrang pakain.'),
            L('Check water exchange or filtration.',
                'Suriin ang pagpapalit ng tubig o filtration.'),
          ],
        MortalityFactor.highTemperature => [
            L('Track afternoon temperatures.',
                'Bantayan ang temperatura sa hapon.'),
            L('Provide shade or access to deeper water.',
                'Maglaan ng lilim o mas malalim na bahagi ng pond.'),
            L('Check dissolved oxygen during hot periods.',
                'Suriin ang oxygen kapag mainit.'),
          ],
        MortalityFactor.lowTemperature => [
            L('Track early-morning temperatures.',
                'Bantayan ang temperatura sa madaling-araw.'),
            L('Check incoming water before adding it.',
                'Sukatin ang papasok na tubig bago ito idagdag.'),
            L('Make temperature changes gradually.',
                'Iwasan ang biglaang pagbabago ng temperatura.'),
          ],
        MortalityFactor.highPh => [
            L('Compare morning and afternoon pH.',
                'Ihambing ang pH sa umaga at hapon.'),
            L('Check for algae blooms.', 'Tingnan kung may algal bloom.'),
            L('Test ammonia when pH stays high.',
                'Mag-test ng ammonia kapag patuloy na mataas ang pH.'),
          ],
        MortalityFactor.lowPh => [
            L('Recheck pH and alkalinity in the pond.',
                'Sukatin muli ang pH at alkalinity ng pond.'),
            L('Test the source water.', 'Suriin ang tubig sa pinagkukunan.'),
            L('Ask a technician how to correct persistently low pH gradually.',
                'Kumonsulta sa technician para sa unti-unting pagwawasto kung patuloy na mababa ang pH.'),
          ],
      };

  Widget _recordCard(MortalityRecord r) {
    final deleting = _deletingId == r.id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: deleting ? null : () => _showRecordDetails(r),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: AppTheme.of(context).card(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.of(context).coral.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: FishIcon(size: 17, color: AppTheme.of(context).coral),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${r.count} ${L('fish', 'isda')} · ${Pond.byId(r.pondId).name}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.of(context).ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _prettyDate(r.date),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.of(context).inkSoft,
                          ),
                        ),
                      ],
                    ),
                    ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.of(context).deep.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _cause(r),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.of(context).deep,
                          ),
                        ),
                      ),
                    ],
                    if (r.notes.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        r.notes,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: AppTheme.of(context).inkSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Edit + delete. While a delete is in flight the row shows a spinner
              // in place of the buttons so it cannot be tapped twice.
              if (deleting)
                Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.of(context).coral,
                    ),
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _openForm(existing: r),
                      tooltip: L('Edit record', 'I-edit ang tala'),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: AppTheme.of(context).inkSoft,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _confirmDelete(r),
                      tooltip: L('Delete record', 'Burahin ang tala'),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: AppTheme.of(context).coral.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRecordDetails(MortalityRecord r) async {
    final analysis = _analysisFor(r);
    final eventAt = r.eventAt;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.of(context).bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) {
        sheetContext.select<AppStore, String>((store) => store.lang);
        return FractionallySizedBox(
          heightFactor: .9,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              child: Semantics(
                container: true,
                label: L(
                    'Mortality Information', 'Impormasyon sa Namatay na Isda'),
                child: Column(
                  key: const ValueKey('mortality-details'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(
                                    '${r.count} ${L('fish died', 'isda ang namatay')}',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.of(context).ink)),
                                const SizedBox(height: 6),
                                Text(
                                    '${eventAt == null ? _prettyDate(r.date) : _dateTime(eventAt.millisecondsSinceEpoch)} · '
                                    '${Pond.byId(r.pondId).name} · ${r.species}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                        color: AppTheme.of(context).inkSoft)),
                              ])),
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                              style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.of(context)
                                      .deep
                                      .withValues(alpha: .12),
                                  foregroundColor: AppTheme.of(context).ink),
                              onPressed: () => Navigator.pop(sheetContext),
                              tooltip: L('Close details', 'Isara ang detalye'),
                              icon: const Icon(Icons.close_rounded, size: 20)),
                        ]),
                    if (r.notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(r.notes,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: AppTheme.of(context).inkSoft)),
                    ],
                    const SizedBox(height: 22),
                    FutureBuilder<MortalityAnalysis?>(
                        future: analysis,
                        builder: (context, snapshot) => snapshot
                                    .connectionState ==
                                ConnectionState.done
                            ? _analysisDetails(snapshot.data, r)
                            : Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(L('Checking recorded readings…',
                                    'Sinusuri ang mga naitalang reading…')))),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// "2026-07-24" → "Jul 24, 2026"; falls back to the raw string.
  String _prettyDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return DateFormat.yMMMd(appDateLocale).format(parsed);
  }
}

/// A month/year chooser: a year stepper over a grid of the twelve months,
/// future months dimmed because they can hold nothing yet.
class _PeriodPicker extends StatefulWidget {
  final int year;
  final int month;
  const _PeriodPicker({required this.year, required this.month});

  @override
  State<_PeriodPicker> createState() => _PeriodPickerState();
}

class _PeriodPickerState extends State<_PeriodPicker> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.year;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.of(context).border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            // Year stepper
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => setState(() => _year--),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                SizedBox(
                  width: 76,
                  child: Text(
                    '$_year',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.of(context).ink,
                    ),
                  ),
                ),
                IconButton(
                  // Never step into a future year.
                  onPressed:
                      _year >= now.year ? null : () => setState(() => _year++),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Month grid
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.2,
              children: List.generate(12, (i) {
                final m = i + 1;
                final isFuture = DateTime(
                  _year,
                  m,
                ).isAfter(DateTime(now.year, now.month));
                final isSelected = _year == widget.year && m == widget.month;
                return _MonthCell(
                  label: DateFormat(
                    'MMM',
                    appDateLocale,
                  ).format(DateTime(_year, m)),
                  selected: isSelected,
                  disabled: isFuture,
                  onTap: isFuture
                      ? null
                      : () => Navigator.pop(context, DateTime(_year, m)),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _MonthCell({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.of(context).deep : AppTheme.of(context).bg,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: disabled
                  ? AppTheme.of(context).inkSoft.withOpacity(0.35)
                  : (selected ? Colors.white : AppTheme.of(context).ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _PeriodArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _PeriodArrow({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 22,
        color: onTap == null
            ? AppTheme.of(context).border
            : AppTheme.of(context).inkSoft,
      ),
    );
  }
}

class _LogButton extends StatelessWidget {
  final bool open;
  final VoidCallback? onTap;

  const _LogButton({required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: open ? AppTheme.of(context).header : AppTheme.deep,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedRotation(
                turns: open ? 0.125 : 0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: const Icon(
                  Icons.add_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                open ? L('Close', 'Isara') : L('Log', 'Itala'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

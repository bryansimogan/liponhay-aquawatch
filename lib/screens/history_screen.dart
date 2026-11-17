import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../models/sensor_data.dart';
import '../models/water_quality.dart';
import '../services/firebase_service.dart';
import '../services/simulation_service.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_header.dart';
import '../widgets/chart_widget.dart';
import '../widgets/loading_emblem.dart';
import '../widgets/reveal.dart';
import '../widgets/paged_list.dart';
import '../services/i18n.dart';
import 'reports_screen.dart';

/// Historical trends for one pond: a range picker, a parameter picker, the
/// chart, and the underlying readings table.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final FirebaseService _firebase = FirebaseService();
  final SimulationService _sim = SimulationService();

  String _pondId = 'pond1';
  bool _simMode = true;
  bool _loading = true;

  /// Hours of history to show, when following a rolling range.
  int _rangeHours = 24;

  /// A specific calendar month, when one has been picked. Set, it wins over
  /// [_rangeHours]; the chips and the month button are two ways of choosing
  /// the same window, so only one can be active.
  DateTime? _month;
  WaterParam _metric = WaterParam.ph;

  List<SensorData> _history = [];

  /// Which load is the current one.
  ///
  /// Picking a second month before the first query returns left two requests
  /// racing: whichever answered last won, and if the first never answered at
  /// all the screen stayed on its loader for good. Every load takes a number,
  /// and a reply is only used while its number is still the latest.
  int _loadToken = 0;

  /// Set when a query gave up, so the empty table can say why rather than
  /// implying the month simply had no readings.
  bool _timedOut = false;

  static const _ranges = <String, int>{
    'Today': 24,
    'Week': 24 * 7,
    '30 Days': 24 * 30,
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _simMode = prefs.getBool('simulation_mode') ?? false;
    _load();
  }

  /// The window to fetch: start, and an end when a month is pinned.
  (DateTime, DateTime?) _window() {
    final m = _month;
    if (m != null) {
      // First of the month up to the first of the next — the month boundary
      // rather than "thirty days back", so a picked month means that month.
      return (DateTime(m.year, m.month), DateTime(m.year, m.month + 1));
    }
    return (DateTime.now().subtract(Duration(hours: _rangeHours)), null);
  }

  String get _rangeLabel {
    final m = _month;
    if (m != null) return DateFormat('MMMM yyyy').format(m);
    return _ranges.entries.firstWhere((e) => e.value == _rangeHours).key;
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _timedOut = false;
    });

    // Readings arrive every 30s, but for longer ranges we only need a
    // representative series — cap the point count so the chart stays legible.
    final points = _month != null
        ? 150
        : (_rangeHours <= 24 ? 48 : (_rangeHours <= 168 ? 84 : 120));

    if (_simMode) {
      final list = _sim.generateHistory(_pondId, count: points);
      if (mounted && token == _loadToken) {
        setState(() {
          _history = list;
          _loading = false;
        });
      }
      return;
    }

    List<SensorData> list = const [];
    bool timedOut = false;
    try {
      // The picker has to bound the window, not just the point count. Asking
      // for a different number of the most recent readings returned the same
      // data for every range, so Today and This Month looked identical.
      final (from, to) = _window();
      list = await _firebase
          .getHistory(_pondId, limit: points, since: from, until: to)
          // A Realtime Database read has no deadline of its own: on a stalled
          // connection it simply never completes, and the screen waits for
          // ever. Twelve seconds is long past the point where a month of
          // readings should have arrived.
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      timedOut = true;
    } catch (e) {
      debugPrint('History load failed: $e');
    }

    // A reply that arrived after the user moved on is not an answer to the
    // question now on screen, so it is dropped rather than drawn.
    if (!mounted || token != _loadToken) return;
    setState(() {
      _history = list;
      _timedOut = timedOut;
      _loading = false;
    });
  }

  Color get _metricColor => switch (_metric) {
        WaterParam.ph => AppTheme.of(context).deep,
        WaterParam.temperature => AppTheme.of(context).coral,
        WaterParam.dissolvedOxygen => AppTheme.of(context).aqua,
      };

  String _metricLabel(WaterParam p) => switch (p) {
        WaterParam.ph => 'pH',
        WaterParam.temperature => 'Temp (°C)',
        WaterParam.dissolvedOxygen => 'DO (mg/L)',
      };

  @override
  Widget build(BuildContext context) {
    final pond = Pond.byId(_pondId);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          AppHeader(
            selectedPondId: _pondId,
            onPondChanged: (id) {
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
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'History - ${pond.name}',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.of(context).ink,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Trends help spot patterns before '
                                          'they become problems.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.35,
                                            color: AppTheme.of(context).inkSoft,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const ReportsScreen())),
                                    icon: const Icon(Icons.summarize_outlined,
                                        size: 16),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          AppTheme.of(context).deep,
                                      side: BorderSide(
                                          color: AppTheme.of(context).border),
                                      minimumSize: const Size(0, 38),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                    ),
                                    label: Text(L('Reports', 'Ulat')),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Reveal(
                              delayMs: 60,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                clipBehavior: Clip.none,
                                child: Row(
                                  children: [
                                    ..._ranges.entries.map((e) {
                                      final selected = _month == null &&
                                          _rangeHours == e.value;
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: _Chip(
                                          label: e.key,
                                          selected: selected,
                                          onTap: () {
                                            if (selected) return;
                                            setState(() {
                                              _month = null;
                                              _rangeHours = e.value;
                                            });
                                            _load();
                                          },
                                        ),
                                      );
                                    }),
                                    _MonthButton(
                                      month: _month,
                                      onPicked: (m) {
                                        setState(() => _month = m);
                                        _load();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Reveal(
                              delayMs: 110,
                              child: Row(
                                children: WaterParam.values.map((p) {
                                  final selected = _metric == p;
                                  final color = switch (p) {
                                    WaterParam.ph => AppTheme.of(context).deep,
                                    WaterParam.temperature =>
                                      AppTheme.of(context).coral,
                                    WaterParam.dissolvedOxygen =>
                                      AppTheme.of(context).aqua,
                                  };
                                  return Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                          right: p == WaterParam.values.last
                                              ? 0
                                              : 6),
                                      child: _MetricButton(
                                        label: _metricLabel(p),
                                        color: color,
                                        selected: selected,
                                        onTap: () =>
                                            setState(() => _metric = p),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Reveal(
                              delayMs: 170,
                              child: SensorChartWidget(
                                data: _history,
                                param: _metric,
                                lineColor: _metricColor,
                              ),
                            ),
                            Reveal(
                              delayMs: 250,
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(top: 16, bottom: 8),
                                child: Row(
                                  children: [
                                    Text(
                                      'READINGS',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.of(context).inkSoft,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$_rangeLabel - ${_history.length} '
                                      '${_history.length == 1 ? "reading" : "readings"}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: AppTheme.of(context)
                                            .inkSoft
                                            .withOpacity(0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _history.isEmpty
                              ? Reveal(
                                  delayMs: 300,
                                  child: Container(
                                    width: double.infinity,
                                    decoration: AppTheme.of(context).card(),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 28, horizontal: 20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _timedOut
                                              ? 'Could not reach the database.'
                                              : 'No readings in this range.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.of(context).ink,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _timedOut
                                              ? 'Check the connection, then '
                                                  'pick the range again.'
                                              : 'The controller writes one '
                                                  'point every 30 seconds.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            height: 1.35,
                                            color: AppTheme.of(context).inkSoft,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Reveal(
                                  delayMs: 300,
                                  child: Container(
                                    decoration: AppTheme.of(context).card(),
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      children: [
                                        const _ReadingsHead(),
                                        Expanded(
                                          child: PagedList(
                                            perPage: 6,
                                            spacing: 0,
                                            items: [
                                              for (final d in _history.reversed)
                                                _ReadingsRow(data: d),
                                            ],
                                          ),
                                        ),
                                      ],
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
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.of(context).deep
              : AppTheme.of(context).surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected
                  ? AppTheme.of(context).deep
                  : AppTheme.of(context).border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? AppTheme.of(context).onPrimary
                : AppTheme.of(context).inkSoft,
          ),
        ),
      ),
    );
  }
}

class _MetricButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _MetricButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              selected ? color.withOpacity(0.1) : AppTheme.of(context).surface,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: selected ? color : AppTheme.of(context).border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: selected ? color : AppTheme.of(context).inkSoft,
          ),
        ),
      ),
    );
  }
}

/// Column widths for the readings table, as flex weights.
///
/// The table used to be a [DataTable] inside a horizontal scroll view, which
/// sized itself to its content: on a narrow phone the last column sat off the
/// edge, and on a wide one a band of empty card was left over on the right.
/// Weights make the four columns divide whatever width there is, so it fits
/// every screen exactly and never scrolls sideways.
const _colFlex = <int>[34, 22, 22, 22];

class _ReadingsHead extends StatelessWidget {
  const _ReadingsHead();

  @override
  Widget build(BuildContext context) {
    const labels = ['TIME', 'pH', 'TEMP', 'DO'];
    return Container(
      color: AppTheme.of(context).deep.withOpacity(0.04),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              flex: _colFlex[i],
              child: Text(
                labels[i],
                textAlign: i == 0 ? TextAlign.left : TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppTheme.of(context).inkSoft.withOpacity(0.9),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadingsRow extends StatelessWidget {
  final SensorData data;
  const _ReadingsRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final ph = ParamReading.classify(WaterParam.ph, data.ph);
    final temperature =
        ParamReading.classify(WaterParam.temperature, data.temperature);
    final dissolvedOxygen =
        ParamReading.classify(WaterParam.dissolvedOxygen, data.dissolvedOxygen);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          top:
              BorderSide(color: AppTheme.of(context).inkSoft.withOpacity(0.10)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _colFlex[0],
            child: Text(
              DateFormat('MMM d · HH:mm').format(data.dateTime),
              style:
                  TextStyle(fontSize: 11, color: AppTheme.of(context).inkSoft),
            ),
          ),
          _cell(context, 1, data.ph.toStringAsFixed(2), ph.level),
          _cell(context, 2, data.temperature.toStringAsFixed(1),
              temperature.level),
          _cell(context, 3, data.dissolvedOxygen.toStringAsFixed(2),
              dissolvedOxygen.level),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, int i, String value, String level) {
    final color = AppTheme.of(context).statusColor(level);
    return Expanded(
      flex: _colFlex[i],
      child: Center(
        child: Container(
          constraints: const BoxConstraints(minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks one calendar month, for looking back at a period that has already
/// ended rather than a window counted back from today.
class _MonthButton extends StatelessWidget {
  final DateTime? month;
  final ValueChanged<DateTime> onPicked;

  const _MonthButton({required this.month, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // January through December of this year, in calendar order — the way a
    // month is picked on paper. Counting backwards from today put November
    // above October and read as a list of "months ago" rather than months.
    final months = List<DateTime>.generate(
      12,
      (i) => DateTime(now.year, i + 1),
    );
    final selected = month != null;

    return PopupMenuButton<DateTime>(
      tooltip: 'Pick a month',
      position: PopupMenuPosition.under,
      onSelected: onPicked,
      itemBuilder: (context) => [
        for (final m in months)
          PopupMenuItem<DateTime>(
            value: m,
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('MMMM').format(m),
                    style: TextStyle(
                      fontSize: 13,
                      // A month that has not happened yet can hold no
                      // readings; dimming it says so before it is tapped.
                      color: m.month > now.month
                          ? AppTheme.of(context).inkSoft.withOpacity(0.45)
                          : AppTheme.of(context).ink,
                      fontWeight: month != null && month!.month == m.month
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (month != null && month!.month == m.month)
                  Icon(Icons.check_rounded,
                      size: 16, color: AppTheme.of(context).deep),
              ],
            ),
          ),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.of(context).deep
              : AppTheme.of(context).surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppTheme.of(context).deep
                : AppTheme.of(context).inkSoft.withOpacity(0.22),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected ? DateFormat('MMMM').format(month!) : 'Month',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppTheme.of(context).onPrimary
                    : AppTheme.of(context).inkSoft,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.expand_more_rounded,
              size: 15,
              color: selected
                  ? AppTheme.of(context).onPrimary
                  : AppTheme.of(context).inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

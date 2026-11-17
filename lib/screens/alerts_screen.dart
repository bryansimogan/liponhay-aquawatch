import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/alert_content.dart';
import '../models/alert_record.dart';
import '../models/water_quality.dart';
import '../services/alert_count_service.dart';
import '../services/firebase_service.dart';
import '../services/app_store.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_header.dart';
import '../widgets/expandable_notice.dart';
import '../widgets/loading_emblem.dart';
import '../widgets/paged_list.dart';
import '../widgets/reveal.dart';

/// Saved record of every SMS alert the system has sent.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final FirebaseService _firebase = FirebaseService();
  AppStore? _demo;
  int _demoClearedAt = 0;
  int _demoReadAt = 0;

  StreamSubscription<List<AlertRecord>>? _subscription;
  List<AlertRecord> _alerts = [];
  bool _loading = true;

  /// Who the SMS alerts go to, shown in the detail sheet. Fetched once.
  String _recipient = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _demo?.removeListener(_refreshDemo);
    super.dispose();
  }

  Future<void> _load() async {
    final store = context.read<AppStore>();
    if (store.simulation) {
      _demo = store;
      store.addListener(_refreshDemo);
      _refreshDemo();
      return;
    }

    _firebase.getSmsRecipient().then((n) {
      if (mounted) setState(() => _recipient = n);
    }).catchError((_) {});

    try {
      _subscription = _firebase.alertsStream().listen((list) {
        if (mounted) {
          setState(() {
            _alerts = list;
            _loading = false;
          });
        }
      }, onError: (_) {
        if (mounted) setState(() => _loading = false);
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _refreshDemo() {
    final store = _demo!;
    setState(() {
      _loading = false;
      _alerts = [
        for (final incident in store.incidents)
          if (incident.ts > _demoClearedAt)
            AlertRecord(
              id: 'demo-${incident.id}',
              parameter: switch (incident.p) {
                'ph' => 'pH',
                't' => 'temperature',
                _ => 'dissolved_oxygen',
              },
              value: double.tryParse(incident.val.split(' ').first) ?? 0,
              severity: incident.lvl == 'crit' ? 'critical' : 'warning',
              condition: incident.title,
              timestamp: incident.ts,
              pondId: 'pond1',
            ),
      ];
    });
  }

  int get _criticalCount =>
      _alerts.where((a) => a.severity == 'critical').length;

  Future<void> _markAllRead() async {
    if (_demo case final store?) {
      _demoReadAt = store.nowMs;
    } else {
      await AlertCountService.instance.markAllRead();
    }
    if (mounted) setState(() {}); // refresh the per-row unread dots
    _toast('All alerts marked as read.');
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all alerts?'),
        content: Text(
          'This removes all ${_alerts.length} saved alerts. New alerts will '
          'still arrive as they happen. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: AppTheme.of(context).coral),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    if (!mounted) return;
    try {
      if (_demo case final store?) {
        _demoClearedAt = store.nowMs;
        _refreshDemo();
      } else {
        await _firebase.clearAllAlerts();
        // The stream delivers the empty list, which also zeroes the badge.
      }
      _toast('Alerts cleared.');
    } catch (_) {
      _toast('Could not clear alerts. Please try again.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
              child: _loading
                  ? const EmblemLoader()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Reveal(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Alert History',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.of(context).ink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _demo == null
                                      ? 'SMS alert history'
                                      : 'Demo Mode · simulated alerts',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: AppTheme.of(context).inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_alerts.isNotEmpty)
                            Reveal(
                              delayMs: 60,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                decoration: AppTheme.of(context).card(),
                                child: Row(
                                  children: [
                                    Expanded(
                                        child: _stat(_alerts.length, 'TOTAL',
                                            AppTheme.of(context).deep)),
                                    Container(
                                        width: 1,
                                        height: 30,
                                        color: AppTheme.of(context).border),
                                    Expanded(
                                        child: _stat(_criticalCount, 'CRITICAL',
                                            AppTheme.of(context).coral)),
                                    Container(
                                        width: 1,
                                        height: 30,
                                        color: AppTheme.of(context).border),
                                    Expanded(
                                        child: _stat(
                                            _alerts.length - _criticalCount,
                                            'WARNING',
                                            AppTheme.of(context).amber)),
                                  ],
                                ),
                              ),
                            ),
                          if (_alerts.isNotEmpty)
                            Reveal(
                              delayMs: 90,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _markAllRead,
                                        icon: const Icon(Icons.done_all_rounded,
                                            size: 16),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              AppTheme.of(context).deep,
                                          side: BorderSide(
                                              color:
                                                  AppTheme.of(context).border),
                                          minimumSize: const Size(0, 42),
                                        ),
                                        label: const Text('Mark all read'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _clearAll,
                                        icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 16),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              AppTheme.of(context).coral,
                                          side: BorderSide(
                                              color: AppTheme.of(context)
                                                  .coral
                                                  .withOpacity(0.4)),
                                          minimumSize: const Size(0, 42),
                                        ),
                                        label: const Text('Clear all'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Expanded(
                            child: PagedList(
                              perPage: 4,
                              items: [
                                for (final a in _alerts) _alertCard(a),
                              ],
                              empty: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 40, horizontal: 20),
                                  decoration: AppTheme.of(context).card(),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.error_outline_rounded,
                                          size: 34,
                                          color: AppTheme.of(context)
                                              .inkSoft
                                              .withOpacity(0.4)),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No alerts yet',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.of(context).ink,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Water quality has stayed within range.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                AppTheme.of(context).inkSoft),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 4),
    );
  }

  Widget _stat(int value, String label, Color color) {
    return Column(
      children: [
        CountUpText(
          value,
          duration: const Duration(milliseconds: 800),
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
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.of(context).inkSoft,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _alertCard(AlertRecord alert) {
    final palette = AppTheme.of(context);
    final color = palette.statusColor(alert.severity);
    final unit = _unitFor(alert.parameter);
    final pond = Pond.byId(alert.pondId).name;
    final reading = alert.value.toStringAsFixed(2);
    return ExpandableNotice(
      key: ValueKey(alert.id),
      title: _prettyParam(alert.parameter),
      timestamp: alert.hasKnownTime
          ? DateFormat('MMM d, h:mm a').format(alert.dateTime)
          : 'Time unknown',
      icon: Icons.warning_amber_rounded,
      accent: color,
      unread: _demo == null
          ? AlertCountService.instance.isUnread(alert)
          : alert.timestamp > _demoReadAt,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$pond · $reading$unit',
            style: TextStyle(color: palette.ink, fontSize: 12),
          ),
          Text(
            alert.condition.isEmpty ? alert.severity : alert.condition,
            style: TextStyle(color: color, fontSize: 12),
          ),
          TextButton(
            onPressed: () => _showDetail(alert),
            child: const Text('View alert details'),
          ),
        ],
      ),
    );
  }

  /// The full plain-language breakdown of one alert — what happened, why, what
  /// it leads to, what to do — plus who the SMS reached. This is the same
  /// content the SMS carries, kept in one place ([AlertContent]).
  void _showDetail(AlertRecord a) {
    final color = AppTheme.of(context).statusColor(a.severity);
    final param = _paramOf(a.parameter);
    final explanation = param == null
        ? null
        : AlertContent.forReading(ParamReading.classify(param, a.value));

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.of(context).surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.of(context).border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (explanation != null) ...[
                  Text(explanation.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    explanation?.title ?? _prettyParam(a.parameter),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.of(context).ink,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    a.severity.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (explanation != null) ...[
              _detailBlock('WHAT HAPPENED', explanation.whatsHappening),
              _detailBlock('WHY IT HAPPENS', explanation.why),
              _detailBlock('EFFECT ON FISH', explanation.consequence),
              _detailBlock('IMMEDIATE ACTION', explanation.whatToDo,
                  highlight: color),
              _actionSteps(explanation.actionSteps, color),
              _detailBlock('FOLLOW-UP MONITORING', explanation.followUp),
            ] else
              _detailBlock(
                'READING',
                '${_prettyParam(a.parameter)} was '
                    '${a.value.toStringAsFixed(2)}${_unitFor(a.parameter)}'
                    '${a.condition.isNotEmpty ? " — ${a.condition}" : ""}.',
              ),
            const SizedBox(height: 8),
            Divider(color: AppTheme.of(context).border),
            const SizedBox(height: 8),
            _metaRow('Reading',
                '${a.value.toStringAsFixed(2)}${_unitFor(a.parameter)}'),
            _metaRow('Pond', Pond.byId(a.pondId).name),
            _metaRow(
                'Time',
                a.hasKnownTime
                    ? DateFormat('MMM d, yyyy · h:mm a').format(a.dateTime)
                    : 'Unknown'),
            _metaRow('SMS', _demo == null ? 'Sent' : 'Simulated'),
            if (_recipient.isNotEmpty) _metaRow('Sent to', _recipient),
          ],
        ),
      ),
    );
  }

  Widget _detailBlock(String label, String body, {Color? highlight}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: highlight != null
          ? AppTheme.of(context).tintedCard(highlight, radius: 12)
          : BoxDecoration(
              color: AppTheme.of(context).bg,
              borderRadius: BorderRadius.circular(12),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: highlight ?? AppTheme.of(context).inkSoft,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppTheme.of(context).ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionSteps(List<String> steps, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.of(context).tintedCard(color, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RECOMMENDED ACTIONS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    steps[i],
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppTheme.of(context).ink,
                    ),
                  ),
                ),
              ],
            ),
            if (i != steps.length - 1) const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.of(context).inkSoft,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.of(context).ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  WaterParam? _paramOf(String raw) {
    switch (raw) {
      case 'pH':
        return WaterParam.ph;
      case 'temperature':
        return WaterParam.temperature;
      case 'dissolved_oxygen':
        return WaterParam.dissolvedOxygen;
      default:
        return null;
    }
  }

  String _prettyParam(String raw) {
    switch (raw) {
      case 'pH':
        return 'pH Level';
      case 'temperature':
        return 'Temperature';
      case 'dissolved_oxygen':
        return 'Dissolved Oxygen';
      default:
        return raw;
    }
  }

  String _unitFor(String raw) {
    switch (raw) {
      case 'temperature':
        return ' °C';
      case 'dissolved_oxygen':
        return ' mg/L';
      default:
        return '';
    }
  }
}

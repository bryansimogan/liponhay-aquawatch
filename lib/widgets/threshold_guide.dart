import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/i18n.dart';

/// A plain-language legend for the safe / warning / critical ranges.
///
/// This is the reference a farmer opens to answer "the reading is 8.9 — is that
/// bad?". The bands below mirror [ParamReading.classify], which is the runtime
/// source of truth; they are the human-facing labels for the same manuscript
/// thresholds (pH 6.5–8.5, temp 25–32 °C, DO ≥ 5 mg/L for tilapia). If a
/// threshold ever moves in classify(), move the matching label here.
class ThresholdGuide {
  const ThresholdGuide._();

  /// [onReplayTour], when given, adds a "Replay app tour" button to the sheet
  /// — tapping it closes the guide and restarts the first-run coach marks.
  static Future<void> show(BuildContext context, {VoidCallback? onReplayTour}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.of(context).surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GuideSheet(onReplayTour: onReplayTour),
    );
  }
}

/// One coloured segment of a parameter's scale.
class _Band {
  final String range;
  final String tier; // 'critical' | 'warning' | 'safe'
  const _Band(this.range, this.tier);
}

class _ParamGuide {
  final String name;
  final String unit;
  final String safeText;
  final List<_Band> bands;
  const _ParamGuide(this.name, this.unit, this.safeText, this.bands);
}

const _guides = <_ParamGuide>[
  _ParamGuide('pH Level', '', 'Safe 6.5 – 8.5', [
    _Band('< 4.0', 'critical'),
    _Band('4.0–6.5', 'warning'),
    _Band('6.5–8.5', 'safe'),
    _Band('8.5–10', 'warning'),
    _Band('> 10', 'critical'),
  ]),
  _ParamGuide('Temperature', '°C', 'Safe 25 – 32 °C', [
    _Band('< 20', 'critical'),
    _Band('20–25', 'warning'),
    _Band('25–32', 'safe'),
    _Band('32–35', 'warning'),
    _Band('> 35', 'critical'),
  ]),
  _ParamGuide('Dissolved Oxygen', 'mg/L', 'Safe 5.0 mg/L and above', [
    _Band('< 2.0', 'critical'),
    _Band('2.0–5.0', 'warning'),
    _Band('≥ 5.0', 'safe'),
  ]),
];

class _GuideSheet extends StatelessWidget {
  final VoidCallback? onReplayTour;
  const _GuideSheet({this.onReplayTour});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
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
          Text(
            'Water Quality Guide',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.of(context).ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'What each reading means for the fish. When a value leaves the '
            'green range you get an SMS, and it is saved under Alerts.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.of(context).inkSoft,
            ),
          ),
          if (onReplayTour != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onReplayTour!();
                },
                icon: const Icon(Icons.replay_rounded, size: 17),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.of(context).deep,
                  side: BorderSide(color: AppTheme.of(context).border),
                  minimumSize: const Size(0, 46),
                ),
                label: Text(L('Replay app tour', 'Ulitin ang gabay')),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Colour legend
          Row(
            children: [
              _legendDot(
                context,
                AppTheme.of(context).statusColor('safe'),
                'Safe',
              ),
              const SizedBox(width: 14),
              _legendDot(
                context,
                AppTheme.of(context).statusColor('warning'),
                'Warning',
              ),
              const SizedBox(width: 14),
              _legendDot(
                context,
                AppTheme.of(context).statusColor('critical'),
                'Critical',
              ),
            ],
          ),
          const SizedBox(height: 18),

          for (final g in _guides) ...[
            _paramBlock(context, g),
            const SizedBox(height: 18),
          ],

          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppTheme.of(context).bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppTheme.of(context).inkSoft,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Warning means act soon; critical means act now. Tap any '
                    'alert to see what to do about it.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppTheme.of(context).inkSoft,
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

  Widget _legendDot(BuildContext context, Color color, String label) {
    return Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.of(context).ink,
          ),
        ),
      ],
    );
  }

  Widget _paramBlock(BuildContext context, _ParamGuide g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              g.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.of(context).ink,
              ),
            ),
            if (g.unit.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                '(${g.unit})',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.of(context).inkSoft,
                ),
              ),
            ],
            const Spacer(),
            Text(
              g.safeText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.of(context).statusColor('safe'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Coloured band strip
        Row(
          children: [
            for (final b in g.bands) ...[
              Expanded(child: _bandCell(context, b)),
              if (b != g.bands.last) const SizedBox(width: 4),
            ],
          ],
        ),
      ],
    );
  }

  Widget _bandCell(BuildContext context, _Band b) {
    final color = AppTheme.of(context).statusColor(b.tier);
    return Column(
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          b.range,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: b.tier == 'safe' ? FontWeight.w700 : FontWeight.w500,
            color: b.tier == 'safe'
                ? AppTheme.of(context).ink
                : AppTheme.of(context).inkSoft,
          ),
        ),
      ],
    );
  }
}

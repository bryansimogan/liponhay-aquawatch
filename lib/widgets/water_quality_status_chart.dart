import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/water_quality.dart';

/// Compares readings using separate display scales for each unit.
class WaterQualityStatusChart extends StatelessWidget {
  const WaterQualityStatusChart({
    super.key,
    required this.ph,
    required this.temperature,
    required this.oxygen,
  });

  final ParamReading ph;
  final ParamReading temperature;
  final ParamReading oxygen;

  static const _plotHeight = 110.0;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.of(context);
    const labelStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

    return Container(
      decoration: palette.card(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Water Quality Status',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: _plotHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final value in const ['100', '75', '50', '25', '0'])
                      Text(value,
                          style:
                              TextStyle(fontSize: 10, color: palette.inkSoft)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Stack(
                  children: [
                    ExcludeSemantics(
                      child: SizedBox(
                        height: _plotHeight,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (var tick = 0; tick < 5; tick++)
                              Divider(
                                height: 1,
                                color: palette.inkSoft.withValues(
                                  alpha: tick == 4 ? 0.5 : 0.19,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _bar(palette, ph, 'pH', 0, 12)),
                        Expanded(child: _bar(palette, oxygen, 'DO', 0, 10)),
                        Expanded(
                            child: _bar(palette, temperature, 'Temp', 15, 40)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final (label, color) in [
                ('Safe', palette.aqua),
                ('Warning', palette.amber),
                ('Critical', palette.coral),
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(label,
                        style: labelStyle.copyWith(color: palette.inkSoft)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bar height is a percentage of each parameter’s display scale.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: palette.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _bar(
    AquaPalette palette,
    ParamReading reading,
    String label,
    double min,
    double max,
  ) {
    final color = palette.statusColor(reading.level);
    final value = reading.value.toStringAsFixed(reading.decimals);
    final fraction = ((reading.value - min) / (max - min)).clamp(0.0, 1.0);
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: palette.ink,
    );

    return Semantics(
      label: '${reading.label}, $value ${reading.unit}, ${reading.level}',
      excludeSemantics: true,
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) {
              final height = _plotHeight * progress;
              return SizedBox(
                height: _plotHeight,
                width: double.infinity,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      width: 35,
                      height: height,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    Positioned(
                        bottom: height + 4, child: Text(value, style: style)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(label, style: style),
          if (reading.unit.isNotEmpty)
            Text(reading.unit,
                style: TextStyle(fontSize: 10, color: palette.inkSoft)),
        ],
      ),
    );
  }
}

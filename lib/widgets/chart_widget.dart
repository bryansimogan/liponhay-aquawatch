import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../models/sensor_data.dart';
import '../models/water_quality.dart';

/// Line chart of one water-quality parameter over time, with the safe range
/// shaded behind the line.
///
/// On first paint (and whenever the data window changes) the line rises from
/// the chart floor to its real values, so the trend reads as being drawn.
class SensorChartWidget extends StatelessWidget {
  final List<SensorData> data;
  final WaterParam param;
  final Color lineColor;

  const SensorChartWidget({
    super.key,
    required this.data,
    required this.param,
    required this.lineColor,
  });

  double _valueOf(SensorData d) => switch (param) {
        WaterParam.ph => d.ph,
        WaterParam.temperature => d.temperature,
        WaterParam.dissolvedOxygen => d.dissolvedOxygen,
      };

  /// Safe band for the shaded region.
  (double, double) get _safeRange => switch (param) {
        WaterParam.ph => (6.5, 8.5),
        WaterParam.temperature => (25.0, 32.0),
        WaterParam.dissolvedOxygen => (5.0, 9.0),
      };

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: AppTheme.of(context).card(),
        child: Center(
          child: Text(
            'No readings yet for this range.',
            style:
                TextStyle(color: AppTheme.of(context).inkSoft, fontSize: 12.5),
          ),
        ),
      );
    }

    final (safeMin, safeMax) = _safeRange;
    final values = data.map(_valueOf).toList();
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    // Include the safe band so it is always visible, then pad a little.
    final minY = (rawMin < safeMin ? rawMin : safeMin) - 0.5;
    final maxY = (rawMax > safeMax ? rawMax : safeMax) + 0.5;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 14, 8),
      decoration: AppTheme.of(context).card(),
      child: Column(
        children: [
          SizedBox(
            height: 190,
            child: TweenAnimationBuilder<double>(
              // Replays when the pond or range changes.
              key: ValueKey(
                  '${param.name}-${data.length}-${data.first.timestamp}'),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: ((maxY - minY) / 4).clamp(0.5, 100),
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: AppTheme.of(context).border,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  // Shaded safe band, fading in with the line.
                  rangeAnnotations: RangeAnnotations(
                    horizontalRangeAnnotations: [
                      HorizontalRangeAnnotation(
                        y1: safeMin,
                        y2: safeMax,
                        color: AppTheme.of(context).aqua.withOpacity(0.10 * t),
                      ),
                    ],
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: (data.length / 5).ceilToDouble(),
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= data.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('HH:mm').format(data[i].dateTime),
                              style: TextStyle(
                                  fontSize: 9,
                                  color: AppTheme.of(context).inkSoft),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            value.toStringAsFixed(1),
                            style: TextStyle(
                                fontSize: 9,
                                color: AppTheme.of(context).inkSoft),
                          ),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: data.asMap().entries.map((e) {
                        final actual = _valueOf(e.value);
                        // Grow from the floor as t goes 0 → 1.
                        final y = minY + (actual - minY) * t;
                        return FlSpot(e.key.toDouble(), y);
                      }).toList(),
                      isCurved: true,
                      curveSmoothness: 0.28,
                      color: lineColor.withOpacity(0.35 + 0.65 * t),
                      barWidth: 2.4,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            lineColor.withOpacity(0.18 * t),
                            lineColor.withOpacity(0.01 * t),
                          ],
                        ),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => AppTheme.of(context).header,
                      tooltipRoundedRadius: 10,
                      getTooltipItems: (spots) => spots.map((s) {
                        return LineTooltipItem(
                          s.y.toStringAsFixed(2),
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 18,
                height: 8,
                decoration: BoxDecoration(
                  color: AppTheme.of(context).aqua.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Shaded band = safe range',
                style: TextStyle(
                    fontSize: 10, color: AppTheme.of(context).inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

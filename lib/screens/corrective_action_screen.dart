import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/sensor_data.dart';
import '../services/firebase_service.dart';
import '../services/simulation_service.dart';
import '../widgets/loading_emblem.dart';
import '../widgets/reveal.dart';

/// Detailed corrective guidance for the current readings: what each
/// out-of-range parameter does to the fish, and the steps to fix it.
class CorrectiveActionScreen extends StatefulWidget {
  const CorrectiveActionScreen({super.key});

  @override
  State<CorrectiveActionScreen> createState() => _CorrectiveActionScreenState();
}

class _CorrectiveActionScreenState extends State<CorrectiveActionScreen> {
  final FirebaseService _firebase = FirebaseService();
  final SimulationService _sim = SimulationService();

  SensorData? _currentData;
  bool _loading = true;
  final bool _simMode = false;

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  Future<void> _loadMode() async {
    _loadData();
  }

  Future<void> _loadData() async {
    if (_simMode) {
      final history = _sim.generateHistory('pond1', count: 1);
      if (history.isNotEmpty) {
        setState(() {
          _currentData = history.last;
          _loading = false;
        });
      }
    } else {
      try {
        final data = await _firebase.getCurrentReading('pond1');
        setState(() {
          _currentData = data;
          _loading = false;
        });
      } catch (e) {
        setState(() => _loading = false);
      }
    }
  }

  List<_Recommendation> _getRecommendations() {
    if (_currentData == null) return [];
    final data = _currentData!;
    final List<_Recommendation> recs = [];

    // ---- pH ----
    if (data.ph < 4) {
      recs.add(_Recommendation(
        icon: Icons.warning_amber_rounded,
        severity: 'CRITICAL',
        parameter: 'pH (${data.ph.toStringAsFixed(2)}) — Strongly Acidic',
        effect:
            'Highly unsafe for fish. Extreme physiological stress, severe gill damage, and high mortality risk.',
        action:
            '1. Immediately add agricultural lime (CaCO₃) or crushed eggshells to raise pH.\n2. Perform emergency partial water change (30-50%).\n3. Remove any organic debris or decaying matter from the pond.\n4. Re-test pH after 2 hours.',
      ));
    } else if (data.ph < 6.5) {
      recs.add(_Recommendation(
        icon: Icons.info_outline_rounded,
        severity: 'WARNING',
        parameter: 'pH (${data.ph.toStringAsFixed(2)}) — Acidic',
        effect:
            'Unsafe for fish. Reduced feed intake, stress, increased susceptibility to disease.',
        action:
            '1. Add agricultural lime or crushed eggshells gradually.\n2. Monitor daily until pH returns to 6.5-8.5 range.\n3. Reduce feeding to minimize organic waste buildup.',
      ));
    } else if (data.ph > 10) {
      recs.add(_Recommendation(
        icon: Icons.warning_amber_rounded,
        severity: 'CRITICAL',
        parameter: 'pH (${data.ph.toStringAsFixed(2)}) — Strongly Alkaline',
        effect:
            'Highly unsafe. Toxic ammonia levels increase, fish suffocation risk, organ damage.',
        action:
            '1. Perform immediate partial water change (30-50%).\n2. Add organic matter (e.g., dried leaves) or dilute white vinegar.\n3. Check for cement or limestone contamination near the pond.\n4. Re-test pH after 2 hours.',
      ));
    } else if (data.ph > 8.5) {
      recs.add(_Recommendation(
        icon: Icons.info_outline_rounded,
        severity: 'WARNING',
        parameter: 'pH (${data.ph.toStringAsFixed(2)}) — Alkaline',
        effect:
            'Stress condition. Altered fish metabolism, reduced growth rate.',
        action:
            '1. Add organic matter or vinegar treatment in small amounts.\n2. Perform partial water change (20-30%).\n3. Monitor pH daily until within safe range.',
      ));
    }

    // ---- Temperature ----
    if (data.temperature < 20) {
      recs.add(_Recommendation(
        icon: Icons.warning_amber_rounded,
        severity: 'CRITICAL',
        parameter:
            'Temp (${data.temperature.toStringAsFixed(1)}°C) — Cold Stress',
        effect:
            'Unsafe. Fish metabolism slows drastically, immune system suppressed, feeding stops.',
        action:
            '1. Reduce water flow from cold sources.\n2. Expose pond to more sunlight (remove shade covers temporarily).\n3. Consider using a water heater for small ponds.\n4. Avoid feeding during cold periods.',
      ));
    } else if (data.temperature < 25) {
      recs.add(_Recommendation(
        icon: Icons.info_outline_rounded,
        severity: 'WARNING',
        parameter:
            'Temp (${data.temperature.toStringAsFixed(1)}°C) — Sub-optimal',
        effect: 'Below optimal range. Slower growth, reduced feeding activity.',
        action:
            '1. Monitor temperature trend throughout the day.\n2. Increase sun exposure if possible.\n3. Reduce water depth slightly to allow warming.',
      ));
    } else if (data.temperature > 35) {
      recs.add(_Recommendation(
        icon: Icons.warning_amber_rounded,
        severity: 'CRITICAL',
        parameter: 'Temp (${data.temperature.toStringAsFixed(1)}°C) — Too Hot',
        effect:
            'Highly unsafe. Oxygen solubility drops severely, fish heat stress, rapid mortality.',
        action:
            '1. Immediately increase water depth.\n2. Install shade covers or floating plants.\n3. Increase aeration / water agitation.\n4. Perform partial water exchange with cooler water.\n5. Reduce stocking density temporarily.',
      ));
    } else if (data.temperature > 32) {
      recs.add(_Recommendation(
        icon: Icons.info_outline_rounded,
        severity: 'WARNING',
        parameter:
            'Temp (${data.temperature.toStringAsFixed(1)}°C) — Warm Stress',
        effect:
            'Risky. Reduced dissolved oxygen levels, increased stress, lower feed conversion.',
        action:
            '1. Increase water depth in the pond.\n2. Add shade covers over part of the pond.\n3. Ensure aerators are running properly.\n4. Monitor closely for signs of fish distress.',
      ));
    }

    // ---- Dissolved Oxygen ----
    if (data.dissolvedOxygen < 2) {
      recs.add(_Recommendation(
        icon: Icons.warning_amber_rounded,
        severity: 'CRITICAL',
        parameter:
            'DO (${data.dissolvedOxygen.toStringAsFixed(2)} mg/L) — Severe',
        effect:
            'Highly unsafe. Risk of fish suffocation and mass mortality. Emergency condition.',
        action:
            '1. IMMEDIATELY activate all aerators and splashers.\n2. Perform emergency partial water change (50%).\n3. Reduce stocking density by transferring fish.\n4. Stop all feeding to reduce oxygen demand.\n5. Remove dead fish to prevent further oxygen depletion.',
      ));
    } else if (data.dissolvedOxygen < 3) {
      recs.add(_Recommendation(
        icon: Icons.info_outline_rounded,
        severity: 'WARNING',
        parameter: 'DO (${data.dissolvedOxygen.toStringAsFixed(2)} mg/L) — Low',
        effect:
            'Unsafe. Fish respiration stressed, growth impaired, increased disease susceptibility.',
        action:
            '1. Turn on aerators / paddlewheels.\n2. Reduce feeding to decrease biological oxygen demand.\n3. Remove excess algae or organic matter.\n4. Monitor continuously.',
      ));
    } else if (data.dissolvedOxygen < 5) {
      recs.add(_Recommendation(
        icon: Icons.info_outline_rounded,
        severity: 'WARNING',
        parameter:
            'DO (${data.dissolvedOxygen.toStringAsFixed(2)} mg/L) — Moderate',
        effect: 'Stress condition. Reduced feeding efficiency, slower growth.',
        action:
            '1. Ensure aerators are operational.\n2. Monitor during early morning (lowest DO period, 4-6 AM).\n3. Consider reducing stocking density.',
      ));
    }

    if (recs.isEmpty) {
      recs.add(_Recommendation(
        icon: Icons.check_circle_outline_rounded,
        severity: 'NORMAL',
        parameter: 'All Parameters Within Safe Range',
        effect:
            'Water quality is optimal for fish health and growth. No immediate action needed.',
        action:
            '1. Continue regular monitoring every 30 minutes.\n2. Maintain consistent feeding schedule.\n3. Perform routine pond maintenance.\n4. Check and clean sensors weekly to prevent biofouling.',
      ));
    }

    return recs;
  }

  @override
  Widget build(BuildContext context) {
    final recs = _getRecommendations();

    final d = _currentData;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Corrective Actions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _loading
          ? const EmblemLoader()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // The readings this advice is based on
                if (d != null)
                  Reveal(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: AppTheme.of(context).card(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CURRENT READINGS · POND 1',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.of(context).inkSoft,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _readingChip('pH', d.ph, 2, '',
                                    AppTheme.of(context).deep),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _readingChip('TEMP', d.temperature, 1,
                                    '°C', AppTheme.of(context).coral),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _readingChip('DO', d.dissolvedOxygen, 2,
                                    '', AppTheme.of(context).aqua),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 18),

                Reveal(
                  delayMs: 70,
                  child: Text(
                    'RECOMMENDATIONS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.of(context).inkSoft,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                ...recs.asMap().entries.map((e) => Reveal(
                      delayMs: 120 + e.key * 80,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildRecCard(e.value),
                      ),
                    )),
              ],
            ),
    );
  }

  Widget _readingChip(
      String label, double value, int decimals, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        children: [
          FittedBox(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                CountUpDecimal(
                  value,
                  decimals: decimals,
                  duration: const Duration(milliseconds: 850),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                if (unit.isNotEmpty)
                  Text(unit, style: TextStyle(fontSize: 11, color: color)),
              ],
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
      ),
    );
  }

  Widget _buildRecCard(_Recommendation r) {
    final color = switch (r.severity) {
      'CRITICAL' => AppTheme.of(context).coral,
      'WARNING' => AppTheme.of(context).amber,
      _ => AppTheme.of(context).aqua,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.of(context).tintedCard(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(r.icon, color: color, size: 17),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  r.severity,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 9.5,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            r.parameter,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: AppTheme.of(context).ink,
            ),
          ),
          const SizedBox(height: 14),
          _blockLabel('EFFECT ON FISH'),
          Text(
            r.effect,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppTheme.of(context).inkSoft,
            ),
          ),
          const SizedBox(height: 14),
          _blockLabel('RECOMMENDED ACTIONS'),
          Text(
            r.action,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: AppTheme.of(context).ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _blockLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.of(context).inkSoft,
            letterSpacing: 0.6,
          ),
        ),
      );
}

class _Recommendation {
  final IconData icon;
  final String severity;
  final String parameter;
  final String effect;
  final String action;

  _Recommendation({
    required this.icon,
    required this.severity,
    required this.parameter,
    required this.effect,
    required this.action,
  });
}

/// Per-parameter water quality classification and corrective advice.
///
/// Thresholds come from the capstone manuscript (Tables 1–3), for Tilapia:
///   pH   6.5 – 8.5      Temp 25 – 32 °C      DO  > 5.0 mg/L
library;

import '../services/i18n.dart';

enum WaterParam { ph, temperature, dissolvedOxygen }

/// A single parameter's reading, judged against its safe range.
class ParamReading {
  final WaterParam param;
  final double value;

  /// 'safe' | 'warning' | 'critical'
  final String level;

  /// Short human-readable condition, e.g. "Optimal", "Warm stress".
  final String condition;

  const ParamReading({
    required this.param,
    required this.value,
    required this.level,
    required this.condition,
  });

  bool get isSafe => level == 'safe';

  String get label {
    switch (param) {
      case WaterParam.ph:
        return 'pH Level';
      case WaterParam.temperature:
        return 'Temperature';
      case WaterParam.dissolvedOxygen:
        return 'Dissolved O₂';
    }
  }

  String get unit {
    switch (param) {
      case WaterParam.ph:
        return '';
      case WaterParam.temperature:
        return '°C';
      case WaterParam.dissolvedOxygen:
        return 'mg/L';
    }
  }

  int get decimals => param == WaterParam.temperature ? 1 : 2;

  String get safeRangeText {
    switch (param) {
      case WaterParam.ph:
        return '6.5 – 8.5';
      case WaterParam.temperature:
        return '25 – 32 °C';
      case WaterParam.dissolvedOxygen:
        return '> 5.0 mg/L';
    }
  }

  /// What the operator should do about it. Null when the reading is safe.
  String? get advice {
    if (isSafe) return null;
    switch (param) {
      case WaterParam.ph:
        if (value < 6.5) {
          return 'pH is low. Add agricultural lime (about 150–200 kg/ha) '
              'and recheck after one week.';
        }
        return 'pH is high. Do a partial water change to bring it back '
            'into range, and avoid adding lime.';
      case WaterParam.temperature:
        if (value < 25) {
          return 'Water is cooler than ideal. Monitor closely, especially '
              'at night, and reduce feeding slightly.';
        }
        return 'Water is warm. Provide shade or increase pond depth to '
            'reduce heat stress on the fish.';
      case WaterParam.dissolvedOxygen:
        return 'Oxygen is low. Turn on the aerator and reduce feeding '
            'until the level recovers above 5 mg/L.';
    }
  }

  static ParamReading classify(WaterParam param, double value) {
    switch (param) {
      case WaterParam.ph:
        if (value < 4) {
          return ParamReading(
            param: param,
            value: value,
            level: 'critical',
            condition: 'Strongly acidic',
          );
        }
        if (value < 6.5) {
          return ParamReading(
            param: param,
            value: value,
            level: 'warning',
            condition: 'Acidic',
          );
        }
        if (value <= 8.5) {
          return ParamReading(
            param: param,
            value: value,
            level: 'safe',
            condition: 'Optimal',
          );
        }
        if (value <= 10) {
          return ParamReading(
            param: param,
            value: value,
            level: 'warning',
            condition: 'Alkaline',
          );
        }
        return ParamReading(
          param: param,
          value: value,
          level: 'critical',
          condition: 'Strongly alkaline',
        );

      case WaterParam.temperature:
        if (value < 20) {
          return ParamReading(
            param: param,
            value: value,
            level: 'critical',
            condition: 'Cold stress',
          );
        }
        if (value < 25) {
          return ParamReading(
            param: param,
            value: value,
            level: 'warning',
            condition: 'Cool',
          );
        }
        if (value <= 32) {
          return ParamReading(
            param: param,
            value: value,
            level: 'safe',
            condition: 'Optimal',
          );
        }
        if (value <= 35) {
          return ParamReading(
            param: param,
            value: value,
            level: 'warning',
            condition: 'Warm stress',
          );
        }
        return ParamReading(
          param: param,
          value: value,
          level: 'critical',
          condition: 'Too hot',
        );

      case WaterParam.dissolvedOxygen:
        if (value < 2) {
          return ParamReading(
            param: param,
            value: value,
            level: 'critical',
            condition: 'Severe depletion',
          );
        }
        if (value < 3) {
          return ParamReading(
            param: param,
            value: value,
            level: 'warning',
            condition: 'Low oxygen',
          );
        }
        if (value < 5) {
          return ParamReading(
            param: param,
            value: value,
            level: 'warning',
            condition: 'Moderate stress',
          );
        }
        return ParamReading(
          param: param,
          value: value,
          level: 'safe',
          condition: 'Optimal',
        );
    }
  }
}

/// Suspected causes offered when logging a fish mortality, each paired with
/// a concrete next step for the operator.
class MortalityCause {
  static const other = 'Other';

  static const options = <String>[
    'Mababang oxygen',
    'Hindi magandang kalidad ng tubig',
    'Sakit / impeksiyon',
    'Predator (hal. daga, ibon, atbp.)',
    'Overfeeding',
    'Dumi ng isda',
    other,
  ];

  /// Converts older English records to the current Filipino labels without a
  /// database migration. Custom Other reasons remain intact.
  static String displayName(String cause) {
    switch (cause) {
      case 'Low oxygen':
        return 'Mababang oxygen';
      case 'Poor water quality':
        return 'Hindi magandang kalidad ng tubig';
      case 'Disease / infection':
        return 'Sakit / impeksiyon';
      case 'Predator':
      case 'Mandaragit':
        return 'Predator (hal. daga, ibon, atbp.)';
      case 'Unknown / Other':
        return other;
      default:
        return cause;
    }
  }

  static String formValueFor(String storedCause) {
    final displayed = displayName(storedCause);
    if (displayed == other || displayed.startsWith('$other:')) return other;
    return options.contains(displayed) ? displayed : other;
  }

  static String otherReasonFor(String storedCause) {
    final displayed = displayName(storedCause);
    return displayed.startsWith('$other:')
        ? displayed.substring('$other:'.length).trim()
        : '';
  }

  static bool isOther(String cause) => formValueFor(cause) == other;

  static String storedValue(String selectedCause, String otherReason) =>
      selectedCause == other ? '$other: ${otherReason.trim()}' : selectedCause;

  static String localizedName(String cause) {
    final stored = displayName(cause);
    if (stored.startsWith('$other:')) {
      return '${L('Other', 'Iba pa')}:${stored.substring(other.length + 1)}';
    }
    return switch (stored) {
      'Mababang oxygen' => L('Low oxygen', stored),
      'Hindi magandang kalidad ng tubig' => L('Poor water quality', stored),
      'Sakit / impeksiyon' => L('Disease / infection', stored),
      'Predator (hal. daga, ibon, atbp.)' => L(
          'Predator (e.g. rats or birds)',
          'Mandaragit (hal. daga o ibon)',
        ),
      'Overfeeding' => L(stored, 'Sobrang pagpapakain'),
      'Dumi ng isda' => L('Fish waste', stored),
      other => L('Other', 'Iba pa'),
      _ => stored,
    };
  }

  static String adviceFor(String cause) {
    if (isOther(cause)) return '';
    return switch (displayName(cause)) {
      'Mababang oxygen' => L(
          'Check the current dissolved oxygen reading and the aerator.',
          'Suriin ang kasalukuyang dissolved oxygen at ang aerator.',
        ),
      'Hindi magandang kalidad ng tubig' => L(
          'Review the recent pH, temperature, and dissolved oxygen readings.',
          'Suriin ang mga nakaraang reading ng pH, temperatura, at dissolved oxygen.',
        ),
      'Sakit / impeksiyon' => L(
          'Consult a fisheries technician about the signs you observed.',
          'Kumonsulta sa fisheries technician tungkol sa mga napansing palatandaan.',
        ),
      'Predator (hal. daga, ibon, atbp.)' => L(
          'Inspect the pond netting and barriers for gaps or signs of entry.',
          'Suriin kung may butas o palatandaan ng pagpasok sa lambat at harang ng pond.',
        ),
      'Overfeeding' => L(
          'Remove uneaten feed and monitor dissolved oxygen and water quality.',
          'Alisin ang hindi nakain na pakain at bantayan ang dissolved oxygen at kalidad ng tubig.',
        ),
      'Dumi ng isda' => L(
          'Check for waste buildup and inspect the filtration and aeration.',
          'Tingnan kung may naipong dumi at suriin ang filtration at aeration.',
        ),
      _ => L(
          'Check other records for repeated observations.',
          'Tingnan kung nauulit ang obserbasyon sa ibang tala.',
        ),
    };
  }
}

import 'water_quality.dart';

/// A plain-language explanation of one abnormal reading.
///
/// The app and the SMS both need to say the same five things about a bad
/// reading — what is happening, why, what it leads to, what to do, and the one
/// recommended action — in words a fish farmer reads without a manual. Keeping
/// that content in one place, keyed by parameter and severity, means a new
/// sensor or a reworded warning is edited here once and every surface follows.
///
/// This is deliberately free of any Flutter import so it can be unit-tested and
/// reused by a background/SMS path without pulling in the widget layer.
class AlertExplanation {
  /// A single leading glyph for the card header, e.g. "🚨" or "⚠️".
  final String emoji;

  /// Short headline in sentence form, e.g. "Dissolved oxygen is critically low".
  final String title;

  /// 1 — what the sensor is seeing right now, with the value.
  final String whatsHappening;

  /// 2 — why it is happening / why it matters.
  final String why;

  /// 3 — what it can lead to if nothing changes.
  final String consequence;

  /// 4 — the concrete thing to do.
  final String whatToDo;

  /// 5 — the one-line recommended action, suitable for a chip or a summary row.
  final String recommendation;

  /// Detailed, ordered corrective actions formerly shown on the Dashboard's
  /// Recommendations screen.
  final List<String> actionSteps;

  /// What to recheck after acting, and when.
  final String followUp;

  const AlertExplanation({
    required this.emoji,
    required this.title,
    required this.whatsHappening,
    required this.why,
    required this.consequence,
    required this.whatToDo,
    required this.recommendation,
    required this.actionSteps,
    required this.followUp,
  });
}

/// Builds [AlertExplanation]s and matching SMS text from a reading.
///
/// Everything routes through [forReading] so the app's alert detail, the
/// Dashboard's advice card, and the SMS preview cannot drift apart. Adding a
/// parameter means adding one branch; adding a sensor type means adding one
/// enum case in [WaterParam] and one branch here.
class AlertContent {
  const AlertContent._();

  /// Whether the value sits below or above the safe band, for parameters that
  /// can breach on either side. Dissolved oxygen only ever breaches [low].
  static _Side _side(ParamReading r) {
    switch (r.param) {
      case WaterParam.ph:
        return r.value < 6.5 ? _Side.low : _Side.high;
      case WaterParam.temperature:
        return r.value < 25 ? _Side.low : _Side.high;
      case WaterParam.dissolvedOxygen:
        return _Side.low;
    }
  }

  /// The full explanation for a reading. Returns null when the reading is safe
  /// — a safe reading has nothing to explain.
  static AlertExplanation? forReading(ParamReading r) {
    if (r.isSafe) return null;
    final crit = r.level == 'critical';
    final side = _side(r);
    final v = r.value.toStringAsFixed(r.decimals);

    switch (r.param) {
      case WaterParam.ph:
        if (side == _Side.low) {
          return AlertExplanation(
            emoji: crit ? '🚨' : '⚠️',
            title: crit
                ? 'Water is dangerously acidic'
                : 'Water is turning acidic',
            whatsHappening:
                'The pH reading is $v, ${crit ? "far below" : "below"} the '
                'safe range of 6.5 – 8.5.',
            why: 'Acidic water often builds up from decaying feed and waste, '
                'heavy rain, or acid-sulfate soil around the pond.',
            consequence: crit
                ? 'At this level the fish are under severe stress — gills are '
                    'damaged and deaths can follow within hours.'
                : 'Left unchecked it slows growth, weakens the fish, and makes '
                    'them prone to disease.',
            whatToDo:
                'Add agricultural lime (about 150–200 kg per hectare) and '
                'recheck the pH after a few days.${crit ? " Do not feed heavily "
                    "until it recovers." : ""}',
            recommendation:
                'Apply agricultural lime and recheck pH after a few days.',
            actionSteps: crit
                ? const [
                    'Immediately add agricultural lime (CaCO₃) or crushed eggshells gradually.',
                    'Perform an emergency partial water change of 30–50%.',
                    'Remove decaying feed, leaves, and other organic debris from the pond.',
                    'Stop heavy feeding until the pH begins to recover.',
                  ]
                : const [
                    'Add agricultural lime or crushed eggshells gradually; do not add the full amount at once.',
                    'Reduce feeding to limit additional organic waste.',
                    'Inspect and remove decaying feed, leaves, or sludge.',
                  ],
            followUp: crit
                ? 'Re-test pH after 2 hours, then continue checking until it is back within 6.5–8.5.'
                : 'Check pH daily and only repeat treatment gradually until it reaches 6.5–8.5.',
          );
        }
        return AlertExplanation(
          emoji: crit ? '🚨' : '⚠️',
          title: crit
              ? 'Water is dangerously alkaline'
              : 'Water is turning alkaline',
          whatsHappening:
              'The pH reading is $v, ${crit ? "far above" : "above"} the safe '
              'range of 6.5 – 8.5.',
          why: 'High pH usually comes from a heavy algae bloom using up the '
              'water\'s acidity during the day, or from too much lime.',
          consequence: crit
              ? 'Ammonia becomes far more toxic at this pH — the fish can be '
                  'poisoned even at normal ammonia levels.'
              : 'It stresses the fish and, combined with warm water, raises '
                  'the risk of an ammonia problem.',
          whatToDo:
              'Do a partial water change to dilute it and stop adding lime. '
              '${crit ? "Reduce feeding until it settles." : ""}',
          recommendation: 'Do a partial water change and stop adding lime.',
          actionSteps: crit
              ? const [
                  'Perform an immediate partial water change of 30–50%.',
                  'Stop adding lime or any alkaline pond treatment.',
                  'Reduce feeding while the pH remains critically high.',
                  'Check for cement, limestone, or excessive algae around the pond.',
                ]
              : const [
                  'Perform a partial water change of 20–30%.',
                  'Stop adding lime and avoid sudden chemical correction.',
                  'Check for an excessive algae bloom or alkaline runoff.',
                ],
          followUp: crit
              ? 'Re-test pH after 2 hours and continue partial water changes if it remains above 8.5.'
              : 'Monitor pH daily, especially in the afternoon when algae can push it higher.',
        );

      case WaterParam.temperature:
        if (side == _Side.low) {
          return AlertExplanation(
            emoji: crit ? '🚨' : '⚠️',
            title: crit ? 'Water is too cold' : 'Water is cooler than ideal',
            whatsHappening:
                'The temperature is $v °C, ${crit ? "well below" : "below"} '
                'the ideal 25 – 32 °C for tilapia.',
            why:
                'Cold spells, heavy rain, or a deep shaded pond pull the water '
                'temperature down, especially overnight.',
            consequence: crit
                ? 'Tilapia stop feeding and their immune system fails below '
                    '20 °C — sustained cold can be fatal.'
                : 'The fish eat less and grow slowly while it stays cool.',
            whatToDo:
                'Reduce feeding to avoid wasted feed fouling the water, and '
                'monitor closely${crit ? ", especially at night" : ""}.',
            recommendation:
                'Reduce feeding and monitor the pond closely overnight.',
            actionSteps: crit
                ? const [
                    'Stop or greatly reduce feeding while the water is below 20 °C.',
                    'Reduce inflow from unusually cold water sources.',
                    'Remove temporary shade so sunlight can warm the pond.',
                    'For a small pond, use a suitable water heater only with safe electrical installation.',
                  ]
                : const [
                    'Reduce feeding because tilapia digest food slowly in cool water.',
                    'Increase safe sun exposure where possible.',
                    'Monitor the temperature trend through the day and overnight.',
                  ],
            followUp: crit
                ? 'Check temperature every 1–2 hours until it rises above 20 °C; resume normal feeding only near the safe range.'
                : 'Recheck in the warmest and coolest parts of the day until it returns to 25–32 °C.',
          );
        }
        return AlertExplanation(
          emoji: crit ? '🚨' : '⚠️',
          title:
              crit ? 'Water is dangerously hot' : 'Water is getting too warm',
          whatsHappening:
              'The temperature is $v °C, ${crit ? "well above" : "above"} the '
              'ideal 25 – 32 °C for tilapia.',
          why: 'Strong sun on a shallow pond heats the water fast, and warm '
              'water holds much less oxygen.',
          consequence: crit
              ? 'Hot water plus low oxygen is the classic fish-kill '
                  'combination — deaths can happen quickly, often at dawn.'
              : 'Warm water lowers oxygen and stresses the fish, raising the '
                  'risk overnight.',
          whatToDo:
              'Provide shade or add fresh water to deepen and cool the pond, '
              'and run the aerator${crit ? " through the night" : ""}.',
          recommendation:
              'Add shade or fresh water and run the aerator to cool the pond.',
          actionSteps: crit
              ? const [
                  'Run all available aerators or increase water agitation immediately.',
                  'Add cooler fresh water gradually and increase pond depth.',
                  'Install shade over part of the pond or use suitable floating plants.',
                  'Reduce feeding and, if overcrowded, reduce stocking density temporarily.',
                ]
              : const [
                  'Increase pond depth or add cooler fresh water gradually.',
                  'Provide shade over part of the pond.',
                  'Confirm that aerators are operating properly.',
                  'Watch for fish gasping or gathering near water inlets.',
                ],
          followUp: crit
              ? 'Recheck temperature and dissolved oxygen every hour until temperature is below 32 °C and oxygen is stable.'
              : 'Monitor through the hottest afternoon hours and again before sunrise.',
        );

      case WaterParam.dissolvedOxygen:
        return AlertExplanation(
          emoji: crit ? '🚨' : '⚠️',
          title: crit ? 'Oxygen is critically low' : 'Oxygen is getting low',
          whatsHappening:
              'Dissolved oxygen is $v mg/L, ${crit ? "far below" : "below"} '
              'the safe level of 5 mg/L.',
          why: 'Oxygen is used up overnight by the fish, algae, and decaying '
              'feed, and warm water holds less of it to begin with.',
          consequence: crit
              ? 'This is the most common cause of a mass fish kill. The fish '
                  'suffocate — expect them gasping at the surface at dawn.'
              : 'If it keeps dropping, especially before sunrise, the fish '
                  'begin to suffocate.',
          whatToDo:
              'Turn on the aerator now and stop feeding until oxygen recovers '
              'above 5 mg/L.${crit ? " Do a partial water change if you can." : ""}',
          recommendation:
              'Turn on the aerator now and stop feeding until oxygen recovers.',
          actionSteps: crit
              ? const [
                  'Immediately activate all aerators, paddlewheels, or splashers.',
                  'Stop all feeding to reduce oxygen demand.',
                  'Perform an emergency partial water change of up to 50% using oxygenated water.',
                  'Transfer some fish if the pond is overcrowded.',
                  'Remove dead fish and decaying material immediately.',
                ]
              : const [
                  'Turn on aerators or paddlewheels and increase surface agitation.',
                  'Reduce or temporarily stop feeding.',
                  'Remove excess algae, uneaten feed, and organic debris.',
                  'Check whether stocking density is too high for the available aeration.',
                ],
          followUp: crit
              ? 'Measure DO every 15–30 minutes until it is above 5 mg/L, then check again before sunrise.'
              : 'Check DO repeatedly, especially between 4–6 AM when oxygen is normally lowest.',
        );
    }
  }

  /// The SMS body for a breached reading — the same five ideas as [forReading],
  /// compressed to a single readable message rather than the terse
  /// "CRITICAL: pH HIGH" the old firmware sent.
  ///
  /// Kept here so the app can preview exactly what a farmer receives. The
  /// device builds the same shape on its own; this is the reference wording.
  static String smsText(ParamReading r,
      {String farmName = 'Liponhay Fish Farm'}) {
    final e = forReading(r);
    if (e == null) return '';
    final tag = r.level == 'critical' ? '🚨 CRITICAL ALERT' : '⚠️ WARNING';
    return '$tag — $farmName\n'
        '${e.title}. ${e.whatsHappening}\n'
        '${e.consequence}\n'
        'Action: ${e.recommendation}';
  }
}

enum _Side { low, high }

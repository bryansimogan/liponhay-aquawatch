/// Parameter metadata, response windows, and the bilingual risk / feeding /
/// "what to do now" content, ported from the AquaWatch HTML prototype
/// (PR, RISK, FEED, DO_NOW, HINT, AUTO).
///
/// Thresholds match [ParamReading.classify]: pH 6.5–8.5 (crit <4 or >10),
/// temp 25–32 °C (crit <20 or >35), DO ≥5 mg/L (crit <2).
library;

import '../services/i18n.dart';

/// Resolve an [en, tl] pair against the current language.
String _p(List<String> pair) => L(pair[0], pair[1]);

/// Per-parameter metadata and the response windows (in minutes) the owner has
/// to act before an incident is marked unresolved.
class ParamMeta {
  final String key; // 'ph' | 't' | 'o'
  final List<String> name; // [en, tl]
  final String unit;
  final int decimals;

  /// [earliest, latest] minutes to act, for warning and critical levels.
  final List<int> warnWindow;
  final List<int> critWindow;

  const ParamMeta(this.key, this.name, this.unit, this.decimals,
      this.warnWindow, this.critWindow);

  String get label => _p(name);

  List<int> window(String lvl) => lvl == 'crit' ? critWindow : warnWindow;
}

const Map<String, ParamMeta> paramMeta = {
  'o': ParamMeta('o', ['Dissolved O₂', 'Dissolved O₂'], 'mg/L', 2, [120, 240],
      [30, 60]),
  'ph': ParamMeta('ph', ['pH level', 'Antas ng pH'], '', 2, [360, 720],
      [120, 240]),
  't': ParamMeta('t', ['Temperature', 'Temperatura'], '°C', 1, [240, 480],
      [120, 180]),
};

/// Format a reading for a parameter, e.g. "2.57 mg/L", "8.90".
String formatReading(String p, double v) {
  final m = paramMeta[p]!;
  final s = v.toStringAsFixed(m.decimals);
  return m.unit.isEmpty ? s : '$s ${m.unit}';
}

/// "X–Y min" or "X–Y h", from a window in minutes.
String windowText(List<int> w) {
  if (w[1] <= 60) return '${w[0]}–${w[1]} min';
  return '${w[0] ~/ 60}–${w[1] ~/ 60} ${L('h', 'oras')}';
}

String levelName(String lvl) =>
    lvl == 'crit' ? L('Critical', 'Kritikal') : L('Warning', 'Babala');

/// Title for an incident, from the parameter and its value.
String paramTitle(String p, double v) {
  if (p == 'o') return L('Low dissolved oxygen', 'Mababang dissolved oxygen');
  if (p == 'ph') {
    return v > 7
        ? L('High pH', 'Mataas na pH')
        : L('Low pH', 'Mababang pH');
  }
  return v > 28
      ? L('High temperature', 'Mataas na temperatura')
      : L('Low temperature', 'Mababang temperatura');
}

/// How far outside the safe range a value sits (0 when safe).
double distance(String p, double v) {
  if (p == 'o') return v < 5 ? 5 - v : 0;
  if (p == 'ph') {
    if (v < 6.5) return 6.5 - v;
    if (v > 8.5) return v - 8.5;
    return 0;
  }
  if (v < 25) return 25 - v;
  if (v > 32) return v - 32;
  return 0;
}

/// Which risk profile applies: 'o' | 'phh' | 'phl' | 'th' | 'tc'.
String riskKey(String p, double v) {
  if (p == 'o') return 'o';
  if (p == 'ph') return v > 8.5 ? 'phh' : 'phl';
  return v > 32 ? 'th' : 'tc';
}

/// A full risk profile: title, one-line summary, causes, and consequences.
class RiskInfo {
  final List<String> title;
  final List<String> summary;
  final List<List<String>> causes; // each [en, tl]
  final List<List<String>> effects; // each [en, tl], ordered 1→3

  const RiskInfo(this.title, this.summary, this.causes, this.effects);

  String get t => _p(title);
  String get s => _p(summary);
  List<String> get causeList => causes.map(_p).toList();
  List<String> get effectList => effects.map(_p).toList();
}

const Map<String, RiskInfo> risk = {
  'o': RiskInfo(
    ['Low oxygen', 'Mababang oxygen'],
    ['Fish can suffocate', 'Maaaring mamatay sa kakulangan ng hangin ang isda'],
    [
      ['No aerator running, or a brownout',
          'Walang tumatakbong aerator, o brownout'],
      ['Too much feed rotting at the bottom and using up oxygen',
          'Sobrang pakain na nabubulok sa ilalim at kumakain ng oxygen'],
      ['Early morning or cloudy weather, when algae make little oxygen',
          'Madaling-araw o maulap, kaunti ang oxygen na nagagawa ng algae'],
      ['Too many fish in the pond', 'Siksikan ang isda sa pond'],
    ],
    [
      ['Fish crowd at the surface and gasp for air',
          'Dumadagsa ang isda sa ibabaw at humahabol ng hangin'],
      ['They stop eating, weaken and get sick more easily',
          'Tumitigil sila sa pagkain, humihina, at mas madaling magkasakit'],
      ['Mass fish kill: the whole pond can be lost within hours',
          'Mass fish kill: puwedeng maubos ang isda sa pond sa loob ng ilang oras'],
    ],
  ),
  'phh': RiskInfo(
    ['High pH (basic water)', 'Mataas na pH (sobrang basic)'],
    ['Burns the gills and raises toxic ammonia',
        'Nasusunog ang hasang at tumataas ang nakalalasong ammonia'],
    [
      ['Heavy algae growth in the daytime', 'Sobrang algae sa maghapon'],
      ['Too much lime or fertilizer', 'Sobrang dayap o pataba'],
      ['Hard, alkaline source water', 'Matigas o alkaline ang pinagkukunang tubig'],
    ],
    [
      ['Gills and skin are irritated; fish swim erratically',
          'Nai-irita ang hasang at balat; hindi mapakali ang isda'],
      ['Ammonia becomes more toxic, which poisons the fish',
          'Mas nakalalason ang ammonia kaya nalalason ang isda'],
      ['Deaths, usually in the afternoon when pH peaks',
          'Pagkamatay, kadalasan sa hapon kapag pinakamataas ang pH'],
    ],
  ),
  'phl': RiskInfo(
    ['Low pH (acidic water)', 'Mababang pH (maasim na tubig)'],
    ['Damages the skin and gills', 'Nasisira ang balat at hasang'],
    [
      ['Heavy rain or acidic soil', 'Malakas na ulan o maasim na lupa'],
      ['Rotting waste and leftover feed', 'Nabubulok na dumi at tirang pakain'],
      ['Not enough lime in the pond', 'Kulang sa dayap ang pond'],
    ],
    [
      ['Skin sores and pale, damaged gills',
          'May sugat sa balat at namumutla o nasisira ang hasang'],
      ['Fish grow slowly and catch diseases easily',
          'Mabagal lumaki at madaling magkasakit'],
      ['Deaths if the water stays acidic',
          'Pagkamatay kapag nanatiling maasim ang tubig'],
    ],
  ),
  'th': RiskInfo(
    ['High temperature', 'Mataas na temperatura'],
    ['Heat stress, and less oxygen at the same time',
        'Heat stress, at nababawasan din ang oxygen'],
    [
      ['Strong sun on shallow water', 'Matinding init ng araw sa mababaw na tubig'],
      ['No shade over the pond', 'Walang lilim ang pond'],
      ['Little water flow or exchange', 'Kaunti ang daloy o palit ng tubig'],
    ],
    [
      ['Fish breathe fast and eat less', 'Mabilis huminga at bumababa ang kain'],
      ['Warm water holds less oxygen, so low-DO problems follow',
          'Mas kaunti ang oxygen sa maligamgam na tubig kaya sumusunod ang mababang DO'],
      ['Heat shock and deaths', 'Heat shock at pagkamatay'],
    ],
  ),
  'tc': RiskInfo(
    ['Low temperature', 'Mababang temperatura'],
    ['Fish become weak and sick', 'Humihina at nagkakasakit ang isda'],
    [
      ['Cold rain or strong cold wind', 'Malamig na ulan o malakas na hangin'],
      ['Cold nights with no sun', 'Malamig na gabi at walang sikat ng araw'],
      ['Cold water poured in too fast', 'Biglaang pagpasok ng malamig na tubig'],
    ],
    [
      ['Fish become sluggish and eat less', 'Tumatamlay at bumababa ang kain'],
      ['Weak immunity: fungus and disease spread',
          'Humihina ang resistensya: kumakalat ang fungus at sakit'],
      ['Deaths if the cold continues', 'Pagkamatay kapag tuloy-tuloy ang lamig'],
    ],
  ),
};

/// Immediate steps, keyed by risk profile.
const Map<String, List<List<String>>> doNow = {
  'o': [
    ['Turn on the aerator now, or use backup power or a spare unit',
        'I-on agad ang aerator, o gamitin ang backup na kuryente o ekstrang unit'],
    ['Let in fresh, clean water if you can',
        'Magpasok ng sariwa at malinis na tubig kung kaya'],
    ['Do not net or move the fish. Handling stresses them more',
        'Huwag hulihin o ilipat ang isda. Mas nakaka-stress ang paghawak'],
  ],
  'phh': [
    ['Change about 20–30% of the water with clean water',
        'Magpalit ng mga 20–30% ng tubig gamit ang malinis na tubig'],
    ['Add shade to cut the sunlight that feeds the algae',
        'Maglagay ng lilim para mabawasan ang sikat ng araw na nagpapadami ng algae'],
    ['Do not add lime or fertilizer', 'Huwag maglagay ng dayap o pataba'],
  ],
  'phl': [
    ['Change about 20–30% of the water with clean water',
        'Magpalit ng mga 20–30% ng tubig gamit ang malinis na tubig'],
    ['Apply agricultural lime in the amount a technician advises',
        'Maglagay ng agricultural lime sa dami na payo ng technician'],
    ['Remove rotting waste and leftover feed at the bottom',
        'Alisin ang nabubulok na dumi at tirang pakain sa ilalim'],
  ],
  'th': [
    ['Put up shade (net or roof) over part of the pond',
        'Maglagay ng lilim (net o bubong) sa bahagi ng pond'],
    ['Let in cool, clean water slowly, not all at once',
        'Magpasok ng malamig at malinis na tubig nang dahan-dahan'],
    ['Run the aerator, since warm water holds less oxygen',
        'I-on ang aerator, dahil kaunti ang oxygen sa maligamgam na tubig'],
  ],
  'tc': [
    ['Keep the water deep, because deep water holds heat better',
        'Panatilihing malalim ang tubig, mas nakakapigil ng init'],
    ['Block strong wind and cold rain from the pond',
        'Harangan ang pond sa malakas na hangin at malamig na ulan'],
    ['Avoid handling or moving the fish until it warms up',
        'Iwasan munang hawakan o ilipat ang isda hanggang uminit'],
  ],
};

/// Feeding advice while an incident is open.
class FeedAdvice {
  final bool stop;
  final List<String> advice;
  const FeedAdvice(this.stop, this.advice);
  String get text => _p(advice);
}

const Map<String, FeedAdvice> feed = {
  'o': FeedAdvice(true, [
    'Stop feeding until DO is back above 5.0 mg/L. Fish use oxygen to digest, and leftover feed rots and uses oxygen too.',
    'Ihinto muna ang pagpapakain hanggang bumalik sa higit 5.0 mg/L ang DO. Gumagamit ng oxygen ang isda sa pagtunaw, at ang tirang pakain ay nabubulok at kumakain din ng oxygen.'
  ]),
  'phh': FeedAdvice(false, [
    'Cut feeding and avoid fertilizer so the algae stop blooming. Algae growth is what pushes the pH up.',
    'Bawasan ang pakain at iwasan ang pataba para hindi dumami ang algae. Ang algae ang nagpapataas ng pH.'
  ]),
  'phl': FeedAdvice(false, [
    'Cut feeding. Leftover feed and waste turn the water acidic as they rot.',
    'Bawasan ang pakain. Ang tirang pakain at dumi ay nagpapaasim sa tubig kapag nabubulok.'
  ]),
  'th': FeedAdvice(false, [
    'Cut feeding and feed only in the early morning and late afternoon, not at midday. Digesting feed adds to the heat stress.',
    'Bawasan ang pakain at magpakain lang sa maagang umaga at hapon, hindi sa tanghali. Dagdag na stress sa init ang pagtunaw ng pakain.'
  ]),
  'tc': FeedAdvice(false, [
    'Cut feeding. Fish digest slowly in cold water, so uneaten feed piles up and spoils the water.',
    'Bawasan ang pakain. Mabagal tumunaw ang isda kapag malamig, kaya naiipon at sumisira sa tubig ang hindi nakain.'
  ]),
};

/// Short hint line per parameter, for the "please take an action" tile.
String hintFor(String p) => switch (p) {
      'o' => L('Turn on the aerator or add oxygen',
          'I-on ang aerator o dagdagan ng oxygen'),
      'ph' => L('Treat the water or do a partial water exchange',
          'Gamutin ang tubig o magpalit ng bahagi ng tubig'),
      _ => L('Add shade, increase water flow or reduce feeding',
          'Magdagdag ng lilim, dagdagan ang daloy o bawasan ang pakain'),
    };

/// The action the app auto-detects from the sensor readings.
String autoActionFor(String p) => switch (p) {
      'o' => L('Aerator / oxygen input', 'Aerator / dagdag na oxygen'),
      'ph' => L('Water treatment / partial exchange',
          'Panggagamot ng tubig / bahagyang palit-tubig'),
      _ => L('Cooling: shade, flow or reduced feeding',
          'Pagpapalamig: lilim, daloy o bawas-pakain'),
    };

/// Minimum improvement in distance-outside-range that counts as progress.
const Map<String, double> improvementDelta = {'o': 0.5, 'ph': 0.3, 't': 0.5};

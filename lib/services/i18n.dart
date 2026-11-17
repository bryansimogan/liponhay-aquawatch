/// Lightweight bilingual layer (English / Tagalog), ported from the AquaWatch
/// HTML prototype's `L(en, tl)` helper.
///
/// A single process-wide [appLang] lets plain data files (response content,
/// risk tips) resolve their own strings without needing a BuildContext. The
/// [AppStore] is the only writer: it updates [appLang] and then notifies its
/// listeners so the UI rebuilds in the chosen language.
library;

/// Current UI language: 'en' or 'tl'. Tagalog by default — the farm owner's
/// language, and what the capstone defense is presented in.
String appLang = 'tl';

/// Pick the English or Tagalog variant of a phrase.
String L(String en, String tl) => appLang == 'tl' ? tl : en;

bool get isTagalog => appLang == 'tl';

String get appDateLocale => isTagalog ? 'fil' : 'en';

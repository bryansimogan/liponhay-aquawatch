import '../services/i18n.dart';
import 'app_notification.dart';

/// Displays saved system notifications in the selected language. Firebase
/// notes and older demo notes keep their original storage format.
extension NotificationCopy on AppNotification {
  String get localizedTitle {
    final days = RegExp(r'^SIM promo expires in (\d+) days$').firstMatch(title);
    if (days != null) {
      return L(title, 'Mag-e-expire ang SIM promo sa loob ng ${days[1]} araw');
    }
    return _translate(title, _titles);
  }

  String get localizedBody {
    if (type == AppNotificationType.promo && id.startsWith('promo-')) {
      final separator = body.lastIndexOf(' · ');
      if (separator >= 0) {
        // The promo name can be entered by the operator. Translate the reminder.
        return body.substring(0, separator + 3) +
            _translate(body.substring(separator + 3), _phrases);
      }
    }
    final demoPromo = RegExp(
      r'^Demo SIM promo: (\d+) (?:h|oras) (\d+) (?:min left|minutong natitira)$',
    ).firstMatch(body);
    if (demoPromo != null) {
      return L(
        'Demo SIM promo: ${demoPromo[1]} h ${demoPromo[2]} min left',
        'Demo SIM promo: ${demoPromo[1]} oras ${demoPromo[2]} minutong natitira',
      );
    }
    return _translate(body, _phrases);
  }
}

String _translate(String value, Map<String, String> englishToTagalog) {
  final replacements = isTagalog
      ? englishToTagalog
      : {for (final entry in englishToTagalog.entries) entry.value: entry.key};
  final patterns = replacements.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final matcher = RegExp(patterns.map(RegExp.escape).join('|'));
  return value.replaceAllMapped(matcher, (match) => replacements[match[0]]!);
}

const _titles = {
  'New history reading': 'Bagong reading sa kasaysayan',
  'Critical alert · ': 'Kritikal na alerto · ',
  'Warning alert · ': 'Babala · ',
  'Dissolved oxygen': 'Natunaw na oxygen',
  'Temperature': 'Temperatura',
  'SIM promo expired': 'Expired na ang SIM promo',
  'SIM promo expires today': 'Mag-e-expire ang SIM promo ngayong araw',
  'SIM promo expires tomorrow': 'Mag-e-expire ang SIM promo bukas',
  'Low dissolved oxygen': 'Mababang dissolved oxygen',
  'High pH': 'Mataas na pH',
  'Low pH': 'Mababang pH',
  'High temperature': 'Mataas na temperatura',
  'Low temperature': 'Mababang temperatura',
  'Action taken': 'Nagawa na ang aksyon',
  'Back in range · verifying': 'Bumalik sa ligtas na saklaw · bine-verify',
  'Resolved · verified safe': 'Naresolba · na-verify na ligtas',
  'Unsafe again · verification reset':
      'Hindi ligtas muli · na-reset ang pag-verify',
  'Not resolved': 'Hindi naresolba',
  'Fish died': 'Namatay na isda',
  'Harvest logged': 'Naitala ang harvest',
  'Update': 'Update ng sistema',
};

const _phrases = {
  'Pond 1': 'Palaisdaan 1',
  'Temp ': 'Temperatura ',
  'Temperature': 'Temperatura',
  'pH level': 'Antas ng pH',
  ' is ': ' ay ',
  ' in ': ' sa ',
  'Act within': 'Kumilos sa loob ng',
  'Strongly acidic': 'Lubhang acidic',
  'Acidic': 'Acidic ang tubig',
  'Strongly alkaline': 'Lubhang alkaline',
  'Alkaline': 'Alkaline ang tubig',
  'Cold stress': 'Stress dahil sa lamig',
  'Cool': 'Malamig',
  'Warm stress': 'Stress dahil sa init',
  'Too hot': 'Masyadong mainit',
  'Severe depletion': 'Kritikal na kakulangan ng oxygen',
  'Low oxygen': 'Mababang oxygen',
  'Moderate stress': 'Katamtamang stress',
  'Optimal': 'Nasa tamang saklaw',
  'Low dissolved oxygen': 'Mababang dissolved oxygen',
  'High pH': 'Mataas na pH',
  'Low pH': 'Mababang pH',
  'High temperature': 'Mataas na temperatura',
  'Low temperature': 'Mababang temperatura',
  'Renew it now to keep SMS alerts working.':
      'I-renew ngayon para patuloy na gumana ang mga SMS alerto.',
  'Renew it before expiry to avoid interrupted SMS alerts.':
      'I-renew bago mag-expire para magpatuloy ang mga SMS alerto.',
  'Demo SIM promo expired': 'Expired na ang demo SIM promo',
  'Aerator / oxygen input': 'Aerator / dagdag na oxygen',
  'Water treatment / partial exchange':
      'Panggagamot ng tubig / bahagyang palit-tubig',
  'Cooling: shade, flow or reduced feeding':
      'Pagpapalamig: lilim, daloy o bawas-pakain',
  'The reading must stay in range for 10 minutes.':
      'Kailangang manatiling ligtas ang reading sa loob ng 10 minuto.',
  'Verified after 10 minutes of safe readings.':
      'Na-verify matapos ang 10 minutong ligtas na readings.',
  'is still': 'ay nananatiling',
  'after the response window': 'matapos ang itinakdang oras',
  'fish died': 'isda ang namatay',
  'Suspected cause': 'Posibleng sanhi',
  ' fish · ': ' isda · ',
};

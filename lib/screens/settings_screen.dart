import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/gsm_config.dart';
import '../services/app_store.dart';
import '../services/firebase_service.dart';
import '../services/i18n.dart';
import '../services/sync_service.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_header.dart';
import '../widgets/reveal.dart';
import '../widgets/sync_status.dart';

/// System settings: data source, SMS recipient, and connection state.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _gsmNumber = String.fromEnvironment('GSM_NUMBER');

  final FirebaseService _firebase = FirebaseService();

  String _smsRecipient = '+63XXXXXXXXXX';
  bool _loadingSms = true;

  GsmConfig _gsm = const GsmConfig();
  StreamSubscription? _gsmSub;

  /// Ticks the promo countdown so "expires in 3 days" becomes "in 2 days" on
  /// its own, without the operator reopening the screen. Day-granularity, so a
  /// minute is frequent enough — the per-second SMS cooldown is a separate job.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    if (!context.read<AppStore>().simulation) _loadSettings();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _gsmSub?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final phone = await _firebase.getSmsRecipient();
      if (mounted) {
        setState(() {
          _smsRecipient = phone;
          _loadingSms = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSms = false);
    }

    if (!mounted) return;
    try {
      _gsmSub = _firebase.gsmConfigStream().listen((cfg) {
        if (mounted) setState(() => _gsm = cfg);
      }, onError: (_) {});
    } catch (_) {
      // Leave the empty default in place if the config cannot be read.
    }
  }

  Future<void> _saveSmsRecipient(String newNumber) async {
    // Normalize to E.164 (+63…) before saving. The device only accepts a
    // number that starts with "+", so a value typed as "09171234567" was
    // written to Firebase fine but then silently rejected on the ESP32 — the
    // alert kept going to the old number. Converting here guarantees what we
    // store is what the firmware will use.
    final normalized = _normalizePhone(newNumber);
    if (normalized == null) {
      _toast('Enter a valid PH mobile number, '
          'e.g. 09171234567 or +639171234567.');
      return;
    }
    try {
      await _firebase.setSmsRecipient(normalized);
      setState(() => _smsRecipient = normalized);
      _toast('SMS recipient saved. The device applies it within a few '
          'minutes (or restart it to apply now).');
    } catch (e) {
      _toast('Could not save the number: $e');
    }
  }

  /// Converts common Philippine mobile formats to E.164 (+63XXXXXXXXXX),
  /// or returns null when it is not a valid mobile number. The firmware
  /// requires the leading "+", so anything that cannot be made valid is
  /// rejected here rather than saved and silently ignored on the device.
  String? _normalizePhone(String raw) {
    // Keep digits and a single leading +.
    var s = raw.trim().replaceAll(RegExp(r'[\s()\-]'), '');
    final hasPlus = s.startsWith('+');
    s = s.replaceAll(RegExp(r'[^0-9]'), '');

    String? national; // the 10 digits after the country code, starting with 9
    if (hasPlus && s.startsWith('63') && s.length == 12) {
      national = s.substring(2);
    } else if (s.startsWith('63') && s.length == 12) {
      national = s.substring(2);
    } else if (s.startsWith('0') && s.length == 11) {
      national = s.substring(1); // 09XXXXXXXXX -> 9XXXXXXXXX
    } else if (s.startsWith('9') && s.length == 10) {
      national = s;
    }

    if (national == null || !national.startsWith('9')) return null;
    return '+63$national';
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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              children: [
                Reveal(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Settings',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.of(context).ink,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Connection, alerts, and system info.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.of(context).inkSoft),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 150),
                          child: SyncPill(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionLabel('CONNECTION'),
                Reveal(
                  delayMs: 40,
                  child: ValueListenableBuilder<bool?>(
                    valueListenable: SyncService.instance.phoneOnline,
                    builder: (context, reachable, _) => _connectionCard(
                      'Phone internet',
                      reachable,
                      'WiFi or mobile data',
                      Icons.wifi_rounded,
                      Icons.wifi_off_rounded,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Reveal(
                  delayMs: 65,
                  child: ValueListenableBuilder<bool?>(
                    valueListenable: SyncService.instance.serverOnline,
                    builder: (context, reachable, _) => _connectionCard(
                      'Firebase server',
                      reachable,
                      'Realtime Database',
                      Icons.cloud_done_outlined,
                      Icons.cloud_off_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Reveal(
                  delayMs: 90,
                  child: ValueListenableBuilder<String>(
                    valueListenable: SyncService.instance.ageLabel,
                    builder: (context, age, _) => ValueListenableBuilder<bool>(
                      valueListenable: SyncService.instance.online,
                      builder: (context, online, _) => _connectionCard(
                        'ESP32',
                        online,
                        'Last reading $age',
                        Icons.sensors_rounded,
                        Icons.sensors_off_rounded,
                      ),
                    ),
                  ),
                ),
                if (!context.read<AppStore>().simulation) ...[
                  const SizedBox(height: 18),
                  _sectionLabel('GSM / SMS'),
                  Reveal(
                    delayMs: 160,
                    child: _card(
                      icon: Icons.sim_card_outlined,
                      iconColor: AppTheme.of(context).deep,
                      title: 'GSM number',
                      subtitle: _gsmNumber.isEmpty
                          ? L('Not configured', 'Walang nakatakdang numero')
                          : _gsmNumber,
                      trailing: const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Reveal(
                    delayMs: 200,
                    child: _card(
                      icon: Icons.sms_outlined,
                      iconColor: AppTheme.of(context).deep,
                      title: 'SMS recipient',
                      subtitle: _loadingSms ? 'Loading...' : _smsRecipient,
                      trailing: TextButton(
                        onPressed: _loadingSms ? null : _showSmsDialog,
                        child: const Text('Change'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Reveal(
                    delayMs: 240,
                    child: _promoCard(),
                  ),
                ],
                const SizedBox(height: 18),
                _sectionLabel(L('LANGUAGE', 'WIKA')),
                Reveal(delayMs: 280, child: _languageCard()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 5),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.of(context).inkSoft,
            letterSpacing: 0.6,
          ),
        ),
      );

  /// English / Tagalog toggle. Flipping it re-languages the whole app.
  Widget _languageCard() {
    final store = context.watch<AppStore>();
    Widget opt(String code, String label) {
      final on = store.lang == code;
      return Expanded(
        child: GestureDetector(
          onTap: () => context.read<AppStore>().lang = code,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: EdgeInsets.only(right: code == 'en' ? 8 : 0),
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on
                  ? AppTheme.of(context).deep.withOpacity(0.1)
                  : AppTheme.of(context).surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: on
                      ? AppTheme.of(context).deep
                      : AppTheme.of(context).border),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: on
                        ? AppTheme.of(context).deep
                        : AppTheme.of(context).inkSoft)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.of(context).card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: AppTheme.of(context).deep.withOpacity(0.11),
                    shape: BoxShape.circle),
                child: Icon(Icons.language_rounded,
                    color: AppTheme.of(context).deep, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(L('App language', 'Wika ng app'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.of(context).ink)),
                    Text(L('Choose English or Tagalog', 'Piliin ang wika'),
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.of(context).inkSoft)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [opt('en', 'English'), opt('tl', 'Tagalog')]),
        ],
      ),
    );
  }

  Widget _connectionCard(String name, bool? reachable, String subtitle,
      IconData connected, IconData disconnected) {
    final palette = AppTheme.of(context);
    final status = switch (reachable) {
      true => 'Online',
      false => 'Offline',
      null => 'Checking',
    };
    return _card(
      icon: reachable == true ? connected : disconnected,
      iconColor: reachable == true ? palette.aqua : palette.coral,
      title: '$name · $status',
      subtitle: subtitle,
      trailing: const SizedBox.shrink(),
    );
  }

  Widget _card({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.of(context).card(),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.11),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.of(context).ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                      fontSize: 11.5, color: AppTheme.of(context).inkSoft),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  void _showSmsDialog() {
    final controller = TextEditingController(text: _smsRecipient);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SMS recipient'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alerts are texted to this number when a reading '
              'leaves its safe range.',
              style: TextStyle(
                  fontSize: 12.5, color: AppTheme.of(context).inkSoft),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              style: TextStyle(fontSize: 14, color: AppTheme.of(context).ink),
              decoration: const InputDecoration(
                hintText: '09171234567 or +639171234567',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'The monitoring device picks up the new number within a few '
              'minutes. Restart the device to apply it right away.',
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: AppTheme.of(context).inkSoft),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _saveSmsRecipient(controller.text);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(80, 42),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Color _expiryColor(String status) {
    switch (status) {
      case 'expired':
      case 'urgent':
        return AppTheme.of(context).coral;
      case 'soon':
        return AppTheme.of(context).amber;
      case 'ok':
        return AppTheme.of(context).deep;
      default:
        return AppTheme.of(context).inkSoft;
    }
  }

  /// SIM load / promo status with a live expiry countdown. Tapping it opens the
  /// editor. The countdown text comes straight from [GsmConfig.expiryLabel],
  /// which recomputes from the current date every time this rebuilds.
  Widget _promoCard() {
    final isSet = !_gsm.isEmpty;
    final status = _gsm.expiryStatus;
    final color = _expiryColor(status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openGsmEditor,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.of(context).card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.11),
                      shape: BoxShape.circle,
                    ),
                    child:
                        Icon(Icons.sim_card_outlined, color: color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSet && _gsm.promoName.isNotEmpty
                              ? _gsm.promoName
                              : 'SIM promo',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.of(context).ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isSet
                              ? '${_gsm.durationDays}-day promo'
                              : 'Not set up — add the SIM promo',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.of(context).inkSoft),
                        ),
                      ],
                    ),
                  ),
                  Text(isSet ? 'Edit' : 'Set up',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.of(context).deep,
                      )),
                ],
              ),
              // The expiry reminder — only once a date is set.
              if (_gsm.expiryStatus != 'none') ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _gsm.expiryLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openGsmEditor() async {
    final saved = await showModalBottomSheet<GsmConfig>(
      context: context,
      backgroundColor: AppTheme.of(context).surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GsmEditorSheet(initial: _gsm),
    );
    if (saved == null) return;
    try {
      await _firebase.setGsmConfig(saved);
      _toast('GSM / SMS settings saved.');
    } catch (_) {
      _toast('Could not save GSM settings. Please try again.');
    }
  }
}

/// The promo editor — just a name and a duration in days. The countdown is
/// computed from those, starting today, so the operator never types a date.
class _GsmEditorSheet extends StatefulWidget {
  final GsmConfig initial;
  const _GsmEditorSheet({required this.initial});

  @override
  State<_GsmEditorSheet> createState() => _GsmEditorSheetState();
}

class _GsmEditorSheetState extends State<_GsmEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _days;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial.promoName);
    _days = TextEditingController(
        text: widget.initial.durationDays > 0
            ? '${widget.initial.durationDays}'
            : '');
    // Rebuild the preview line as either field changes.
    _name.addListener(_onChanged);
    _days.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _days.dispose();
    super.dispose();
  }

  int get _dayCount => int.tryParse(_days.text.trim()) ?? 0;

  /// Live preview of the resulting countdown, from today.
  String get _preview {
    final d = _dayCount;
    if (d <= 0) return 'Enter how many days the promo runs.';
    final expiry = DateTime.now().add(Duration(days: d));
    return 'Counts down $d days · expires ${DateFormat('MMM d, yyyy').format(expiry)}';
  }

  void _save() {
    final name = _name.text.trim();
    final days = _dayCount;
    if (name.isEmpty) {
      _toast('Enter the promo name.');
      return;
    }
    if (days <= 0) {
      _toast('Enter how many days the promo runs.');
      return;
    }
    Navigator.pop(context, GsmConfig.promo(name: name, days: days));
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final valid = _name.text.trim().isNotEmpty && _dayCount > 0;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
              'SIM Promo',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.of(context).ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Enter the promo name and how many days it runs. The app counts '
              'down on its own, starting today.',
              style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppTheme.of(context).inkSoft),
            ),
            const SizedBox(height: 18),
            _fieldLabel('Promo name'),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(fontSize: 14, color: AppTheme.of(context).ink),
              decoration: const InputDecoration(hintText: 'e.g. GIGA Unli'),
            ),
            const SizedBox(height: 14),
            _fieldLabel('Duration (days)'),
            TextField(
              controller: _days,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 14, color: AppTheme.of(context).ink),
              decoration: const InputDecoration(hintText: 'e.g. 30'),
            ),
            const SizedBox(height: 14),
            // Live preview of the countdown that will result.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: valid
                    ? AppTheme.of(context).deep.withOpacity(0.07)
                    : AppTheme.of(context).bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined,
                      size: 16,
                      color: valid
                          ? AppTheme.of(context).deep
                          : AppTheme.of(context).inkSoft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _preview,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: valid
                            ? AppTheme.of(context).deep
                            : AppTheme.of(context).inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: valid ? _save : null,
                    child: const Text('Save Promo'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.of(context).inkSoft,
          ),
        ),
      );
}

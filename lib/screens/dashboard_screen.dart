import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../models/sensor_data.dart';
import '../models/water_quality.dart';
import '../services/firebase_service.dart';
import '../services/app_store.dart';
import '../services/i18n.dart';
import '../services/sync_service.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/coach_mark.dart';
import '../widgets/app_header.dart';
import '../widgets/loading_emblem.dart';
import '../widgets/reveal.dart';
import '../widgets/sync_status.dart';
import '../widgets/threshold_guide.dart';
import '../widgets/water_quality_status_chart.dart';

/// Live water-quality dashboard for the selected pond.
class DashboardScreen extends StatefulWidget {
  /// The reading the splash already fetched, if it got one.
  ///
  /// Without it the Dashboard opened on its own loader and waited for the
  /// stream all over again — so after the splash finished you saw a second,
  /// shorter load. The work was already done; this hands it across instead of
  /// throwing it away.
  final SensorData? initialReading;

  const DashboardScreen({super.key, this.initialReading});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirebaseService _firebase = FirebaseService();
  AppStore? _demoStore;

  String _pondId = 'pond1';
  bool _simMode = true;
  bool _loading = true;

  /// A pull-to-refresh in flight, kept apart from [_loading].
  ///
  /// Refreshing used to raise _loading, which swapped the RefreshIndicator
  /// itself out of the tree — disposing the very widget running the gesture,
  /// mid-gesture. This flag draws the fish over the list instead, so the
  /// indicator stays mounted and the pull finishes the way it started.
  bool _refreshing = false;

  SensorData? _data;
  StreamSubscription? _sub;

  /// Stops the loader from waiting for ever.
  ///
  /// The stream only speaks when Firebase has something to say. With the
  /// controller down and the phone's link slow or gone, it may never speak at
  /// all — and the screen sat on a spinning fish with no way out. The screen
  /// now gives up waiting and shows what it knows, which is sometimes only
  /// that nothing has arrived.
  Timer? _firstReadingDeadline;

  // Coach-mark targets, keyed on the real widgets so the first-run tour can
  // spotlight each one where it actually sits.
  final _kPond = GlobalKey();
  final _kConn = GlobalKey();
  final _kPh = GlobalKey();
  final _kTemp = GlobalKey();
  final _kDo = GlobalKey();
  final _kUpdated = GlobalKey();
  final _kSafe = GlobalKey();
  final _kGuide = GlobalKey();
  final _navKeys = List.generate(6, (_) => GlobalKey());

  static const _tourDoneKey = 'dashboard_tour_done';

  @override
  void initState() {
    super.initState();
    // Open with what the splash already has, so there is nothing to wait for.
    if (widget.initialReading != null) {
      _data = widget.initialReading;
      _loading = false;
    }
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _simMode = context.read<AppStore>().simulation;
    await SyncService.instance.start(simMode: _simMode);
    if (!mounted) return;
    _listen();
    _maybeStartTour(prefs);
  }

  /// Runs the guided tour once, on a fresh install. After it finishes or is
  /// skipped the flag is set, so closing and reopening the app never shows it
  /// again — it is only for a new install (or a manual replay from the guide).
  Future<void> _maybeStartTour(SharedPreferences prefs) async {
    if (prefs.getBool(_tourDoneKey) ?? false) return;
    await _startTour();
  }

  /// Shows the coach-mark tour now, waiting for the cards to be laid out first.
  /// Used both for the first-run tour and the "Replay app tour" button.
  Future<void> _startTour() async {
    for (var i = 0; i < 30 && mounted && (_loading || _data == null); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    await CoachMark.show(context, steps: _tourSteps());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_tourDoneKey, true);
    } catch (_) {}
  }

  List<CoachStep> _tourSteps() => [
        CoachStep(
          targetKey: _kPond,
          title: L("Farm / Pond", "Farm at Palaisdaan"),
          body: L(
            "Shows the farm and the selected pond (Pond 1 · Tilapia).",
            "Makikita rito ang farm at ang napiling palaisdaan (Pond 1 · Tilapia).",
          ),
        ),
        CoachStep(
          targetKey: _kConn,
          title: L("Connection Status", "Katayuan ng Koneksyon"),
          body: L(
            "Check whether the phone is online and whether readings have synced.",
            "Tingnan kung online ang telepono at kung naka-sync ang mga reading.",
          ),
        ),
        CoachStep(
          targetKey: _kPh,
          title: L("pH Level", "Antas ng pH"),
          body: L(
            "Shows whether the water is acidic, within range, or alkaline.",
            "Makikita kung acidic, nasa ligtas na saklaw, o alkaline ang tubig.",
          ),
        ),
        CoachStep(
          targetKey: _kTemp,
          title: L("Temperature", "Temperatura"),
          body: L(
            "Shows the water temperature and whether it is in the safe range.",
            "Makikita ang temperatura ng tubig at kung nasa ligtas itong saklaw.",
          ),
        ),
        CoachStep(
          targetKey: _kDo,
          title: L("Dissolved Oxygen", "Dissolved Oxygen"),
          body: L(
            "Shows how much oxygen is dissolved in the water.",
            "Makikita ang dami ng oxygen na natunaw sa tubig.",
          ),
        ),
        CoachStep(
          targetKey: _kUpdated,
          title: L("Last Update", "Huling Update"),
          body: L(
            "Shows when the most recent reading was synced.",
            "Makikita kung kailan huling nag-sync ang reading.",
          ),
        ),
        CoachStep(
          targetKey: _kSafe,
          title: L("Water Quality Status", "Kalagayan ng Tubig"),
          body: L(
            "Compares the three current readings and their safety status.",
            "Inihahambing ang tatlong kasalukuyang reading at ang kalagayan ng bawat isa.",
          ),
        ),
        CoachStep(
          targetKey: _kGuide,
          title: L("Water Quality Guide", "Gabay sa Kalidad ng Tubig"),
          body: L(
            "Tap to see the safe, warning, and critical ranges for each parameter.",
            "Pindutin para makita ang ligtas, may babala, at kritikal na saklaw ng bawat parameter.",
          ),
        ),
        CoachStep(
          targetKey: _navKeys[1],
          shape: CoachShape.circle,
          title: L("History", "Kasaysayan"),
          body: L(
            "View past readings and trends by day, week, or month.",
            "Tingnan ang mga nakaraang reading at trend ayon sa araw, linggo, o buwan.",
          ),
        ),
        CoachStep(
          targetKey: _navKeys[2],
          shape: CoachShape.circle,
          title: L("Fish Mortality", "Tala ng Namatay na Isda"),
          body: L(
            "Enter the number of fish that died. The app checks recorded readings closest to the event for possible causes.",
            "Ilagay ang bilang ng namatay na isda. Susuriin ng app ang readings na pinakamalapit sa oras ng insidente para sa mga posibleng sanhi.",
          ),
        ),
        CoachStep(
          targetKey: _navKeys[3],
          shape: CoachShape.circle,
          title: L("Manage", "Pamahalaan"),
          body: L(
            "Track incidents and the 10-minute check after a reading returns to the safe range.",
            "Subaybayan ang mga insidente at ang 10-minutong pag-verify kapag bumalik sa ligtas na saklaw ang reading.",
          ),
        ),
        CoachStep(
          targetKey: _navKeys[4],
          shape: CoachShape.circle,
          title: L("Alerts", "Mga Alerto"),
          body: L(
            "Open an alert to see details about the abnormal reading.",
            "Buksan ang alerto para makita ang mga detalye ng abnormal na reading.",
          ),
        ),
        CoachStep(
          targetKey: _navKeys[5],
          shape: CoachShape.circle,
          title: L("Settings", "Mga Setting"),
          body: L(
            "Change the language, review the connection, or start Demo Mode.",
            "Palitan ang wika, tingnan ang koneksyon, o simulan ang Demo Mode.",
          ),
        ),
      ];

  void _listen() {
    _sub?.cancel();
    _firstReadingDeadline?.cancel();
    final listeningPond = _pondId;
    _firstReadingDeadline = Timer(const Duration(seconds: 8), () {
      if (mounted && _loading) setState(() => _loading = false);
    });

    if (_simMode) {
      _firstReadingDeadline?.cancel();
      if (_demoStore == null) {
        _demoStore = context.read<AppStore>();
        _demoStore!.addListener(_publishDemoReading);
      }
      _publishDemoReading();
    } else {
      // Display saved values while offline, but never count a cache read as a
      // live ESP32 contact.
      if (_data == null) {
        _firebase.getCachedCurrentReading(listeningPond).then((cached) {
          if (!mounted ||
              _pondId != listeningPond ||
              cached == null ||
              _data != null) {
            return;
          }
          setState(() {
            _data = cached;
            _loading = false;
          });
        });
      }
      _sub = _firebase.currentReadingStream(_pondId).listen(
        (data) {
          if (data != null) {
            // The device's own reading timestamp, not the phone's receive
            // time — so a stale ESP32 reading reads as stale, not "just now".
            SyncService.instance.markDeviceSeen(data.timestamp);
            _firstReadingDeadline?.cancel();
            if (mounted) {
              setState(() {
                _data = data;
                _loading = false;
              });
            }
          } else if (mounted) {
            _firstReadingDeadline?.cancel();
            setState(() => _loading = false);
          }
        },
        onError: (_) {
          _firstReadingDeadline?.cancel();
          if (mounted) setState(() => _loading = false);
        },
      );
    }
  }

  void _publishDemoReading() {
    if (!mounted) return;
    setState(() {
      _data = _demoStore!.currentReading;
      _loading = false;
    });
  }

  /// Pull-to-refresh, shown the same way a fresh open is.
  ///
  /// It used to resubscribe and return immediately, so the gesture snapped
  /// back with nothing to look at and no sign anything had happened. Raising
  /// the same loader the screen opens behind makes a refresh and an open look
  /// like the one act they are.
  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    _listen();

    // Long enough for the fish to register as a step rather than a blink.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _refreshing = false);
  }

  void _changePond(String pondId) {
    setState(() {
      _pondId = pondId;
      _loading = true;
      _data = null;
    });
    _listen();
  }

  @override
  void dispose() {
    _firstReadingDeadline?.cancel();
    _sub?.cancel();
    _demoStore?.removeListener(_publishDemoReading);
    super.dispose();
  }

  /// Shown when the controller has not reported yet.
  ///
  /// Scrollable on purpose: pull-to-refresh needs something that scrolls, and
  /// this is exactly the screen a farmer will want to pull on.
  Widget _awaitingFirstReading() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        const SyncBanner(),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 22),
          decoration: AppTheme.of(context).card(),
          child: Column(
            children: [
              Icon(
                Icons.sensors_off_rounded,
                size: 34,
                color: AppTheme.of(context).inkSoft.withOpacity(0.45),
              ),
              const SizedBox(height: 14),
              Text(
                'No reading yet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.of(context).ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The controller has not sent anything. It may be powered '
                'off, out of WiFi range, or still starting up.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppTheme.of(context).inkSoft,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pull down to try again',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.of(context).deep.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<ParamReading> get _readings {
    final d = _data;
    if (d == null) return const [];
    return [
      ParamReading.classify(WaterParam.ph, d.ph),
      ParamReading.classify(WaterParam.temperature, d.temperature),
      ParamReading.classify(WaterParam.dissolvedOxygen, d.dissolvedOxygen),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pond = Pond.byId(_pondId);
    final readings = _readings;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          AppHeader(selectedPondId: _pondId, onPondChanged: _changePond),
          Expanded(
            child: Stack(
              children: [
                _loading
                    ? const EmblemLoader()
                    // readings is empty whenever no reading has arrived. The grid
                    // below reaches straight into readings[0], so rendering it in
                    // that state threw a RangeError and the screen went red —
                    // which is what "it doesn't load when the ESP32 is off" was.
                    : readings.isEmpty
                        ? RefreshIndicator(
                            color: AppTheme.of(context).deep,
                            onRefresh: _refresh,
                            child: _awaitingFirstReading(),
                          )
                        : RefreshIndicator(
                            color: AppTheme.of(context).deep,
                            onRefresh: _refresh,
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 20),
                              children: [
                                // Title row + sync chip
                                Reveal(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          key: _kPond,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _simMode
                                                  ? 'Demo mode · Monitoring'
                                                  : 'Monitoring',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.of(context)
                                                    .inkSoft,
                                              ),
                                            ),
                                            Text(
                                              '${pond.name} · ${pond.species}',
                                              style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.of(context).ink,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Row(
                                          children: [
                                            IconButton(
                                              onPressed: _startTour,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints:
                                                  const BoxConstraints(),
                                              padding: const EdgeInsets.all(6),
                                              tooltip: L(
                                                'Replay app tour',
                                                'Ulitin ang gabay',
                                              ),
                                              icon: Icon(
                                                Icons.help_outline_rounded,
                                                size: 19,
                                                color: AppTheme.of(context)
                                                    .inkSoft,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            KeyedSubtree(
                                              key: _kConn,
                                              child: const SyncPill(),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // 2 × 2 grid of readings
                                Reveal(
                                  delayMs: 70,
                                  child: IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: KeyedSubtree(
                                            key: _kPh,
                                            child: _readingCard(readings[0]),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: KeyedSubtree(
                                            key: _kTemp,
                                            child: _readingCard(readings[1]),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Reveal(
                                  delayMs: 140,
                                  child: IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: KeyedSubtree(
                                            key: _kDo,
                                            child: _readingCard(readings[2]),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: KeyedSubtree(
                                            key: _kUpdated,
                                            child: _updatedCard(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),
                                Reveal(
                                  delayMs: 210,
                                  child: WaterQualityStatusChart(
                                    key: _kSafe,
                                    ph: readings[0],
                                    temperature: readings[1],
                                    oxygen: readings[2],
                                  ),
                                ),
                                Reveal(
                                  delayMs: 280,
                                  child: Material(
                                    key: _kGuide,
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => ThresholdGuide.show(context),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        margin: const EdgeInsets.only(top: 10),
                                        padding: const EdgeInsets.all(16),
                                        decoration: AppTheme.of(context).card(),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.water_drop_outlined,
                                              size: 19,
                                              color: AppTheme.of(context).aqua,
                                            ),
                                            SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Water Quality Guide',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: AppTheme.of(
                                                        context,
                                                      ).ink,
                                                    ),
                                                  ),
                                                  SizedBox(height: 2),
                                                  Text(
                                                    'Green, yellow, and red ranges for each reading',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: AppTheme.of(
                                                        context,
                                                      ).inkSoft,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              color:
                                                  AppTheme.of(context).inkSoft,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                // The same mark as every other wait, laid over the readings
                // so they stay in view while the new ones arrive.
                if (_refreshing)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: AppTheme.of(context).bg.withOpacity(0.88),
                        child: const EmblemLoader(size: 120),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(currentIndex: 0, itemKeys: _navKeys),
    );
  }

  Widget _readingCard(ParamReading r) {
    final color = AppTheme.of(context).statusColor(r.level);
    final icon = switch (r.param) {
      WaterParam.ph => Icons.water_drop_outlined,
      WaterParam.temperature => Icons.thermostat_rounded,
      WaterParam.dissolvedOxygen => Icons.waves_rounded,
    };

    return Container(
      constraints: const BoxConstraints(minHeight: 146),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.of(context).card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: 0,
                        end: (r.value /
                                switch (r.param) {
                                  WaterParam.ph => 14.0,
                                  WaterParam.temperature => 50.0,
                                  WaterParam.dissolvedOxygen => 15.0,
                                })
                            .clamp(0.0, 1.0),
                      ),
                      duration: const Duration(milliseconds: 950),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => SizedBox(
                        width: 46,
                        height: 46,
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 4,
                          color: color,
                          backgroundColor: color.withValues(alpha: .13),
                        ),
                      ),
                    ),
                    Icon(icon, size: 19, color: color),
                  ],
                ),
              ),
              const Spacer(),
              // Status pill animates its colour as the level changes.
              AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  r.level.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            r.label,
            style: TextStyle(fontSize: 11, color: AppTheme.of(context).inkSoft),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              CountUpDecimal(
                r.value,
                decimals: r.decimals,
                duration: const Duration(milliseconds: 850),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.of(context).ink,
                  height: 1.1,
                ),
              ),
              if (r.unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  r.unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.of(context).inkSoft,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(r.condition, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  /// Teal tile showing how fresh the data is.
  Widget _updatedCard() {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: SyncService.instance.lastSynced,
      builder: (context, lastSynced, _) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.of(context).header,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.schedule_rounded, size: 25, color: Colors.white),
              const SizedBox(height: 8),
              Text(
                'Updated',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                SyncService.relativeLabel(lastSynced),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

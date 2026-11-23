import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/app_store.dart';
import '../services/sync_service.dart';
import '../services/notification_service.dart';
import '../widgets/loading_emblem.dart';
import '../widgets/fade_through_route.dart';
import 'dashboard_screen.dart';

/// Opening sequence: the brand image fades up, hands over to the loading
/// emblem, and the emblem turns until the app is actually ready.
///
/// The sign-in that used to run before `runApp` happens here instead. It could
/// take several seconds on a cold start or a slow link, and doing it first
/// meant the phone sat on a blank white frame for all of it. Behind a splash,
/// the same wait reads as the app opening.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// The brand image holds for this long before the loader takes over, so the
  /// name is readable even when sign-in returns instantly.
  static const _logoHold = Duration(milliseconds: 1300);

  /// Once the loader is on screen it stays at least this long. Without a floor
  /// a fast sign-in makes it flash for a few frames, which looks like a glitch
  /// rather than a step.
  static const _loaderFloor = Duration(milliseconds: 1100);

  late final AnimationController _logoIn;
  late final AnimationController _drift;
  late final AnimationController _handover;
  late final AnimationController _exit;

  @override
  void initState() {
    super.initState();

    _logoIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    // A slow push in across the whole splash. Small enough that nobody names
    // it, large enough that the screen reads as alive rather than a frozen
    // picture someone forgot to advance.
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    _handover = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _logoIn.forward();
    _drift.forward();
    _run();
  }

  Future<void> _run() async {
    // Sign-in starts immediately and runs alongside the animation rather than
    // after it, so the two waits overlap instead of adding up.
    final signIn = _ensureSignedIn();
    final services = signIn.then((_) => _startServices());

    await Future<void>.delayed(_logoHold);
    if (!mounted) return;
    _handover.forward();

    await Future.wait([services, Future<void>.delayed(_loaderFloor)]);
    if (!mounted) return;

    context.read<AppStore>().connectLive();
    await _exit.forward();
    if (!mounted) return;

    // Straight to the Dashboard; a fresh install gets the guided coach-mark
    // tour there, over the real screen.
    Navigator.of(context).pushReplacement(
      FadeThroughRoute(
        screen: const DashboardScreen(),
      ),
    );
  }

  Future<void> _startServices() async {
    await SyncService.instance.start();
    await NotificationService.instance.start();
  }

  /// An anonymous session, so database rules that require `auth != null` still
  /// pass now that the login screen is gone.
  ///
  /// Failure is not fatal: if the Anonymous provider is off or the phone is
  /// offline, the app still opens and reads still work wherever the rules
  /// allow them. The timeout is what stops a dead network from holding the
  /// splash forever.
  Future<void> _ensureSignedIn() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    try {
      await FirebaseAuth.instance
          .signInAnonymously()
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Anonymous sign-in skipped: $e');
    }
  }

  @override
  void dispose() {
    _logoIn.dispose();
    _drift.dispose();
    _handover.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoFade = CurvedAnimation(parent: _logoIn, curve: Curves.easeOut);
    final logoSettle = Tween<double>(begin: 1.04, end: 1.0).animate(
      CurvedAnimation(parent: _logoIn, curve: Curves.easeOutCubic),
    );
    // Barely there. Cover already has to trim a fifth of the width to fill a
    // phone; anything more than a hair of zoom on top of that starts taking
    // the picture with it.
    final drift = Tween<double>(begin: 1.0, end: 1.015).animate(
      CurvedAnimation(parent: _drift, curve: Curves.easeInOut),
    );

    return Scaffold(
      backgroundColor: AppTheme.deep,
      body: AnimatedBuilder(
        animation: Listenable.merge([_handover, _exit, _drift]),
        builder: (context, _) {
          final handover = Curves.easeInOut.transform(_handover.value);
          return Opacity(
            opacity: 1 - _exit.value,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The brand image, fading out as the loader arrives.
                Opacity(
                  opacity: 1 - handover,
                  child: FadeTransition(
                    opacity: logoFade,
                    child: ScaleTransition(
                      scale: logoSettle,
                      child: Transform.scale(
                        scale: drift.value,
                        child: Image.asset(
                          'assets/brand/logo.jpg',
                          // Fills the screen edge to edge. At 887x1774 the
                          // artwork is close to a phone's own shape, so cover
                          // trims about a tenth of the width — half what the
                          // squarer earlier image lost.
                          fit: BoxFit.cover,
                          // Centred. The artwork sits the mark and the name in
                          // the middle with open water above and the sea floor
                          // below, so an even trim takes only background from
                          // both ends. Biasing upward pushed the water surface
                          // off the top edge.
                          alignment: Alignment.center,
                        ),
                      ),
                    ),
                  ),
                ),

                // The loader, fading in over it.
                //
                // On the same pond the brand image sits on, so the handover is
                // one photograph settling into another rather than the picture
                // dropping away to a flat panel.
                Opacity(
                  opacity: handover,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/brand/loading_bg.jpg',
                        fit: BoxFit.cover,
                      ),
                      // The sky is bright and the artwork is white line work,
                      // so it needs something to sit against. Deeper than the
                      // in-app loader's scrim because the caption has to be
                      // read here, not just glanced at.
                      Container(
                        color: const Color(0xFF0F4C5C).withOpacity(0.55),
                      ),
                      Center(
                        child: SizedBox(
                          width: 300,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              FishLoader(size: 190),
                              SizedBox(height: 26),
                              _LoadingCaption(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The waiting message, drawn rather than baked into the artwork.
///
/// It was part of loading.png, which meant it scaled with the emblem and went
/// soft on a high-density screen. As text it stays sharp at any size, and the
/// ellipsis can actually count — a still "..." beside a turning emblem looks
/// like the animation is the only thing working.
class _LoadingCaption extends StatefulWidget {
  const _LoadingCaption();

  @override
  State<_LoadingCaption> createState() => _LoadingCaptionState();
}

class _LoadingCaptionState extends State<_LoadingCaption>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _breathe;
  late final AnimationController _dots;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    // A slow rise and fall in brightness. Waiting reads as waiting rather than
    // as a frozen frame, without anything moving enough to pull the eye off
    // the emblem.
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _enter.dispose();
    _breathe.dispose();
    _dots.dispose();
    super.dispose();
  }

  /// Two lines, the second arriving a beat after the first.
  Widget _line(String text, {required double start, required double size}) {
    final slice = CurvedAnimation(
      parent: _enter,
      curve:
          Interval(start, (start + 0.6).clamp(0.0, 1.0), curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: slice,
      builder: (context, child) => Opacity(
        opacity: slice.value,
        child: Transform.translate(
          offset: Offset(0, (1 - slice.value) * 10),
          child: child,
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: size,
          height: 1.35,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: const Color(0xFFDFFBF4),
          // Echoes the glow the artwork carries, so the drawn text sits in the
          // same world as the emblem above it.
          shadows: const [
            Shadow(color: Color(0xAA23E0B8), blurRadius: 14),
            Shadow(color: Color(0x5512D6C8), blurRadius: 26),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breathe, _dots]),
      builder: (context, _) {
        // Zero to three dots, a quarter of the cycle each.
        final shown = (_dots.value * 4).floor().clamp(0, 3);
        final dots = '.' * shown;

        return Opacity(
          opacity: 0.72 + 0.28 * _breathe.value,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _line('Setting up the water buoy', start: 0.0, size: 17),
              const SizedBox(height: 2),
              // The dots are padded to their full width so the line does not
              // shift sideways as they come and go.
              _line('please wait a second$dots${' ' * (3 - shown)}',
                  start: 0.25, size: 17),
            ],
          ),
        );
      },
    );
  }
}

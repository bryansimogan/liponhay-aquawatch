import 'dart:async';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/sync_service.dart';

/// Two chips: this phone's link, and the controller's.
///
/// They were one chip reading "Synced" or "Offline", which could not say which
/// of the two had actually dropped. Split, the pair answers the question a
/// farmer asks first — is it me or is it the pond?
///
///   Online  · Synced          everything reporting
///   Online  · 12 mins ago     phone fine, controller quiet
///   Offline · 12 mins ago     phone has no data or WiFi
///
/// The labels re-render every 20s so a relative time never goes stale.
class SyncPill extends StatefulWidget {
  const SyncPill({super.key});

  @override
  State<SyncPill> createState() => _SyncPillState();
}

class _SyncPillState extends State<SyncPill> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(
      const Duration(seconds: 20),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SyncService.instance.phoneOnline,
      builder: (context, phoneOnline, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: SyncService.instance.online,
          builder: (context, synced, _) {
            return ValueListenableBuilder<DateTime?>(
              valueListenable: SyncService.instance.lastSynced,
              builder: (context, lastSynced, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Chip(
                      icon: phoneOnline
                          ? Icons.wifi_rounded
                          : Icons.wifi_off_rounded,
                      label: phoneOnline ? 'Online' : 'Offline',
                      color: phoneOnline
                          ? AppTheme.of(context).deep
                          : AppTheme.of(context).coral,
                    ),
                    const SizedBox(width: 6),
                    _Chip(
                      icon: synced
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      // With nothing fresh from the device, the age of the
                      // last reading says more than the word "offline" does.
                      label: synced
                          ? 'Synced'
                          : 'Last sync ${SyncService.relativeLabel(lastSynced)}',
                      color: synced
                          ? AppTheme.of(context).aqua
                          : AppTheme.of(context).amber,
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Icon(icon, key: ValueKey(icon), size: 12, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner that slides down when something is not reporting, and names which.
///
/// It used to say "LAST SYNCED 12 MINS AGO" for either failure. That is the
/// right sentence for a quiet controller and the wrong one for a phone with
/// no data left — there, the reading is not late, it is simply unreachable,
/// and the fix is load rather than a trip to the pond.
class SyncBanner extends StatefulWidget {
  const SyncBanner({super.key});

  @override
  State<SyncBanner> createState() => _SyncBannerState();
}

class _SyncBannerState extends State<SyncBanner> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(
      const Duration(seconds: 20),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SyncService.instance.phoneOnline,
      builder: (context, phoneOnline, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: SyncService.instance.online,
          builder: (context, online, _) {
            return ValueListenableBuilder<DateTime?>(
              valueListenable: SyncService.instance.lastSynced,
              builder: (context, lastSynced, _) {
                // The phone's own link is the more urgent of the two, and the
                // only one the person reading this can do anything about.
                final tone = phoneOnline
                    ? AppTheme.of(context).amber
                    : AppTheme.of(context).coral;
                final icon = phoneOnline
                    ? Icons.sensors_off_rounded
                    : Icons.wifi_off_rounded;
                final message = phoneOnline
                    ? 'CONTROLLER QUIET · LAST READING '
                        '${SyncService.relativeLabel(lastSynced).toUpperCase()}'
                    : 'NO CONNECTION · CHECK WIFI OR MOBILE DATA';
                return AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: online
                      ? const SizedBox(width: double.infinity)
                      : AnimatedOpacity(
                          opacity: 1,
                          duration: const Duration(milliseconds: 240),
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 11),
                            decoration: BoxDecoration(
                              color: tone.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: tone.withOpacity(0.25)),
                            ),
                            child: Row(
                              children: [
                                Icon(icon, size: 16, color: tone),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    message,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: tone,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                );
              },
            );
          },
        );
      },
    );
  }
}

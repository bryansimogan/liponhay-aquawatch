import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/sync_service.dart';

/// The Dashboard uses a single row and leaves connection diagnostics to Settings.
class DashboardSyncPills extends StatelessWidget {
  const DashboardSyncPills({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    final palette = AppTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(
          [sync.phoneOnline, sync.online, sync.lastSynced, sync.ageLabel]),
      builder: (context, _) {
        final internet = sync.phoneOnline.value;
        final synced = sync.online.value;
        final last = sync.lastSynced.value;
        final internetColor = internet == true
            ? (Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF70D79C)
                : const Color(0xFF267447))
            : palette.amber;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Chip(
              dot: true,
              label: switch (internet) {
                true => 'Online',
                false => 'Offline',
                null => 'Checking',
              },
              color: internetColor,
              compact: compact,
            ),
            SizedBox(width: compact ? 3 : 5),
            _Chip(
              label: synced
                  ? 'Synced'
                  : last == null
                      ? 'Not synced yet'
                      : 'Last synced ${sync.ageLabel.value}',
              color: synced ? palette.aqua : palette.amber,
              compact: compact,
            ),
          ],
        );
      },
    );
  }
}

/// Distinct connection states using the existing compact status chips.
class SyncPill extends StatelessWidget {
  const SyncPill({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge(
          [sync.phoneOnline, sync.serverOnline, sync.online, sync.ageLabel]),
      builder: (context, _) {
        final palette = AppTheme.of(context);
        Widget chip(String name, bool? reachable, IconData icon) {
          final status = switch (reachable) {
            true => 'Online',
            false => 'Offline',
            null => 'Checking',
          };
          return _Chip(
            icon: icon,
            label: '$name $status',
            color: reachable == true ? palette.aqua : palette.amber,
          );
        }

        return Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            chip('Phone', sync.phoneOnline.value, Icons.wifi_rounded),
            chip('Server', sync.serverOnline.value, Icons.cloud_outlined),
            chip('ESP32', sync.online.value, Icons.sensors_rounded),
            _Chip(
              icon: Icons.schedule_rounded,
              label: 'Last sync ${sync.ageLabel.value}',
              color: palette.deep,
            ),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData? icon;
  final bool dot;
  final bool compact;
  final String label;
  final Color color;

  const _Chip({
    this.icon,
    this.dot = false,
    this.compact = false,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 8, vertical: compact ? 4 : 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Icon(icon, key: ValueKey(icon), size: 12, color: color),
            ),
            const SizedBox(width: 5),
          ] else if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10 : 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the reason readings are unavailable while keeping the last sample.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge(
          [sync.phoneOnline, sync.serverOnline, sync.online, sync.ageLabel]),
      builder: (context, _) {
        final palette = AppTheme.of(context);
        final phone = sync.phoneOnline.value;
        final server = sync.serverOnline.value;
        final hardware = sync.online.value;
        final (message, icon, tone) = switch ((phone, server, hardware)) {
          (false, _, _) => (
              'PHONE OFFLINE · CHECK WIFI OR MOBILE DATA',
              Icons.wifi_off_rounded,
              palette.coral
            ),
          (_, false, _) => (
              'SERVER OFFLINE · RECONNECTING',
              Icons.cloud_off_outlined,
              palette.coral
            ),
          (_, _, false) => (
              'ESP32 OFFLINE · LAST READING ${sync.ageLabel.value.toUpperCase()}',
              Icons.sensors_off_rounded,
              palette.amber
            ),
          _ => ('', Icons.sensors_rounded, palette.aqua),
        };
        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: message.isEmpty
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tone.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 16, color: tone),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(message,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: tone,
                                letterSpacing: 0.3)),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

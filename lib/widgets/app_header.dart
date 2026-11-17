import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_store.dart';
import '../services/i18n.dart';
import '../app_theme.dart';
import '../screens/notifications_screen.dart';
import '../services/notification_service.dart';
import 'fade_through_route.dart';

/// The ponds the farm monitors.
///
/// One, because the controller has one sensor set and writes to one pond
/// (NUMBER_OF_PONDS in the firmware). Listing three here showed the same
/// reading under three names, which read as three instrumented ponds.
///
/// This list is the single source of truth: every pond selector in the app
/// hides itself when there is only one entry, so adding a second sensor set
/// means adding a line here and nothing else.
class Pond {
  final String id;
  final String name;
  final String species;
  const Pond(this.id, this.name, this.species);

  static const all = <Pond>[
    Pond('pond1', 'Pond 1', 'Tilapia'),
  ];

  /// Whether a pond picker is worth showing at all.
  static bool get hasChoice => all.length > 1;

  static Pond byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);
}

/// Deep-teal header used at the top of every screen: brand block, alert bell
/// with an unread badge, and an optional pond selector.
class AppHeader extends StatelessWidget {
  /// Currently selected pond id, or null to hide the selector.
  final String? selectedPondId;

  /// Called with the new pond id when the user picks one.
  final ValueChanged<String>? onPondChanged;

  /// Overrides the notification badge. Normally the header follows the
  /// shared [NotificationService] inbox.
  final int? notificationCount;

  /// Set true on the Notifications screen so the bell does not reopen itself.
  final bool notificationsIsCurrentScreen;

  const AppHeader({
    super.key,
    this.selectedPondId,
    this.onPondChanged,
    this.notificationCount,
    this.notificationsIsCurrentScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.of(context);
    // A picker offering one option is a control that cannot do anything, so
    // it is hidden until there is a second pond to switch to.
    final showSelector =
        selectedPondId != null && onPondChanged != null && Pond.hasChoice;

    return Container(
      decoration: BoxDecoration(
        color: palette.header,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Column(
            children: [
              Row(
                children: [
                  // The mark alone, keyed off its teal field so it sits
                  // directly on the header instead of inside a visible square
                  // of a slightly different teal.
                  Image.asset(
                    'assets/brand/icon_mark.png',
                    width: 30,
                    height: 30,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: const Text(
                      'Liponhay Fish Farm',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: () => AppAppearance.toggle(palette.brightness),
                    tooltip: palette.brightness == Brightness.dark
                        ? 'Switch to light mode'
                        : 'Switch to dark mode',
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(42),
                      backgroundColor: const Color(0x24FFFFFF),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                    iconSize: 20,
                    icon: Icon(palette.brightness == Brightness.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined),
                  ),
                  const SizedBox(width: 6),
                  _bell(context),
                ],
              ),
              if (showSelector) ...[
                const SizedBox(height: 12),
                _PondSelector(
                  selectedPondId: selectedPondId!,
                  onChanged: onPondChanged!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension on AppHeader {
  VoidCallback? _openNotifications(BuildContext context) =>
      notificationsIsCurrentScreen
          ? null
          : () => Navigator.of(context).push(
                FadeThroughRoute(screen: const NotificationsScreen()),
              );

  Widget _bell(BuildContext context) {
    final onTap = _openNotifications(context);
    final demo = context.watch<AppStore?>();
    if (notificationCount != null) {
      return _BellButton(count: notificationCount!, onTap: onTap);
    }
    if (demo?.simulation == true) {
      return _BellButton(count: demo!.unseenNotes, onTap: onTap);
    }
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.instance.unreadCount,
      builder: (context, n, _) => _BellButton(count: n, onTap: onTap),
    );
  }
}

class _BellButton extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const _BellButton({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.15),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  count > 0
                      ? Icons.notifications_rounded
                      : Icons.notifications_none_rounded,
                  color: Colors.white,
                  size: 18,
                  semanticLabel: L('Notifications', 'Mga Abiso'),
                ),
              ),
              if (count > 0)
                Positioned(
                  top: 1,
                  right: 1,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 15, minHeight: 15),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.of(context).coral,
                      shape: count > 9 ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius:
                          count > 9 ? BorderRadius.circular(999) : null,
                      border: Border.all(
                          color: AppTheme.of(context).header, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PondSelector extends StatelessWidget {
  final String selectedPondId;
  final ValueChanged<String> onChanged;

  const _PondSelector({
    required this.selectedPondId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = Pond.byId(selectedPondId);

    return Material(
      color: Colors.white.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<String>(
        // Anchored under the button so it reads like the design's dropdown.
        offset: const Offset(0, 44),
        color: AppTheme.of(context).surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        onSelected: onChanged,
        itemBuilder: (context) => Pond.all.map((p) {
          final isSelected = p.id == selectedPondId;
          return PopupMenuItem<String>(
            value: p.id,
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${p.name} — ${p.species}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected
                          ? AppTheme.of(context).deep
                          : AppTheme.of(context).ink,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded,
                      size: 15, color: AppTheme.of(context).aqua),
              ],
            ),
          );
        }).toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${selected.name} — ${selected.species}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(Icons.expand_more_rounded,
                  size: 18, color: Colors.white.withOpacity(0.9)),
            ],
          ),
        ),
      ),
    );
  }
}

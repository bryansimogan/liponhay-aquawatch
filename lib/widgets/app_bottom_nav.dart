import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../services/i18n.dart';
import '../screens/dashboard_screen.dart';
import '../screens/history_screen.dart';
import '../screens/mortality_screen.dart';
import '../screens/manage_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/settings_screen.dart';
import 'fish_icon.dart';
import 'fade_through_route.dart';

/// White bottom navigation bar. Pass it to `Scaffold.bottomNavigationBar`.
///
/// Tab changes use a fade-through transition (the Material pattern for
/// bottom-nav switches) so screens feel like one surface rather than a
/// slideshow.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;

  /// Optional per-tab keys, so the first-run coach-mark tour can point at an
  /// individual tab ("this is History"). Length must match the tab count when
  /// provided; ignored otherwise.
  final List<GlobalKey>? itemKeys;

  const AppBottomNav({super.key, required this.currentIndex, this.itemKeys});

  static List<_NavItem> get _items => <_NavItem>[
        _NavItem(
          label: L('Dashboard', 'Dashboard'),
          builder: (c, sel) => Icon(
              sel ? Icons.home_rounded : Icons.home_outlined,
              size: 20,
              color: c),
        ),
        _NavItem(
          label: L('History', 'Kasaysayan'),
          builder: (c, sel) =>
              Icon(Icons.show_chart_rounded, size: 20, color: c),
        ),
        _NavItem(
          label: L('Mortality', 'Namatay'),
          builder: (c, sel) => FishIcon(size: 20, color: c),
        ),
        _NavItem(
          label: L('Manage', 'Pamahalaan'),
          builder: (c, sel) => Icon(
              sel ? Icons.assignment_rounded : Icons.assignment_outlined,
              size: 20,
              color: c),
        ),
        _NavItem(
          label: L('Alerts', 'Alerto'),
          builder: (c, sel) => Icon(
              sel ? Icons.error_rounded : Icons.error_outline_rounded,
              size: 20,
              color: c),
        ),
        _NavItem(
          label: L('Settings', 'Setting'),
          builder: (c, sel) => Icon(
              sel ? Icons.settings_rounded : Icons.settings_outlined,
              size: 20,
              color: c),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.of(context).surface,
        border: Border(top: BorderSide(color: AppTheme.of(context).border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: List.generate(_items.length, (i) {
              final k = (itemKeys != null && itemKeys!.length == _items.length)
                  ? itemKeys![i]
                  : null;
              return Expanded(key: k, child: _buildTab(context, i));
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(BuildContext context, int index) {
    final item = _items[index];
    final isSelected = index == currentIndex;
    final color =
        isSelected ? AppTheme.of(context).deep : AppTheme.of(context).inkSoft;

    return InkWell(
      onTap: () {
        if (isSelected) return;
        HapticFeedback.selectionClick();
        _navigateTo(context, index);
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 220),
              // easeOutBack overshoots its target and springs back. On a tab
              // icon that reads as a twitch, and with the label weight and the
              // underline moving at the same time the whole bar looked like it
              // shook on every tap. easeOutCubic arrives and stops.
              curve: Curves.easeOutCubic,
              child: item.builder(color, isSelected),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
              child: Text(item.label),
            ),
            const SizedBox(height: 3),
            // Underline indicator grows in on the active tab.
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              height: 2,
              width: isSelected ? 18 : 0,
              decoration: BoxDecoration(
                color: AppTheme.of(context).deep,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, int index) {
    Widget screen;
    switch (index) {
      case 0:
        screen = const DashboardScreen();
        break;
      case 1:
        screen = const HistoryScreen();
        break;
      case 2:
        screen = const MortalityScreen();
        break;
      case 3:
        screen = const ManageScreen();
        break;
      case 4:
        screen = const AlertsScreen();
        break;
      case 5:
        screen = const SettingsScreen();
        break;
      default:
        return;
    }
    Navigator.pushReplacement(context, FadeThroughRoute(screen: screen));
  }
}

class _NavItem {
  final String label;

  /// Builds the tab glyph for the given colour and selected state.
  final Widget Function(Color color, bool isSelected) builder;

  const _NavItem({required this.label, required this.builder});
}

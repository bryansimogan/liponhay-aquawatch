import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/app_notification.dart';
import '../models/notification_copy.dart';
import '../services/notification_service.dart';
import '../services/app_store.dart';
import '../services/i18n.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_header.dart';
import '../widgets/expandable_notice.dart';
import '../widgets/fade_through_route.dart';
import 'alerts_screen.dart';
import 'history_screen.dart';
import 'manage_screen.dart';
import 'settings_screen.dart';

/// In-app inbox for History records, Alerts, and SIM promo reminders.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final service = NotificationService.instance;
    return ValueListenableBuilder<List<AppNotification>>(
      valueListenable: service.items,
      builder: (context, liveItems, _) {
        final items = store.simulation ? store.notes : liveItems;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              const AppHeader(notificationsIsCurrentScreen: true),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  L('Notifications', 'Mga Abiso'),
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.of(context).ink,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  L('History, water alerts, and promo reminders.',
                                      'Kasaysayan, mga alerto sa tubig, at paalala sa promo.'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.of(context).inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (items.any((item) => !item.read))
                            TextButton(
                              onPressed: store.simulation
                                  ? store.markNotesSeen
                                  : service.markAllRead,
                              child: Text(
                                  L('Mark all read', 'Markahang nabasa lahat')),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: items.isEmpty
                            ? _empty(context)
                            : ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) =>
                                    _item(context, items[index]),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: const AppBottomNav(currentIndex: -1),
        );
      },
    );
  }

  Widget _item(BuildContext context, AppNotification item) {
    final palette = AppTheme.of(context);
    final store = context.read<AppStore>();
    final (icon, color, label, destination) =
        switch ((store.simulation, item.type)) {
      (true, AppNotificationType.history || AppNotificationType.alert) => (
          Icons.assignment_outlined,
          palette.aqua,
          L('Open Management', 'Buksan ang Pamahalaan'),
          const ManageScreen(),
        ),
      (false, AppNotificationType.history) => (
          Icons.show_chart_rounded,
          palette.deep,
          L('Open History', 'Buksan ang Kasaysayan'),
          const HistoryScreen(),
        ),
      (false, AppNotificationType.alert) => (
          Icons.error_outline_rounded,
          palette.coral,
          L('Open Alerts', 'Buksan ang Mga Alerto'),
          const AlertsScreen(),
        ),
      (_, AppNotificationType.promo) => (
          Icons.sim_card_alert_outlined,
          palette.amber,
          L('Open Settings', 'Buksan ang Setting'),
          const SettingsScreen(),
        ),
    };

    return ExpandableNotice(
      key: ValueKey(item.id),
      title: item.localizedTitle,
      timestamp: item.timestamp > 0
          ? DateFormat.MMMd(appDateLocale).add_jm().format(
                DateTime.fromMillisecondsSinceEpoch(item.timestamp),
              )
          : L('Time unavailable', 'Walang oras na nakatala'),
      icon: icon,
      accent: color,
      unread: !item.read,
      onExpansionChanged: (expanded) {
        if (!expanded || item.read) return;
        if (store.simulation) {
          store.markNoteRead(item.id);
        } else {
          NotificationService.instance.markRead(item.id);
        }
      },
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.localizedBody,
              style: TextStyle(color: palette.inkSoft, fontSize: 12)),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              FadeThroughRoute(screen: destination),
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          decoration: AppTheme.of(context).card(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none_rounded,
                  size: 34, color: AppTheme.of(context).inkSoft),
              SizedBox(height: 12),
              Text(
                L('No notifications yet', 'Wala pang abiso'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.of(context).ink,
                ),
              ),
              SizedBox(height: 4),
              Text(
                L('New notifications appear here.',
                    'Dito lalabas ang mga bagong abiso.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: AppTheme.of(context).inkSoft),
              ),
            ],
          ),
        ),
      );
}

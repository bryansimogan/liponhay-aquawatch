import 'package:flutter/material.dart';

import '../app_theme.dart';

class ExpandableNotice extends StatelessWidget {
  const ExpandableNotice({
    super.key,
    required this.title,
    required this.timestamp,
    required this.icon,
    required this.accent,
    required this.unread,
    required this.details,
    this.onExpansionChanged,
  });

  final String title;
  final String timestamp;
  final IconData icon;
  final Color accent;
  final bool unread;
  final Widget details;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.of(context);
    final shape = RoundedRectangleBorder(
      side: BorderSide(color: palette.border),
      borderRadius: BorderRadius.circular(12),
    );

    return ExpansionTile(
      minTileHeight: 50,
      tilePadding: const EdgeInsets.symmetric(horizontal: 10),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      shape: shape,
      collapsedShape: shape,
      backgroundColor: palette.surface,
      collapsedBackgroundColor: palette.surface,
      iconColor: palette.deep,
      collapsedIconColor: palette.inkSoft,
      onExpansionChanged: onExpansionChanged,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: accent.withValues(alpha: 0.12),
        child: Icon(icon, size: 15, color: accent),
      ),
      title: Row(
        children: [
          if (unread) ...[
            Icon(Icons.circle, color: accent, size: 6),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: palette.ink,
                fontSize: 12,
                fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(timestamp,
          style: TextStyle(fontSize: 10, color: palette.inkSoft)),
      children: [
        Divider(color: palette.inkSoft.withValues(alpha: 0.18), height: 12),
        details,
      ],
    );
  }
}

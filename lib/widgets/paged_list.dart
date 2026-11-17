import 'package:flutter/material.dart';

import '../app_theme.dart';

/// A list broken into fixed pages instead of one long scroll.
///
/// Each page shows up to [perPage] items and fills the space it is given; a
/// footer steps between pages with ‹ / › and dots. Built for the record lists
/// (alerts, mortality, history rows) where the operator wanted "pages, not
/// scroll" — one screenful at a time, Next to see more.
class PagedList extends StatefulWidget {
  final List<Widget> items;
  final int perPage;
  final Widget? empty;

  /// Gap between items on a page. The record lists want breathing room (the
  /// default 8); a table whose rows carry their own divider passes 0 so the
  /// page reads as one continuous table instead of spaced cards.
  final double spacing;

  const PagedList({
    super.key,
    required this.items,
    this.perPage = 4,
    this.empty,
    this.spacing = 8,
  });

  @override
  State<PagedList> createState() => _PagedListState();
}

class _PagedListState extends State<PagedList> {
  final _controller = PageController();
  int _page = 0;

  int get _pageCount => (widget.items.length / widget.perPage).ceil();

  @override
  void didUpdateWidget(PagedList old) {
    super.didUpdateWidget(old);
    // The list can shrink (a record deleted, a filter changed); keep the page
    // in range so it never lands on an empty page past the end.
    final last = _pageCount - 1;
    if (_page > last && last >= 0) {
      _page = last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpToPage(_page);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Widget> _pageItems(int page) {
    final start = page * widget.perPage;
    final end = (start + widget.perPage).clamp(0, widget.items.length);
    return widget.items.sublist(start, end);
  }

  void _go(int page) {
    if (page < 0 || page >= _pageCount) return;
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return widget.empty ?? const SizedBox.shrink();
    }

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (p) => setState(() => _page = p),
            itemCount: _pageCount,
            itemBuilder: (context, page) {
              final items = _pageItems(page);
              return ListView(
                // Each page is its own short list. It rarely needs to scroll —
                // perPage is sized to fit — but allowing it means a tall item
                // on a small phone degrades gracefully instead of overflowing.
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  for (final item in items)
                    Padding(
                      padding: EdgeInsets.only(bottom: widget.spacing),
                      child: item,
                    ),
                ],
              );
            },
          ),
        ),
        if (_pageCount > 1) _footer(),
      ],
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _arrow(Icons.chevron_left_rounded, _page > 0, () => _go(_page - 1)),
          const SizedBox(width: 4),
          // Dots — compact even with many pages.
          if (_pageCount <= 8)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_pageCount, (i) {
                final on = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: on ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: on
                        ? AppTheme.of(context).deep
                        : AppTheme.of(context).border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            )
          else
            Text(
              'Page ${_page + 1} of $_pageCount',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.of(context).inkSoft,
              ),
            ),
          const SizedBox(width: 4),
          _arrow(Icons.chevron_right_rounded, _page < _pageCount - 1,
              () => _go(_page + 1)),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, bool enabled, VoidCallback onTap) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon,
          size: 24,
          color: enabled
              ? AppTheme.of(context).deep
              : AppTheme.of(context).border),
    );
  }
}

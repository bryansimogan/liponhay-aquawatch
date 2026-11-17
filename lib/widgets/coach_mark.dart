import 'dart:async';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/i18n.dart';

enum CoachShape { rect, circle }

/// One stop on the guided tour: the widget to spotlight (via its [GlobalKey])
/// and what to say about it.
class CoachStep {
  final GlobalKey targetKey;
  final String title;
  final String body;
  final CoachShape shape;
  final double padding;

  const CoachStep({
    required this.targetKey,
    required this.title,
    required this.body,
    this.shape = CoachShape.rect,
    this.padding = 8,
  });
}

/// A first-run coach-mark tour: dims the screen, cuts a spotlight hole around
/// each target in turn, and floats an explanation beside it with Back / Next.
///
/// It reads the live position of each target from its key every frame, and
/// scrolls a target into view before spotlighting it, so it works over a
/// scrolling page without hard-coded coordinates.
class CoachMark {
  static Future<void> show(
    BuildContext context, {
    required List<CoachStep> steps,
    VoidCallback? onFinish,
  }) {
    final overlay = Overlay.of(context);
    final done = Completer<void>();
    late OverlayEntry entry;

    void close() {
      if (entry.mounted) entry.remove();
      onFinish?.call();
      if (!done.isCompleted) done.complete();
    }

    entry = OverlayEntry(
      builder: (_) => _CoachView(steps: steps, onClose: close),
    );
    overlay.insert(entry);
    return done.future;
  }
}

class _CoachView extends StatefulWidget {
  final List<CoachStep> steps;
  final VoidCallback onClose;
  const _CoachView({required this.steps, required this.onClose});

  @override
  State<_CoachView> createState() => _CoachViewState();
}

class _CoachViewState extends State<_CoachView>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  Rect? _rect;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Bring the current target into view, then measure it.
  Future<void> _prepare() async {
    final ctx = widget.steps[_index].targetKey.currentContext;
    if (ctx != null) {
      final scrollable = Scrollable.maybeOf(ctx);
      if (scrollable != null) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.45,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
        );
        // Let the scroll settle before measuring.
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
    if (mounted) setState(_measure);
  }

  void _measure() {
    final ctx = widget.steps[_index].targetKey.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      _rect = null;
      return;
    }
    final topLeft = box.localToGlobal(Offset.zero);
    _rect = topLeft & box.size;
  }

  void _go(int next) {
    if (next < 0) return;
    if (next >= widget.steps.length) {
      widget.onClose();
      return;
    }
    setState(() {
      _index = next;
      _rect = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    final media = MediaQuery.of(context);
    final screen = media.size;
    final hole = _rect?.inflate(step.padding);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dimmed backdrop with a spotlight hole. Tapping it advances.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _go(_index + 1),
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: _ScrimPainter(
                    hole: hole,
                    shape: step.shape,
                    glow: _pulse.value,
                  ),
                ),
              ),
            ),
          ),

          // Explanation callout, placed beside the hole.
          _callout(step, hole, screen, media.padding),
        ],
      ),
    );
  }

  Widget _callout(CoachStep step, Rect? hole, Size screen, EdgeInsets safe) {
    const gutter = 16.0;
    final total = widget.steps.length;

    final card = _CoachCard(
      step: step,
      index: _index,
      total: total,
      onBack: _index > 0 ? () => _go(_index - 1) : null,
      onNext: () => _go(_index + 1),
      onSkip: widget.onClose,
      isLast: _index == total - 1,
    );

    // No measurable target (rare) → center it.
    if (hole == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: gutter),
          child: card,
        ),
      );
    }

    // Prefer below the hole; flip above when there isn't room.
    final spaceBelow = screen.height - hole.bottom - safe.bottom;
    final below = spaceBelow > 210;
    if (below) {
      return Positioned(
        top: hole.bottom + 14,
        left: gutter,
        right: gutter,
        child: card,
      );
    }
    return Positioned(
      bottom: screen.height - hole.top + 14,
      left: gutter,
      right: gutter,
      child: card,
    );
  }
}

class _ScrimPainter extends CustomPainter {
  final Rect? hole;
  final CoachShape shape;
  final double glow;

  _ScrimPainter({required this.hole, required this.shape, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withOpacity(0.74);
    final full = Offset.zero & size;

    if (hole == null) {
      canvas.drawRect(full, scrim);
      return;
    }

    final holePath = Path();
    final rr = RRect.fromRectAndRadius(hole!, const Radius.circular(16));
    if (shape == CoachShape.circle) {
      holePath.addOval(hole!);
    } else {
      holePath.addRRect(rr);
    }

    final dimmed = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      holePath,
    );
    canvas.drawPath(dimmed, scrim);

    // Accent ring, gently pulsing.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppTheme.aqua.withOpacity(0.9);
    final glowRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 + 5 * glow
      ..color = AppTheme.aqua.withOpacity(0.28 * (1 - glow));

    if (shape == CoachShape.circle) {
      canvas.drawOval(hole!, glowRing);
      canvas.drawOval(hole!, ring);
    } else {
      canvas.drawRRect(rr, glowRing);
      canvas.drawRRect(rr, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) =>
      old.hole != hole || old.glow != glow || old.shape != shape;
}

class _CoachCard extends StatelessWidget {
  final CoachStep step;
  final int index;
  final int total;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool isLast;

  const _CoachCard({
    required this.step,
    required this.index,
    required this.total,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.of(context).surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.of(context).deep,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${index + 1} / $total',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.of(context).onPrimary,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onSkip,
                child: Text(
                  isLast ? '' : L('Skip', 'Laktawan'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.of(context).inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            step.title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.of(context).ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            step.body,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppTheme.of(context).inkSoft,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (onBack != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: onBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.of(context).deep,
                      side: BorderSide(color: AppTheme.of(context).border),
                      minimumSize: const Size(0, 46),
                    ),
                    child: Text(L('Back', 'Bumalik')),
                  ),
                ),
              if (onBack != null) const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.of(context).deep,
                    foregroundColor: AppTheme.of(context).onPrimary,
                    minimumSize: const Size(0, 46),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  child: Text(
                    isLast ? L('Done', 'Tapos') : L('Next', 'Susunod'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

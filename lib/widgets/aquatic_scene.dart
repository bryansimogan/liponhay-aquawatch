import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_theme.dart';

/// Decorative scenery only; measurements continue to come from the controller.
class AquaticBackground extends StatelessWidget {
  final Widget child;
  const AquaticBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: Theme.of(context).brightness == Brightness.dark
              ? const [Color(0xFF08323D), Color(0xFF04181E)]
              : const [Color(0xFFE4F5F5), Color(0xFFB5E2E8)],
        )),
        child: child,
      );
}

class PondScene extends StatefulWidget {
  const PondScene({super.key});
  @override
  State<PondScene> createState() => _PondSceneState();
}

class _PondSceneState extends State<PondScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion =
      AnimationController(vsync: this, duration: const Duration(seconds: 18));
  double _angle = -.12;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
    } else {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Decorative fish pond illustration. Drag to rotate.',
        child: Column(children: [
          GestureDetector(
            onHorizontalDragUpdate: (d) => setState(() {
              _angle = (_angle + d.delta.dx * .003).clamp(-.5, .5);
            }),
            child: SizedBox(
              height: 210,
              width: double.infinity,
              child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, _) => CustomPaint(
                      painter: _PondPainter(_motion.value, _angle))),
            ),
          ),
          Text('Drag to explore your pond',
              style:
                  TextStyle(fontSize: 10, color: AppTheme.of(context).inkSoft)),
          const SizedBox(height: 16),
        ]),
      );
}

class _PondPainter extends CustomPainter {
  final double progress;
  final double angle;
  _PondPainter(this.progress, this.angle);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 - 6);
    canvas.rotate(angle);
    final width = math.min(size.width * .8, 290.0);
    final water = Path()
      ..moveTo(0, -72)
      ..lineTo(width / 2, -8)
      ..lineTo(0, 64)
      ..lineTo(-width / 2, -8)
      ..close();
    final base = Path()
      ..moveTo(-width / 2, -8)
      ..lineTo(0, 64)
      ..lineTo(width / 2, -8)
      ..lineTo(width / 2, 25)
      ..lineTo(0, 97)
      ..lineTo(-width / 2, 25)
      ..close();
    canvas.drawShadow(base, const Color(0x770D3B47), 16, true);
    canvas.drawPath(base, Paint()..color = AppTheme.deep);
    canvas.drawPath(
        water,
        Paint()
          ..shader = const LinearGradient(
                  colors: [Color(0xFF2FD0C0), Color(0xFF1A8FB0)])
              .createShader(Rect.fromLTWH(-width / 2, -72, width, 136)));
    canvas.save();
    canvas.clipPath(water);
    for (var i = 0; i < 7; i++) {
      final phase = progress * math.pi * 2 + i;
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(math.sin(phase) * 45, (i - 3) * 20.0),
              width: width * .8,
              height: 35),
          Paint()
            ..color = Colors.white.withValues(alpha: .16)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
    for (var i = 0; i < 4; i++) {
      final phase = progress * math.pi * 2 + i * 1.7;
      canvas.save();
      canvas.translate(math.cos(phase) * width * .25, math.sin(phase) * 35);
      canvas.rotate(math.sin(phase) * .6);
      final fish = Paint()..color = const Color(0xFFFFB27A);
      canvas.drawOval(const Rect.fromLTWH(-12, -5, 24, 10), fish);
      canvas.drawPath(
          Path()
            ..moveTo(-10, 0)
            ..lineTo(-19, -7)
            ..lineTo(-19, 7)
            ..close(),
          fish);
      canvas.drawCircle(
          const Offset(7, -1), 1.2, Paint()..color = AppTheme.deep);
      canvas.restore();
    }
    canvas.restore();
    canvas.drawPath(
        water,
        Paint()
          ..color = Colors.white.withValues(alpha: .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PondPainter old) =>
      old.progress != progress || old.angle != angle;
}

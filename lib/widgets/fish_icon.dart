import 'package:flutter/material.dart';

/// A clean, filled fish glyph (facing right, with a cut-out eye) drawn with a
/// CustomPainter so it scales crisply at any size and takes any color — used
/// in place of the generic paw icon, since this app monitors *fish* ponds.
class FishIcon extends StatelessWidget {
  final double size;
  final Color color;

  const FishIcon({super.key, this.size = 24, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _FishPainter(color)),
    );
  }
}

class _FishPainter extends CustomPainter {
  final Color color;
  _FishPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Fish body + triangular tail (facing right).
    final body = Path()
      ..moveTo(w * 0.86, h * 0.50) // nose
      ..quadraticBezierTo(w * 0.58, h * 0.16, w * 0.34, h * 0.30) // top back
      ..lineTo(w * 0.12, h * 0.18) // tail top
      ..lineTo(w * 0.12, h * 0.82) // tail bottom
      ..lineTo(w * 0.34, h * 0.70) // bottom back
      ..quadraticBezierTo(w * 0.58, h * 0.84, w * 0.86, h * 0.50) // belly
      ..close();

    // Eye as a hole so it reads on any background.
    final eye = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(w * 0.66, h * 0.42),
        radius: w * 0.055,
      ));

    final fish = Path.combine(PathOperation.difference, body, eye);

    canvas.drawPath(
      fish,
      Paint()
        ..color = color
        ..isAntiAlias = true
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _FishPainter oldDelegate) =>
      oldDelegate.color != color;
}

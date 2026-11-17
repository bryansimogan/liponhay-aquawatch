import 'package:flutter/material.dart';

/// Fades + gently slides a child upward when the screen first appears.
/// Use [delayMs] to stagger multiple items (e.g. index * 60).
class Reveal extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final Duration duration;
  final double offsetY;

  const Reveal({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.duration = const Duration(milliseconds: 420),
    this.offsetY = 18,
  });

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    if (widget.delayMs == 0) {
      _controller.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(0, widget.offsetY * (1 - _slide.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Animates an integer counting up from 0 to [value] when it first appears,
/// and smoothly re-counts when [value] changes.
class CountUpText extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;
  final String suffix;

  const CountUpText(
    this.value, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 900),
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return Text('${animatedValue.round()}$suffix', style: style);
      },
    );
  }
}

/// Animates a decimal value counting up (for sensor readings like pH 7.24).
class CountUpDecimal extends StatelessWidget {
  final double value;
  final int decimals;
  final TextStyle? style;
  final Duration duration;
  final String suffix;

  const CountUpDecimal(
    this.value, {
    super.key,
    this.decimals = 1,
    this.style,
    this.duration = const Duration(milliseconds: 900),
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return Text(
          '${animatedValue.toStringAsFixed(decimals)}$suffix',
          style: style,
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

/// Shared cross-fade route for tab-adjacent app navigation.
class FadeThroughRoute extends PageRouteBuilder<void> {
  final Widget screen;

  FadeThroughRoute({required this.screen})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => screen,
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
        );
}

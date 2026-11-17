import 'package:flutter/material.dart';

import '../app_theme.dart';

/// The fish circling its bubble trail, shown wherever the app is waiting.
///
/// The frames come from the supplied GIF. Two things were done to it first:
/// the "loading..." lettering baked into its middle was painted out, and the
/// flat green field it sat on was turned into real transparency — so the mark
/// drops onto any background instead of carrying a green square with it.
///
/// It is an animated WebP rather than a GIF because GIF has only on-or-off
/// transparency, which would have left a hard green fringe around every
/// anti-aliased bubble.
class FishLoader extends StatelessWidget {
  /// Width and height in logical pixels. The artwork is square.
  final double size;

  /// Repaints the mark in this colour, keeping its transparency.
  ///
  /// The artwork is white, which is right on the splash photograph and all
  /// but invisible on the app's near-white background — a white fish turning
  /// on #F5F8F7 is a blank panel. Tinting costs nothing and avoids shipping a
  /// second copy of fifty frames.
  final Color? color;

  const FishLoader({super.key, this.size = 96, this.color});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/loading_fish.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: color == null ? null : BlendMode.srcIn,
      // The animation carries itself; nothing here rotates it.
      gaplessPlayback: true,
    );
  }
}

/// Centred [FishLoader], for a screen waiting on its first data.
///
/// Deliberately just the fish. Putting the pond photograph behind it made
/// every in-app wait look like the splash arriving a second time — you saw
/// the opening, then what appeared to be another opening with a little more
/// loading left in it. The photograph belongs to the splash; inside the app
/// the mark alone says the same thing without announcing a new screen.
class EmblemLoader extends StatelessWidget {
  final double size;
  const EmblemLoader({super.key, this.size = 110});

  @override
  Widget build(BuildContext context) => Center(
        // Brand teal, because inside the app this sits on the light surface
        // rather than on the splash photograph.
        child: FishLoader(size: size, color: AppTheme.of(context).deep),
      );
}

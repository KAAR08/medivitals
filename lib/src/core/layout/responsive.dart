import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Window widths from which the app switches to its wide (desktop/tablet)
/// layout. Below it, phones get exactly the phone layout.
abstract final class Breakpoints {
  /// Side navigation rail instead of the bottom bar.
  static const double wide = 720;

  /// Lists, forms and detail screens never grow wider than this, so they keep
  /// the phone's proportions on a big window.
  static const double readable = 720;
}

extension ResponsiveContext on BuildContext {
  bool get isWide => MediaQuery.sizeOf(this).width >= Breakpoints.wide;
}

/// Centres [child] in a column at most [maxWidth] wide. On a phone the column
/// is the full width, so nothing changes there.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.readable,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.min(constraints.maxWidth, maxWidth);
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
          child: child,
        ),
      );
    });
  }
}

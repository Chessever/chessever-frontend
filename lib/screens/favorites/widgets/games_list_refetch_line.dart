import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// The Games list's quiet "working on it": a thin rounded line across the
/// top of the list while a fetch that replaces the list (a search, its
/// close, a filter) is on its way. The list it replaces stays on screen
/// under it, so the page never empties into a spinner and nothing jumps.
///
/// It eases in and out on a spring; with reduced motion it simply appears
/// and goes. Out of the way of touches and screen readers: the list under it
/// is the content. It is drawn like the event Games search's line (muted ink,
/// no track), so every Games list reads its pending search the same way.
class GamesListRefetchLine extends StatelessWidget {
  const GamesListRefetchLine({super.key, required this.active});

  /// A replacement is on its way.
  final bool active;

  /// The line's thickness.
  static const double thickness = 2;

  static const CupertinoMotion _motion = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 240),
    snapToEnd: true,
  );

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: SingleMotionBuilder(
            motion: _motion,
            value: active ? 1.0 : 0.0,
            active: !reduce,
            builder: (context, shown, _) {
              final opacity = shown.clamp(0.0, 1.0);
              // Gone, it is not built at all: the indicator's own repeating
              // animation stops with it.
              if (opacity < 0.01) {
                return const SizedBox(height: thickness);
              }
              final colors = context.colors;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: Opacity(
                  opacity: opacity,
                  child: LinearProgressIndicator(
                    key: const ValueKey('games_list_refetch_line'),
                    minHeight: thickness,
                    borderRadius: BorderRadius.circular(thickness / 2),
                    backgroundColor: Colors.transparent,
                    color: colors.textPrimaryMuted,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

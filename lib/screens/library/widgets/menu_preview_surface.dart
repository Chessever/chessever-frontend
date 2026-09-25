import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/widgets.dart';

/// A solid, rounded plate behind a bare row (a line of text on a sheet, a
/// player name over the Feed) so its lifted copy reads on the menu's scrim.
///
/// The plate bleeds past the row by [outset] without changing the row's own
/// layout, so the copy still sits exactly on the row it came from. Painted in
/// the row's own surface colour it is invisible in place, which lets a host
/// keep it on permanently and use the row itself as the preview.
class MenuPreviewSurface extends StatelessWidget {
  const MenuPreviewSurface({
    super.key,
    required this.color,
    required this.child,
    this.outset = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.borderRadius,
  });

  final Color color;
  final Widget child;
  final EdgeInsets outset;

  /// Defaults to a 12 (`.br`) radius. A plate with no [outset] behind a
  /// rounded card should pass the card's own radius so no corner peeks out.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      // The row lays out exactly as it would without the plate.
      fit: StackFit.passthrough,
      children: [
        Positioned(
          left: -outset.left,
          right: -outset.right,
          top: -outset.top,
          bottom: -outset.bottom,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: borderRadius ?? BorderRadius.circular(12.br),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

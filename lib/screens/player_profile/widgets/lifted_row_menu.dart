import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:flutter/material.dart';

/// [CardContextMenu] for list rows that have no surface of their own (a player
/// row drawn straight on the page, a search result on the search panel).
///
/// The shared menu lifts a copy of the pressed card over the scrim. A card
/// with its own fill reads as one lit object; a transparent row does not: its
/// text floats over the dimmed original a hair out of register. So the copy
/// here is set on [surfaceColor], the colour the row already sits on, and
/// rounded, which is exactly how the row looks in the list, now as one object.
///
/// The live row is untouched: [child] keeps its own taps; only the long-press
/// is taken here, so leave [child] without an `onLongPress` of its own.
class LiftedRowMenu extends StatelessWidget {
  const LiftedRowMenu({
    super.key,
    required this.actions,
    required this.child,
    this.onPreviewTap,
    this.preview,
    this.surfaceColor,
    this.enabled = true,
  });

  final CardMenuActionsBuilder actions;
  final Widget child;

  /// Tapping the lifted copy. The menu closes first.
  final VoidCallback? onPreviewTap;

  /// A lighter copy to lift instead of [child], for rows whose live build
  /// carries something that must not exist twice (a hero tag).
  final Widget? preview;

  /// The colour behind the row in its list. Defaults to the page background.
  final Color? surfaceColor;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Builder(
      builder: (rowContext) => GestureDetector(
        // Children keep their own taps; only the long-press is ours.
        behavior: HitTestBehavior.deferToChild,
        onLongPress: () => open(rowContext),
        child: child,
      ),
    );
  }

  /// Opens the menu anchored to the row [rowContext] belongs to.
  Future<void> open(BuildContext rowContext) {
    return CardContextMenu.open(
      rowContext,
      actions: actions,
      preview: LiftedRowSurface(color: surfaceColor, child: preview ?? child),
      onPreviewTap: onPreviewTap,
    );
  }
}

/// The surface a lifted row is set on. See [LiftedRowMenu].
///
/// In its list a row is a segment: a rule under it, corners rounded only at
/// the ends of a group. Lifted alone, those marks read as a slice cut out of a
/// table, and the rule turns into a hard hairline along one edge of the plate.
/// So the plate rounds all four corners (at the menu panel's radius, so the
/// copy and the panel beside it read as one pair), and every row inside can
/// ask [isLifted] to draw itself whole: no separator, no half-rounded corners.
class LiftedRowSurface extends StatelessWidget {
  const LiftedRowSurface({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  /// Whether [context] is inside a lifted copy rather than the live list.
  /// Rows that draw list-segment marks (a bottom rule) leave them off here.
  static bool isLifted(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_LiftedRowScope>() != null;

  @override
  Widget build(BuildContext context) {
    // The shared focus menu's panel radius (library_context_menu.dart).
    final radius = BorderRadius.circular(14.br);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? context.colors.background,
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: _LiftedRowScope(child: child),
      ),
    );
  }
}

/// Marks a subtree as a lifted copy. Never changes for a mounted element, so
/// readers look it up without registering a dependency.
class _LiftedRowScope extends InheritedWidget {
  const _LiftedRowScope({required super.child});

  @override
  bool updateShouldNotify(_LiftedRowScope oldWidget) => false;
}

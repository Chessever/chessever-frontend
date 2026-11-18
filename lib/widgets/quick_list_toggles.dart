import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/live_first_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A bare one-tap toolbar glyph for list screens (Trello #1420).
///
/// No tile, fill or border behind the glyph: ink alone carries the state,
/// [AppColors.accentText] when [selected] and [restingColor] (default
/// [AppColors.iconPrimary]) otherwise. A null [onTap] dims the glyph and marks
/// it disabled. The 44 x 44 square is the tap target only. [label] is both the
/// tooltip and the accessible name (with the badge count appended); pass
/// [toggled] for on/off controls so assistive tech reads the state.
class QuickToggleIconButton extends StatelessWidget {
  const QuickToggleIconButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.toggled,
    this.badgeCount,
    this.restingColor,
  });

  final String label;
  final VoidCallback? onTap;

  /// The glyph, built under the toolbar's [IconTheme] for size and color.
  final Widget child;
  final bool selected;
  final bool? toggled;

  /// A count drawn on the glyph's top-right corner (active filters).
  final int? badgeCount;

  /// Ink at rest, for glyphs that sit beside quieter ones (inside a search
  /// field, next to the magnifier). Defaults to [AppColors.iconPrimary].
  final Color? restingColor;

  static const double _target = 44;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    final ink = selected
        ? colors.accentText
        : (restingColor ?? colors.iconPrimary);
    final count = badgeCount ?? 0;
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: toggled,
      label: count > 0 ? '$label, $count active' : label,
      // The glyph's own gesture sits under excludeSemantics, so the tap has
      // to be offered here for Switch Access and Voice Control.
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.square(
            dimension: _target,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: enabled ? 1 : 0.4,
                  child: IconTheme.merge(
                    data: IconThemeData(color: ink, size: 20.ic),
                    child: child,
                  ),
                ),
                if (count > 0)
                  Positioned(
                    top: 6,
                    right: 4,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.brand,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      // The badge is a fixed 16 px coin, so its digit may
                      // not grow past it with the system text size.
                      child: Text(
                        '$count',
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.15),
                        style: AppTypography.textXsMedium.copyWith(
                          color: colors.inkOnAccent,
                          fontSize: 10,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One-tap Live first, wearing the web's Live mark ([LiveFirstMark]).
class LiveFirstToggleButton extends StatelessWidget {
  const LiveFirstToggleButton({
    super.key,
    required this.pressed,
    required this.onTap,
    this.subject = 'games',
    this.restingColor,
  });

  final bool pressed;
  final VoidCallback? onTap;

  /// What the list holds, for the label: `games` or `events`.
  final String subject;

  /// See [QuickToggleIconButton.restingColor].
  final Color? restingColor;

  @override
  Widget build(BuildContext context) {
    return QuickToggleIconButton(
      label: pressed
          ? 'Live $subject are shown first'
          : 'Show live $subject first',
      selected: pressed,
      toggled: pressed,
      onTap: onTap,
      restingColor: restingColor,
      child: const LiveFirstMark(),
    );
  }
}

/// One-tap Classical-only filter, wearing the owl time-control mark.
class ClassicalToggleButton extends StatelessWidget {
  const ClassicalToggleButton({
    super.key,
    required this.pressed,
    required this.onTap,
  });

  final bool pressed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return QuickToggleIconButton(
      label: pressed
          ? 'Showing classical games only'
          : 'Show classical games only',
      selected: pressed,
      toggled: pressed,
      onTap: onTap,
      child: const _ClassicalToolbarGlyph(),
    );
  }
}

/// The owl face from the time-control coin, drawn in the toolbar's ink.
class _ClassicalToolbarGlyph extends StatelessWidget {
  const _ClassicalToolbarGlyph();

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = iconTheme.size ?? 20.ic;
    return SvgPicture.asset(
      SvgAsset.classicalToolbar,
      width: size,
      height: size,
      excludeFromSemantics: true,
      colorFilter: ColorFilter.mode(
        iconTheme.color ?? context.colors.iconPrimary,
        BlendMode.srcIn,
      ),
    );
  }
}

/// The board-view mark, drawn like an [Icon]: size and ink from [IconTheme].
class BoardViewGlyph extends StatelessWidget {
  const BoardViewGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = iconTheme.size ?? 20.ic;
    // The asset's ink fills its whole box; a Material icon's ink keeps to the
    // middle 20 of 24 units. Drawing it at that share keeps it the same
    // optical size as the tune and live marks beside it.
    final ink = size * 20 / 24;
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: SvgPicture.asset(
          SvgAsset.chase_grid,
          width: ink,
          height: ink,
          excludeFromSemantics: true,
          colorFilter: ColorFilter.mode(
            iconTheme.color ?? context.colors.iconPrimary,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}

/// One-tap switch between the list's card and board views, wearing
/// [BoardViewGlyph]. [onTap] flips the view mode.
class BoardViewToggleButton extends StatelessWidget {
  const BoardViewToggleButton({super.key, required this.onTap});

  final VoidCallback? onTap;

  static const String label = 'Change board view';

  @override
  Widget build(BuildContext context) {
    return QuickToggleIconButton(
      label: label,
      onTap: onTap,
      child: const BoardViewGlyph(),
    );
  }
}

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search/search_motion.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

/// The clear button at the end of a search field, as X draws it: a bare
/// circled x in the magnifier's resting tint, there only while the field
/// holds text. It empties the field and nothing else; putting the search
/// away is Cancel's, beside the field ([SearchCancelButton]).
///
/// It grows out of the field's edge on [SearchMotion.accent] (width and
/// scale off one value, so it fills its slot exactly and is never clipped
/// mid-travel) and goes the same way. Its box is the field's line height
/// tall unless [tapHeight] says otherwise, so it never changes the field's
/// height; in a home top bar it takes a 44pt tap ([HomeTopBarTapTarget]).
///
/// With the field's [focusNode] it belongs to the field: pressing it is not
/// a tap outside it, so the app's keyboard dismissal (`DismissKeyboard`)
/// leaves the keyboard up instead of dropping it at the press and raising
/// it again when the clear lands.
///
/// The glyph is set against the box's end so its centre sits as far in from
/// the field's end as the magnifier's sits from its start: the two marks
/// frame the text symmetrically.
class SearchClearButton extends StatelessWidget {
  const SearchClearButton({
    super.key,
    required this.controller,
    required this.onTap,
    this.focusNode,
    this.color,
    this.tapHeight,
    this.tooltip = 'Clear search',
  });

  final TextEditingController controller;
  final VoidCallback onTap;

  /// The field's focus node: pressing the x keeps the keyboard up.
  final FocusNode? focusNode;

  /// The glyph's tint: the field's magnifier's, where that is not
  /// [AppColors.iconSecondary].
  final Color? color;

  /// How tall the tap box stands, for a field tall enough to give the x a
  /// 44pt target. Null is [box]'s height, the field's line.
  final double? tapHeight;

  /// The accessible name.
  final String tooltip;

  /// The circled x.
  static const double glyph = 18;

  /// The box it is drawn in, the whole of it the tap.
  static const Size box = Size(32, 24);

  /// Between the glyph and the box's end: the magnifier's glyph is inset by
  /// as much within its own 20pt box.
  static const double endInset = 1;

  /// Where the glyph's centre sits in from the box's end.
  static const double glyphCentre = endInset + glyph / 2;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.iconSecondary;
    Widget button = Semantics(
      container: true,
      button: true,
      label: tooltip,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('search_field_clear'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: box.width,
          height: tapHeight ?? box.height,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: endInset),
              child: SvgWidget(
                SvgAsset.searchClearIcon,
                height: glyph,
                width: glyph,
                colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
              ),
            ),
          ),
        ),
      ),
    );
    final node = focusNode;
    if (node != null) {
      button = TextFieldTapRegion(
        child: KeyboardDismissExclusion(focusNode: node, child: button),
      );
    }
    return ListenableBuilder(
      listenable: controller,
      child: button,
      builder: (context, button) => SqueezeSlot(
        open: controller.text.isNotEmpty,
        motion: SearchMotion.accent,
        // A 44pt reach in the home top bar without growing the row.
        child: HomeTopBarTapTarget(child: button!),
      ),
    );
  }
}

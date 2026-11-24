import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search/search_motion.dart';
import 'package:flutter/material.dart';

/// A search field's Cancel, as X sets it: a plain word at the end of the
/// search row, outside the field and after its filter, there while the
/// field has the cursor or holds text. The clear button inside the field
/// only empties it ([SearchClearButton]); Cancel puts the search away
/// ([onCancel]: the query cleared, the keyboard down, the page back).
///
/// Its room opens on the field morph's spring ([SearchMotion.morph]): the
/// field beside it narrows by exactly as much, frame by frame, and the word
/// slides in from past the screen's edge, so nothing jumps. Under reduced
/// motion it lands at once. Closed, it takes no room, no paint, no taps and
/// no place in the semantics tree; closing, it takes no taps.
///
/// A full-page search that is open for as long as it is shown (the search
/// header, `SearchModeHeader`) draws a [SearchCancelWord] itself instead.
class SearchCancelButton extends StatelessWidget {
  const SearchCancelButton({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCancel,
    this.cancelKey = const ValueKey('search_tab_cancel'),
    this.hint = 'Clears the search',
    this.startGap,
    this.endInset = 0,
    this.textStyle,
    this.minHeight,
    this.whileHoldingText = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCancel;

  /// Whether Cancel stays once the field lets go of the cursor while it
  /// still holds text. A bar whose own controls come back when the field
  /// lets go (the Library's Board and Add) turns it off: there Cancel would
  /// land between the field and those controls, so it shows only while the
  /// field has the cursor.
  final bool whileHoldingText;

  /// On the word's tap target.
  final Key cancelKey;

  /// The accessible hint: what Cancel does on this page.
  final String hint;

  /// The gap before the word ([SearchCancelWord.startGap]).
  final double? startGap;

  /// Room after the word that still takes its tap
  /// ([SearchCancelWord.endInset]).
  final double endInset;

  /// The word's type ([SearchCancelWord.textStyle]).
  final TextStyle? textStyle;

  /// The word's least height ([SearchCancelWord.minHeight]).
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      child: SearchCancelWord(
        tapKey: cancelKey,
        focusNode: focusNode,
        onTap: onCancel,
        hint: hint,
        startGap: startGap,
        endInset: endInset,
        textStyle: textStyle,
        minHeight: minHeight,
      ),
      builder: (context, word) {
        final open =
            focusNode.hasFocus ||
            (whileHoldingText && controller.text.isNotEmpty);
        // Parked the moment it is visually at rest, so the field morph it
        // rides with stops ticking when it does.
        return ParkedMotionBuilder(
          motion: SearchMotion.morph,
          value: open ? 1.0 : 0.0,
          active: !reduce,
          child: word,
          builder: (context, value, word) {
            // Land exactly on the ends.
            final f = value < 0.01
                ? 0.0
                : value > 0.99
                ? 1.0
                : value;
            // Closed: no room, no paint, no taps.
            if (f == 0) return const SizedBox.shrink();
            return IgnorePointer(
              ignoring: !open,
              child: ExcludeSemantics(
                excluding: !open,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: f,
                  child: word,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The word itself: the field's type in the page's primary ink, a step
/// quieter while pressed. A 44pt target: the gap before it (and [endInset]
/// after it) and the row's full height take the tap too. It belongs to the
/// field (a tap here is not a tap outside it), so pressing it never drops
/// the keyboard before the tap lands.
class SearchCancelWord extends StatefulWidget {
  const SearchCancelWord({
    super.key,
    required this.focusNode,
    required this.onTap,
    this.tapKey = const ValueKey('search_tab_cancel'),
    this.hint = 'Clears the search',
    this.endInset = 0,
    this.startGap,
    this.textStyle,
    this.minHeight,
  });

  /// The field's focus node.
  final FocusNode focusNode;
  final VoidCallback onTap;

  /// On the tap target (tests and e2e find Cancel by it).
  final Key tapKey;

  /// The accessible hint: what Cancel does on this page.
  final String hint;

  /// Room after the word that still takes its tap: a row that ends on the
  /// gutter minus a glyph button's reach gives it back here, so the word
  /// itself ends on the gutter.
  final double endInset;

  /// The gap before the word, the tap's too: [gap] straight after the
  /// field, [afterGlyph] after a bare glyph (a home bar's Filters). After a
  /// 44pt glyph button, whose box already holds its glyph 12pt in, pass the
  /// rest of [afterGlyph].
  final double? startGap;

  /// Between the field and the word.
  static double get gap => 12.w;

  /// Between a trailing glyph (Filters) and the word: as far as that glyph
  /// sits from the field, and clear of the count on its shoulder.
  static const double afterGlyph = 16;

  /// The word's type: the field's, medium. Null is the home bar field's
  /// ([HomeTopBarMetrics.fieldTextStyle]); a field set smaller passes its
  /// own so the word reads at the field's size, as X's does.
  final TextStyle? textStyle;

  /// The least height the word stands, the whole of it the tap: [extent]
  /// unless given. A home top bar passes 0: its frame carries the 44pt
  /// reach ([HomeTopBarTapTarget]), and the bar's row, shorter than 44pt on
  /// a small phone, must not grow while the word is open.
  final double? minHeight;

  /// How tall the word stands by default: a 44pt target, on every device
  /// (scaling it with the width made it 66pt on a tablet, taller than the
  /// search row). A row shorter than this holds it as its least height, so
  /// the word opening never makes the row taller and moves the page under
  /// it.
  static const double extent = HomeTopBarMetrics.minTapTarget;

  @override
  State<SearchCancelWord> createState() => _SearchCancelWordState();
}

class _SearchCancelWordState extends State<SearchCancelWord> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = widget.textStyle ?? HomeTopBarMetrics.fieldTextStyle;
    return TextFieldTapRegion(
      child: KeyboardDismissExclusion(
        focusNode: widget.focusNode,
        child: HomeTopBarTapTarget(
          child: Semantics(
            container: true,
            button: true,
            label: 'Cancel',
            hint: widget.hint,
            onTap: widget.onTap,
            excludeSemantics: true,
            child: GestureDetector(
              key: widget.tapKey,
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _press(true),
              onTapUp: (_) => _press(false),
              onTapCancel: () => _press(false),
              onTap: widget.onTap,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: widget.minHeight ?? SearchCancelWord.extent,
                  minWidth: SearchCancelWord.extent,
                ),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: widget.startGap ?? SearchCancelWord.gap,
                    end: widget.endInset,
                  ),
                  child: Center(
                    widthFactor: 1,
                    // Chrome: it stops growing where the bar's other words do,
                    // so the field keeps its room at large text sizes.
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: HomeTopBarMetrics.maxTextScale,
                      child: Text(
                        'Cancel',
                        maxLines: 1,
                        softWrap: false,
                        style: style.copyWith(
                          fontWeight: FontWeight.w500,
                          color: _pressed
                              ? colors.textSecondary
                              : colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

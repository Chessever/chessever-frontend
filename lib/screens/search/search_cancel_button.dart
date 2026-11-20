import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search/search_motion.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// The Search tab's Cancel, as X sets it: a plain word at the end of the
/// search row, outside the field, there while the field has the cursor or
/// holds text. A tap gives the field back to rest ([onCancel]: the query
/// cleared, the keyboard down, the landing back).
///
/// Its room opens on the field morph's spring ([SearchMotion.morph]): the
/// field beside it narrows by exactly as much, frame by frame, and the word
/// slides in from past the screen's edge, so nothing jumps. Under reduced
/// motion it lands at once. Closed, it takes no room, no paint, no taps and
/// no place in the semantics tree; closing, it takes no taps.
class SearchCancelButton extends StatelessWidget {
  const SearchCancelButton({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      child: _CancelWord(focusNode: focusNode, onTap: onCancel),
      builder: (context, word) {
        final open = focusNode.hasFocus || controller.text.isNotEmpty;
        return SingleMotionBuilder(
          motion: SearchMotion.morph,
          value: open ? 1.0 : 0.0,
          active: !reduce,
          child: word,
          builder: (context, value, word) {
            // A spring only approaches its end: land exactly on it.
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
/// quieter while pressed. A 44pt target: the gap before it and the row's
/// full height take the tap too. It belongs to the field (a tap here is not
/// a tap outside it), so pressing it never drops the keyboard before the
/// tap lands.
class _CancelWord extends StatefulWidget {
  const _CancelWord({required this.focusNode, required this.onTap});

  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  State<_CancelWord> createState() => _CancelWordState();
}

class _CancelWordState extends State<_CancelWord> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = math.max(HomeTopBarMetrics.minTapTarget, 44.w);
    return TextFieldTapRegion(
      child: KeyboardDismissExclusion(
        focusNode: widget.focusNode,
        child: Semantics(
          container: true,
          button: true,
          label: 'Cancel',
          hint: 'Clears the search',
          onTap: widget.onTap,
          excludeSemantics: true,
          child: GestureDetector(
            key: const ValueKey('search_tab_cancel'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _press(true),
            onTapUp: (_) => _press(false),
            onTapCancel: () => _press(false),
            onTap: widget.onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: target, minWidth: target),
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: 12.w),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    'Cancel',
                    maxLines: 1,
                    softWrap: false,
                    style: HomeTopBarMetrics.fieldTextStyle.copyWith(
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
    );
  }
}

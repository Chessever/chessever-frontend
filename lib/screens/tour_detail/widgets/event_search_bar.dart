import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search/search_motion.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/material.dart';

/// The search field's frame on every Games tab, the event page and
/// collections: the app's one search field look ([HomeSearchFieldSurface],
/// the Search tab's and Events' field). The page's surface, lifting a hair
/// toward the ink with a self-coloured edge while [focusNode] has focus, on
/// the spring the home field lifts on, as tall as the home field and in its
/// type (`SimpleSearchBar`).
///
/// Inside a [SearchModeHeader] its fill is a [SearchFieldFill]: the frame
/// the search morph's glass lands on and becomes, in the same colours.
class EventSearchBarFrame extends StatelessWidget {
  const EventSearchBarFrame({
    super.key,
    required this.child,
    this.horizontalPadding = 0,
    this.compact = false,
    this.focusNode,
  });

  final Widget child;
  final double horizontalPadding;

  /// No strip around the field (4.h above, 8.h below), so the row it sits in
  /// sets the spacing: the search header's form. Off for a field placed on
  /// its own above a list.
  final bool compact;

  /// The field's focus: the frame lifts while it has it, and a tap anywhere
  /// on the frame (not only on the line of text) puts the cursor in. Null,
  /// the frame rests.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final handoff = SearchFieldHandoff.maybeOf(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final focus = focusNode;

    Widget surface(double lift, Widget child) {
      if (handoff == null) {
        return HomeSearchFieldSurface(lift: lift, child: child);
      }
      return SearchFieldFill(
        key: handoff.frameKey,
        color: HomeSearchFieldSurface.fillOf(context, lift),
        edge: HomeSearchFieldSurface.edgeOf(context, lift),
        radius: HomeSearchFieldSurface.radius,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: HomeSearchFieldSurface.heightOf(context),
          ),
          child: child,
        ),
      );
    }

    Widget field;
    if (focus == null) {
      field = surface(0, child);
    } else {
      field = ListenableBuilder(
        listenable: focus,
        child: child,
        builder: (context, child) {
          final target = focus.hasFocus ? 1.0 : 0.0;
          return ParkedMotionBuilder(
            value: target,
            motion: SearchMotion.morph,
            child: child,
            // The same tree with reduced motion, only landed: the field never
            // remounts (and drops its keyboard) when the setting changes.
            builder: (context, lift, child) =>
                surface(reduce ? target : lift, child!),
          );
        },
      );
      field = GestureDetector(
        // The text is one line tall in a taller field: the rest of the frame
        // still puts the cursor in. The text, the clear button and anything
        // else in the field keep their own taps.
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () {
          if (!focus.hasFocus) focus.requestFocus();
        },
        child: field,
      );
    }

    return Padding(
      padding: compact
          ? EdgeInsets.symmetric(horizontal: horizontalPadding)
          : EdgeInsets.fromLTRB(horizontalPadding, 4.h, horizontalPadding, 8.h),
      child: field,
    );
  }
}

import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// The header of a Games list's full-page search (Trello #1420), shared by
/// Favorites and Countrymen: a way back, the field, and the list's filters as
/// bare glyphs after it, nothing else. It takes the place of the screen's
/// title row and tabs; the same Games list fills the page under it, filtered
/// as the reader types. The event screen's search header has the same
/// geometry, so every search reads as one object.
class GamesSearchHeader extends StatelessWidget {
  const GamesSearchHeader({
    super.key,
    required this.field,
    required this.onClose,
    this.trailing = const <Widget>[],
  });

  /// The search field, autofocused by its owner.
  final Widget field;

  /// Leaves the search: clears the query and brings the header back.
  final VoidCallback onClose;

  /// Bare 44pt glyph buttons after the field (Classical, Filters).
  final List<Widget> trailing;

  /// How far a 44pt glyph button's target reaches past its 20pt glyph.
  static const double _glyphReach = 12;

  @override
  Widget build(BuildContext context) {
    final side = ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);
    return Padding(
      // The chevron's glyph and the last trailing glyph land on the gutter;
      // their 44pt targets reach into it.
      // Never negative: a folded Duo pane is narrower than the gutter.
      padding: EdgeInsetsDirectional.fromSTEB(
        math.max(0.0, side - _glyphReach),
        4.h,
        trailing.isEmpty ? side : math.max(0.0, side - _glyphReach),
        10.h,
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              key: const ValueKey('games_search_close'),
              tooltip: 'Close search',
              padding: EdgeInsets.zero,
              onPressed: () {
                HapticFeedbackService.navigation();
                onClose();
              },
              icon: Icon(
                Icons.arrow_back_ios_new_outlined,
                size: 22,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(child: field),
            ),
          ),
          if (trailing.isNotEmpty) ...[const SizedBox(width: 4), ...trailing],
        ],
      ),
    );
  }
}

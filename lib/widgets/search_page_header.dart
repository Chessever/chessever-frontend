import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// The header while a page is being searched: a way back and the field, and
/// nothing else. The page's own content fills the screen under it, filtered
/// as the reader types. The same geometry as the event screen's search, so
/// every full-page search in the app opens alike.
///
/// [field] is the page's own search field (usually a [SimpleSearchBar] in an
/// `EventSearchBarFrame`), filter glyph included when the page has filters.
class SearchPageHeader extends StatelessWidget {
  const SearchPageHeader({
    super.key,
    required this.field,
    required this.onClose,
    this.closeKey = const ValueKey('search_page_close'),
  });

  final Widget field;

  /// Leaves the search; the page clears what was searched.
  final VoidCallback onClose;
  final Key closeKey;

  @override
  Widget build(BuildContext context) {
    final side = ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);
    return Padding(
      // The chevron's glyph lands on the gutter; its 44pt target reaches
      // into it (never past the screen's edge, on the narrowest windows).
      padding: EdgeInsetsDirectional.fromSTEB(
        math.max(0, side - 12),
        4.h,
        side,
        10.h,
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              key: closeKey,
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
        ],
      ),
    );
  }
}

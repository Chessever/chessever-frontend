import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/material.dart';

/// What a list shows when its search, or its filters, leave nothing: one
/// composition on every Games tab (the event's Games and Combined,
/// Favorites, Countrymen, Smart event, Miniatures, a player's games, Prep),
/// and the Search tab's own: said once, quietly, on the list's gutter where
/// the first row would have been.
///
/// 'No matches for "carlsen"' when there are words to echo ([query]), else
/// 'No matching games'. With [onClear], one way back under it: "Clear
/// search", or "Clear filters" when [filtered] (the filters, not the words,
/// emptied the list). No mark, no card, no advice paragraph: the empty list
/// itself says the rest.
///
/// Drawn whole from its first frame: nothing about it waits on an entrance
/// animation, and a screen reader hears it as it appears (a live region).
///
/// Put it where the list's rows would be: as the list's body, or as a
/// sliver with [SearchNoMatches.sliver].
class SearchNoMatches extends StatelessWidget {
  const SearchNoMatches({
    super.key,
    this.query,
    this.subject = 'games',
    this.filtered = false,
    this.onClear,
    this.clearLabel,
  });

  /// [SearchNoMatches] in a `CustomScrollView`.
  static Widget sliver({
    Key? key,
    String? query,
    String subject = 'games',
    bool filtered = false,
    VoidCallback? onClear,
    String? clearLabel,
  }) => SliverToBoxAdapter(
    key: key,
    child: SearchNoMatches(
      query: query,
      subject: subject,
      filtered: filtered,
      onClear: onClear,
      clearLabel: clearLabel,
    ),
  );

  /// The words searched, echoed back. Null or blank says only that nothing
  /// matched.
  final String? query;

  /// What the list holds, plural ("games", "players"), for the line with no
  /// words to echo.
  final String subject;

  /// The filters (not only the words) are what leave the list empty: the
  /// action clears them.
  final bool filtered;

  /// Clears what empties the list. It plays the button haptic itself, so
  /// the callback should not play another. Null: no action.
  final VoidCallback? onClear;

  /// The action's words; [clearLabelFor] by default.
  final String? clearLabel;

  /// The line: the query echoed, or what the list holds.
  static String titleFor({String? query, String subject = 'games'}) {
    final words = query?.trim() ?? '';
    return words.isEmpty ? 'No matching $subject' : 'No matches for "$words"';
  }

  /// The action's default words.
  static String clearLabelFor({required bool filtered}) =>
      filtered ? 'Clear filters' : 'Clear search';

  /// How far below the list's top the line sits: where its first row would
  /// have started.
  static double get topGap => 20.h;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gutter = SearchHeaderMetrics.gutter;
    final clear = onClear;
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(gutter, topGap, gutter, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                titleFor(query: query, subject: subject),
                key: const ValueKey('search_no_matches_title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textMdRegular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            if (clear != null)
              _ClearAction(
                label: clearLabel ?? clearLabelFor(filtered: filtered),
                onTap: clear,
              ),
          ],
        ),
      ),
    );
  }
}

/// The way back to every row: the words alone in the brand's tonal accent,
/// on the line's start edge, with a 44pt target and the app's press.
class _ClearAction extends StatelessWidget {
  const _ClearAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  void _activate() {
    HapticFeedbackService.buttonPress();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: _activate,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('search_no_matches_clear'),
        behavior: HitTestBehavior.opaque,
        onTap: _activate,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            heightFactor: 1,
            child: PressSpring(
              pressedScale: 0.96,
              child: Text(
                label,
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.accentText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

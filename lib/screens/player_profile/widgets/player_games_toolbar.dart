import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/utils/legible_ink.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/simple_search_bar.dart' show SpringHintWord;
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:flutter/material.dart';

/// What a line of text [line] tall gains at the reader's text size. Nothing
/// at the default size, so every height below is its designed one there.
double _textGrowth(BuildContext context, double line) =>
    math.max(0, MediaQuery.textScalerOf(context).scale(line) - line);

/// The row above a player's games: search, filters and the list layout.
/// One widget for every screen that lists a player's games (the profile's
/// Games tab, My Prep), so the controls cannot drift apart.
class PlayerGamesSearchBar extends StatefulWidget {
  const PlayerGamesSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.onFilterTap,
    required this.onLayoutToggle,
    this.hasQuery = false,
    this.hasActiveFilters = false,
    this.activeFilterCount = 0,
    this.searchFieldKey,
    this.filterButtonKey,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilterTap;
  final VoidCallback onLayoutToggle;

  /// A search is applied to the list, whatever the field shows right now.
  final bool hasQuery;
  final bool hasActiveFilters;
  final int activeFilterCount;
  final Key? searchFieldKey;
  final Key? filterButtonKey;

  /// The row's height, for the header that reserves room for it. It grows
  /// with larger text so the search line is never cut.
  static double heightOf(BuildContext context) =>
      48.h + _textGrowth(context, 22.f);

  @override
  State<PlayerGamesSearchBar> createState() => _PlayerGamesSearchBarState();
}

class _PlayerGamesSearchBarState extends State<PlayerGamesSearchBar> {
  // Rotating "Search <word>" hint — mirrors the home and TWIC search bars so
  // the animated second word is consistent across the app.
  static const List<String> _rotatingHints = <String>[
    'event',
    'opponent',
    'opening',
  ];
  static const Duration _hintRotationInterval = Duration(seconds: 2);
  // Must comfortably cover SpringHintWord's 420ms spring so the last word
  // finishes animating out before we collapse back to plain "Search".
  static const Duration _hintCycleFadeOutDuration = Duration(milliseconds: 460);
  Timer? _hintRotationTimer;
  Timer? _hintFadeOutTimer;
  int _hintIndex = 0;
  // Rotation runs a single full pass, then collapses back to plain "Search".
  bool _hintCycleDone = false;
  // Transient: after the final tick we pass '' to SpringHintWord so it
  // spring-fades the last word out before the overlay disappears — fixes
  // the abrupt "snap" at cycle end.
  bool _hintCycleFadingOut = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onSearchFocusChange);
    widget.controller.addListener(_onSearchTextChange);
    _restartHintRotation();
  }

  @override
  void didUpdateWidget(PlayerGamesSearchBar old) {
    super.didUpdateWidget(old);
    if (!identical(old.focusNode, widget.focusNode)) {
      old.focusNode.removeListener(_onSearchFocusChange);
      widget.focusNode.addListener(_onSearchFocusChange);
    }
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onSearchTextChange);
      widget.controller.addListener(_onSearchTextChange);
    }
  }

  @override
  void dispose() {
    _hintRotationTimer?.cancel();
    _hintFadeOutTimer?.cancel();
    widget.focusNode.removeListener(_onSearchFocusChange);
    widget.controller.removeListener(_onSearchTextChange);
    super.dispose();
  }

  void _onSearchFocusChange() {
    if (!mounted) return;
    setState(() {});
    if (widget.focusNode.hasFocus) {
      _hintRotationTimer?.cancel();
    } else {
      _restartHintRotation();
    }
  }

  void _onSearchTextChange() {
    if (!mounted) return;
    final hasText = widget.controller.text.isNotEmpty;
    final running = _hintRotationTimer?.isActive ?? false;
    if (hasText && running) {
      _hintRotationTimer?.cancel();
    } else if (!hasText && !running && !widget.focusNode.hasFocus) {
      _restartHintRotation();
    }
  }

  void _restartHintRotation() {
    _hintRotationTimer?.cancel();
    if (_hintCycleDone || _hintCycleFadingOut || _rotatingHints.length <= 1) {
      return;
    }
    if (widget.controller.text.isNotEmpty || widget.focusNode.hasFocus) return;
    _hintRotationTimer = Timer.periodic(_hintRotationInterval, (_) {
      if (!mounted) return;
      final next = _hintIndex + 1;
      if (next >= _rotatingHints.length) {
        _hintRotationTimer?.cancel();
        setState(() => _hintCycleFadingOut = true);
        _hintFadeOutTimer?.cancel();
        _hintFadeOutTimer = Timer(_hintCycleFadeOutDuration, () {
          if (!mounted) return;
          setState(() => _hintCycleDone = true);
        });
      } else {
        setState(() => _hintIndex = next);
      }
    });
  }

  Widget _buildRotatingSearchHint() {
    // Pass an empty word during the fade-out phase so SpringHintWord animates
    // the final entry out instead of disappearing in a single frame.
    final word = _hintCycleFadingOut
        ? ''
        : _rotatingHints[_hintIndex % _rotatingHints.length];
    final style = AppTypography.textSmRegular.copyWith(
      color: context.colors.textSecondary,
    );
    return IgnorePointer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flexible, so large text in a narrow field is cut, not overflowed.
          Flexible(
            child: Text(
              'Search ',
              style: style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          ),
          Flexible(
            child: SpringHintWord(word: word, style: style),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFilters = widget.hasActiveFilters;
    final activeFilterCount = widget.activeFilterCount;
    final searchBarHeight = PlayerGamesSearchBar.heightOf(context);
    final controller = widget.controller;
    final focusNode = widget.focusNode;

    return SizedBox(
      height: searchBarHeight,
      child: Row(
        children: [
          // Search field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: context.colors.surfaceRecessed),
              ),
              child: Row(
                children: [
                  SizedBox(width: 12.w),
                  Icon(
                    Icons.search,
                    size: 20.sp,
                    color: context.colors.textSecondary,
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Builder(
                      builder: (_) {
                        final showRotating =
                            !_hintCycleDone &&
                            controller.text.isEmpty &&
                            !focusNode.hasFocus;
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            if (showRotating) _buildRotatingSearchHint(),
                            TextField(
                              key: widget.searchFieldKey,
                              controller: controller,
                              focusNode: focusNode,
                              style: AppTypography.textSmRegular.copyWith(
                                color: context.colors.textPrimary,
                              ),
                              onChanged: widget.onChanged,
                              decoration: InputDecoration(
                                isDense: true,
                                // The TextField owns the "Search" hint except
                                // while the rotating overlay is driving it.
                                hintText: showRotating ? null : 'Search',
                                hintStyle: AppTypography.textSmRegular.copyWith(
                                  color: context.colors.textSecondary,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 14.h,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (controller.text.isNotEmpty || widget.hasQuery) ...[
                    Tooltip(
                      message: 'Clear search',
                      child: GestureDetector(
                        onTap: widget.onClear,
                        child: Icon(
                          Icons.close,
                          size: 20.sp,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                  ],
                  SizedBox(width: 8.w),
                ],
              ),
            ),
          ),

          // Filter button
          SizedBox(width: 8.w),
          Tooltip(
            message: 'Filter and sort games',
            child: GestureDetector(
              onTap: widget.onFilterTap,
              child: Container(
                key: widget.filterButtonKey,
                width: searchBarHeight,
                height: searchBarHeight,
                decoration: BoxDecoration(
                  color: hasActiveFilters
                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                      : context.colors.background,
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(
                    color: hasActiveFilters
                        ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                        : context.colors.surfaceRecessed,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 20.sp,
                      color: hasActiveFilters
                          ? (context.isLightTheme
                                ? context.colors.danger
                                : const Color(0xFFEF4444))
                          : context.colors.textSecondary,
                    ),
                    if (hasActiveFilters)
                      Positioned(
                        right: 6.w,
                        top: 6.h,
                        child: Container(
                          width: 14.w,
                          height: 14.h,
                          decoration: BoxDecoration(
                            color: context.isLightTheme
                                ? context.colors.danger
                                : const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$activeFilterCount',
                              style: AppTypography.textXsBold.copyWith(
                                color: context.isLightTheme
                                    ? labelOnFill(
                                        context,
                                        context.colors.danger,
                                      )
                                    : context.colors.textPrimary,
                                fontSize: 9.sp,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Layout toggle button
          SizedBox(width: 8.w),
          Tooltip(
            message: 'Change games layout',
            child: GestureDetector(
              onTap: widget.onLayoutToggle,
              child: Container(
                width: searchBarHeight,
                height: searchBarHeight,
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(color: context.colors.surfaceRecessed),
                ),
                // Every Games list's board-view mark ([BoardViewGlyph]).
                child: Center(
                  child: IconTheme(
                    data: IconThemeData(
                      size: 20.sp,
                      color: context.colors.textSecondary,
                    ),
                    child: const BoardViewGlyph(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The line over a player's games on the profile: how many games the list
/// holds, what narrows it (with a way to clear that), the layout and the
/// filters, as the list toolbars elsewhere draw them (bare glyphs, the one
/// filter count).
///
/// It is the Games tab's own line, so it stays when the tab is searched (the
/// list under the search is the tab's, controls included), and it is always
/// there, one height, so nothing over the list moves when a filter or a
/// query starts narrowing it.
class PlayerGamesListToolbar extends StatelessWidget {
  const PlayerGamesListToolbar({
    super.key,
    required this.gameCount,
    required this.filterCount,
    required this.onClearFilters,
    required this.onOpenFilters,
    required this.onToggleLayout,
    required this.inset,
    this.morePending = false,
    this.filterButtonKey,
    this.controlsInSearchHeader = false,
  });

  /// The page's search header carries the board view and Filters while its
  /// search is open: here they step aside with the page's header (their
  /// room kept, so the count line never moves).
  final bool controlsInSearchHeader;

  /// The games the list holds for its filters and search; null while its
  /// first page loads.
  final int? gameCount;

  /// More pages wait beyond [gameCount] and their total is not known.
  final bool morePending;

  /// What the filter sheet narrows (the result included), not the search.
  final int filterCount;
  final VoidCallback onClearFilters;
  final VoidCallback onOpenFilters;
  final VoidCallback onToggleLayout;

  /// The list's side margin: the words start on it and the last glyph ends
  /// on it.
  final double inset;
  final Key? filterButtonKey;

  /// The glyphs' 44pt targets reach this far past their 20pt glyphs.
  static const double _reach = 12;

  /// The line's height: the glyphs' targets, grown with larger text.
  static double heightOf(BuildContext context) =>
      44 + _textGrowth(context, 20.f);

  /// "1.2K games", "60+ games", "1 game".
  static String countLabel(int count, {bool morePending = false}) {
    final more = morePending ? '+' : '';
    final noun = count == 1 && !morePending ? 'game' : 'games';
    return '${formatCompactCount(count)}$more $noun';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const figures = [FontFeature.tabularFigures()];
    final muted = AppTypography.textSmRegular.copyWith(
      color: colors.textSecondary,
      fontFeatures: figures,
    );
    final count = gameCount;
    final games = count == null
        ? null
        : countLabel(count, morePending: morePending);

    final Widget summary;
    if (filterCount > 0) {
      final filters = '$filterCount filter${filterCount == 1 ? '' : 's'}';
      summary = Row(
        children: [
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: filters,
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.textPrimary,
                      fontFeatures: figures,
                    ),
                  ),
                  if (games != null) TextSpan(text: ' · $games', style: muted),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Semantics(
            button: true,
            label: 'Clear filters',
            excludeSemantics: true,
            onTap: onClearFilters,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClearFilters,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10.w),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      'Clear',
                      style: AppTypography.textSmMedium.copyWith(
                        color: colors.accentText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      summary = Text(
        games ?? '',
        style: muted,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return SizedBox(
      height: heightOf(context),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: inset,
          end: math.max(0.0, inset - _reach),
        ),
        child: Row(
          children: [
            Expanded(child: summary),
            _controls(context),
          ],
        ),
      ),
    );
  }
}

extension on PlayerGamesListToolbar {
  Widget _controls(BuildContext context) {
    final Widget controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BoardViewToggleButton(onTap: onToggleLayout),
        SearchModeFilterButton(
          key: filterButtonKey,
          count: filterCount,
          onTap: onOpenFilters,
        ),
      ],
    );
    final scope = controlsInSearchHeader
        ? SearchModeScope.maybeOf(context)
        : null;
    if (scope == null) return controls;
    final away = scope.isSearching;
    return IgnorePointer(
      ignoring: away,
      child: ExcludeSemantics(
        excluding: away,
        child: FadeTransition(
          opacity: scope.pageHeaderOpacity,
          child: controls,
        ),
      ),
    );
  }
}

/// The strip under the search row while the list is narrowed: how many
/// filters are on and how many games they leave. Tapping it clears them.
class PlayerGamesActiveFiltersChip extends StatelessWidget {
  const PlayerGamesActiveFiltersChip({
    super.key,
    required this.activeFilterCount,
    required this.gameCount,
    required this.onClear,
    this.resultLabel,
  });

  final int activeFilterCount;
  final int gameCount;
  final VoidCallback onClear;

  /// The result filter in force (`Wins`), named beside the count.
  final String? resultLabel;

  /// The room the strip takes under the search row, with its gap below.
  /// It grows with larger text, as its one line does.
  static double heightOf(BuildContext context) =>
      42.h + _textGrowth(context, 20.f);

  @override
  Widget build(BuildContext context) {
    // Used as text on its own 10% tint: paper needs the deeper danger ink.
    final filterRedColor = context.isLightTheme
        ? context.colors.danger
        : const Color(0xFFEF4444);
    return GestureDetector(
      onTap: onClear,
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: filterRedColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(color: filterRedColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_rounded, size: 16.sp, color: filterRedColor),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(
                '$activeFilterCount filter${activeFilterCount > 1 ? 's' : ''} active · ${formatCompactCount(gameCount)} games',
                style: AppTypography.textXsMedium.copyWith(
                  color: filterRedColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (resultLabel != null) ...[
              SizedBox(width: 8.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: filterRedColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6.br),
                ),
                child: Text(
                  resultLabel!,
                  style: AppTypography.textXsRegular.copyWith(
                    color: filterRedColor,
                  ),
                ),
              ),
            ],
            SizedBox(width: 8.w),
            Icon(Icons.close_rounded, size: 14.sp, color: filterRedColor),
          ],
        ),
      ),
    );
  }
}

/// What the list shows when filters or a search leave no game: the one
/// no-hits state every Games list shows ([SearchNoMatches]), on the list's
/// gutter where its first row would have been.
///
/// [query] is echoed back ('No matches for "carl"'). [filtered]: the
/// filter sheet narrows the list too, so the action clears the filters
/// ("Clear filters"); otherwise it clears the words ("Clear search").
/// [onClear] does what the action says and plays no haptic of its own.
class PlayerGamesNoMatches extends StatelessWidget {
  const PlayerGamesNoMatches({
    super.key,
    this.query,
    this.filtered = false,
    required this.onClear,
  });

  final String? query;
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) =>
      SearchNoMatches(query: query, filtered: filtered, onClear: onClear);
}

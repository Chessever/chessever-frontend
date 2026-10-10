import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/utils/legible_ink.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/simple_search_bar.dart' show SpringHintWord;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    final word =
        _hintCycleFadingOut
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
          Flexible(child: SpringHintWord(word: word, style: style)),
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
                  color:
                      hasActiveFilters
                          ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                          : context.colors.background,
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(
                    color:
                        hasActiveFilters
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
                      color:
                          hasActiveFilters
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
                            color:
                                context.isLightTheme
                                    ? context.colors.danger
                                    : const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$activeFilterCount',
                              style: AppTypography.textXsBold.copyWith(
                                color:
                                    context.isLightTheme
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
                child: Center(
                  child: SvgPicture.asset(
                    SvgAsset.chase_grid,
                    width: 20.sp,
                    height: 20.sp,
                    colorFilter: ColorFilter.mode(
                      context.colors.textSecondary,
                      BlendMode.srcIn,
                    ),
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
    final filterRedColor =
        context.isLightTheme ? context.colors.danger : const Color(0xFFEF4444);
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

/// What the list shows when filters or a search leave no game.
class PlayerGamesNoMatches extends StatelessWidget {
  const PlayerGamesNoMatches({super.key, required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 56.sp,
            color: context.textInk(0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No matching games',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try adjusting your filters',
            style: AppTypography.textSmRegular.copyWith(
              color: context.textInk(0.55),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Text(
                'Clear Filters',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:flutter/material.dart';

/// Shows the game filter dialog and returns the selected filter or null if cancelled

Future<GameFilter?> showGameFilterDialog({
  required BuildContext context,
  required GameFilter currentFilter,
  bool showFormatFilter = true,
  bool showLiveFilter = true,
  bool showSortSection = false,
  bool showColorFilter = true,
  bool showSortDirection = true,
}) {
  return showAlertModal<GameFilter>(
    context: context,
    horizontalPadding: 0,
    child: GameFilterDialog(
      initialFilter: currentFilter,
      showFormatFilter: showFormatFilter,
      showLiveFilter: showLiveFilter,
      showSortSection: showSortSection,
      showColorFilter: showColorFilter,
      showSortDirection: showSortDirection,
    ),
  );
}

class GameFilterDialog extends StatefulWidget {
  const GameFilterDialog({
    super.key,
    required this.initialFilter,
    this.showFormatFilter = true,
    this.showLiveFilter = true,
    this.showSortSection = false,
    this.showColorFilter = true,
    this.showSortDirection = true,
  });

  final GameFilter initialFilter;
  final bool showFormatFilter;
  final bool showLiveFilter;
  final bool showSortSection;
  // Database/My-Likes contexts hide the Color filter and the asc/desc sort
  // direction toggle (sort stays Date-style descending). Other screens keep
  // both (defaults true).
  final bool showColorFilter;
  final bool showSortDirection;

  @override
  State<GameFilterDialog> createState() => _GameFilterDialogState();
}

class _GameFilterDialogState extends State<GameFilterDialog> {
  late GameResultFilter _result;
  late GameColorFilter _color;
  late GameTimeControlFilter _timeControl;
  late GameOnlineFilter _online;
  late GameLiveFilter _live;
  late RangeValues _yearRange;
  late int? _selectedMinRating;
  late List<GameSortCriterion> _sorts;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _result = widget.initialFilter.result;
    _color = widget.initialFilter.color;
    _timeControl = widget.initialFilter.timeControl;
    _online = widget.initialFilter.online;
    _live = widget.initialFilter.live;
    _yearRange = RangeValues(
      widget.initialFilter.minYear.toDouble(),
      widget.initialFilter.maxYear.toDouble(),
    );
    _selectedMinRating = RatingTierFilter.normalizeMinRating(
      widget.initialFilter.minRating,
    );
    _sorts = List<GameSortCriterion>.of(widget.initialFilter.sorts);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = 320.w;
    return _buildDialogCard(context, dialogWidth);
  }

  Widget _buildDialogCard(BuildContext context, double dialogWidth) {
    return Container(
      width: dialogWidth,
      constraints: BoxConstraints(maxHeight: 580.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              radius: Radius.circular(4.br),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Status (Live / Completed) — top priority when shown.
                    // In database/My-Likes contexts the caller drops this
                    // (saved games are always finished) and asks for Sort
                    // controls in its place via [showSortSection].
                    if (widget.showLiveFilter) ...[
                      _sectionLabel('Status'),
                      SizedBox(height: 8.h),
                      _chipGrid<GameLiveFilter>(
                        values: GameLiveFilter.values,
                        selected: _live,
                        label:
                            (v) =>
                                v == GameLiveFilter.all ? 'All' : v.displayText,
                        onTap: (v) {
                          HapticFeedbackService.selection();
                          setState(() => _live = v);
                        },
                      ),
                      SizedBox(height: 20.h),
                    ] else if (widget.showSortSection) ...[
                      _buildSortSection(),
                      SizedBox(height: 20.h),
                    ],

                    // 2. Time Control
                    _sectionLabel('Time Control'),
                    SizedBox(height: 8.h),
                    _chipGrid<GameTimeControlFilter>(
                      values: GameTimeControlFilter.values,
                      selected: _timeControl,
                      label:
                          (v) =>
                              v == GameTimeControlFilter.all
                                  ? 'All'
                                  : v.displayText,
                      onTap: (v) {
                        HapticFeedbackService.selection();
                        setState(() => _timeControl = v);
                      },
                    ),
                    SizedBox(height: 20.h),

                    // 3. Level
                    _sectionLabel('Level'),
                    SizedBox(height: 8.h),
                    RatingTierFilter(
                      selectedMinRating: _selectedMinRating,
                      onChanged: (value) {
                        HapticFeedbackService.selection();
                        setState(() => _selectedMinRating = value);
                      },
                    ),
                    SizedBox(height: 20.h),

                    // 4. Result (box grid)
                    _sectionLabel('Result'),
                    SizedBox(height: 8.h),
                    _chipGrid<GameResultFilter>(
                      values: GameResultFilter.values,
                      selected: _result,
                      label:
                          (v) =>
                              v == GameResultFilter.all ? 'All' : v.displayText,
                      onTap: (v) {
                        HapticFeedbackService.selection();
                        setState(() => _result = v);
                      },
                    ),
                    SizedBox(height: 20.h),

                    // 5. Color (box grid) — hidden in database/My-Likes
                    // contexts via [showColorFilter].
                    if (widget.showColorFilter) ...[
                      _sectionLabel('Color'),
                      SizedBox(height: 8.h),
                      _chipGrid<GameColorFilter>(
                        values: GameColorFilter.values,
                        selected: _color,
                        label:
                            (v) =>
                                v == GameColorFilter.all
                                    ? 'All'
                                    : v.displayText,
                        onTap: (v) {
                          HapticFeedbackService.selection();
                          setState(() => _color = v);
                        },
                      ),
                      SizedBox(height: 20.h),
                    ],

                    // 6. Format (online/OTB) — only when caller enables it
                    if (widget.showFormatFilter) ...[
                      _sectionLabel('Format'),
                      SizedBox(height: 8.h),
                      _chipGrid<GameOnlineFilter>(
                        values: GameOnlineFilter.values,
                        selected: _online,
                        label:
                            (v) =>
                                v == GameOnlineFilter.all
                                    ? 'All'
                                    : v.displayText,
                        onTap: (v) {
                          HapticFeedbackService.selection();
                          setState(() => _online = v);
                        },
                      ),
                      SizedBox(height: 20.h),
                    ],

                    // 7. Year range
                    _sectionLabel('Year'),
                    SizedBox(height: 8.h),
                    _rangeSliderCard(
                      values: _yearRange,
                      min: GameFilter.absoluteMinYear.toDouble(),
                      max: DateTime.now().year.toDouble(),
                      divisions:
                          DateTime.now().year - GameFilter.absoluteMinYear,
                      onChanged: (v) => setState(() => _yearRange = v),
                    ),
                    SizedBox(height: 12.h),
                  ],
                ),
              ),
            ),
          ),
          _buildButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 18.h, 12.w, 6.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Filters',
            style: AppTypography.textMdBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close_rounded,
              color: context.colors.textPrimary.withValues(alpha: 0.6),
              size: 20.ic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Padding(
      padding: EdgeInsets.all(20.sp),
      child: Row(
        children: [
          // Reset button
          Expanded(
            child: SizedBox(
              height: 48.h,
              child: OutlinedButton(
                onPressed: _resetFilters,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                  backgroundColor: context.colors.surface,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                ),
                child: Text(
                  'Reset',
                  style: AppTypography.textSmBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          // Apply button
          Expanded(
            child: SizedBox(
              height: 48.h,
              child: ElevatedButton(
                onPressed: _applyFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.textPrimary,
                  foregroundColor: kBlackColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                ),
                child: Text(
                  'Apply Filters',
                  style: AppTypography.textSmBold.copyWith(color: kBlackColor),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a [GameFilter] from the dialog's current local field state.
  /// Single source of truth for both Apply (what we return) and the
  /// "is anything active?" check that gates the Clear affordance — so adding
  /// a new field can't leave the two out of sync.
  GameFilter _currentLocalFilter() {
    return GameFilter(
      result: _result,
      // Color hidden → never carry a stale color filter (no UI to clear it).
      color: widget.showColorFilter ? _color : GameColorFilter.all,
      timeControl: _timeControl,
      online: _online,
      live: _live,
      minYear: _yearRange.start.round(),
      maxYear: _yearRange.end.round(),
      minRating: _selectedMinRating ?? GameFilter.defaultMinRating,
      maxRating: GameFilter.absoluteMaxRating,
      sorts: widget.showSortSection ? _sorts : const [],
    );
  }

  /// True when any filter or sort differs from the default — i.e. there is
  /// something for Clear to clear.
  bool get _hasAnythingToClear {
    final f = _currentLocalFilter();
    return f.hasActiveFilters || f.hasActiveSorts;
  }

  void _resetFilters() {
    HapticFeedbackService.buttonPress();
    // Return the default filter immediately (clears all filters) and close.
    Navigator.of(context).pop(GameFilter.defaultFilter());
  }

  /// Clear ALL filters and sorts in place, without closing the dialog — the
  /// in-dialog twin of Reset. Mirrors [GameFilter.defaultFilter] field-for-field
  /// so nothing is left behind (Reset previously cleared everything but Clear
  /// only cleared sorts).
  void _clearFilters() {
    FocusScope.of(context).unfocus();
    HapticFeedbackService.selection();
    setState(() {
      _result = GameResultFilter.all;
      _color = GameColorFilter.all;
      _timeControl = GameTimeControlFilter.all;
      _online = GameOnlineFilter.all;
      _live = GameLiveFilter.all;
      _yearRange = RangeValues(
        GameFilter.defaultMinYear.toDouble(),
        DateTime.now().year.toDouble(),
      );
      _selectedMinRating = RatingTierFilter.normalizeMinRating(
        GameFilter.defaultMinRating,
      );
      _sorts = const [];
    });
  }

  void _applyFilters() {
    FocusScope.of(context).unfocus();
    HapticFeedbackService.buttonPress();
    Navigator.of(context).pop(_currentLocalFilter());
  }

  String _sortFieldLabel(GamebaseSortField f) {
    switch (f) {
      case GamebaseSortField.date:
        return 'Date';
      case GamebaseSortField.whiteElo:
        return 'White Elo';
      case GamebaseSortField.blackElo:
        return 'Black Elo';
      case GamebaseSortField.avgElo:
        return 'Avg Elo';
    }
  }

  /// Single-key sort picker. Only ONE field can be active at a time — tapping
  /// a different field replaces the current sort. Tapping the active field
  /// cycles its direction (descending → ascending → removed) when direction is
  /// enabled, otherwise just toggles it off. (Kept as a 0/1-length list so the
  /// filter model and its consumers stay unchanged.)
  void _cycleSort(GamebaseSortField field) {
    HapticFeedbackService.selection();
    setState(() {
      final index = _sorts.indexWhere((s) => s.field == field);
      if (index < 0) {
        // A new field replaces any existing sort — single-select.
        _sorts = [GameSortCriterion(field: field)];
        return;
      }
      final current = _sorts[index];
      if (widget.showSortDirection &&
          current.direction == GamebaseSortDirection.desc) {
        _sorts = [current.copyWith(direction: GamebaseSortDirection.asc)];
        return;
      }
      _sorts = const [];
    });
  }

  Widget _buildSortSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('Sort'),
            const Spacer(),
            // Dialog-level Clear (Sort is the top section in sort-enabled
            // dialogs, so this reads as a global clear). Wipes every filter
            // AND sort in place — the no-close twin of Reset — and shows
            // whenever anything is non-default, not only when a sort is set.
            if (_hasAnythingToClear)
              GestureDetector(
                onTap: _clearFilters,
                child: Text(
                  'Clear',
                  style: AppTypography.textXsBold.copyWith(
                    color: kPrimaryColor,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: GamebaseSortField.values.map(_buildSortChip).toList(),
        ),
      ],
    );
  }

  Widget _buildSortChip(GamebaseSortField field) {
    final index = _sorts.indexWhere((s) => s.field == field);
    final isSelected = index >= 0;
    final criterion = isSelected ? _sorts[index] : null;

    return GestureDetector(
      onTap: () => _cycleSort(field),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryColor : context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(8.br),
        ),
        // The direction-arrow slot keeps a FIXED footprint whether or not the
        // chip is selected, so toggling only swaps slot CONTENT (and color),
        // never the chip's size — no Wrap reflow / sibling jump.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _sortFieldLabel(field),
              style: AppTypography.textXsMedium.copyWith(
                color: isSelected ? kBlackColor : context.colors.textPrimary,
              ),
            ),
            if (widget.showSortDirection) ...[
              SizedBox(width: 4.w),
              // Direction arrow slot (reserved even when unselected).
              SizedBox(
                width: 12.ic,
                height: 12.ic,
                child:
                    isSelected
                        ? Icon(
                          criterion!.direction == GamebaseSortDirection.asc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 12.ic,
                          color: kBlackColor,
                        )
                        : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.textSmMedium.copyWith(
        color: context.colors.textPrimary,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _chipGrid<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onTap,
  }) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children:
          values.map((v) {
            final isSelected = v == selected;
            return GestureDetector(
              onTap: () => onTap(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? kPrimaryColor
                          : context.colors.surfaceRecessed,
                  borderRadius: BorderRadius.circular(8.br),
                ),
                child: Text(
                  label(v),
                  style: AppTypography.textXsMedium.copyWith(
                    color:
                        isSelected ? kBlackColor : context.colors.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _rangeSliderCard({
    required RangeValues values,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<RangeValues> onChanged,
  }) {
    return WheelRangeFilter(
      minValue: min,
      maxValue: max,
      currentStart: values.start,
      currentEnd: values.end,
      divisions: divisions,
      onChanged: onChanged,
    );
  }
}

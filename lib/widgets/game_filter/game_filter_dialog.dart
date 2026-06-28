import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart';
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
  bool showTimeControlFilter = true,
  bool showSortSection = false,
  bool showColorFilter = true,
  bool showSortDirection = true,
  bool showLevelFilter = true,
  bool showYearFilter = true,
}) {
  return showAlertModal<GameFilter>(
    context: context,
    horizontalPadding: 0,
    child: GameFilterDialog(
      initialFilter: currentFilter,
      showFormatFilter: showFormatFilter,
      showLiveFilter: showLiveFilter,
      showTimeControlFilter: showTimeControlFilter,
      showSortSection: showSortSection,
      showColorFilter: showColorFilter,
      showSortDirection: showSortDirection,
      showLevelFilter: showLevelFilter,
      showYearFilter: showYearFilter,
    ),
  );
}

class GameFilterDialog extends StatefulWidget {
  const GameFilterDialog({
    super.key,
    required this.initialFilter,
    this.showFormatFilter = true,
    this.showLiveFilter = true,
    this.showTimeControlFilter = true,
    this.showSortSection = false,
    this.showColorFilter = true,
    this.showSortDirection = true,
    this.showLevelFilter = true,
    this.showYearFilter = true,
  });

  final GameFilter initialFilter;
  final bool showFormatFilter;
  final bool showLiveFilter;

  /// Hidden when the surrounding context already pins a time control (e.g. a
  /// smart event generated from a Blitz/Rapid/Classical filter).
  final bool showTimeControlFilter;
  final bool showSortSection;
  // Database/My-Likes contexts hide the Color filter and the asc/desc sort
  // direction toggle (sort stays Date-style descending). Other screens keep
  // both (defaults true).
  final bool showColorFilter;
  final bool showSortDirection;
  final bool showLevelFilter;
  final bool showYearFilter;

  @override
  State<GameFilterDialog> createState() => _GameFilterDialogState();
}

class _GameFilterDialogState extends State<GameFilterDialog> {
  late GameResultFilter _result;
  late GameColorFilter _color;
  late GameFinishFilter _finish;
  late GameTimeControlFilter _timeControl;
  late GameOnlineFilter _online;
  late GameLiveFilter _live;
  late GameEcoFilter _eco;
  late RangeValues _yearRange;
  late int? _selectedMinRating;
  late List<GameSortCriterion> _sorts;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _result = widget.initialFilter.result;
    _color = widget.initialFilter.color;
    _finish = widget.initialFilter.finish;
    _timeControl = widget.initialFilter.timeControl;
    _online = widget.initialFilter.online;
    _live = widget.initialFilter.live;
    _eco = widget.initialFilter.eco;
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
                    // Standard smart-game filter order:
                    // Time control → Avg. Rating → ECO / Opening → Finish → Result → Date range.
                    if (widget.showTimeControlFilter) ...[
                      _sectionLabel('Time Control'),
                      SizedBox(height: 8.h),
                      _chipGrid<GameTimeControlFilter>(
                        values: GameTimeControlFilter.values,
                        selected: _timeControl,
                        label: (v) => v == GameTimeControlFilter.all
                            ? 'All'
                            : v.displayText,
                        onTap: (v) {
                          HapticFeedbackService.selection();
                          setState(() => _timeControl = v);
                        },
                      ),
                      SizedBox(height: 20.h),
                    ],

                    if (widget.showLevelFilter) ...[
                      _sectionLabel('Avg. Rating'),
                      SizedBox(height: 8.h),
                      RatingTierFilter(
                        selectedMinRating: _selectedMinRating,
                        onChanged: (value) {
                          HapticFeedbackService.selection();
                          setState(() => _selectedMinRating = value);
                        },
                      ),
                      SizedBox(height: 20.h),
                    ],

                    _sectionLabel('ECO / Opening'),
                    SizedBox(height: 8.h),
                    EcoFilterDropdown(
                      value: _eco,
                      onChanged: (value) {
                        HapticFeedbackService.selection();
                        setState(() => _eco = value);
                      },
                    ),
                    SizedBox(height: 20.h),

                    _sectionLabel('Finish'),
                    SizedBox(height: 8.h),
                    _chipGrid<GameFinishFilter>(
                      values: GameFinishFilter.values,
                      selected: _finish,
                      label: (v) => v.displayText,
                      onTap: (v) {
                        HapticFeedbackService.selection();
                        setState(() => _finish = v);
                      },
                    ),
                    SizedBox(height: 20.h),

                    _sectionLabel('Result'),
                    SizedBox(height: 8.h),
                    _chipGrid<GameResultFilter>(
                      values: GameResultFilter.values,
                      selected: _result,
                      label: (v) =>
                          v == GameResultFilter.all ? 'All' : v.displayText,
                      onTap: (v) {
                        HapticFeedbackService.selection();
                        setState(() => _result = v);
                      },
                    ),
                    SizedBox(height: 20.h),

                    if (widget.showColorFilter) ...[
                      _sectionLabel('Color'),
                      SizedBox(height: 8.h),
                      _chipGrid<GameColorFilter>(
                        values: GameColorFilter.values,
                        selected: _color,
                        label: (v) =>
                            v == GameColorFilter.all ? 'All' : v.displayText,
                        onTap: (v) {
                          HapticFeedbackService.selection();
                          setState(() => _color = v);
                        },
                      ),
                      SizedBox(height: 20.h),
                    ],

                    if (widget.showLiveFilter) ...[
                      _sectionLabel('Status'),
                      SizedBox(height: 8.h),
                      _chipGrid<GameLiveFilter>(
                        values: GameLiveFilter.values,
                        selected: _live,
                        label: (v) =>
                            v == GameLiveFilter.all ? 'All' : v.displayText,
                        onTap: (v) {
                          HapticFeedbackService.selection();
                          setState(() => _live = v);
                        },
                      ),
                      SizedBox(height: 20.h),
                    ],

                    if (widget.showSortSection) ...[
                      _buildSortSection(),
                      SizedBox(height: 20.h),
                    ],

                    if (widget.showFormatFilter) ...[
                      _sectionLabel('Format'),
                      SizedBox(height: 8.h),
                      _chipGrid<GameOnlineFilter>(
                        values: GameOnlineFilter.values,
                        selected: _online,
                        label: (v) =>
                            v == GameOnlineFilter.all ? 'All' : v.displayText,
                        onTap: (v) {
                          HapticFeedbackService.selection();
                          setState(() => _online = v);
                        },
                      ),
                      SizedBox(height: 20.h),
                    ],

                    // 7. Year range
                    if (widget.showYearFilter) ...[
                      _sectionLabel('Date Range'),
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
      finish: _finish,
      eco: _eco,
      // Same rule for a hidden Time Control section.
      timeControl: widget.showTimeControlFilter
          ? _timeControl
          : GameTimeControlFilter.all,
      online: _online,
      live: _live,
      minYear: widget.showYearFilter
          ? _yearRange.start.round()
          : GameFilter.defaultMinYear,
      maxYear: widget.showYearFilter
          ? _yearRange.end.round()
          : DateTime.now().year,
      minRating: widget.showLevelFilter
          ? _selectedMinRating ?? GameFilter.defaultMinRating
          : GameFilter.defaultMinRating,
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
      _finish = GameFinishFilter.all;
      _timeControl = GameTimeControlFilter.all;
      _online = GameOnlineFilter.all;
      _live = GameLiveFilter.all;
      _eco = GameEcoFilter.all;
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
        _adaptiveChipLayout(
          measureLabels: GamebaseSortField.values.map(_sortFieldLabel).toList(),
          extraPerChip: widget.showSortDirection ? 4.w + 12.ic : 0,
          chipsBuilder: (expanded) => GamebaseSortField.values
              .map((f) => _buildSortChip(f, expanded: expanded))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildSortChip(GamebaseSortField field, {required bool expanded}) {
    final index = _sorts.indexWhere((s) => s.field == field);
    final isSelected = index >= 0;
    final criterion = isSelected ? _sorts[index] : null;

    return GestureDetector(
      onTap: () => _cycleSort(field),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        alignment: expanded ? Alignment.center : null,
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
                child: isSelected
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

  /// Lays a section's chips on one content-hugging row when they fit;
  /// otherwise switches to a tidy two-per-row grid of equal-width cells.
  /// A ragged Wrap (three chips plus one dangling onto the next line) reads
  /// as misalignment in a 320-wide dialog, so overflow always realigns to
  /// the grid. [extraPerChip] accounts for non-text chip content (e.g. the
  /// sort chips' reserved direction-arrow slot).
  Widget _adaptiveChipLayout({
    required List<String> measureLabels,
    required List<Widget> Function(bool expanded) chipsBuilder,
    double extraPerChip = 0,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        var total = 8.w * (measureLabels.length - 1);
        for (final label in measureLabels) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: AppTypography.textXsMedium),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
          )..layout();
          total += painter.width + 28.w + extraPerChip;
        }

        if (total <= constraints.maxWidth) {
          return Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: chipsBuilder(false),
          );
        }

        final chips = chipsBuilder(true);
        return Column(
          children: [
            for (var i = 0; i < chips.length; i += 2) ...[
              if (i > 0) SizedBox(height: 8.h),
              Row(
                children: [
                  Expanded(child: chips[i]),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: i + 1 < chips.length
                        ? chips[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _chipGrid<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onTap,
  }) {
    return _adaptiveChipLayout(
      measureLabels: values.map(label).toList(),
      chipsBuilder: (expanded) => values.map((v) {
        final isSelected = v == selected;
        return GestureDetector(
          onTap: () => onTap(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            // Equal-width grid cells center their label; row chips
            // hug their content as before.
            alignment: expanded ? Alignment.center : null,
            decoration: BoxDecoration(
              color: isSelected
                  ? kPrimaryColor
                  : context.colors.surfaceRecessed,
              borderRadius: BorderRadius.circular(8.br),
            ),
            child: Text(
              label(v),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXsMedium.copyWith(
                color: isSelected ? kBlackColor : context.colors.textPrimary,
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

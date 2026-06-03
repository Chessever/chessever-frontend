import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

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
  return showDialog<GameFilter>(
    context: context,
    barrierColor: Colors.transparent,
    builder:
        (_) => GameFilterDialog(
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
  double _targetValue = 0.0;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _targetValue = 1.0);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = 320.w;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          const Positioned.fill(child: BackDropFilterWidget()),
          Center(
            child: GestureDetector(
              onTap: () {},
              child: SingleMotionBuilder(
                motion: const CupertinoMotion.smooth(),
                value: _targetValue,
                builder: (context, value, _) {
                  final scale = 0.95 + (0.05 * value);
                  final opacity = value.clamp(0.0, 1.0).toDouble();
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: _buildDialogCard(context, dialogWidth),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogCard(BuildContext context, double dialogWidth) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(maxHeight: 580.h),
        decoration: BoxDecoration(
          color: kBlackColor,
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(
            color: context.colors.surfaceRecessed.withValues(alpha: 0.3),
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
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.w,
                    vertical: 8.h,
                  ),
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
                          label: (v) =>
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
                        label: (v) => v == GameTimeControlFilter.all
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
                        label: (v) =>
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
                          label: (v) =>
                              v == GameColorFilter.all ? 'All' : v.displayText,
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
                          label: (v) => v == GameOnlineFilter.all
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
            style: AppTypography.textMdBold.copyWith(color: context.colors.textPrimary),
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
                  style: AppTypography.textSmBold.copyWith(color: context.colors.textPrimary),
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

  void _resetFilters() {
    HapticFeedbackService.buttonPress();
    // Return the default filter immediately (clears all filters)
    Navigator.of(context).pop(GameFilter.defaultFilter());
  }

  void _applyFilters() {
    FocusScope.of(context).unfocus();
    HapticFeedbackService.buttonPress();
    final newFilter = GameFilter(
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
    Navigator.of(context).pop(newFilter);
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

  /// Multi-key sort picker. Tapping a field appends it to the ordered sort
  /// list (primary first). Tapping a selected field cycles its direction
  /// (descending → ascending → removed) when direction is enabled, otherwise
  /// just toggles it off. Each selected chip shows its 1-based priority and,
  /// when enabled, an arrow for its direction.
  void _cycleSort(GamebaseSortField field) {
    HapticFeedbackService.selection();
    setState(() {
      final index = _sorts.indexWhere((s) => s.field == field);
      if (index < 0) {
        _sorts = [..._sorts, GameSortCriterion(field: field)];
        return;
      }
      final current = _sorts[index];
      if (widget.showSortDirection &&
          current.direction == GamebaseSortDirection.desc) {
        final updated = [..._sorts];
        updated[index] =
            current.copyWith(direction: GamebaseSortDirection.asc);
        _sorts = updated;
        return;
      }
      _sorts = [..._sorts]..removeAt(index);
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
            if (_sorts.isNotEmpty)
              GestureDetector(
                onTap: () {
                  HapticFeedbackService.selection();
                  setState(() => _sorts = const []);
                },
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Container(
                width: 16.w,
                height: 16.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kBlackColor.withValues(alpha: 0.28),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: AppTypography.textXsBold.copyWith(
                    color: kBlackColor,
                    fontSize: 9.sp,
                    height: 1,
                  ),
                ),
              ),
              SizedBox(width: 6.w),
            ],
            Text(
              _sortFieldLabel(field),
              style: AppTypography.textXsMedium.copyWith(
                color: isSelected ? kBlackColor : context.colors.textPrimary,
              ),
            ),
            if (isSelected && widget.showSortDirection) ...[
              SizedBox(width: 4.w),
              Icon(
                criterion!.direction == GamebaseSortDirection.asc
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 12.ic,
                color: kBlackColor,
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
      children: values.map((v) {
        final isSelected = v == selected;
        return GestureDetector(
          onTap: () => onTap(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: isSelected ? kPrimaryColor : context.colors.surfaceRecessed,
              borderRadius: BorderRadius.circular(8.br),
            ),
            child: Text(
              label(v),
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

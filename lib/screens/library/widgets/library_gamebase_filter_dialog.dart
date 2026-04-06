import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/game_filter/expandable_filter_dropdown.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Filter model for Gamebase library search.
/// Supports only filters available in the Gamebase API:
/// - result (1-0, 0-1, ½-½)
/// - color (all, white, black)
/// - timeControl (CLASSICAL, RAPID, BLITZ)
/// - yearFrom/yearTo
/// - ratingFrom/ratingTo
class GamebaseFilter {
  GamebaseFilter({
    this.tournamentType = GameTournamentTypeFilter.all,
    this.result = GameResultFilter.all,
    this.color = GameColorFilter.all,
    this.timeControl = GameTimeControlFilter.all,
    this.minYear = 1800,
    int? maxYear,
    this.minRating = 0,
    this.maxRating = 3500,
  }) : maxYear = maxYear ?? DateTime.now().year;

  final GameTournamentTypeFilter tournamentType;
  final GameResultFilter result;
  final GameColorFilter color;
  final GameTimeControlFilter timeControl;
  final int minYear;
  final int maxYear;
  final int minRating;
  final int maxRating;

  /// Check if any filter is active (not default)
  bool get hasActiveFilters =>
      tournamentType != GameTournamentTypeFilter.all ||
      result != GameResultFilter.all ||
      color != GameColorFilter.all ||
      timeControl != GameTimeControlFilter.all ||
      minYear != 1800 ||
      maxYear != DateTime.now().year ||
      minRating != 0 ||
      maxRating != 3500;

  /// Count of active filters
  int get activeFilterCount {
    int count = 0;
    if (tournamentType != GameTournamentTypeFilter.all) count++;
    if (result != GameResultFilter.all) count++;
    if (color != GameColorFilter.all) count++;
    if (timeControl != GameTimeControlFilter.all) count++;
    if (minYear != 1800 || maxYear != DateTime.now().year) count++;
    if (minRating != 0 || maxRating != 3500) count++;
    return count;
  }

  GamebaseFilter copyWith({
    GameTournamentTypeFilter? tournamentType,
    GameResultFilter? result,
    GameColorFilter? color,
    GameTimeControlFilter? timeControl,
    int? minYear,
    int? maxYear,
    int? minRating,
    int? maxRating,
  }) {
    return GamebaseFilter(
      tournamentType: tournamentType ?? this.tournamentType,
      result: result ?? this.result,
      color: color ?? this.color,
      timeControl: timeControl ?? this.timeControl,
      minYear: minYear ?? this.minYear,
      maxYear: maxYear ?? this.maxYear,
      minRating: minRating ?? this.minRating,
      maxRating: maxRating ?? this.maxRating,
    );
  }

  /// Convert result to Gamebase API format
  String? get resultApiValue {
    switch (result) {
      case GameResultFilter.all:
        return null;
      case GameResultFilter.whiteWins:
        return 'W';
      case GameResultFilter.blackWins:
        return 'B';
      case GameResultFilter.draw:
        return 'D';
    }
  }

  /// Convert color to Gamebase API format
  String? get colorApiValue {
    switch (color) {
      case GameColorFilter.all:
        return null;
      case GameColorFilter.white:
        return 'white';
      case GameColorFilter.black:
        return 'black';
    }
  }

  /// Convert time control to Gamebase API format
  String? get timeControlApiValue {
    switch (timeControl) {
      case GameTimeControlFilter.all:
        return null;
      case GameTimeControlFilter.classical:
        return 'CLASSICAL';
      case GameTimeControlFilter.rapid:
        return 'RAPID';
      case GameTimeControlFilter.blitz:
        return 'BLITZ';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GamebaseFilter &&
        other.tournamentType == tournamentType &&
        other.result == result &&
        other.color == color &&
        other.timeControl == timeControl &&
        other.minYear == minYear &&
        other.maxYear == maxYear &&
        other.minRating == minRating &&
        other.maxRating == maxRating;
  }

  @override
  int get hashCode => Object.hash(
    tournamentType,
    result,
    color,
    timeControl,
    minYear,
    maxYear,
    minRating,
    maxRating,
  );
}

/// Shows the gamebase filter dialog and returns the selected filter or null if cancelled
Future<GamebaseFilter?> showLibraryGamebaseFilterDialog({
  required BuildContext context,
  required GamebaseFilter currentFilter,
}) {
  return showDialog<GamebaseFilter>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => LibraryGamebaseFilterDialog(initialFilter: currentFilter),
  );
}

class LibraryGamebaseFilterDialog extends StatefulWidget {
  const LibraryGamebaseFilterDialog({super.key, required this.initialFilter});

  final GamebaseFilter initialFilter;

  @override
  State<LibraryGamebaseFilterDialog> createState() =>
      _LibraryGamebaseFilterDialogState();
}

class _LibraryGamebaseFilterDialogState
    extends State<LibraryGamebaseFilterDialog> {
  late GameTournamentTypeFilter _tournamentType;
  late GameResultFilter _result;
  late GameColorFilter _color;
  late GameTimeControlFilter _timeControl;
  late RangeValues _yearRange;
  late RangeValues _ratingRange;

  final ScrollController _scrollController = ScrollController();
  double _targetValue = 0.0;

  @override
  void initState() {
    super.initState();
    _tournamentType = widget.initialFilter.tournamentType;
    _result = widget.initialFilter.result;
    _color = widget.initialFilter.color;
    _timeControl = widget.initialFilter.timeControl;
    _yearRange = RangeValues(
      widget.initialFilter.minYear.toDouble(),
      widget.initialFilter.maxYear.toDouble(),
    );
    _ratingRange = RangeValues(
      widget.initialFilter.minRating.toDouble(),
      widget.initialFilter.maxRating.toDouble(),
    );

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
        constraints: BoxConstraints(maxHeight: 560.h),
        decoration: BoxDecoration(
          color: kBackgroundColor,
          borderRadius: BorderRadius.circular(4.br),
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
                      // Result filter
                      _sectionLabel('Result'),
                      SizedBox(height: 8.h),
                      ExpandableFilterDropdown<GameResultFilter>(
                        value: _result,
                        items: GameResultFilter.values,
                        itemLabel: (v) => v.displayText,
                        onChanged: (v) => setState(() => _result = v),
                      ),
                      SizedBox(height: 20.h),

                      // Color filter
                      _sectionLabel('Color'),
                      SizedBox(height: 8.h),
                      ExpandableFilterDropdown<GameColorFilter>(
                        value: _color,
                        items: GameColorFilter.values,
                        itemLabel: (v) => v.displayText,
                        onChanged: (v) => setState(() => _color = v),
                      ),
                      SizedBox(height: 20.h),

                      // Time Control filter
                      _sectionLabel('Time Control'),
                      SizedBox(height: 8.h),
                      ExpandableFilterDropdown<GameTimeControlFilter>(
                        value: _timeControl,
                        items: GameTimeControlFilter.values,
                        itemLabel: (v) => v.displayText,
                        itemAssetPath: (v) => v.assetPath,
                        onChanged: (v) => setState(() => _timeControl = v),
                      ),
                      SizedBox(height: 20.h),

                      // Year range slider
                      _sectionLabel('Year'),
                      SizedBox(height: 8.h),
                      _rangeSliderCard(
                        values: _yearRange,
                        min: 1800,
                        max: DateTime.now().year.toDouble(),
                        divisions: DateTime.now().year - 1800,
                        onChanged: (v) => setState(() => _yearRange = v),
                      ),
                      SizedBox(height: 20.h),

                      // Rating range slider
                      _sectionLabel('Rating'),
                      SizedBox(height: 8.h),
                      _rangeSliderCard(
                        values: _ratingRange,
                        min: 0,
                        max: 3500,
                        divisions: 70,
                        onChanged: (v) => setState(() => _ratingRange = v),
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
            style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close_rounded,
              color: kWhiteColor.withValues(alpha: 0.6),
              size: 20.ic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
      child: Row(
        children: [
          // Reset button — CSS: bg #1A1A1C, radius 4px
          Expanded(
            child: GestureDetector(
              onTap: _resetFilters,
              child: Container(
                height: 40.h,
                decoration: BoxDecoration(
                  color: kBlack2Color,
                  borderRadius: BorderRadius.circular(4.br),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Reset',
                  style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
                ),
              ),
            ),
          ),
          SizedBox(width: 16.w),
          // Apply button — CSS: bg white, radius 4px
          Expanded(
            child: GestureDetector(
              onTap: _applyFilters,
              child: Container(
                height: 40.h,
                decoration: BoxDecoration(
                  color: kWhiteColor,
                  borderRadius: BorderRadius.circular(4.br),
                ),
                alignment: Alignment.center,
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
    Navigator.of(context).pop(GamebaseFilter());
  }

  void _applyFilters() {
    HapticFeedbackService.buttonPress();
    final newFilter = GamebaseFilter(
      tournamentType: _tournamentType,
      result: _result,
      color: _color,
      timeControl: _timeControl,
      minYear: _yearRange.start.round(),
      maxYear: _yearRange.end.round(),
      minRating: _ratingRange.start.round(),
      maxRating: _ratingRange.end.round(),
    );
    Navigator.of(context).pop(newFilter);
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.textSmMedium.copyWith(
        color: kWhiteColor,
        letterSpacing: 0.3,
      ),
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

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart';
import 'package:chessever2/widgets/game_filter/expandable_filter_dropdown.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
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
    this.isOnline = GameOnlineFilter.all,
    GameEcoFilter? eco,
    this.minYear = GameFilter.defaultMinYear,
    int? maxYear,
    this.minRating = GameFilter.defaultMinRating,
    this.maxRating = GameFilter.absoluteMaxRating,
  }) : eco = eco ?? GameEcoFilter.all,
       maxYear = maxYear ?? DateTime.now().year;

  final GameTournamentTypeFilter tournamentType;
  final GameResultFilter result;
  final GameColorFilter color;
  final GameTimeControlFilter timeControl;
  final GameOnlineFilter isOnline;
  final GameEcoFilter eco;
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
      isOnline != GameOnlineFilter.all ||
      !eco.isAll ||
      minYear != GameFilter.defaultMinYear ||
      maxYear != DateTime.now().year ||
      minRating != GameFilter.defaultMinRating ||
      maxRating != GameFilter.absoluteMaxRating;

  /// Count of active filters
  int get activeFilterCount {
    int count = 0;
    if (tournamentType != GameTournamentTypeFilter.all) count++;
    if (result != GameResultFilter.all) count++;
    if (color != GameColorFilter.all) count++;
    if (timeControl != GameTimeControlFilter.all) count++;
    if (isOnline != GameOnlineFilter.all) count++;
    if (!eco.isAll) count++;
    if (minYear != GameFilter.defaultMinYear || maxYear != DateTime.now().year)
      count++;
    if (minRating != GameFilter.defaultMinRating ||
        maxRating != GameFilter.absoluteMaxRating)
      count++;
    return count;
  }

  GamebaseFilter copyWith({
    GameTournamentTypeFilter? tournamentType,
    GameResultFilter? result,
    GameColorFilter? color,
    GameTimeControlFilter? timeControl,
    GameOnlineFilter? isOnline,
    GameEcoFilter? eco,
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
      isOnline: isOnline ?? this.isOnline,
      eco: eco ?? this.eco,
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

  /// Convert online filter to Gamebase API format
  bool? get isOnlineApiValue {
    switch (isOnline) {
      case GameOnlineFilter.all:
        return null;
      case GameOnlineFilter.online:
        return true;
      case GameOnlineFilter.otb:
        return false;
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
        other.isOnline == isOnline &&
        other.eco == eco &&
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
    isOnline,
    eco,
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
  late GameOnlineFilter _isOnline;
  late GameEcoFilter _eco;
  late RangeValues _yearRange;
  late int? _selectedMinRating;

  final ScrollController _scrollController = ScrollController();
  double _targetValue = 0.0;

  @override
  void initState() {
    super.initState();
    _tournamentType = widget.initialFilter.tournamentType;
    _result = widget.initialFilter.result;
    _color = widget.initialFilter.color;
    _timeControl = widget.initialFilter.timeControl;
    _isOnline = widget.initialFilter.isOnline;
    _eco = widget.initialFilter.eco;
    _yearRange = RangeValues(
      widget.initialFilter.minYear.toDouble(),
      widget.initialFilter.maxYear.toDouble(),
    );
    _selectedMinRating = RatingTierFilter.normalizeMinRating(
      widget.initialFilter.minRating,
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

                      // Online filter
                      _sectionLabel('Format'),
                      SizedBox(height: 8.h),
                      ExpandableFilterDropdown<GameOnlineFilter>(
                        value: _isOnline,
                        items: GameOnlineFilter.values,
                        itemLabel: (v) => v.displayText,
                        onChanged: (v) => setState(() => _isOnline = v),
                      ),
                      SizedBox(height: 20.h),

                      // ECO filter
                      _sectionLabel('Opening'),
                      SizedBox(height: 8.h),
                      EcoFilterDropdown(
                        value: _eco,
                        onChanged: (v) => setState(() => _eco = v),
                      ),
                      SizedBox(height: 20.h),

                      // Year range slider
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
                      SizedBox(height: 20.h),

                      _sectionLabel('Level'),
                      SizedBox(height: 8.h),
                      RatingTierFilter(
                        selectedMinRating: _selectedMinRating,
                        onChanged: (value) {
                          HapticFeedbackService.selection();
                          setState(() => _selectedMinRating = value);
                        },
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
    final activeChipWidgets = <Widget>[];

    Widget buildChip(String label, VoidCallback onRemove) {
      return GestureDetector(
        onTap: () {
          HapticFeedbackService.buttonPress();
          onRemove();
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: kPrimaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4.br),
            border: Border.all(color: kPrimaryColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.textXsMedium.copyWith(
                  color: kPrimaryColor,
                ),
              ),
              SizedBox(width: 4.w),
              Icon(Icons.close_rounded, color: kPrimaryColor, size: 14.ic),
            ],
          ),
        ),
      );
    }

    if (_result != GameResultFilter.all) {
      activeChipWidgets.add(
        buildChip('Result: ${_result.displayText}', () {
          setState(() => _result = GameResultFilter.all);
        }),
      );
    }
    if (_color != GameColorFilter.all) {
      activeChipWidgets.add(
        buildChip('Color: ${_color.displayText}', () {
          setState(() => _color = GameColorFilter.all);
        }),
      );
    }
    if (_timeControl != GameTimeControlFilter.all) {
      activeChipWidgets.add(
        buildChip('TC: ${_timeControl.displayText}', () {
          setState(() => _timeControl = GameTimeControlFilter.all);
        }),
      );
    }
    if (_isOnline != GameOnlineFilter.all) {
      activeChipWidgets.add(
        buildChip('Format: ${_isOnline.displayText}', () {
          setState(() => _isOnline = GameOnlineFilter.all);
        }),
      );
    }
    if (!_eco.isAll) {
      activeChipWidgets.add(
        buildChip('ECO: ${_eco.code}', () {
          setState(() => _eco = GameEcoFilter.all);
        }),
      );
    }
    if (_yearRange.start > GameFilter.defaultMinYear ||
        _yearRange.end < DateTime.now().year) {
      activeChipWidgets.add(
        buildChip(
          'Year: ${_yearRange.start.round()}-${_yearRange.end.round()}',
          () {
            setState(
              () =>
                  _yearRange = RangeValues(
                    GameFilter.defaultMinYear.toDouble(),
                    DateTime.now().year.toDouble(),
                  ),
            );
          },
        ),
      );
    }
    final ratingLabel = RatingTierFilter.labelForMinRating(_selectedMinRating);
    if (ratingLabel != null) {
      activeChipWidgets.add(
        buildChip('Level: $ratingLabel', () {
          setState(() => _selectedMinRating = null);
        }),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 18.h, 12.w, 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (activeChipWidgets.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Wrap(spacing: 6.w, runSpacing: 6.h, children: activeChipWidgets),
            SizedBox(height: 4.h),
          ],
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
    FocusScope.of(context).unfocus();
    HapticFeedbackService.buttonPress();
    final newFilter = GamebaseFilter(
      tournamentType: _tournamentType,
      result: _result,
      color: _color,
      timeControl: _timeControl,
      isOnline: _isOnline,
      eco: _eco,
      minYear: _yearRange.start.round(),
      maxYear: _yearRange.end.round(),
      minRating: _selectedMinRating ?? GameFilter.defaultMinRating,
      maxRating: GameFilter.absoluteMaxRating,
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

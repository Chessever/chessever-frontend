import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart';
import 'package:chessever2/widgets/game_filter/expandable_filter_dropdown.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Shows the game filter dialog and returns the selected filter or null if cancelled
Future<GameFilter?> showGameFilterDialog({
  required BuildContext context,
  required GameFilter currentFilter,
}) {
  return showDialog<GameFilter>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => GameFilterDialog(
      initialFilter: currentFilter,
    ),
  );
}

class GameFilterDialog extends StatefulWidget {
  const GameFilterDialog({
    super.key,
    required this.initialFilter,
  });

  final GameFilter initialFilter;

  @override
  State<GameFilterDialog> createState() => _GameFilterDialogState();
}

class _GameFilterDialogState extends State<GameFilterDialog> {
  late GameResultFilter _result;
  late GameColorFilter _color;
  late GameTimeControlFilter _timeControl;
  late GameEcoFilter _eco;
  late RangeValues _yearRange;
  late RangeValues _ratingRange;

  final ScrollController _scrollController = ScrollController();
  double _targetValue = 0.0;

  @override
  void initState() {
    super.initState();
    _result = widget.initialFilter.result;
    _color = widget.initialFilter.color;
    _timeControl = widget.initialFilter.timeControl;
    _eco = widget.initialFilter.eco;
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
        constraints: BoxConstraints(maxHeight: 580.h),
        decoration: BoxDecoration(
          color: kBlackColor,
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(
            color: kDarkGreyColor.withValues(alpha: 0.3),
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
                        min: 1990,
                        max: DateTime.now().year.toDouble(),
                        divisions: DateTime.now().year - 1990,
                        labelStart: _yearRange.start.round().toString(),
                        labelEnd: _yearRange.end.round().toString(),
                        onChanged: (v) => setState(() => _yearRange = v),
                      ),
                      // Rating range slider
                      SizedBox(height: 20.h),
                      _sectionLabel('Rating'),
                      SizedBox(height: 8.h),
                      _rangeSliderCard(
                        values: _ratingRange,
                        min: 1000,
                        max: 3500,
                        divisions: 50,
                        labelStart: _ratingRange.start.round().toString(),
                        labelEnd: _ratingRange.end.round().toString(),
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
                  foregroundColor: kWhiteColor,
                  backgroundColor: kBlack2Color,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                ),
                child: Text(
                  'Reset',
                  style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
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
                  backgroundColor: kWhiteColor,
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
    HapticFeedbackService.buttonPress();
    final newFilter = GameFilter(
      result: _result,
      color: _color,
      timeControl: _timeControl,
      eco: _eco,
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
    required String labelStart,
    required String labelEnd,
    required ValueChanged<RangeValues> onChanged,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kDividerColor),
      ),
      child: Column(
        children: [
          // Labels showing current range values
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                labelStart,
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
              ),
              Text(
                labelEnd,
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          // Range slider
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: kWhiteColor,
              inactiveTrackColor: kDividerColor,
              thumbColor: kWhiteColor,
              overlayColor: kWhiteColor.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              rangeThumbShape: const RoundRangeSliderThumbShape(
                enabledThumbRadius: 10,
              ),
              rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
            ),
            child: RangeSlider(
              values: values,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

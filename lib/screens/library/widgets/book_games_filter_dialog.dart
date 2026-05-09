import 'package:chessever2/screens/library/providers/book_games_search_provider.dart';
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

Future<BookGamesFilter?> showBookGamesFilterDialog({
  required BuildContext context,
  required BookGamesFilter currentFilter,
}) {
  return showDialog<BookGamesFilter>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => BookGamesFilterDialog(initialFilter: currentFilter),
  );
}

class BookGamesFilterDialog extends StatefulWidget {
  const BookGamesFilterDialog({super.key, required this.initialFilter});

  final BookGamesFilter initialFilter;

  @override
  State<BookGamesFilterDialog> createState() => _BookGamesFilterDialogState();
}

class _BookGamesFilterDialogState extends State<BookGamesFilterDialog> {
  late BookGamesResultFilter _result;
  late BookGamesColorFilter _color;
  late BookGamesTimeControlFilter _timeControl;
  late RangeValues _yearRange;
  late int? _selectedMinRating;
  late final TextEditingController _openingController;
  late final TextEditingController _ecoController;
  late final TextEditingController _eventController;
  late final TextEditingController _playerController;
  late final TextEditingController _federationController;

  double _targetValue = 0.0;

  @override
  void initState() {
    super.initState();
    _result = widget.initialFilter.result;
    _color = widget.initialFilter.color;
    _timeControl = widget.initialFilter.timeControl;
    _yearRange = RangeValues(
      widget.initialFilter.minYear.toDouble(),
      widget.initialFilter.maxYear.toDouble(),
    );
    _selectedMinRating = RatingTierFilter.normalizeMinRating(
      widget.initialFilter.minRating,
    );

    _openingController = TextEditingController(
      text: widget.initialFilter.opening,
    );
    _ecoController = TextEditingController(text: widget.initialFilter.eco);
    _eventController = TextEditingController(text: widget.initialFilter.event);
    _playerController = TextEditingController(
      text: widget.initialFilter.player,
    );
    _federationController = TextEditingController(
      text: widget.initialFilter.federation,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _targetValue = 1.0);
      }
    });
  }

  @override
  void dispose() {
    _openingController.dispose();
    _ecoController.dispose();
    _eventController.dispose();
    _playerController.dispose();
    _federationController.dispose();
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
          color: kBlackColor,
          borderRadius: BorderRadius.circular(12.br),
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
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('Result'),
                    SizedBox(height: 8.h),
                    _dropdown<BookGamesResultFilter>(
                      value: _result,
                      items: BookGamesResultFilter.values,
                      itemLabel: (v) => v.displayText,
                      onChanged: (v) => setState(() => _result = v),
                    ),
                    SizedBox(height: 16.h),

                    _sectionLabel('Color'),
                    SizedBox(height: 8.h),
                    _dropdown<BookGamesColorFilter>(
                      value: _color,
                      items: BookGamesColorFilter.values,
                      itemLabel: (v) => v.displayText,
                      onChanged: (v) => setState(() => _color = v),
                    ),
                    SizedBox(height: 16.h),

                    _sectionLabel('Time Control'),
                    SizedBox(height: 8.h),
                    _dropdown<BookGamesTimeControlFilter>(
                      value: _timeControl,
                      items: BookGamesTimeControlFilter.values,
                      itemLabel: (v) => v.displayText,
                      onChanged: (v) => setState(() => _timeControl = v),
                    ),
                    SizedBox(height: 16.h),

                    _sectionLabel('Year'),
                    SizedBox(height: 8.h),
                    _rangeSlider(
                      values: _yearRange,
                      min: GameFilter.absoluteMinYear.toDouble(),
                      max: DateTime.now().year.toDouble(),
                      divisions:
                          DateTime.now().year - GameFilter.absoluteMinYear,
                      onChanged: (v) => setState(() => _yearRange = v),
                    ),
                    SizedBox(height: 16.h),

                    _sectionLabel('Level'),
                    SizedBox(height: 8.h),
                    RatingTierFilter(
                      selectedMinRating: _selectedMinRating,
                      onChanged: (value) {
                        HapticFeedbackService.selection();
                        setState(() => _selectedMinRating = value);
                      },
                    ),
                    SizedBox(height: 16.h),

                    _sectionLabel('Opening / ECO'),
                    SizedBox(height: 8.h),
                    _textField(
                      controller: _openingController,
                      hintText: 'Opening (e.g., Sicilian Defense)',
                    ),
                    SizedBox(height: 8.h),
                    _textField(
                      controller: _ecoController,
                      hintText: 'ECO code (e.g., B07)',
                    ),
                    SizedBox(height: 16.h),

                    _sectionLabel('Event / Tournament'),
                    SizedBox(height: 8.h),
                    _textField(
                      controller: _eventController,
                      hintText: 'Event (e.g., Candidates 2024)',
                    ),
                    SizedBox(height: 16.h),

                    _sectionLabel('Player'),
                    SizedBox(height: 8.h),
                    _textField(
                      controller: _playerController,
                      hintText: 'Player name or FIDE ID',
                    ),
                    SizedBox(height: 16.h),

                    _sectionLabel('Country / Federation'),
                    SizedBox(height: 8.h),
                    _textField(
                      controller: _federationController,
                      hintText: 'Country or federation (e.g., NOR)',
                    ),
                    SizedBox(height: 8.h),
                  ],
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
          Expanded(
            child: SizedBox(
              height: 44.h,
              child: OutlinedButton(
                onPressed: _resetFilters,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kWhiteColor,
                  backgroundColor: context.colors.surface,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.br),
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
          Expanded(
            child: SizedBox(
              height: 44.h,
              child: ElevatedButton(
                onPressed: _applyFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kWhiteColor,
                  foregroundColor: kBlackColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.br),
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
    setState(() {
      final defaults = BookGamesFilter.defaultFilter();
      _result = defaults.result;
      _color = defaults.color;
      _timeControl = defaults.timeControl;
      _yearRange = RangeValues(
        defaults.minYear.toDouble(),
        defaults.maxYear.toDouble(),
      );
      _selectedMinRating = RatingTierFilter.normalizeMinRating(
        defaults.minRating,
      );
      _openingController.text = defaults.opening;
      _ecoController.text = defaults.eco;
      _eventController.text = defaults.event;
      _playerController.text = defaults.player;
      _federationController.text = defaults.federation;
    });
  }

  void _applyFilters() {
    FocusScope.of(context).unfocus();
    HapticFeedbackService.buttonPress();
    final newFilter = BookGamesFilter(
      result: _result,
      color: _color,
      timeControl: _timeControl,
      minYear: _yearRange.start.round(),
      maxYear: _yearRange.end.round(),
      minRating: _selectedMinRating ?? GameFilter.defaultMinRating,
      maxRating: GameFilter.absoluteMaxRating,
      opening: _openingController.text.trim(),
      eco: _ecoController.text.trim(),
      event: _eventController.text.trim(),
      player: _playerController.text.trim(),
      federation: _federationController.text.trim(),
    );
    Navigator.of(context).pop(newFilter);
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.textXsMedium.copyWith(
        color: context.colors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: kDividerColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: kBlack2Color,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: context.colors.textSecondary,
            size: 20.ic,
          ),
          items:
              items
                  .map(
                    (v) => DropdownMenuItem<T>(
                      value: v,
                      child: Text(
                        itemLabel(v),
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hintText,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: kDividerColor),
      ),
      child: TextField(
        controller: controller,
        style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTypography.textSmRegular.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.5),
          ),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }

  Widget _rangeSlider({
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

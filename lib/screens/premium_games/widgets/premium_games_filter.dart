import 'package:chessever2/screens/premium_games/providers/premium_games_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Shows the premium games filter dialog.
Future<PremiumGamesFilter?> showPremiumGamesFilterDialog({
  required BuildContext context,
  required PremiumGamesType type,
  required PremiumGamesFilter currentFilter,
}) async {
  return showDialog<PremiumGamesFilter>(
    context: context,
    barrierColor: Colors.transparent,
    builder:
        (_) =>
            PremiumGamesFilterDialog(type: type, initialFilter: currentFilter),
  );
}

/// Filter dialog for premium games.
class PremiumGamesFilterDialog extends ConsumerStatefulWidget {
  const PremiumGamesFilterDialog({
    required this.type,
    required this.initialFilter,
    super.key,
  });

  final PremiumGamesType type;
  final PremiumGamesFilter initialFilter;

  @override
  ConsumerState<PremiumGamesFilterDialog> createState() =>
      _PremiumGamesFilterDialogState();
}

class _PremiumGamesFilterDialogState
    extends ConsumerState<PremiumGamesFilterDialog> {
  late PremiumGamesDateRange _dateRange;
  late PremiumGamesResult _result;
  late RangeValues _eloRange;
  bool _eloFilterEnabled = false;

  @override
  void initState() {
    super.initState();
    _dateRange = widget.initialFilter.dateRange;
    _result = widget.initialFilter.result;
    _eloFilterEnabled =
        widget.initialFilter.minElo != null ||
        widget.initialFilter.maxElo != null;
    _eloRange = RangeValues(
      widget.initialFilter.minElo?.toDouble() ??
          GameFilter.defaultMinRating.toDouble(),
      widget.initialFilter.maxElo?.toDouble() ?? 3000,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = 300.w;
    final horizontalPadding = 20.w;
    final verticalPadding = 16.h;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          const Positioned.fill(child: BackDropFilterWidget()),
          GestureDetector(
            onTap: () {},
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.zero,
              child: Container(
                width: dialogWidth,
                constraints: BoxConstraints(maxHeight: 520.h),
                decoration: BoxDecoration(
                  color: kBlackColor,
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(
                    color: kDarkGreyColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          left: horizontalPadding,
                          right: horizontalPadding,
                          top: verticalPadding,
                          bottom: 0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Filters',
                                  style: AppTypography.textMdBold.copyWith(
                                    color: kWhiteColor,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: Icon(
                                    Icons.close_rounded,
                                    color: kWhiteColor.withValues(alpha: 0.6),
                                    size: 20.ic,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 20.h),

                            // Date Range
                            _SectionTitle(title: 'Date Range'),
                            SizedBox(height: 8.h),
                            _ChipGrid(
                              items: PremiumGamesDateRange.values,
                              selectedItem: _dateRange,
                              getLabel: (item) => item.displayText,
                              onSelected: (item) {
                                HapticFeedbackService.selection();
                                setState(() => _dateRange = item);
                              },
                            ),
                            SizedBox(height: 20.h),

                            // Result
                            _SectionTitle(title: 'Result'),
                            SizedBox(height: 8.h),
                            _ChipGrid(
                              items: PremiumGamesResult.values,
                              selectedItem: _result,
                              getLabel: (item) => item.displayText,
                              onSelected: (item) {
                                HapticFeedbackService.selection();
                                setState(() => _result = item);
                              },
                            ),
                            SizedBox(height: 20.h),

                            // ELO Range
                            _SectionTitle(
                              title: 'ELO Range',
                              trailing: Switch(
                                value: _eloFilterEnabled,
                                onChanged: (value) {
                                  HapticFeedbackService.selection();
                                  setState(() => _eloFilterEnabled = value);
                                },
                                activeThumbColor: kPrimaryColor,
                                activeTrackColor: kPrimaryColor.withValues(
                                  alpha: 0.3,
                                ),
                                inactiveThumbColor: kDarkGreyColor,
                                inactiveTrackColor: kDarkGreyColor.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            SizedBox(height: 8.h),
                            AnimatedOpacity(
                              opacity: _eloFilterEnabled ? 1.0 : 0.4,
                              duration: const Duration(milliseconds: 150),
                              child: IgnorePointer(
                                ignoring: !_eloFilterEnabled,
                                child: WheelRangeFilter(
                                  minValue:
                                      GameFilter.absoluteMinRating.toDouble(),
                                  maxValue: 3200,
                                  currentStart: _eloRange.start,
                                  currentEnd: _eloRange.end,
                                  divisions:
                                      (3200 - GameFilter.absoluteMinRating) ~/
                                      50,
                                  onChanged: (values) {
                                    setState(() => _eloRange = values);
                                  },
                                ),
                              ),
                            ),
                            SizedBox(height: 16.h),
                          ],
                        ),
                      ),

                      // Buttons
                      Padding(
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
                                    backgroundColor: kBlack2Color,
                                    side: BorderSide.none,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.br),
                                    ),
                                  ),
                                  child: Text(
                                    'Reset',
                                    style: AppTypography.textSmMedium.copyWith(
                                      color: kWhiteColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 12.sp),
                            Expanded(
                              child: SizedBox(
                                height: 44.h,
                                child: ElevatedButton(
                                  onPressed: _applyFilters,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimaryColor,
                                    foregroundColor: kBlackColor,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.br),
                                    ),
                                  ),
                                  child: Text(
                                    'Apply',
                                    style: AppTypography.textSmMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
      _dateRange = PremiumGamesDateRange.allTime;
      _result = PremiumGamesResult.all;
      _eloFilterEnabled = false;
      _eloRange = RangeValues(GameFilter.defaultMinRating.toDouble(), 3000);
    });
  }

  void _applyFilters() {
    HapticFeedbackService.buttonPress();
    final filter = PremiumGamesFilter(
      dateRange: _dateRange,
      result: _result,
      minElo: _eloFilterEnabled ? _eloRange.start.round() : null,
      maxElo: _eloFilterEnabled ? _eloRange.end.round() : null,
    );
    Navigator.pop(context, filter);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor.withValues(alpha: 0.8),
            letterSpacing: 0.3,
          ),
        ),
        if (trailing != null) SizedBox(height: 28.h, child: trailing),
      ],
    );
  }
}

class _ChipGrid<T> extends StatelessWidget {
  const _ChipGrid({
    required this.items,
    required this.selectedItem,
    required this.getLabel,
    required this.onSelected,
  });

  final List<T> items;
  final T selectedItem;
  final String Function(T) getLabel;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8.sp,
        crossAxisSpacing: 8.sp,
        childAspectRatio: 3.2,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = item == selectedItem;

        return GestureDetector(
          onTap: () => onSelected(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? kPrimaryColor : kBlack2Color,
              borderRadius: BorderRadius.circular(8.br),
              border: Border.all(
                color:
                    isSelected
                        ? kPrimaryColor
                        : kDarkGreyColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Text(
              getLabel(item),
              style: AppTypography.textXsMedium.copyWith(
                color: isSelected ? kBlackColor : kWhiteColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

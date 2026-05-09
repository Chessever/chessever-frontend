import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_typography.dart';
import '../utils/haptic_feedback_service.dart';
import '../utils/responsive_helper.dart';

class RoundSelector extends StatelessWidget {
  final int currentRound;
  final int totalRounds;
  final Function(int) onRoundSelected;

  const RoundSelector({
    Key? key,
    required this.currentRound,
    required this.totalRounds,
    required this.onRoundSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedbackService.dropdownSelect();
        _showRoundPicker(context);
      },
      child: Container(
        // width: 84, // Exact width: 84px
        height: 24.h, // Exact height: 24px
        padding: EdgeInsets.symmetric(horizontal: 8.w),
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.circular(8.br),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Round $currentRound',
              style: AppTypography.textSmBold.copyWith(color: context.colors.textPrimary),
            ),
            SizedBox(width: 7.w), // Exact gap: 7px
            Image.asset(
              'assets/svgs/round_selector.png',
              width: 20.w,
              height: 20.h,
            ),
          ],
        ),
      ),
    );
  }

  void _showRoundPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      constraints: ResponsiveHelper.bottomSheetConstraints,
      builder: (context) {
        return Container(
          padding: EdgeInsets.symmetric(vertical: 24.h, horizontal: 16.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Round',
                style: AppTypography.textLgBold.copyWith(color: context.colors.textPrimary),
              ),
              SizedBox(height: 16.h),
              SizedBox(
                height: 300.h, // Fixed height to prevent overflow
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: totalRounds,
                  itemBuilder: (context, index) {
                    final roundNumber = index + 1;
                    final isSelected = roundNumber == currentRound;

                    return ListTile(
                      onTap: () {
                        HapticFeedbackService.selection();
                        Navigator.pop(context);
                        onRoundSelected(roundNumber);
                      },
                      title: Text(
                        'Round $roundNumber',
                        style: AppTypography.textMdMedium.copyWith(
                          color: isSelected ? kPrimaryColor : context.colors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

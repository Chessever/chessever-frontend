import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_typography.dart';

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
        _showRoundPicker(context);
      },
      child: Container(
        // width: 84, // Exact width: 84px
        height: 24, // Exact height: 24px
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: kBackgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Round $currentRound',
              style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
            ),
            const SizedBox(width: 7), // Exact gap: 7px
            Image.asset(
              'assets/svgs/round_selector.png',
              width: 20,
              height: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showRoundPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kBlack2Color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Round',
                style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: totalRounds,
                  itemBuilder: (context, index) {
                    final roundNumber = index + 1;
                    final isSelected = roundNumber == currentRound;

                    return ListTile(
                      onTap: () {
                        Navigator.pop(context);
                        onRoundSelected(roundNumber);
                      },
                      title: Text(
                        'Round $roundNumber',
                        style: AppTypography.textMdMedium.copyWith(
                          color: isSelected ? kPrimaryColor : kWhiteColor,
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

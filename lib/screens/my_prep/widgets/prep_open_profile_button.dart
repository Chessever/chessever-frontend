import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Opens a profile from beneath its sources: My Games, an unfolded opponent,
/// and the player's Library folder.
class PrepOpenProfileButton extends StatelessWidget {
  const PrepOpenProfileButton({super.key, required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () {
        HapticFeedbackService.cardTap();
        PrepProfileScreen.open(context, profileId);
      },
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: context.colors.textPrimary,
        foregroundColor: context.colors.textInverse,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.br),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              'Open profile',
              textAlign: TextAlign.center,
              style: AppTypography.textSmBold,
            ),
          ),
          SizedBox(width: 8.w),
          Icon(Icons.arrow_forward_rounded, size: 18.sp),
        ],
      ),
    );
  }
}

import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/hamburger_menu/settings_dialog.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

void showSettingsDialog(BuildContext context) {
  // Close drawer if open
  Navigator.pop(context);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    // backgroundColor: Colors.transparent,
    builder: (BuildContext bottomSheetContext) {
      final bottomPadding = MediaQuery.of(bottomSheetContext).viewInsets.bottom;

      return Padding(
        padding: EdgeInsets.only(
          // left: 24.w,
          // right: 24.w,
          // bottom: bottomPadding + 24.h,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          child: Container(
            color: kPopUpColor,
            child: IntrinsicHeight(
              // Prevent it from expanding full height
              child: SingleChildScrollView(child: const SettingsDialog()),
            ),
          ),
        ),
      );
    },
  );
}

void showDeleteAccountDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black87,
    builder: (BuildContext context) {
      return _DeleteAccountDialog();
    },
  );
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({Key? key}) : super(key: key);

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  bool _hasReadWarning = false;

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'info@chessever.com',
      query: 'subject=Account Deletion Request&body=Hello ChessEver Team,%0A%0AI would like to request the deletion of my account and all associated data.%0A%0AMy username/email: [Please fill in]%0A%0AThank you.',
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 380.w,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A1A1A),
              Color(0xFF0D0D0D),
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.red.withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.1),
              blurRadius: 40,
              spreadRadius: -10,
              offset: Offset(0, 20),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: Offset(0, 15),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(
            children: [
              // Dramatic background pattern - chess board inspired
              Positioned.fill(
                child: CustomPaint(
                  painter: _ChessPatternPainter(),
                ),
              ),

              // Main content
              SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with fallen king icon
                    Container(
                    padding: EdgeInsets.all(28.sp),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.red.withOpacity(0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        // Animated chess king falling
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glow effect
                            Container(
                              width: 80.w,
                              height: 80.h,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.red.withOpacity(0.3),
                                    Colors.red.withOpacity(0.05),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            )
                                .animate(onPlay: (controller) => controller.repeat())
                                .scale(
                                  begin: Offset(0.8, 0.8),
                                  end: Offset(1.2, 1.2),
                                  duration: 2000.ms,
                                  curve: Curves.easeInOut,
                                ),

                            // King icon with tilt animation
                            Transform.rotate(
                              angle: 0.3,
                              child: Icon(
                                Icons.logout_rounded, // Using logout icon as chess piece substitute
                                size: 40.ic,
                                color: Colors.red.shade400,
                              ),
                            )
                                .animate()
                                .rotate(
                                  begin: 0,
                                  end: 0.1,
                                  duration: 600.ms,
                                  curve: Curves.easeOutBack,
                                )
                                .fadeIn(duration: 400.ms)
                                .scale(
                                  begin: Offset(0.5, 0.5),
                                  duration: 600.ms,
                                  curve: Curves.elasticOut,
                                ),
                          ],
                        ),

                        SizedBox(height: 20.h),

                        // Title with dramatic styling
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              Colors.red.shade300,
                              Colors.red.shade600,
                            ],
                          ).createShader(bounds),
                          child: Text(
                            'Sacrifice Your Account',
                            style: AppTypography.textXlBold.copyWith(
                              color: Colors.white,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 200.ms, duration: 500.ms)
                            .slideY(begin: -0.3, end: 0),

                        SizedBox(height: 8.h),

                        Text(
                          'A permanent endgame',
                          style: AppTypography.textSmRegular.copyWith(
                            color: Colors.red.withOpacity(0.5),
                            fontStyle: FontStyle.italic,
                            letterSpacing: 1.2,
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 400.ms, duration: 500.ms),
                      ],
                    ),
                  ),

                  // Content section
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28.sp),
                    child: Column(
                      children: [
                        // Warning card
                        Container(
                          padding: EdgeInsets.all(20.sp),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.15),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.red.shade400,
                                    size: 20.ic,
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    'This action cannot be undone',
                                    style: AppTypography.textSmMedium.copyWith(
                                      color: Colors.red.shade400,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12.h),
                              Text(
                                'Deleting your account will permanently remove:',
                                style: AppTypography.textSmRegular.copyWith(
                                  color: kWhiteColor.withOpacity(0.8),
                                ),
                              ),
                              SizedBox(height: 12.h),
                              _BulletPoint('All your game history and analysis'),
                              _BulletPoint('Your favorite players and settings'),
                              _BulletPoint('Your countryman preferences'),
                              _BulletPoint('All personal data associated with your account'),
                            ],
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 500.ms, duration: 500.ms)
                            .slideX(begin: -0.1, end: 0),

                        SizedBox(height: 20.h),

                        // Process explanation
                        Container(
                          padding: EdgeInsets.all(20.sp),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                kWhiteColor.withOpacity(0.03),
                                kWhiteColor.withOpacity(0.01),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: kWhiteColor.withOpacity(0.08),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 32.w,
                                    height: 32.h,
                                    decoration: BoxDecoration(
                                      color: kWhiteColor.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.email_outlined,
                                      size: 18.ic,
                                      color: kWhiteColor.withOpacity(0.7),
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Text(
                                      'How to Delete Your Account',
                                      style: AppTypography.textMdMedium.copyWith(
                                        color: kWhiteColor.withOpacity(0.9),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16.h),
                              Text(
                                'To ensure the security of your request, account deletion requires email verification:',
                                style: AppTypography.textSmRegular.copyWith(
                                  color: kWhiteColor.withOpacity(0.6),
                                ),
                              ),
                              SizedBox(height: 12.h),
                              Row(
                                children: [
                                  Container(
                                    width: 24.w,
                                    height: 24.h,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: kGreenColor.withOpacity(0.5),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '1',
                                        style: AppTypography.textXsRegular.copyWith(
                                          color: kGreenColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Text(
                                      'Send an email to info@chessever.com',
                                      style: AppTypography.textSmRegular.copyWith(
                                        color: kWhiteColor.withOpacity(0.7),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8.h),
                              Row(
                                children: [
                                  Container(
                                    width: 24.w,
                                    height: 24.h,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: kGreenColor.withOpacity(0.5),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '2',
                                        style: AppTypography.textXsRegular.copyWith(
                                          color: kGreenColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Text(
                                      'Include your username or email address',
                                      style: AppTypography.textSmRegular.copyWith(
                                        color: kWhiteColor.withOpacity(0.7),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8.h),
                              Row(
                                children: [
                                  Container(
                                    width: 24.w,
                                    height: 24.h,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: kGreenColor.withOpacity(0.5),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '3',
                                        style: AppTypography.textXsRegular.copyWith(
                                          color: kGreenColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Text(
                                      'We\'ll securely delete all your data within 30 days',
                                      style: AppTypography.textSmRegular.copyWith(
                                        color: kWhiteColor.withOpacity(0.7),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 600.ms, duration: 500.ms)
                            .slideX(begin: 0.1, end: 0),

                        SizedBox(height: 20.h),

                        // Checkbox
                        InkWell(
                          onTap: () {
                            HapticFeedbackService.selection();
                            setState(() {
                              _hasReadWarning = !_hasReadWarning;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.sp),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: 200.ms,
                                  width: 22.w,
                                  height: 22.h,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: _hasReadWarning
                                          ? Colors.red.shade400
                                          : kWhiteColor.withOpacity(0.3),
                                      width: 2,
                                    ),
                                    color: _hasReadWarning
                                        ? Colors.red.withOpacity(0.2)
                                        : Colors.transparent,
                                  ),
                                  child: _hasReadWarning
                                      ? Icon(
                                          Icons.check,
                                          size: 14.ic,
                                          color: Colors.red.shade300,
                                        )
                                          .animate()
                                          .scale(
                                            begin: Offset(0, 0),
                                            duration: 200.ms,
                                            curve: Curves.elasticOut,
                                          )
                                      : null,
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Text(
                                    'I understand this action is permanent',
                                    style: AppTypography.textSmRegular.copyWith(
                                      color: kWhiteColor.withOpacity(0.7),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 700.ms, duration: 400.ms),

                        SizedBox(height: 24.h),
                      ],
                    ),
                  ),

                  // Action buttons
                  Container(
                    padding: EdgeInsets.all(24.sp),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          kWhiteColor.withOpacity(0.02),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        // Cancel button
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              HapticFeedbackService.buttonPress();
                              Navigator.of(context).pop();
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 14.h),
                              backgroundColor: kWhiteColor.withOpacity(0.05),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: kWhiteColor.withOpacity(0.1),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              'Keep Playing',
                              style: AppTypography.textSmMedium.copyWith(
                                color: kWhiteColor.withOpacity(0.8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                        SizedBox(width: 12.w),

                        // Delete button
                        Expanded(
                          child: AnimatedOpacity(
                            opacity: _hasReadWarning ? 1.0 : 0.4,
                            duration: 200.ms,
                            child: TextButton(
                              onPressed: _hasReadWarning
                                  ? () {
                                      HapticFeedbackService.heavy();
                                      _launchEmail();
                                    }
                                  : null,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 14.h),
                                backgroundColor: _hasReadWarning
                                    ? Colors.red.withOpacity(0.15)
                                    : Colors.red.withOpacity(0.05),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: _hasReadWarning
                                        ? Colors.red.withOpacity(0.4)
                                        : Colors.red.withOpacity(0.1),
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.email_outlined,
                                    size: 16.ic,
                                    color: _hasReadWarning
                                        ? Colors.red.shade300
                                        : Colors.red.withOpacity(0.3),
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    'Send Email',
                                    style: AppTypography.textSmMedium.copyWith(
                                      color: _hasReadWarning
                                          ? Colors.red.shade300
                                          : Colors.red.withOpacity(0.3),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 800.ms, duration: 400.ms)
                      .slideY(begin: 0.2, end: 0),
                  ],
                ),
              ),
            ],
          ),
        ),
      )
          .animate()
          .scale(
            begin: Offset(0.85, 0.85),
            duration: 400.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 250.ms),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;

  const _BulletPoint(this.text, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: 6.h),
            width: 4.w,
            height: 4.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withOpacity(0.4),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              text,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withOpacity(0.6),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for chess board pattern background
class _ChessPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final squareSize = 40.0;

    for (var i = 0; i < size.width / squareSize; i++) {
      for (var j = 0; j < size.height / squareSize; j++) {
        if ((i + j) % 2 == 0) {
          paint.color = Colors.red.withOpacity(0.02);
          canvas.drawRect(
            Rect.fromLTWH(
              i * squareSize,
              j * squareSize,
              squareSize,
              squareSize,
            ),
            paint,
          );
        }
      }
    }

    // Add gradient overlay
    final gradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withOpacity(0.3),
          Colors.transparent,
          Colors.black.withOpacity(0.4),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      gradient,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

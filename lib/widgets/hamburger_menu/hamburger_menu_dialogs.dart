import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hamburger_menu/settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog({super.key});

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  bool _hasReadWarning = false;
  bool _isDeleting = false;
  String? _errorMessage;

  Future<void> _deleteAccount() async {
    if (_isDeleting) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authStateProvider.notifier).deleteAccount();
      if (mounted) {
        Navigator.of(context).pop();
        // The auth state change will handle navigation to login screen
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
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
          maxWidth: 340.w,
          // Removed maxHeight constraint to let it size by content, but kept it minimal
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
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.red.withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.1),
              blurRadius: 30,
              spreadRadius: -5,
              offset: Offset(0, 15),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              // Background pattern
              Positioned.fill(
                child: CustomPaint(
                  painter: _ChessPatternPainter(),
                ),
              ),

              // Main content
              Padding(
                padding: EdgeInsets.all(24.sp),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Compact Header
                    Container(
                      padding: EdgeInsets.all(16.sp),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withOpacity(0.1),
                      ),
                      child: Icon(
                        Icons.delete_forever_rounded,
                        size: 32.ic,
                        color: Colors.red.shade400,
                      ),
                    )
                        .animate()
                        .scale(
                          duration: 400.ms,
                          curve: Curves.easeOutBack,
                        )
                        .fadeIn(duration: 300.ms),

                    SizedBox(height: 16.h),

                    Text(
                      'Delete Account?',
                      style: AppTypography.textLgBold.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ).animate().fadeIn(delay: 100.ms).slideY(begin: -0.2, end: 0),

                    SizedBox(height: 8.h),

                    Text(
                      'This action is permanent and cannot be undone. All your data, history, and preferences will be lost forever.',
                      textAlign: TextAlign.center,
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor.withOpacity(0.7),
                        height: 1.4,
                      ),
                    ).animate().fadeIn(delay: 200.ms),

                    SizedBox(height: 24.h),

                    // Warning / Checkbox Section
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () {
                          HapticFeedbackService.selection();
                          setState(() {
                            _hasReadWarning = !_hasReadWarning;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: 200.ms,
                              width: 20.w,
                              height: 20.h,
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
                                      size: 12.ic,
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
                                'I understand the consequences',
                                style: AppTypography.textSmMedium.copyWith(
                                  color: _hasReadWarning
                                      ? Colors.red.shade300
                                      : kWhiteColor.withOpacity(0.8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.1, end: 0),

                    // Error message
                    if (_errorMessage != null)
                      Padding(
                        padding: EdgeInsets.only(top: 16.h),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: AppTypography.textXsRegular.copyWith(
                            color: Colors.red.shade300,
                          ),
                        ),
                      ).animate().fadeIn(),

                    SizedBox(height: 24.h),

                    // Action buttons
                    Row(
                      children: [
                        // Cancel button
                        Expanded(
                          child: TextButton(
                            onPressed: _isDeleting
                                ? null
                                : () {
                                    HapticFeedbackService.buttonPress();
                                    Navigator.of(context).pop();
                                  },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              backgroundColor: kWhiteColor.withOpacity(0.05),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: AppTypography.textSmMedium.copyWith(
                                color: kWhiteColor.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ),

                        SizedBox(width: 12.w),

                        // Delete button
                        Expanded(
                          child: AnimatedOpacity(
                            opacity: _hasReadWarning ? 1.0 : 0.5,
                            duration: 200.ms,
                            child: TextButton(
                              onPressed: (_hasReadWarning && !_isDeleting)
                                  ? () {
                                      HapticFeedbackService.heavy();
                                      _deleteAccount();
                                    }
                                  : null,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                backgroundColor: Colors.red.withOpacity(0.15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Colors.red.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: _isDeleting
                                  ? SizedBox(
                                      width: 16.w,
                                      height: 16.h,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.red.shade300,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      'Delete',
                                      style: AppTypography.textSmMedium.copyWith(
                                        color: Colors.red.shade300,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0),
                  ],
                ),
              ),
            ],
          ),
        ),
      )
          .animate()
          .scale(
            begin: Offset(0.9, 0.9),
            duration: 300.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 200.ms),
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

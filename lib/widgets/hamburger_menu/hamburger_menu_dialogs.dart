import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void showSettingsDialog(BuildContext context) {
  // Close hamburger drawer, then push the unified Settings page.
  Navigator.pop(context);
  Navigator.of(context).push(SettingsPage.route());
}

void showDeleteAccountDialog(BuildContext context) {
  showAlertModal<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: context.colors.scrim,
    child: const _DeleteAccountDialog(),
  );
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
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
    } catch (e, st) {
      talker.handle(e, st);
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _errorMessage = userFacingError(
            e,
            fallback: 'Could not delete your account. Please try again.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Ink that sits on the solid danger fill: paper on light, black on dark.
    final onDanger = context.isLightTheme ? colors.surface : colors.textInverse;

    return Container(
      constraints: BoxConstraints(maxWidth: 340.w),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: EdgeInsets.all(24.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.delete_forever_rounded,
            size: 36.ic,
            color: colors.danger,
          ),
          SizedBox(height: 12.h),
          Text(
            'Delete account?',
            textAlign: TextAlign.center,
            style: AppTypography.textLgBold.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'This cannot be undone. Your data, history and preferences are '
            'deleted with it.',
            textAlign: TextAlign.center,
            style: AppTypography.textSmRegular.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          SizedBox(height: 20.h),

          // The confirmation the Delete button waits on.
          MergeSemantics(
            child: Semantics(
              checked: _hasReadWarning,
              child: Material(
                color: colors.danger.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    HapticFeedbackService.selection();
                    setState(() => _hasReadWarning = !_hasReadWarning);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.sp,
                        vertical: 12.sp,
                      ),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 20.ic,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color:
                                    _hasReadWarning
                                        ? colors.danger
                                        : Colors.transparent,
                                border: Border.all(
                                  color:
                                      _hasReadWarning
                                          ? colors.danger
                                          : colors.textSecondary,
                                  width: 2,
                                ),
                              ),
                              child:
                                  _hasReadWarning
                                      ? Icon(
                                        Icons.check_rounded,
                                        size: 14.ic,
                                        color: onDanger,
                                      )
                                      : null,
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Text(
                              'I understand the consequences',
                              style: AppTypography.textSmMedium.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (_errorMessage != null)
            Padding(
              padding: EdgeInsets.only(top: 16.h),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: AppTypography.textXsRegular.copyWith(
                  color: colors.danger,
                ),
              ),
            ),

          SizedBox(height: 24.h),

          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed:
                      _isDeleting
                          ? null
                          : () {
                            HapticFeedbackService.buttonPress();
                            Navigator.of(context).pop();
                          },
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: colors.surface,
                    foregroundColor: colors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              // Solid danger once confirmed; until then it rests at half
              // strength and takes no taps.
              Expanded(
                child: Opacity(
                  opacity: _hasReadWarning ? 1.0 : 0.5,
                  child: TextButton(
                    onPressed:
                        (_hasReadWarning && !_isDeleting)
                            ? () {
                              HapticFeedbackService.heavy();
                              _deleteAccount();
                            }
                            : null,
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: colors.danger,
                      disabledBackgroundColor: colors.danger,
                      foregroundColor: onDanger,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child:
                        _isDeleting
                            ? SizedBox.square(
                              dimension: 16.ic,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  onDanger,
                                ),
                              ),
                            )
                            : Text(
                              'Delete',
                              style: AppTypography.textSmMedium.copyWith(
                                color: onDanger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

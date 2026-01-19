import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:terminate_restart/terminate_restart.dart';

class ShorebirdUpdateDialog extends StatefulWidget {
  final UpdateStatus initialStatus;

  const ShorebirdUpdateDialog({
    super.key,
    this.initialStatus = UpdateStatus.outdated,
  });

  @override
  State<ShorebirdUpdateDialog> createState() => _ShorebirdUpdateDialogState();
}

class _ShorebirdUpdateDialogState extends State<ShorebirdUpdateDialog> {
  final _shorebirdCodePush = ShorebirdUpdater();
  late bool _isDownloading;
  late bool _isReadyToRestart;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isDownloading = false;
    _isReadyToRestart = widget.initialStatus == UpdateStatus.restartRequired;
  }

  Future<void> _downloadUpdate() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    try {
      if (kDebugMode) {
        await Future.delayed(const Duration(seconds: 2));
      } else {
        await _shorebirdCodePush.update();
      }

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isReadyToRestart = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Failed to download update. Please try again.';
        });
      }
    }
  }

  void _restartApp() {
    TerminateRestart.instance.restartApp(
      options: const TerminateRestartOptions(terminate: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: ResponsiveHelper.isTablet ? 400.w : 340.w,
        padding: EdgeInsets.all(24.sp),
        decoration: BoxDecoration(
          color: kPopUpColor,
          borderRadius: BorderRadius.circular(20.sp),
          boxShadow: [
            BoxShadow(
              color: kBlack2Color.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon
            Container(
              padding: EdgeInsets.all(16.sp),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isReadyToRestart ? Icons.check_rounded : Icons.system_update_rounded,
                color: _isReadyToRestart ? kGreenColor : kPrimaryColor,
                size: 32.sp,
              ),
            ),
            SizedBox(height: 24.h),

            // Title
            Text(
              _isReadyToRestart ? 'Update Ready' : 'Update Available',
              style: AppTypography.textLgMedium.copyWith(color: kWhiteColor),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12.h),

            // Description
            Text(
              _isReadyToRestart
                  ? 'The update has been downloaded successfully. Restart the app to apply the changes.'
                  : 'A new version of ChessEver is available. Update now to get the latest features and improvements.',
              style: AppTypography.textSmRegular.copyWith(
                color: kSecondaryTextColor,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32.h),

            // Error Message
            if (_errorMessage != null)
              Padding(
                padding: EdgeInsets.only(bottom: 16.h),
                child: Text(
                  _errorMessage!,
                  style: AppTypography.textXsRegular.copyWith(color: kRedColor),
                  textAlign: TextAlign.center,
                ),
              ),

            // Progress Indicator
            if (_isDownloading)
              Column(
                children: [
                  LinearProgressIndicator(
                    backgroundColor: kBlack3Color,
                    valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryColor),
                    borderRadius: BorderRadius.circular(2.sp),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    'Downloading update...',
                    style: AppTypography.textXsRegular.copyWith(
                      color: kSecondaryTextColor,
                    ),
                  ),
                ],
              )
            else
            // Buttons
              Row(
                children: [
                  // Later Button
                  if (!_isReadyToRestart)
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.sp),
                            side: const BorderSide(color: kDividerColor),
                          ),
                        ),
                        child: Text(
                          'Later',
                          style: AppTypography.textSmMedium.copyWith(
                            color: kSecondaryTextColor,
                          ),
                        ),
                      ),
                    ),
                  if (!_isReadyToRestart) SizedBox(width: 12.w),

                  // Action Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isReadyToRestart ? _restartApp : _downloadUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isReadyToRestart ? kGreenColor : kPrimaryColor,
                        foregroundColor: kWhiteColor,
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.sp),
                        ),
                      ),
                      child: Text(
                        _isReadyToRestart ? 'Restart App' : 'Update Now',
                        style: AppTypography.textSmMedium.copyWith(
                          color: kWhiteColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
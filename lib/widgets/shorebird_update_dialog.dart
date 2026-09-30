import 'package:chessever2/theme/app_colors.dart';
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

  /// Fill of the one action: brand cyan to download, green once the patch
  /// is ready (the deep paper green in light, the bright one in dark).
  Color _actionFill(BuildContext context) {
    final colors = context.colors;
    if (!_isReadyToRestart) return colors.brand;
    return context.isLightTheme ? colors.successStrong : colors.success;
  }

  /// Label ink on [_actionFill]. The old white label read 2.4:1 on cyan and
  /// 3.6:1 on green; these clear AA (dark ink ~6-7:1, paper on the deep
  /// green ~6:1).
  Color _actionInk(BuildContext context) {
    final colors = context.colors;
    return _isReadyToRestart && context.isLightTheme
        ? colors.surface
        : colors.inkOnAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ResponsiveHelper.isTablet ? 400.w : 340.w,
      padding: EdgeInsets.all(24.sp),
      decoration: BoxDecoration(
        color: context.colors.popup,
        borderRadius: BorderRadius.circular(20.sp),
        // Dark keeps its soft surface halo; on paper that halo is a pale
        // glow over the scrim, so light casts one short ink shadow.
        boxShadow: [
          context.isLightTheme
              ? BoxShadow(
                color: context.colors.shadow,
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
              // Dark: one short black shadow cast downward, not a pale halo
              // radiating on every side.
              : BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon
          // A bare mark, no tinted disc behind it; the padding keeps the
          // dialog's rhythm.
          Padding(
            padding: EdgeInsets.all(8.sp),
            child: Icon(
              _isReadyToRestart
                  ? Icons.check_rounded
                  : Icons.system_update_rounded,
              // successStrong is kGreenColor in dark; on paper it deepens.
              color:
                  _isReadyToRestart
                      ? context.colors.successStrong
                      : context.colors.accentText,
              size: 32.sp,
            ),
          ),
          SizedBox(height: 24.h),

          // Title
          Text(
            _isReadyToRestart ? 'Update Ready' : 'Update Available',
            style: AppTypography.textLgMedium.copyWith(
              color: context.colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 12.h),

          // Description
          Text(
            _isReadyToRestart
                ? 'The update has been downloaded successfully. Restart the app to apply the changes.'
                : 'A new version of ChessEver is available. Update now to get the latest features and improvements.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
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
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.danger,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // Progress Indicator
          if (_isDownloading)
            Column(
              children: [
                LinearProgressIndicator(
                  backgroundColor: context.colors.surfaceRecessed,
                  // accentText is kPrimaryColor in dark; cyan on the
                  // recessed paper track is ~1.5:1.
                  valueColor: AlwaysStoppedAnimation<Color>(
                    context.colors.accentText,
                  ),
                  borderRadius: BorderRadius.circular(2.sp),
                ),
                SizedBox(height: 12.h),
                Text(
                  'Downloading update...',
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textSecondary,
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
                      // A quiet text decline beside the one filled action,
                      // not an outlined twin of it.
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        foregroundColor: context.colors.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.sp),
                        ),
                      ),
                      child: Text(
                        'Later',
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                if (!_isReadyToRestart) SizedBox(width: 12.w),

                // Action Button
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        _isReadyToRestart ? _restartApp : _downloadUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _actionFill(context),
                      foregroundColor: _actionInk(context),
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.sp),
                      ),
                    ),
                    child: Text(
                      _isReadyToRestart ? 'Restart App' : 'Update Now',
                      style: AppTypography.textSmMedium.copyWith(
                        color: _actionInk(context),
                        fontWeight: FontWeight.w600,
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

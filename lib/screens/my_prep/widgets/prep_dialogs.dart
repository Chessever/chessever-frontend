import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:flutter/material.dart';

/// What the add sheet hands back: a display name and the accounts the
/// reader typed, each already confirmed to exist.
class PrepAddResult {
  const PrepAddResult(this.name, this.accounts);

  /// A profile is named after its ChessEver player when it has one.
  factory PrepAddResult.named(List<PrepAccount> accounts) {
    final named =
        accounts.where((a) => a.source == PrepSource.chessever).firstOrNull ??
        accounts.first;
    return PrepAddResult(named.displayName ?? named.username, accounts);
  }

  final String name;
  final List<PrepAccount> accounts;
}

/// Renames a profile.
Future<String?> showPrepRenameDialog(
  BuildContext context,
  String current, {
  String title = 'Rename',
}) {
  return showAlertModal<String>(
    context: context,
    child: _RenameDialog(current: current, title: title),
  );
}

/// The card every Prep dialog sits on, matching the Library's dialogs.
class PrepDialogCard extends StatelessWidget {
  const PrepDialogCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final Widget icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PrepDialogSurface(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24.sp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrepDialogHeader(leading: icon, title: title, subtitle: subtitle),
            SizedBox(height: 22.h),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// The rounded surface a Prep dialog's content sits on.
class PrepDialogSurface extends StatelessWidget {
  const PrepDialogSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: ResponsiveHelper.isTablet ? 440 : double.infinity,
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(24.br),
        ),
        child: child,
      ),
    );
  }
}

/// A Prep dialog's heading: its mark, then the title over its subtitle. A
/// dialog of several pages names the page it is on with [step], and keeps
/// [trailingInset] clear for a close button laid over the heading's end.
class PrepDialogHeader extends StatelessWidget {
  const PrepDialogHeader({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.gap,
    this.step,
    this.stepLabel,
    this.trailingInset = 0,
    this.band,
  });

  final Widget leading;
  final String title;
  final String? subtitle;

  /// The space between [leading] and the title. 14 by default.
  final double? gap;
  final String? step;
  final String? stepLabel;
  final double trailingInset;

  /// The height of the line the mark and the page number sit on, measured
  /// from the heading's top. Without one they centre on the whole heading;
  /// with one they hold that line when a long title wraps under it, level
  /// with a control laid over the heading's end.
  final double? band;

  /// How tall a one-line title over a one-line subtitle stands.
  static double blockHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final title = AppTypography.textLgBold;
    final subtitle = AppTypography.textXsRegular;
    return scaler.scale(title.fontSize!) * title.height! +
        2.h +
        scaler.scale(subtitle.fontSize!) * (16 / 12);
  }

  Widget _onBand(Widget child) => band == null
      ? child
      : SizedBox(
          height: band,
          child: Center(widthFactor: 1, child: child),
        );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: band == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        _onBand(leading),
        SizedBox(width: gap ?? 14.w),
        Expanded(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: band ?? 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.textLgBold.copyWith(
                    color: colors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    subtitle!,
                    style: AppTypography.textXsRegular.copyWith(
                      color: colors.textSecondary,
                      height: 16 / 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (step != null) ...[
          SizedBox(width: 8.w),
          _onBand(
            Text(
              step!,
              semanticsLabel: stepLabel,
              style: AppTypography.textSmMedium.copyWith(
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
        if (trailingInset > 0) SizedBox(width: trailingInset),
      ],
    );
  }
}

/// Cancel and a primary action, as the Library's dialogs lay them out.
class PrepDialogActions extends StatelessWidget {
  const PrepDialogActions({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.onCancel,
    this.busy = false,
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;

  /// Where Cancel leads when the nearest navigator is not the way out, as on
  /// a page inside a sheet. Pops by default.
  final VoidCallback? onCancel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: onCancel ?? () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 15.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
            child: Text(
              'Cancel',
              style: AppTypography.textSmMedium.copyWith(
                color: context.textInk(0.55),
              ),
            ),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.textPrimary,
              foregroundColor: context.colors.textInverse,
              disabledBackgroundColor: context.colors.textPrimary.withValues(
                alpha: 0.12,
              ),
              disabledForegroundColor: context.textInk(0.4),
              padding: EdgeInsets.symmetric(vertical: 15.h),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
            child: busy
                ? SizedBox.square(
                    dimension: 16.sp,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.textInverse,
                    ),
                  )
                : Text(confirmLabel, style: AppTypography.textSmBold),
          ),
        ),
      ],
    );
  }
}

/// A field label in the Library dialogs' style.
class PrepFieldLabel extends StatelessWidget {
  const PrepFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 8.h),
    child: Text(
      text,
      style: AppTypography.textXsMedium.copyWith(color: context.textInk(0.55)),
    ),
  );
}

InputDecoration prepInputDecoration(
  BuildContext context, {
  required String hint,
  Widget? prefix,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: AppTypography.textMdRegular.copyWith(
      color: context.textInk(0.3),
    ),
    filled: true,
    fillColor: context.colors.textPrimary.withValues(alpha: 0.05),
    contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 15.h),
    counterText: '',
    prefixIcon: prefix,
    prefixIconConstraints: BoxConstraints(minWidth: 48.w),
    suffixIcon: suffix,
    suffixIconConstraints: BoxConstraints(minWidth: 44.w),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12.br),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12.br),
      borderSide: BorderSide(color: context.colors.accentText, width: 1.5),
    ),
  );
}

// ------------------------------------------------------------------ rename

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current, required this.title});
  final String current;
  final String title;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.current);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    HapticFeedbackService.medium();
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return PrepDialogCard(
      icon: Icon(
        Icons.edit_rounded,
        color: context.colors.textPrimary,
        size: 22.sp,
      ),
      title: widget.title,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _save(),
          style: AppTypography.textMdMedium.copyWith(
            color: context.colors.textPrimary,
          ),
          cursorColor: context.colors.accentText,
          decoration: prepInputDecoration(context, hint: 'Name'),
        ),
        SizedBox(height: 24.h),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => PrepDialogActions(
            confirmLabel: 'Save',
            onConfirm: _controller.text.trim().isEmpty ? null : _save,
          ),
        ),
      ],
    );
  }
}

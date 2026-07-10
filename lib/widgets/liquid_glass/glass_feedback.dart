import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Package [GlassToast] helper with app defaults.
///
/// Returns a dismiss callback from [GlassToast.show].
VoidCallback showGlassSnack(
  BuildContext context, {
  required String message,
  GlassToastType type = GlassToastType.neutral,
  Duration duration = const Duration(seconds: 3),
}) {
  return GlassToast.show(
    context,
    message: message,
    type: type,
    duration: duration,
    position: GlassToastPosition.bottom,
  );
}

/// Package [GlassDialog] confirm path (replaces material confirm sheets).
Future<bool?> showGlassConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  bool destructive = false,
}) {
  return GlassDialog.show<bool>(
    context: context,
    title: title,
    message: message,
    barrierDismissible: true,
    actions: [
      GlassDialogAction(
        label: cancelText,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      GlassDialogAction(
        label: confirmText,
        isDestructive: destructive,
        isPrimary: !destructive,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
}

/// Package [GlassSheet] for generic modal content.
Future<T?> showAppGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  return GlassSheet.show<T>(
    context: context,
    isDismissible: isDismissible,
    builder: builder,
  );
}

/// Package action sheet for destructive / multi-choice menus.
Future<T?> showAppGlassActionSheet<T>({
  required BuildContext context,
  String? title,
  String? message,
  required List<GlassActionSheetAction> actions,
}) {
  return showGlassActionSheet<T>(
    context: context,
    title: title,
    message: message,
    actions: actions,
  );
}

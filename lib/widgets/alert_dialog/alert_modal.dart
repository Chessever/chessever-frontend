import 'package:flutter/material.dart';

void showAlertModal({
  required BuildContext context,
  required Widget child,
  Color? backgroundColor,
  bool barrierDismissible = true,
  Color barrierColor = Colors.transparent, // Default to transparent
}) => showDialog(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierColor: barrierColor,
  builder: (ctx) {
    return Dialog(
      backgroundColor: backgroundColor ?? Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24.0,
        vertical: 24.0,
      ),
      child: child,
    );
  },
);

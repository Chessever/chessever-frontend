import 'package:chessever2/widgets/blur_background.dart';
import 'package:flutter/material.dart';

void showAlertModal({
  required BuildContext context,
  required Widget child,
  Color? backgroundColor,
  bool barrierDismissible = true,
  double horizontalPadding = 24.0,
  double verticalPadding = 24.0,
  Color barrierColor = Colors.transparent, // Default to transparent
}) => showDialog(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierColor: barrierColor,
  builder: (ctx) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Stack(
          children: [
            GestureDetector(
              onTap: barrierDismissible ? () => Navigator.pop(context) : null,
              child: BlurBackground(),
            ),
            child,
          ],
        ),
      ),
    );
  },
);

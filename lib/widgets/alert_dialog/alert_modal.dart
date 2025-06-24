import 'dart:ui';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:flutter/material.dart';

void showAlertModal({
  required BuildContext context,
  required Widget child,
  Color? backgroundColor,
  bool barrierDismissible = true,
  double horizontalPadding = 24.0,
  double verticalPadding = 24.0,
  Color barrierColor =
      Colors.black54, // Changed default to semi-transparent black
}) => showDialog(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierColor:
      Colors.transparent, // Always transparent to allow our custom backdrop
  builder: (ctx) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        // Close dialog when tapping outside - using ctx instead of context
        onTap: barrierDismissible ? () => Navigator.pop(ctx) : null,
        child: Stack(
          children: [
            // Backdrop filter for blur effect
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(color: barrierColor),
              ),
            ),
            // Dialog content - wrapped in GestureDetector to prevent closing when tapping on it
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: GestureDetector(
                onTap: () {}, // Absorb the tap
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  },
);

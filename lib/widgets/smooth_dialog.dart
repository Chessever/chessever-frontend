import 'package:flutter/material.dart';
import 'package:motor/motor.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'keyboard_animation_builder.dart';

// Simple cache for keyboard height
class KeyboardHeightStorage {
  static double _height = 336.0; // Default iOS height approx
  static double get height => _height;
  static set height(double value) {
    if (value > 50) _height = value; // Ignore small changes
  }
}

Future<T?> showSmoothDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  FocusNode? focusNode,
  bool anchorToBottom = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 0), // We handle animation manually
    pageBuilder: (context, animation, secondaryAnimation) {
      return SmoothDialogWrapper(
        builder: builder,
        focusNode: focusNode,
        anchorToBottom: anchorToBottom,
      );
    },
  );
}

class SmoothDialogWrapper extends StatefulWidget {
  final WidgetBuilder builder;
  final FocusNode? focusNode;
  final bool anchorToBottom;

  const SmoothDialogWrapper({
    super.key,
    required this.builder,
    this.focusNode,
    this.anchorToBottom = true,
  });

  @override
  State<SmoothDialogWrapper> createState() => _SmoothDialogWrapperState();
}

class _SmoothDialogWrapperState extends State<SmoothDialogWrapper> {
  double _targetValue = 0.0;

  @override
  void initState() {
    super.initState();
    // Trigger animation after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _targetValue = 1.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Update keyboard height if we see a larger one
    final currentInsets = MediaQuery.of(context).viewInsets.bottom;
    if (currentInsets > 0) {
      KeyboardHeightStorage.height = currentInsets;
    }

    return SingleMotionBuilder(
      motion: const CupertinoMotion.smooth(),
      value: _targetValue,
      builder: (context, value, child) {
        final scale = 0.95 + (0.05 * value);
        final opacity = value.clamp(0.0, 1.0).toDouble();
        
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: _buildDialogContent(context),
          ),
        );
      },
    );
  }

  Widget _buildDialogContent(BuildContext context) {
    final child = Material(
      color: Colors.transparent,
      child: widget.builder(context),
    );

    if (!widget.anchorToBottom) {
      return MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        removeTop: true,
        child: child,
      );
    }

    return KeyboardAnimationBuilder(
      keyboardTotalHeight: KeyboardHeightStorage.height,
      interpolateLastPart: true,
      focusNode: widget.focusNode,
      builder: (context, keyboardHeight) {
        return Padding(
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 24.h),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

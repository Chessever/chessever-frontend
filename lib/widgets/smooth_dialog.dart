import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:chessever2/providers/keyboard_total_height_provider.dart';
import 'package:chessever2/utils/keyboard_animation_builder.dart';
import 'package:chessever2/utils/responsive_helper.dart';

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
    transitionDuration: const Duration(
      milliseconds: 0,
    ), // We handle animation manually
    pageBuilder: (context, animation, secondaryAnimation) {
      return SmoothDialogWrapper(
        builder: builder,
        focusNode: focusNode,
        anchorToBottom: anchorToBottom,
      );
    },
  );
}

class SmoothDialogWrapper extends ConsumerStatefulWidget {
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
  ConsumerState<SmoothDialogWrapper> createState() =>
      _SmoothDialogWrapperState();
}

class _SmoothDialogWrapperState extends ConsumerState<SmoothDialogWrapper> {
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
    // Update the shared keyboard cache if system insets report something bigger
    final currentInsets = MediaQuery.viewInsetsOf(context).bottom;
    if (currentInsets > 0) {
      ref.read(keyboardTotalHeightProvider.notifier).update(currentInsets);
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
    final child = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.isTablet ? 500.0 : double.infinity,
        ),
        child: Material(
          color: Colors.transparent,
          child: widget.builder(context),
        ),
      ),
    );

    if (!widget.anchorToBottom) {
      return MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        removeTop: true,
        child: child,
      );
    }

    final keyboardTotalHeight = ref.watch(keyboardTotalHeightProvider);
    return KeyboardAnimationBuilder(
      keyboardTotalHeight: keyboardTotalHeight,
      interpolateLastPart: Platform.isIOS,
      focusNode: widget.focusNode,
      onChange: (height) {
        if (height > 0) {
          ref.read(keyboardTotalHeightProvider.notifier).update(height);
        }
      },
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

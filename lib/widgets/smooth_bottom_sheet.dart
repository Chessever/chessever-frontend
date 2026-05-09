import 'dart:ui';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Shows a smooth bottom sheet with Motor-powered spring animations.
/// Uses CupertinoMotion for natural iOS-like feel.
Future<T?> showSmoothBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useBlur = false,
  Color? backgroundColor,
  double? maxHeight,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero, // Motor handles animation
    pageBuilder: (context, animation, secondaryAnimation) {
      return _SmoothBottomSheetWrapper<T>(
        builder: builder,
        isDismissible: isDismissible,
        enableDrag: enableDrag,
        useBlur: useBlur,
        backgroundColor: backgroundColor,
        maxHeight: maxHeight,
      );
    },
  );
}

class _SmoothBottomSheetWrapper<T> extends StatefulWidget {
  const _SmoothBottomSheetWrapper({
    required this.builder,
    required this.isDismissible,
    required this.enableDrag,
    required this.useBlur,
    this.backgroundColor,
    this.maxHeight,
  });

  final WidgetBuilder builder;
  final bool isDismissible;
  final bool enableDrag;
  final bool useBlur;
  final Color? backgroundColor;
  final double? maxHeight;

  @override
  State<_SmoothBottomSheetWrapper<T>> createState() =>
      _SmoothBottomSheetWrapperState<T>();
}

class _SmoothBottomSheetWrapperState<T>
    extends State<_SmoothBottomSheetWrapper<T>> {
  double _slideProgress = 0.0; // 0 = hidden, 1 = fully visible
  double _barrierOpacity = 0.0;
  double _dragOffset = 0.0;
  bool _isDragging = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _slideProgress = 1.0;
          _barrierOpacity = 1.0;
        });
      }
    });
  }

  void _close([T? result]) {
    if (_isClosing) return;
    _isClosing = true;
    setState(() {
      _slideProgress = 0.0;
      _barrierOpacity = 0.0;
    });
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    });
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enableDrag) return;
    _isDragging = true;
    _dragOffset = 0.0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enableDrag || !_isDragging) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 500.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enableDrag || !_isDragging) return;
    _isDragging = false;

    final velocity = details.velocity.pixelsPerSecond.dy;
    final shouldClose = _dragOffset > 100 || velocity > 500;

    if (shouldClose && widget.isDismissible) {
      _close();
    } else {
      setState(() {
        _dragOffset = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = widget.maxHeight ?? screenHeight * 0.9;

    return Stack(
      children: [
        // Barrier with optional blur
        GestureDetector(
          onTap: widget.isDismissible ? () => _close() : null,
          child: SingleMotionBuilder(
            motion: const CupertinoMotion.smooth(),
            value: _barrierOpacity,
            builder: (context, opacity, child) {
              return widget.useBlur
                  ? BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 8 * opacity,
                      sigmaY: 8 * opacity,
                    ),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5 * opacity),
                    ),
                  )
                  : Container(
                    color: Colors.black.withValues(alpha: 0.5 * opacity),
                  );
            },
          ),
        ),

        // Bottom sheet content - tablet has max width
        Positioned(
          left: ResponsiveHelper.isTablet ? null : 0,
          right: ResponsiveHelper.isTablet ? null : 0,
          bottom: 0,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.isTablet ? 500.0 : double.infinity,
              ),
              child: SingleMotionBuilder(
                motion:
                    _isDragging
                        ? const LinearMotion(Duration(milliseconds: 1))
                        : const CupertinoMotion.bouncy(),
                value: _slideProgress,
                builder: (context, progress, child) {
                  final slideOffset =
                      (1 - progress) * maxSheetHeight + _dragOffset;

                  return Transform.translate(
                    offset: Offset(0, slideOffset),
                    child: child,
                  );
                },
                child: GestureDetector(
                  onVerticalDragStart: _onDragStart,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxSheetHeight),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.backgroundColor ?? context.colors.surface,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(20.br),
                            topRight: Radius.circular(20.br),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Drag handle
                            if (widget.enableDrag)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: 12.h,
                                  bottom: 8.h,
                                ),
                                child: Container(
                                  width: 36.w,
                                  height: 4.h,
                                  decoration: BoxDecoration(
                                    color: context.colors.textPrimary.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(2.br),
                                  ),
                                ),
                              ),
                            // Content
                            Flexible(child: widget.builder(context)),
                            // Safe area padding
                            SizedBox(
                              height: MediaQuery.of(context).viewPadding.bottom,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

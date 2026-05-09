import 'dart:async';

import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Global state to track when tablet-safe popups are open.
/// Used to defer rebuilds that would close popups unexpectedly.
class TabletPopupState {
  static bool isAnyPopupOpen = false;

  static void markOpen() => isAnyPopupOpen = true;
  static void markClosed() => isAnyPopupOpen = false;
}

/// Shows a popup menu that is safe from phantom tap dismissals on tablets.
///
/// On tablets, this uses a custom overlay with a timing guard to prevent
/// the phantom taps that occur ~300-400ms after opening from dismissing the menu.
/// On mobile, this uses the standard [showMenu] function.
///
/// Usage:
/// ```dart
/// showTabletSafeMenu(
///   context: context,
///   position: RelativeRect.fromLTRB(x, y, x2, y2),
///   items: [
///     PopupMenuItem(value: 'action1', child: Text('Action 1')),
///     PopupMenuItem(value: 'action2', child: Text('Action 2')),
///   ],
/// ).then((value) {
///   if (value == 'action1') { /* handle */ }
/// });
/// ```
Future<T?> showTabletSafeMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double? elevation,
  Color? color,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  bool useRootNavigator = false,
}) async {
  if (!ResponsiveHelper.isTablet) {
    // On mobile, use standard showMenu
    return showMenu<T>(
      context: context,
      position: position,
      items: items,
      initialValue: initialValue,
      elevation: elevation,
      color: color,
      shape: shape,
      constraints: constraints,
      useRootNavigator: useRootNavigator,
    );
  }

  // On tablets, use our custom overlay-based menu with timing guard
  return _showTabletOverlayMenu<T>(
    context: context,
    position: position,
    items: items,
    elevation: elevation,
    color: color,
    shape: shape,
    constraints: constraints,
  );
}

Future<T?> _showTabletOverlayMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  double? elevation,
  Color? color,
  ShapeBorder? shape,
  BoxConstraints? constraints,
}) {
  final completer = Completer<T?>();

  final overlay = Overlay.of(context);

  // Calculate menu position with bounds checking for tablets
  final screenWidth = MediaQuery.of(context).size.width;
  final menuWidth =
      constraints != null &&
              constraints.minWidth == constraints.maxWidth &&
              constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 240.0;
  const horizontalPadding = 16.0;

  // Calculate the right edge of where the menu would be if left-aligned to button
  final menuRightEdge = position.left + menuWidth;

  // Track if we're aligning from the right (for animation alignment)
  bool isRightAligned = false;

  // If menu would extend beyond screen, align menu's right edge with button's right edge
  double left;
  if (menuRightEdge > screenWidth - horizontalPadding) {
    // position.right in RelativeRect.fromLTRB is the x-coordinate of the button's right edge
    // So menu's left = button's right edge - menu width
    left = (position.right - menuWidth).clamp(
      horizontalPadding,
      screenWidth - menuWidth - horizontalPadding,
    );
    isRightAligned = true;
  } else {
    left = position.left;
  }

  final top = position.top;

  TabletPopupState.markOpen();
  HapticFeedback.selectionClick();

  final openedAt = DateTime.now();
  const minOpenDuration = Duration(milliseconds: 600);

  bool canDismiss() {
    final elapsed = DateTime.now().difference(openedAt);
    return elapsed >= minOpenDuration;
  }

  late OverlayEntry overlayEntry;
  AnimationController? animationController;

  void closeMenu([T? result]) {
    if (completer.isCompleted) return;

    TabletPopupState.markClosed();

    if (animationController != null) {
      animationController!.reverse().then((_) {
        overlayEntry.remove();
        animationController?.dispose();
        animationController = null;
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      });
    } else {
      overlayEntry.remove();
      completer.complete(result);
    }
  }

  void handleBarrierTap() {
    if (!canDismiss()) {
      debugPrint('🛡️ TABLET MENU: dismiss blocked - opened too recently');
      return;
    }
    closeMenu();
  }

  // Get the navigator's ticker provider for animation
  final navigatorState = Navigator.of(context);

  overlayEntry = OverlayEntry(
    builder: (overlayContext) {
      // Create animation controller if not already created
      animationController ??= AnimationController(
        vsync: navigatorState,
        duration: const Duration(milliseconds: 200),
      )..forward();

      final animation = CurvedAnimation(
        parent: animationController!,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return Stack(
        children: [
          // Barrier with timing guard
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: handleBarrierTap,
              onHorizontalDragStart: (_) {},
              onHorizontalDragUpdate: (_) {},
              onHorizontalDragEnd: (_) {},
              child: Container(color: Colors.black.withValues(alpha: 0.01)),
            ),
          ),
          // Menu
          Positioned(
            left: left,
            top: top,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final progress = animation.value.clamp(0.0, 1.0);
                return Transform.scale(
                  scale: 0.92 + (progress * 0.08),
                  // Align animation to the side the menu is anchored to
                  alignment:
                      isRightAligned ? Alignment.topRight : Alignment.topLeft,
                  child: Opacity(opacity: progress, child: child),
                );
              },
              child: Material(
                elevation: elevation ?? 8,
                borderRadius:
                    shape is RoundedRectangleBorder
                        ? shape.borderRadius as BorderRadius?
                        : BorderRadius.circular(12),
                color: color ?? context.colors.surfaceRecessed,
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: constraints ?? const BoxConstraints(),
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children:
                          items.map((item) {
                            if (item is PopupMenuItem<T>) {
                              return InkWell(
                                onTap: () {
                                  if (item.onTap != null) {
                                    item.onTap!();
                                  }
                                  closeMenu(item.value);
                                },
                                child: Padding(
                                  padding: item.padding ?? EdgeInsets.zero,
                                  child: item.child,
                                ),
                              );
                            } else if (item is PopupMenuDivider) {
                              return Divider(
                                height: item.height,
                                thickness: 0.5,
                                color: Colors.white.withValues(alpha: 0.1),
                              );
                            }
                            return const SizedBox.shrink();
                          }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  overlay.insert(overlayEntry);

  return completer.future;
}

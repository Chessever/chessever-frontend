import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// One row in a long-press context menu.
@immutable
class LibraryMenuAction {
  const LibraryMenuAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;

  /// Runs after the menu has closed, so the action is free to push routes,
  /// open sheets or show snacks against the host screen.
  final FutureOr<void> Function() onSelected;

  /// Renders in the danger colour and sits behind a stronger separator.
  final bool destructive;

  final bool enabled;
}

/// Fixed row height. The layout math below positions the menu against the
/// pressed card *before* it is laid out, so rows must be a known constant.
///
/// Sits exactly on the platform's 44dp minimum: the menu should be as compact
/// as it can be without any row becoming harder to hit.
const double _kRowHeight = 44.0;

/// Rows scale up with the design system but never below the platform's 44dp
/// minimum tap target — `.h` shrinks on short screens, which would otherwise
/// make every action harder to hit on exactly the phones with least room.
double _rowHeight() => math.max(_kRowHeight, _kRowHeight.h);
const double _kSeparator = 1.0;
const double _kGap = 8.0;
const double _kScreenMargin = 16.0;
const double _kMinMenuWidth = 200.0;

/// Long-press context menu for library cards.
///
/// The pressed card stays lit while everything else dims, and the action list
/// opens anchored to it — so the menu reads as belonging to that one row rather
/// than floating in from nowhere. [previewBuilder] should rebuild the same card
/// that was pressed; it is painted at the card's exact on-screen rect.
///
/// Dismisses on scrim tap and on Android back (it is a real route, not an
/// overlay entry). The selected action runs *after* the pop completes.
Future<void> showLibraryContextMenu({
  required BuildContext context,
  required List<LibraryMenuAction> actions,
  WidgetBuilder? previewBuilder,
  VoidCallback? onPreviewTap,
}) async {
  if (actions.isEmpty) return;

  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return;
  final anchorRect =
      renderObject.localToGlobal(Offset.zero) & renderObject.size;

  // The press is what summoned the menu, so the confirmation belongs to the
  // press — raised here rather than at each call site so no host can forget it.
  HapticFeedbackService.contextMenu();

  final selected = await showGeneralDialog<LibraryMenuAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: context.colors.scrim,
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, _, __) {
      return _LibraryContextMenuLayer(
        animation: animation,
        anchorRect: anchorRect,
        actions: actions,
        previewBuilder: previewBuilder,
        onPreviewTap:
            onPreviewTap == null
                ? null
                : () {
                  Navigator.of(dialogContext).pop();
                  onPreviewTap();
                },
      );
    },
  );

  if (selected == null) return;
  await selected.onSelected();
}

class _LibraryContextMenuLayer extends StatefulWidget {
  const _LibraryContextMenuLayer({
    required this.animation,
    required this.anchorRect,
    required this.actions,
    required this.previewBuilder,
    required this.onPreviewTap,
  });

  final Animation<double> animation;
  final Rect anchorRect;
  final List<LibraryMenuAction> actions;
  final WidgetBuilder? previewBuilder;
  final VoidCallback? onPreviewTap;

  @override
  State<_LibraryContextMenuLayer> createState() =>
      _LibraryContextMenuLayerState();
}

class _LibraryContextMenuLayerState extends State<_LibraryContextMenuLayer> {
  /// Spring target for the pop. Fade stays on the route's own animation, so a
  /// spring that never advances still leaves a fully visible, usable menu.
  double _pop = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _pop = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final animation = widget.animation;
    final anchorRect = widget.anchorRect;
    final actions = widget.actions;
    final previewBuilder = widget.previewBuilder;
    final onPreviewTap = widget.onPreviewTap;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final topLimit = media.padding.top + 12.h;
    final bottomLimit = screen.height - media.padding.bottom - 12.h;
    final available = bottomLimit - topLimit;

    // The minimum yields to the maximum on a narrow viewport (split screen,
    // small phone in landscape) so the clamp can never invert.
    final maxWidth = math.max(screen.width - 2 * _kScreenMargin.w, 1.0);
    final minWidth = math.min(_kMinMenuWidth.w, maxWidth);
    final width = anchorRect.width.clamp(minWidth, maxWidth).toDouble();
    final left =
        anchorRect.left
            .clamp(
              _kScreenMargin.w,
              math.max(
                screen.width - _kScreenMargin.w - width,
                _kScreenMargin.w,
              ),
            )
            .toDouble();

    final menuHeight =
        actions.length * _rowHeight() + (actions.length - 1) * _kSeparator;
    final previewHeight = previewBuilder == null ? 0.0 : anchorRect.height;

    // Preview + menu only survive together when they actually fit between the
    // safe-area edges; otherwise the card is dropped so the menu is never the
    // thing that gets clipped.
    var showPreview =
        previewBuilder != null &&
        previewHeight + _kGap.h + menuHeight <= available;

    final blockHeight =
        showPreview ? previewHeight + _kGap.h + menuHeight : menuHeight;

    double top;
    double? maxMenuHeight;
    if (blockHeight <= available) {
      top =
          anchorRect.top.clamp(topLimit, bottomLimit - blockHeight).toDouble();
    } else {
      // Menu alone is taller than the viewport (never expected with the current
      // action sets, but a long list must scroll rather than overflow).
      showPreview = false;
      top = topLimit;
      maxMenuHeight = math.max(available, _rowHeight());
    }

    // `drive` instead of CurvedAnimation: this widget has no State to dispose
    // one from, and the derived animation needs no lifecycle of its own.
    final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));

    // The menu grows out of the edge it is attached to, so the motion reads as
    // the card opening rather than a panel appearing.
    final menuOrigin = showPreview ? Alignment.topCenter : Alignment.centerLeft;

    // showGeneralDialog's transitionBuilder has no Material ancestor of its
    // own. Without one, Text/Icon in the action rows (and any Text in a
    // preview card) hit Flutter's yellow double-underline debug style.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            child: FadeTransition(
              opacity: curved,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showPreview) ...[
                    ScaleTransition(
                      scale: Tween<double>(begin: 1, end: 1.03).animate(curved),
                      // Deliberately unconstrained in height: the fit maths above
                      // uses the measured card height, but forcing it here would
                      // crop the copy if it laid out even a pixel taller.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onPreviewTap,
                        // The preview is a rebuilt copy of the card; its own
                        // tap/long-press handlers must stay inert so the only
                        // live gesture is the one this layer owns.
                        child: IgnorePointer(child: previewBuilder!(context)),
                      ),
                    ),
                    SizedBox(height: _kGap.h),
                  ],
                  // Spring-driven pop, so the menu arrives with physics rather
                  // than on a fixed curve — it settles the way every other
                  // surface in the app does.
                  SingleMotionBuilder(
                    motion: const CupertinoMotion.snappy(),
                    value: _pop,
                    builder: (context, value, child) {
                      // A spring only ever asymptotes towards its target, so
                      // the last frames sit at 0.999998 — enough to shave the
                      // painted row under the 44dp minimum and to resample the
                      // text a fraction blurry. Settle on exact identity.
                      final t = value.clamp(0.0, 1.4);
                      final scale =
                          (t - 1).abs() < 0.002 ? 1.0 : 0.94 + 0.06 * t;
                      return Transform.scale(
                        scale: scale,
                        alignment: menuOrigin,
                        child: child,
                      );
                    },
                    child: _MenuSurface(
                      actions: actions,
                      maxHeight: maxMenuHeight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuSurface extends StatelessWidget {
  const _MenuSurface({required this.actions, this.maxHeight});

  final List<LibraryMenuAction> actions;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      final action = actions[i];
      if (i > 0) {
        final previous = actions[i - 1];
        rows.add(
          Divider(
            height: _kSeparator,
            thickness: _kSeparator,
            // A destructive action earns a heavier rule so it never reads as
            // the next item in the list.
            color:
                action.destructive && !previous.destructive
                    ? context.colors.dividerStrong
                    : context.colors.divider,
          ),
        );
      }
      rows.add(_MenuRow(action: action));
    }

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );

    return Container(
      decoration: BoxDecoration(
        color: context.colors.popup,
        borderRadius: BorderRadius.circular(14.br),
        boxShadow: [
          // One light source, low offset, no spread — depth without a bloom.
          BoxShadow(
            color: context.colors.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child:
          maxHeight == null
              ? column
              : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight!),
                child: SingleChildScrollView(child: column),
              ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.action});

  final LibraryMenuAction action;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final base =
        action.destructive ? context.colors.danger : context.colors.textPrimary;
    final iconBase =
        action.destructive ? context.colors.danger : context.colors.iconPrimary;
    final foreground = action.enabled ? base : base.withValues(alpha: 0.35);
    final iconColor =
        action.enabled ? iconBase : iconBase.withValues(alpha: 0.35);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: action.enabled ? (_) => _setPressed(true) : null,
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap:
          action.enabled
              ? () {
                HapticFeedbackService.light();
                Navigator.of(context).pop(action);
              }
              : null,
      child: Container(
        height: _rowHeight(),
        padding: EdgeInsets.symmetric(horizontal: 13.w),
        color:
            _pressed
                ? context.colors.textPrimary.withValues(alpha: 0.07)
                : Colors.transparent,
        child: Row(
          children: [
            // Every Material glyph renders in a square box at this size, so the
            // icons sit flush with the row's own padding and every label starts
            // on the same axis — no phantom inset from a wider lead column.
            Icon(action.icon, size: 17.sp, color: iconColor),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textSmMedium.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

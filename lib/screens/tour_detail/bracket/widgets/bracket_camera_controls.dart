import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';

class BracketCameraControls extends StatelessWidget {
  const BracketCameraControls({
    required this.onZoomOut,
    required this.onToggleOverview,
    required this.onZoomIn,
    required this.isOverview,
    super.key,
  });

  final VoidCallback onZoomOut;
  final VoidCallback onToggleOverview;
  final VoidCallback onZoomIn;
  final bool isOverview;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      key: const ValueKey('bracket-camera-controls'),
      color: colors.popup.withValues(alpha: 0.96),
      elevation: 0,
      shadowColor: colors.shadow,
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CameraButton(
              key: const ValueKey('bracket-zoom-out'),
              tooltip: 'Zoom out',
              icon: Icons.remove_rounded,
              onPressed: onZoomOut,
            ),
            _Divider(color: colors.divider),
            _CameraButton(
              key: const ValueKey('bracket-fit-reset'),
              tooltip: isOverview ? 'Focus current round' : 'Fit whole bracket',
              icon:
                  isOverview
                      ? Icons.center_focus_strong_rounded
                      : Icons.fit_screen_rounded,
              isAccent: isOverview,
              onPressed: onToggleOverview,
            ),
            _Divider(color: colors.divider),
            _CameraButton(
              key: const ValueKey('bracket-zoom-in'),
              tooltip: 'Zoom in',
              icon: Icons.add_rounded,
              onPressed: onZoomIn,
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraButton extends StatelessWidget {
  const _CameraButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isAccent = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkResponse(
          onTap: () {
            HapticFeedbackService.buttonPress();
            onPressed();
          },
          radius: 26,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color:
                  isAccent ? context.colors.brand : context.colors.iconPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 22, color: color.withValues(alpha: 0.8));
}

class BracketGestureHint extends StatelessWidget {
  const BracketGestureHint({required this.visible, super.key});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IgnorePointer(
      child: AnimatedOpacity(
        key: const ValueKey('bracket-gesture-hint'),
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: colors.popup.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: colors.divider),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.open_with_rounded,
                color: colors.iconSecondary,
                size: 15,
              ),
              const SizedBox(width: 7),
              Text(
                'Drag to move · Pinch to zoom',
                style: TextStyle(
                  fontFamily: 'InterDisplay',
                  color: colors.textPrimaryMuted,
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BracketPartialNote extends StatelessWidget {
  const BracketPartialNote({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'Pairings appear as they are published',
      child: Container(
        key: const ValueKey('bracket-partial-note'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: colors.popup.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, color: colors.iconSecondary, size: 14),
            const SizedBox(width: 6),
            Text(
              'Pairings appear as they are published',
              style: TextStyle(
                fontFamily: 'InterDisplay',
                color: colors.textSecondary,
                fontSize: 10.5,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

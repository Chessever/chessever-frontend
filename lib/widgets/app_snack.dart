import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Semantic weight of a snack. Only the ink changes — the capsule itself is
/// always the same black object, so two stacked toasts never fight each other
/// for attention the way a red bar next to a grey bar used to.
enum AppSnackTone { neutral, danger, success }

/// The one and only way to raise a transient message in this app.
///
/// Deliberate properties, in order of how often they were gotten wrong before
/// this existed:
///
/// * **It always auto-dismisses.** Flutter >=3.38 flips `SnackBar.persist` to
///   true whenever an action is present, which pinned "Removed from …" banners
///   over unrelated screens forever. Every snack built here passes
///   `persist: false`.
/// * **One at a time.** Showing a snack retires the current one instead of
///   queueing behind it, so a stale message can never outlive its screen.
/// * **Black, in both themes.** The capsule is the app's ink, not the theme's
///   surface, so the message reads as a layer floating over the product rather
///   than a piece of the page.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showAppSnack(
  BuildContext context,
  String message, {
  AppSnackTone tone = AppSnackTone.neutral,
  String? actionLabel,
  FutureOr<void> Function()? onAction,
  Duration? duration,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return null;
  return showAppSnackOn(
    messenger,
    message,
    tone: tone,
    actionLabel: actionLabel,
    onAction: onAction,
    duration: duration,
  );
}

/// [showAppSnack] for callers that captured the messenger before an `await`
/// (the safe pattern when the originating widget can unmount mid-flight).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackOn(
  ScaffoldMessengerState messenger,
  String message, {
  AppSnackTone tone = AppSnackTone.neutral,
  String? actionLabel,
  FutureOr<void> Function()? onAction,
  Duration? duration,
}) {
  final life = duration ?? _defaultDuration(tone: tone, hasAction: actionLabel != null);
  // Replace rather than queue: a message that has to wait its turn is stale by
  // the time it lands.
  messenger.hideCurrentSnackBar();

  final width = _capsuleWidth(messenger.context);

  return messenger.showSnackBar(
    SnackBar(
      duration: life,
      // Non-negotiable — see the class doc.
      persist: false,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      // The capsule casts its own shadow; hard-edge clipping would shear it
      // off at the snack bounds and leave a visible seam under the object.
      clipBehavior: Clip.none,
      margin: width == null ? EdgeInsets.fromLTRB(12.sp, 0, 12.sp, 12.sp) : null,
      width: width,
      dismissDirection: DismissDirection.down,
      content: _AppSnackCapsule(
        message: message,
        tone: tone,
        actionLabel: actionLabel,
        onAction: onAction,
        life: life,
      ),
    ),
  );
}

Duration _defaultDuration({required AppSnackTone tone, required bool hasAction}) {
  if (hasAction) return const Duration(seconds: 5);
  return tone == AppSnackTone.danger
      ? const Duration(seconds: 4)
      : const Duration(seconds: 3);
}

/// Phones get edge margins; anything wider gets a centred capsule so the text
/// never stretches into an unreadable single line across a tablet.
double? _capsuleWidth(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  if (screenWidth < 560) return null;
  return math.min(520, screenWidth - 96);
}

// Ink. Pure neutral black — no blue-slate, no theme surface.
const Color _capsuleInk = Color(0xFF08080A);
const Color _dangerInk = Color(0xFFFF8F84);
const Color _successInk = Color(0xFF5CD08A);

class _AppSnackCapsule extends StatelessWidget {
  const _AppSnackCapsule({
    required this.message,
    required this.tone,
    required this.actionLabel,
    required this.onAction,
    required this.life,
  });

  final String message;
  final AppSnackTone tone;
  final String? actionLabel;
  final FutureOr<void> Function()? onAction;
  final Duration life;

  Color get _messageColor => switch (tone) {
    AppSnackTone.neutral => Colors.white.withValues(alpha: 0.94),
    AppSnackTone.danger => _dangerInk,
    AppSnackTone.success => _successInk,
  };

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16.br);
    // Entrance is ~250ms before the dismiss timer starts; matching it here
    // keeps the drain rule honest about how long is actually left.
    final drainLife = life + const Duration(milliseconds: 250);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Container(
      decoration: BoxDecoration(
        color: _capsuleInk,
        borderRadius: radius,
        // Self-coloured edge: felt as a lip catching light, not read as a
        // drawn outline.
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          // One tight, low-offset, self-tinted shadow. Enough to lift the
          // capsule off a near-black app background; never a bloom.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Padding(
              // With an action the row gives up its own right/vertical inset:
              // the label's tap target (which has to clear 44dp) supplies the
              // spacing instead, so the capsule keeps one optical rhythm
              // rather than double-padding the button.
              padding:
                  actionLabel == null
                      ? EdgeInsets.fromLTRB(16.sp, 13.sp, 16.sp, 15.sp)
                      : EdgeInsets.fromLTRB(16.sp, 6.sp, 8.sp, 8.sp),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textSmMedium.copyWith(
                        color: _messageColor,
                      ),
                    ),
                  ),
                  if (actionLabel != null) ...[
                    SizedBox(width: 12.sp),
                    _SnackActionLabel(
                      label: actionLabel!,
                      // Cyan is the app's single accent, but it collides with
                      // the red of an error, so a danger snack answers in white.
                      color:
                          tone == AppSnackTone.danger
                              ? Colors.white.withValues(alpha: 0.95)
                              : kPrimaryColor,
                      onPressed: onAction,
                    ),
                  ],
                ],
              ),
            ),
            // Specular lip: a hairline of light catching the top edge, fading
            // out before either corner so it reads as a lit surface rather
            // than a second drawn border.
            Positioned(
              top: 0,
              left: 14.sp,
              right: 14.sp,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.16),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // The one authored detail: a hairline that drains along the bottom
            // edge for exactly as long as the snack has left to live, so the
            // capsule tells you it is about to leave instead of just leaving.
            if (!reduceMotion)
              Positioned(
                left: 16.sp,
                right: 16.sp,
                bottom: 6.sp,
                height: 2,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 1, end: 0),
                  duration: drainLife,
                  curve: Curves.linear,
                  builder: (context, value, _) {
                    return FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _messageColor.withValues(alpha: 0.26),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SnackActionLabel extends StatelessWidget {
  const _SnackActionLabel({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final FutureOr<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8.br),
        onTap: () {
          // Same contract as SnackBarAction: acting on a snack closes it.
          ScaffoldMessenger.of(context).hideCurrentSnackBar(
            reason: SnackBarClosedReason.action,
          );
          onPressed?.call();
        },
        // 44dp minimum: the label is small, the thing you press is not. Raw
        // dp on purpose — a tap target is an accessibility floor, so it must
        // not shrink with the responsive scale on smaller devices.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.sp),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: AppTypography.textSmSemiBold.copyWith(color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

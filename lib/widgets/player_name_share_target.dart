import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Tappable player/team identity that opens the existing share preview.
///
/// Optional [showShareHint] draws a quiet north-east arrow beside the name —
/// the same 45° “open/share” cue many apps use — without bringing back a
/// permanent share button in the app-bar actions next to the heart.
///
/// Use [compactHint] when the identity is centered (player profile): the arrow
/// hugs the name. Leave it false for leading app-bar titles (scorecards) where
/// the name row should keep filling available width.
class PlayerNameShareTarget extends StatelessWidget {
  const PlayerNameShareTarget({
    required this.playerName,
    required this.onShare,
    required this.child,
    this.showShareHint = true,
    this.compactHint = false,
    this.coachmarkKey,
    this.coachmarkMessage,
    super.key,
  });

  final String playerName;
  final Future<void> Function() onShare;
  final Widget child;
  final bool showShareHint;
  final bool compactHint;
  final GlobalKey<TooltipState>? coachmarkKey;
  final String? coachmarkMessage;

  @override
  Widget build(BuildContext context) {
    final Widget labeled;
    if (!showShareHint) {
      labeled = child;
    } else if (compactHint) {
      labeled = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: child),
          SizedBox(width: 4.w),
          Icon(
            Icons.arrow_outward_rounded,
            size: 14.ic,
            color: context.colors.textTertiary,
          ),
        ],
      );
    } else {
      labeled = Row(
        children: [
          Flexible(child: child),
          SizedBox(width: 4.w),
          Icon(
            Icons.arrow_outward_rounded,
            size: 14.ic,
            color: context.colors.textTertiary,
          ),
        ],
      );
    }

    final target = Semantics(
      button: true,
      label: 'Share $playerName',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          Tooltip.dismissAllToolTips();
          await onShare();
        },
        child: labeled,
      ),
    );

    final message = coachmarkMessage?.trim();
    if (message == null || message.isEmpty) return target;
    return Tooltip(
      key: coachmarkKey,
      message: message,
      triggerMode: TooltipTriggerMode.manual,
      preferBelow: true,
      showDuration: const Duration(seconds: 6),
      child: target,
    );
  }
}

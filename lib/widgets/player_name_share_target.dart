import 'package:flutter/material.dart';

class PlayerNameShareTarget extends StatelessWidget {
  const PlayerNameShareTarget({
    required this.playerName,
    required this.onShare,
    required this.child,
    this.coachmarkKey,
    this.coachmarkMessage,
    super.key,
  });

  final String playerName;
  final Future<void> Function() onShare;
  final Widget child;
  final GlobalKey<TooltipState>? coachmarkKey;
  final String? coachmarkMessage;

  @override
  Widget build(BuildContext context) {
    final target = Semantics(
      button: true,
      label: 'Share $playerName',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          Tooltip.dismissAllToolTips();
          await onShare();
        },
        child: child,
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

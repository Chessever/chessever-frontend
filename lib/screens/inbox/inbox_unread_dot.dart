import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// In-app brand cyan, not a native app-icon badge or notification permission.
class InboxUnreadDot extends StatelessWidget {
  const InboxUnreadDot({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Unread Inbox message',
    child: Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: kPrimaryColor,
        shape: BoxShape.circle,
      ),
    ),
  );
}

class InboxAvatarBadge extends StatelessWidget {
  const InboxAvatarBadge({
    super.key,
    required this.unread,
    required this.child,
  });
  final bool unread;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      child,
      if (unread)
        const Positioned(
          top: 0,
          right: 0,
          child: InboxUnreadDot(key: ValueKey('inbox-avatar-dot')),
        ),
    ],
  );
}

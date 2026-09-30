import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/most_liked_screen.dart';
import 'package:chessever2/screens/my_likes/my_likes_hub_screen.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';

/// Personal likes and community rankings share one Discovery destination.
class LikesScreen extends StatelessWidget {
  const LikesScreen({super.key});

  static Future<void> open(BuildContext context) {
    HapticFeedbackService.cardTap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LikesScreen()));
  }

  @override
  Widget build(BuildContext context) => EventViewShell(
    title: 'Likes',
    titleIcon: Icon(Icons.favorite_rounded),
    tabs: const ['My Likes', 'Most Liked'],
    pageBuilder: (context, index) => _LikesTab(
      key: ValueKey('likes_tab_$index'),
      child: index == 0
          ? const MyLikesHubScreen(embedded: true)
          : const MostLikedScreen(embedded: true),
    ),
  );
}

/// Switching between personal likes and rankings keeps each one's selected
/// secondary tab, search/filter state, and scroll position.
class _LikesTab extends StatefulWidget {
  const _LikesTab({super.key, required this.child});

  final Widget child;

  @override
  State<_LikesTab> createState() => _LikesTabState();
}

class _LikesTabState extends State<_LikesTab>
    with AutomaticKeepAliveClientMixin<_LikesTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

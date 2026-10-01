import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/most_liked_screen.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_event_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hub_tile.dart' show hubGutter;
import 'package:chessever2/widgets/hub_tile_captions.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';

/// Community rankings, with a door to the separate personal archive.
class LikesScreen extends StatefulWidget {
  const LikesScreen({super.key});

  static Future<void> open(BuildContext context) {
    HapticFeedbackService.cardTap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LikesScreen()));
  }

  @override
  State<LikesScreen> createState() => _LikesScreenState();
}

class _LikesScreenState extends State<LikesScreen> {
  final _tabs = EventViewController();
  MostLikedPlayer? _player;

  void _pickPlayer(MostLikedPlayer player) {
    setState(() => _player = player);
    _tabs.showTab(1, scrollToTop: true);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EventViewShell(
    title: 'Likes',
    titleIcon: const Icon(Icons.favorite_rounded),
    tabs: const ['About', 'Games', 'Players'],
    controller: _tabs,
    pageBuilder: (context, index) => _LikesTab(
      key: ValueKey('likes_tab_$index'),
      child: index == 0
          ? const LikesAboutPage()
          : MostLikedPage(
              view: index == 1 ? MostLikedView.games : MostLikedView.players,
              playerFilter: _player,
              onPickPlayer: _pickPlayer,
              onClearPlayerFilter: () => setState(() => _player = null),
            ),
    ),
  );
}

/// Each ranking page keeps its filter and scroll position across tab changes.
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

/// The community ranking explained beside its personal-archive entry point.
class LikesAboutPage extends ConsumerWidget {
  const LikesAboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(likedGamesProvider.select(likesSummary));
    return ListView(
      padding: EdgeInsets.only(top: 12.h, bottom: 32.h),
      children: [
        DiscoveryEventCard(
          key: const ValueKey('discovery_my_likes_card'),
          title: 'My Likes',
          caption: hubLikesCaption(summary),
          artSection: SpaceSection.likes,
          centerContent: true,
          onOpen: () {
            HapticFeedbackService.cardTap();
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MyLikesScreen()),
            );
          },
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(hubGutter, 28.h, hubGutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Games the community loves',
                style: AppTypography.textLgMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                'Games ranks the most liked games for the selected day, week, '
                'month or year. Players shows everyone involved in those games, '
                'ranked by their games’ total likes. Choose a player to see '
                'their games in the ranking.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              SizedBox(height: 20.h),
              Text(
                'Double-tap the chessboard or tap its heart to like a game. '
                'Your saved games are in My Likes, also available in Library.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              SizedBox(height: 20.h),
              Text(
                'Today’s games are free. Premium opens earlier dates, weekly, '
                'monthly and yearly rankings, and the Players list.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/utils/player_menu_actions.dart';
import 'package:chessever2/screens/player_profile/widgets/lifted_row_menu.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// "‹  21–27 Sep  ›": walks the picked period one day, week, month or year
/// at a time. Earlier periods are Premium for free accounts, shown by the
/// padlock beside the arrow, and stop at the first day there were likes; the
/// next arrow is disabled on the current period, since the future has no
/// ranking. The page's one date control ([DiscoveryDateStepper]), so it
/// reads exactly like the Miniatures one.
class MostLikedDateControl extends StatelessWidget {
  const MostLikedDateControl({
    super.key,
    required this.query,
    required this.now,
    required this.locked,
    required this.onPrevious,
    required this.onNext,
    this.edgeInset = 0,
  });

  final MostLikedQuery query;
  final DateTime now;

  /// Earlier periods sit behind the Premium boundary for this viewer.
  final bool locked;

  /// Null when there is no earlier period to go to.
  final VoidCallback? onPrevious;

  /// Null on the current period.
  final VoidCallback? onNext;

  /// See [DiscoveryDateStepper.edgeInset].
  final double edgeInset;

  String get _unit => switch (query.period) {
    MostLikedPeriod.today => 'day',
    MostLikedPeriod.week => 'week',
    MostLikedPeriod.month => 'month',
    MostLikedPeriod.year => 'year',
  };

  @override
  Widget build(BuildContext context) {
    final label = query.label(now);
    return DiscoveryDateStepper(
      label: label,
      labelSemantics: 'Most liked, $label',
      previousSemantics: locked
          ? 'Previous $_unit, Premium'
          : 'Previous $_unit',
      nextSemantics: 'Next $_unit',
      previousLocked: locked,
      onPrevious: onPrevious,
      onNext: onNext,
      edgeInset: edgeInset,
    );
  }
}

/// The Players view: everyone with a game in the ranking, most-liked first.
/// Each row reads like the Miniatures Players leaderboard (rank, photo,
/// flag and rating, the likes where Miniatures has W-L) but in Discovery's
/// own compact voice, and every text in it can shrink before it overflows.
/// A tap opens the player's profile.
class MostLikedPlayersList extends StatelessWidget {
  const MostLikedPlayersList({super.key, required this.players});

  final List<MostLikedPlayer> players;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in players)
            _PlayerRow(
              key: ValueKey('most_liked_player_${row.rank}'),
              row: row,
            ),
        ],
      ),
    );
  }
}

class _PlayerRow extends ConsumerWidget {
  const _PlayerRow({super.key, required this.row});

  final MostLikedPlayer row;

  void _open(BuildContext context) {
    HapticFeedbackService.cardTap();
    final p = row.player;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerProfileScreen(
          fideId: p.fideId,
          playerName: p.name,
          title: p.title.trim().isEmpty ? null : p.title.trim(),
          federation: p.countryCode.trim().isEmpty
              ? null
              : p.countryCode.trim(),
          rating: p.rating > 0 ? p.rating : null,
          gamebasePlayerId: p.gamebasePlayerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = row.player;
    final photo = ref.watch(playerPhotoProvider(p.fideId)).valueOrNull;
    final title = p.title.trim();
    final flag = p.countryCode.trim();
    final games = row.games == 1 ? '1 game' : '${row.games} games';
    final detail = [if (p.rating > 0) '${p.rating}', games].join(' · ');

    // Long-press lifts the row into the shared focus menu. The row's one
    // semantics node sits above the menu and carries both actions, so a
    // screen reader can open the profile and reach the menu from the row.
    final menu = LiftedRowMenu(
      onPreviewTap: () => _open(context),
      actions: (rowContext) => playerMenuActions(
        rowContext,
        ref,
        playerName: p.name,
        fideId: p.fideId,
        title: title.isEmpty ? null : title,
        federation: flag.isEmpty ? null : flag,
        rating: p.rating > 0 ? p.rating : null,
        gamebasePlayerId: p.gamebasePlayerId,
        onOpen: () {
          if (context.mounted) _open(context);
        },
      ),
      child: _buildRow(context, photo: photo, title: title, detail: detail),
    );
    final likes = discoveryLikes(row.likes);
    return Builder(
      builder: (rowContext) => Semantics(
        container: true,
        button: true,
        label:
            '${row.rank}, ${[if (title.isNotEmpty) title, p.name].join(' ')}, '
            '$detail, $likes',
        onTap: () => _open(context),
        onLongPress: () => menu.open(rowContext),
        onLongPressHint: 'More actions',
        excludeSemantics: true,
        child: menu,
      ),
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required String? photo,
    required String title,
    required String detail,
  }) {
    final p = row.player;
    final flag = p.countryCode.trim();

    return WallPressable(
      pressScale: 0.98,
      onTap: () => _open(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 56.w),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.w),
          child: Row(
            children: [
              SizedBox(
                width: 20.w,
                child: Text(
                  '${row.rank}',
                  maxLines: 1,
                  style: discoveryType(
                    context,
                    DiscoveryType.label,
                    weight: FontWeight.w700,
                    tabular: true,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              PlayerInitialsAvatar(
                photoUrl: photo,
                initials: wallInitials(p.name),
                size: 40.w,
                borderRadius: 4.br,
                title: title.isEmpty ? null : title,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: discoveryType(context, DiscoveryType.body),
                    ),
                    SizedBox(height: 2.w),
                    Row(
                      children: [
                        if (FederationFlag.hasVisibleFlag(flag)) ...[
                          FederationFlag(
                            federation: flag,
                            width: 16.w,
                            height: 11.w,
                            borderRadius: BorderRadius.circular(2.br),
                          ),
                          SizedBox(width: 6.w),
                        ],
                        Flexible(
                          child: Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: discoveryType(
                              context,
                              DiscoveryType.meta,
                              tabular: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              DiscoveryLikes(likes: row.likes),
            ],
          ),
        ),
      ),
    );
  }
}

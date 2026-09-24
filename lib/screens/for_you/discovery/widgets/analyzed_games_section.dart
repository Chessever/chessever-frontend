import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Premium outcome Analyzed Games sells.
const String kAnalyzedGamesUpgradeCta = 'See turning points';

/// Analyzed games: the strongest finished games of the last days that already
/// carry a full engine review. Premium opens them on the board with the
/// review; free accounts see the same cards with the padlock notch, and a tap
/// leads to the Premium boundary first.
class AnalyzedGamesSection extends ConsumerWidget {
  const AnalyzedGamesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribed = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );
    final analyzed = ref.watch(discoveryAnalyzedGamesProvider);

    void open(List<GamesTourModel> games, int index) {
      if (subscribed) {
        openDiscoveryGame(context, ref, games, index);
        return;
      }
      unlockThen(
        context,
        ref,
        () => openDiscoveryGame(context, ref, games, index),
        featureId: 'analyzed_games',
        returnTo: discoveryReturnTo('analyzed_games'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const DiscoverySectionHeader(title: 'Analyzed games'),
        SizedBox(height: 8.w),
        analyzed.when(
          data: (games) {
            if (games.isEmpty) {
              return const DiscoveryNotice(
                text: 'No analyzed games in the last three days',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DiscoveryRail(
                  children: [
                    for (var i = 0; i < games.length; i++)
                      DiscoveryGridGame(
                        key: ValueKey('analyzed_${games[i].gameId}'),
                        games: games,
                        index: i,
                        locked: !subscribed,
                        label: _meta(games[i]),
                        onOpen: open,
                      ),
                  ],
                ),
                if (!subscribed) ...[
                  SizedBox(height: 4.w),
                  DiscoveryUpgradeLine(
                    label: kAnalyzedGamesUpgradeCta,
                    onTap: () => open(games, 0),
                  ),
                ],
              ],
            );
          },
          loading: () {
            final card = discoveryGridCardWidth(context);
            return DiscoverySkeletonRail(
              width: card,
              height: card + 48.w + 24.w,
            );
          },
          error: (_, __) => DiscoveryNotice(
            text: "Couldn't load analyzed games",
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(discoveryAnalyzedGamesProvider),
          ),
        ),
      ],
    );
  }

  /// "[owl] Ø 2791 · Sep 23": the average is the line's one figure, the
  /// day stays quiet. Ratings are never comma-grouped.
  static Widget _meta(GamesTourModel game) {
    final avg = discoveryAverageRating(game);
    final day = discoveryGameDay(game);
    final date = day == null ? null : discoveryDay(day);
    return DiscoveryCardMeta(
      timeControlAsset: TimeControlGlyph.assetForLabel(game.timeControl),
      parts: [
        if (avg != null) DiscoveryMetaPart.figure('$avg', prefix: 'Ø '),
        if (date != null) DiscoveryMetaPart.text(date),
      ],
      semanticsLabel: [
        if (game.timeControl?.trim().isNotEmpty ?? false)
          game.timeControl!.trim(),
        if (avg != null) 'average rating $avg',
        if (date != null) date,
      ].join(', '),
    );
  }
}

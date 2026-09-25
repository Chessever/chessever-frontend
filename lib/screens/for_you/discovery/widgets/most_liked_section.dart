import 'dart:math' as math;

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart'
    show LiveGamesBatchKey;
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/most_liked_screen.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_controls.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/board_like_heart.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Premium outcome Most Liked sells, word for word from the spec.
const String kMostLikedUpgradeCta = 'View weekly, monthly, and yearly rankings';

/// The honest line while the ranking function is not deployed.
const String kMostLikedNotLive = 'Most Liked starts once ranking is live';

/// Whether the viewer may see Premium periods. Debug builds pass the premium
/// guard for everyone, so they may pick any period too; otherwise a picked
/// Premium period that the account no longer has falls back to Today.
bool _canSeePremiumPeriods(bool subscribed) => subscribed || kDebugMode;

/// The ranking the Most liked page is on: the picked period holding the
/// walked-to day, with Premium periods and earlier days folded back to the
/// current day for an account without Premium. Watches what it reads, so a
/// page and its tabs call it from build and always agree.
MostLikedQuery mostLikedActiveQuery(WidgetRef ref, {DateTime? now}) {
  final subscribed = ref.watch(
    subscriptionProvider.select((s) => s.isSubscribed),
  );
  final premium = _canSeePremiumPeriods(subscribed);
  final picked = ref.watch(mostLikedPeriodProvider);
  final period = picked.isPremium && !premium ? MostLikedPeriod.today : picked;
  final day = ref.watch(mostLikedDayProvider);
  return MostLikedQuery(period, (premium ? day : null) ?? now ?? DateTime.now());
}

/// "[glyph] Sinquefield Cup" over a card: where the game was played. Only
/// on tablets, where the preview stands beside Miniatures and its cards
/// share that section's one-line label slot, so the two columns keep one
/// grid; on a phone the heart on the board says enough.
Widget? _eventMeta(MostLikedEntry entry) {
  final event = discoveryShortEventName(entry.eventName);
  if (event == null) return null;
  return DiscoveryCardMeta(
    timeControlAsset: TimeControlGlyph.assetForLabel(entry.game.timeControl),
    parts: [DiscoveryMetaPart.text(event)],
    semanticsLabel: entry.eventName ?? event,
  );
}

/// "[glyph] ♥ 1.1K · Sinquefield Cup" over a list row: a row has no board
/// for the heart, and its strip shows the clocks, so the likes ride here.
Widget _likesMeta(MostLikedEntry entry) {
  final event = discoveryShortEventName(entry.eventName);
  return DiscoveryCardMeta(
    timeControlAsset: TimeControlGlyph.assetForLabel(entry.game.timeControl),
    parts: [
      DiscoveryMetaPart.likes(entry.likes),
      if (event != null) DiscoveryMetaPart.text(event),
    ],
    semanticsLabel: [
      discoveryLikes(entry.likes),
      ?(entry.eventName ?? event),
    ].join(', '),
  );
}

/// Each board's like count, set in the heart on its corner.
Widget _heart(MostLikedEntry entry, double boardSize) =>
    LikeCountHeart(likes: entry.likes, size: likeHeartSizeFor(boardSize));

/// Sends the viewer through the paywall to the week's ranking on the Most
/// liked page: what the upgrade line under the free ranking sells.
Future<void> _openWeeklyRanking(BuildContext context, WidgetRef ref) {
  return unlockThen(
    context,
    ref,
    () {
      ref.read(mostLikedPeriodProvider.notifier).state = MostLikedPeriod.week;
      ref.read(mostLikedDayProvider.notifier).state = null;
      if (context.mounted) MostLikedScreen.open(context);
    },
    featureId: 'most_liked_rankings',
    returnTo: discoveryReturnTo('most_liked'),
  );
}

// ---------------------------------------------------------------- the hub

/// Discovery's Most liked: today's ranking as a short preview, laid out the
/// way an event's Games tab lays out its games (the viewer's own games view
/// setting), each board holding its like count in a heart. Four cards (two
/// boards in board view) in rank order; "See all" opens the whole ranking,
/// with its periods, dates and players, on the Most liked page. Opening any
/// card hands the board the whole ranking, so previous/next walks past the
/// preview.
///
/// Always today's ranking: a period picked on the page never moves the hub.
/// The preview is archive-cheap: no card streams or runs the engine.
class MostLikedPreview extends ConsumerWidget {
  const MostLikedPreview({super.key, this.now});

  /// Pins "today" in tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribed = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );
    final query = MostLikedQuery(MostLikedPeriod.today, now ?? DateTime.now());
    final result = ref.watch(mostLikedProvider(query));
    final labelled = ResponsiveHelper.isTablet;
    // Nothing to rank anywhere while the function is missing: no See all to
    // an empty page, and nothing sold.
    final notLive = result.valueOrNull?.status == MostLikedStatus.notLive;
    final upgrade = subscribed || notLive
        ? null
        : DiscoveryUpgradeLine(
            label: kMostLikedUpgradeCta,
            quiet: true,
            onTap: () => _openWeeklyRanking(context, ref),
          );
    void retry() => ref.invalidate(mostLikedProvider(query));

    final body = result.when(
      data: (value) {
        switch (value.status) {
          case MostLikedStatus.notLive:
            return const DiscoveryNotice(text: kMostLikedNotLive);
          case MostLikedStatus.premiumRequired:
            // Today is free; a refusal here is a server hiccup, not a sale.
            return DiscoveryNotice(
              text: "Couldn't load Most liked",
              actionLabel: 'Retry',
              onAction: retry,
            );
          case MostLikedStatus.ranked:
            break;
        }
        final entries = value.entries;
        if (entries.isEmpty) {
          return const DiscoveryNotice(text: 'No games liked yet today');
        }
        return DiscoveryGameList(
          games: [for (final e in entries) e.game],
          limit: kDiscoveryPreviewCards,
          boardLimit: kDiscoveryPreviewBoards,
          badgeFor: (i, boardSize) => _heart(entries[i], boardSize),
          labelFor: labelled ? (i) => _eventMeta(entries[i]) : null,
          rowLabelFor: (i) => _likesMeta(entries[i]),
          streamEnabled: false,
          allowStockfishFallback: false,
        );
      },
      loading: () => DiscoveryGameListSkeleton(
        count: kDiscoveryPreviewCards,
        boardCount: kDiscoveryPreviewBoards,
        labels: labelled,
        rowLabels: true,
      ),
      error: (_, __) => DiscoveryNotice(
        text: "Couldn't load Most liked",
        actionLabel: 'Retry',
        onAction: retry,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DiscoverySectionHeader(
          title: 'Most liked',
          trailing: notLive
              ? null
              : DiscoveryAction(
                  label: 'See all',
                  arrow: true,
                  semanticsLabel: 'See all of Most liked',
                  onTap: () => MostLikedScreen.open(context),
                ),
        ),
        SizedBox(height: 8.w),
        body,
        if (upgrade != null) ...[SizedBox(height: 4.w), upgrade],
      ],
    );
  }
}

// ---------------------------------------------------------------- the page

/// The Most liked page's ranking: the community ranking of games by how many
/// people liked them. Today is free; Week, Month and Year sit behind the
/// Premium boundary, and so do the date control's earlier periods and the
/// Players view (everyone with a game in the ranking). Every period is a
/// calendar one the date control walks: a day, a Monday-to-Sunday week, a
/// month, a year.
///
/// The segments pick the period and the date control under them walks it,
/// the way a calendar picks Day | Week | Month | Year over the date it
/// shows (the page's title already says Most liked). Under them, [view]
/// decides what is listed: the games, in rank order and
/// in the viewer's games view setting, each board holding its like count; or
/// the players in the ranking. Both tabs of the page share one query
/// ([mostLikedActiveQuery]), so they always rank the same period.
class MostLikedSection extends ConsumerWidget {
  const MostLikedSection({
    super.key,
    this.view = MostLikedView.games,
    this.now,
  });

  final MostLikedView view;

  /// Pins "now" in tests.
  final DateTime? now;

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    MostLikedPeriod period,
  ) async {
    if (!period.isPremium) {
      ref.read(mostLikedPeriodProvider.notifier).state = period;
      return;
    }
    await unlockThen(
      context,
      ref,
      () {
        ref.read(mostLikedPeriodProvider.notifier).state = period;
      },
      featureId: 'most_liked_rankings',
      returnTo: discoveryReturnTo('most_liked'),
    );
  }

  /// Moves the ranking to [target]. Walking back is Premium ([locked] sends
  /// it through the paywall first); arriving on the current period clears
  /// the pick, so the ranking follows the clock again.
  Future<void> _walk(
    BuildContext context,
    WidgetRef ref,
    MostLikedQuery target,
    bool locked,
  ) async {
    void apply() {
      ref.read(mostLikedDayProvider.notifier).state =
          target.isCurrent(DateTime.now()) ? null : target.start;
    }

    if (!locked) {
      apply();
      return;
    }
    await unlockThen(
      context,
      ref,
      apply,
      featureId: 'most_liked_archive',
      returnTo: discoveryReturnTo('most_liked'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribed = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );
    final premium = _canSeePremiumPeriods(subscribed);
    final locked = !subscribed;
    final now = this.now ?? DateTime.now();
    final query = mostLikedActiveQuery(ref, now: now);
    final result = ref.watch(mostLikedProvider(query));
    final previous = query.previous;
    final next = query.next(now);
    // The Players list is Premium. It opens for a subscriber, and (in debug
    // builds, where the guard lets everyone through) once the guard passed.
    final playersOpen =
        subscribed ||
        (premium && ref.watch(mostLikedViewProvider) == MostLikedView.players);

    // With the ranking function missing there is nothing to rank in any
    // period, so nothing is offered: no periods, no date to walk, no paywall.
    final notLive = result.valueOrNull?.status == MostLikedStatus.notLive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The period picker, then the one it picked: the calendar pattern
        // of a segmented Day | Week | Month | Year over the date it shows,
        // stepped by the arrows either side. Nothing while ranking is not
        // live: no periods, no date to walk, no paywall.
        if (!notLive) ...[
          // Edge to edge with the page's Games | Players switcher above it
          // (EventViewShell sets it 20 in on phones, 32 on tablets), so the
          // two controls stack on one pair of edges.
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: math.max(
                0,
                ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp) -
                    discoveryGutter,
              ),
            ),
            child: DiscoverySegments<MostLikedPeriod>(
              values: MostLikedPeriod.values,
              selected: query.period,
              label: (p) => p.label,
              locked: (p) => p.isPremium && locked,
              semanticsPrefix: 'Most liked',
              onSelect: (p) => _select(context, ref, p),
            ),
          ),
          SizedBox(height: 4.w),
          Center(
            child: MostLikedDateControl(
              query: query,
              now: now,
              locked: locked,
              onPrevious: previous == null
                  ? null
                  : () => _walk(context, ref, previous, locked),
              onNext: next == null
                  ? null
                  : () => _walk(context, ref, next, false),
            ),
          ),
          SizedBox(height: 8.w),
        ],
        if (view == MostLikedView.players && !playersOpen && !notLive)
          DiscoveryNotice(
            text: 'See everyone in this ranking',
            actionLabel: 'Unlock',
            onAction: () => unlockThen(
              context,
              ref,
              () {
                ref.read(mostLikedViewProvider.notifier).state =
                    MostLikedView.players;
              },
              featureId: 'most_liked_players',
              returnTo: discoveryReturnTo('most_liked'),
            ),
          )
        else
          result.when(
            data: (value) => _PageBody(
              result: value,
              query: query,
              view: view,
              isCurrent: query.isCurrent(now),
              isToday: query.isFree(now),
              locked: locked,
              onUpgrade: () => _select(context, ref, MostLikedPeriod.week),
              onRetry: () => ref.invalidate(mostLikedProvider(query)),
            ),
            loading: () => view == MostLikedView.players
                ? const _PlayersSkeleton()
                : const DiscoveryGameListSkeleton(
                    count: 8,
                    boardCount: kDiscoveryPreviewBoards,
                    rowLabels: true,
                  ),
            error: (_, __) => DiscoveryNotice(
              text: "Couldn't load Most liked",
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(mostLikedProvider(query)),
            ),
          ),
      ],
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.result,
    required this.query,
    required this.view,
    required this.isCurrent,
    required this.isToday,
    required this.locked,
    required this.onUpgrade,
    required this.onRetry,
  });

  final MostLikedResult result;
  final MostLikedQuery query;
  final MostLikedView view;

  /// The ranking is the current period's, so its unfinished games can move.
  final bool isCurrent;

  /// The ranking is the current day's (not an earlier day's).
  final bool isToday;

  /// Premium periods, days and the players list are behind the boundary.
  final bool locked;
  final VoidCallback onUpgrade;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (result.status) {
      case MostLikedStatus.notLive:
        // Premium would unlock the same notice, so nothing is sold until the
        // ranking is live.
        return const DiscoveryNotice(text: kMostLikedNotLive);
      case MostLikedStatus.premiumRequired:
        // The server refused a Premium window. A subscriber seeing this has
        // an entitlement that has not reached the server yet.
        return locked
            ? DiscoveryUpgradeLine(label: kMostLikedUpgradeCta, onTap: onUpgrade)
            : DiscoveryNotice(
                text: 'Your Premium is still syncing',
                actionLabel: 'Retry',
                onAction: onRetry,
              );
      case MostLikedStatus.ranked:
        break;
    }

    final entries = result.entries;
    final upgrade = locked && query.period == MostLikedPeriod.today
        ? DiscoveryUpgradeLine(label: kMostLikedUpgradeCta, onTap: onUpgrade)
        : null;

    final Widget list;
    if (entries.isEmpty) {
      list = DiscoveryNotice(
        text: isToday
            ? 'No games liked yet today'
            : query.period == MostLikedPeriod.today
            ? 'No games liked that day'
            : 'No games liked in this period',
      );
    } else if (view == MostLikedView.players) {
      final players = aggregateMostLikedPlayers(entries);
      list = players.isEmpty
          ? const DiscoveryNotice(text: 'No players in this ranking yet')
          : MostLikedPlayersList(players: players);
    } else {
      final games = [for (final e in entries) e.game];
      // The current period's unfinished broadcast games stream, all on one
      // channel for the page; nothing runs the on-device engine.
      final batches = isCurrent
          ? liveBatchKeysForGames(
              games: games,
              scopePrefix: 'most_liked_page:${query.period.name}',
            )
          : const <String, LiveGamesBatchKey>{};
      list = DiscoveryGameList(
        games: games,
        badgeFor: (i, boardSize) => _heart(entries[i], boardSize),
        rowLabelFor: (i) => _likesMeta(entries[i]),
        streamEnabled: isCurrent,
        liveBatchKeyFor: (i) => batches[games[i].gameId],
        allowStockfishFallback: false,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        list,
        if (upgrade != null) ...[SizedBox(height: 4.w), upgrade],
      ],
    );
  }
}

/// The Players list while the ranking loads: plates of its rows' final
/// geometry (rank, face, name), so nothing moves when the players land.
class _PlayersSkeleton extends StatelessWidget {
  const _PlayersSkeleton();

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.surfaceRecessed;
    return ExcludeSemantics(
      child: SkeletonWidget(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 6; i++)
                SizedBox(
                  height: MostLikedPlayersList.rowHeight,
                  child: Row(
                    children: [
                      SizedBox(width: MostLikedPlayersList.rankWidth + 8.w),
                      SizedBox.square(
                        dimension: MostLikedPlayersList.avatarSize,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: ink,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: 0.5,
                            child: SizedBox(
                              height: 10.w,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: ink,
                                  borderRadius: BorderRadius.circular(2.br),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

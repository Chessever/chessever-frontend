import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart'
    show showGameShareOverlay;
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/game_space_shortcut.dart';
import 'dart:math' as math;
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
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/board_like_heart.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_event_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Premium outcome Most Liked sells, word for word from the spec.
const String kMostLikedUpgradeCta = 'View weekly, monthly, and yearly rankings';

/// The honest line while the ranking function is not deployed.
const String kMostLikedNotLive = 'Most Liked starts once ranking is live';

/// The ranking the Most liked page is on: the picked period holding the
/// walked-to day. Every period, every date and both views are browsed the
/// same by everyone; only opening a non-Today game is gated. Watches what it
/// reads, so a page and its tabs call it from build and always agree.
MostLikedQuery mostLikedActiveQuery(WidgetRef ref, {DateTime? now}) {
  final period = ref.watch(mostLikedPeriodProvider);
  final day = ref.watch(mostLikedDayProvider);
  return MostLikedQuery(period, day ?? now ?? DateTime.now());
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

/// Discovery's compact event-style door into today's ranking. The full
/// ranking keeps its existing periods, dates and player tabs.
class MostLikedPreview extends ConsumerWidget {
  const MostLikedPreview({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = MostLikedQuery(MostLikedPeriod.today, now ?? DateTime.now());
    final result = ref.watch(mostLikedProvider(query));
    final ranking = result.valueOrNull;
    final ranked = ranking?.status == MostLikedStatus.ranked;
    final failed =
        result.hasError || ranking?.status == MostLikedStatus.premiumRequired;
    final caption = failed
        ? "Couldn't load Most liked"
        : ranking?.status == MostLikedStatus.notLive
        ? kMostLikedNotLive
        : ranked && ranking!.entries.isEmpty
        ? 'No games liked yet today'
        : "Today's community favorites";
    return DiscoveryEventCard(
      key: const ValueKey('discovery_most_liked_card'),
      title: 'Most liked',
      artSection: SpaceSection.likes,
      count: ranked ? ranking!.entries.length : null,
      // The ranking is capped, so this is the returned ranked list's size,
      // rather than a claim about every game liked today.
      countQualifier: 'ranked',
      caption: caption,
      onOpen: () => MostLikedScreen.open(context),
      onRetry: failed ? () => ref.invalidate(mostLikedProvider(query)) : null,
    );
  }
}

// ---------------------------------------------------------------- the page

/// Picks a freely browsable ranking period; its game-opening action is gated.
Future<void> _selectPeriod(
  BuildContext context,
  WidgetRef ref,
  MostLikedPeriod period,
) async {
  ref.read(mostLikedPeriodProvider.notifier).state = period;
}

/// Moves the ranking to [target]. Arriving on the current period clears the
/// pick, so the ranking follows the clock again.
void _walkTo(WidgetRef ref, MostLikedQuery target) {
  ref.read(mostLikedDayProvider.notifier).state =
      target.isCurrent(DateTime.now()) ? null : target.start;
}

/// The Most liked page's period controls: the calendar pattern of a
/// segmented Today | Week | Month | Year over the period it picked, stepped
/// one day, week, month or year at a time by the arrows either side.
///
/// The page pins it above its scrolling list, so Games and Players carry the
/// same controls in the same place however far either list is scrolled.
/// Both read [mostLikedActiveQuery], so they always rank the same period.
/// Nothing while ranking is not live: no periods, no date to walk.
class MostLikedPeriodBar extends ConsumerWidget {
  const MostLikedPeriodBar({super.key, this.now});

  /// Pins "now" in tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = this.now ?? DateTime.now();
    final query = mostLikedActiveQuery(ref, now: now);
    final notLive = ref.watch(
      mostLikedProvider(
        query,
      ).select((r) => r.valueOrNull?.status == MostLikedStatus.notLive),
    );
    if (notLive) return const SizedBox.shrink();
    final previous = query.previous;
    final next = query.next(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
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
            semanticsPrefix: 'Most liked',
            onSelect: (p) => _selectPeriod(context, ref, p),
          ),
        ),
        SizedBox(height: 4.w),
        Center(
          child: MostLikedDateControl(
            query: query,
            now: now,
            onPrevious: previous == null ? null : () => _walkTo(ref, previous),
            onNext: next == null ? null : () => _walkTo(ref, next),
          ),
        ),
        SizedBox(height: 8.w),
      ],
    );
  }
}

/// The Most liked page's ranking: the community ranking of games by how many
/// people liked them. Every period, every earlier date and the Players view
/// (everyone with a game in the ranking) are browsed the same by everyone;
/// opening a game in any period goes through the Premium guard. Every
/// period is a calendar one the date control walks: a day, a
/// Monday-to-Sunday week, a month, a year.
///
/// [MostLikedPeriodBar] picks the period and walks it, pinned above this
/// list by the page. Under it, [view] decides what is listed: the games, in
/// rank order and in the viewer's games view setting, each board holding
/// its like count; or the players in the ranking. Both tabs of the page
/// share one query ([mostLikedActiveQuery]), so they always rank the same
/// period.
class MostLikedSection extends ConsumerWidget {
  const MostLikedSection({
    super.key,
    this.view = MostLikedView.games,
    this.now,
    this.playerFilter,
    this.onPickPlayer,
    this.onClearPlayerFilter,
  });

  final MostLikedView view;

  /// Pins "now" in tests.
  final DateTime? now;

  /// When set, the games view lists only this player's ranked games.
  final MostLikedPlayer? playerFilter;

  /// Tapping a player in the players view picks them; the page narrows
  /// Games to them. Null keeps the old behavior (open their profile).
  final ValueChanged<MostLikedPlayer>? onPickPlayer;

  /// Clears [playerFilter]; shown as the narrowed banner's dismiss.
  final VoidCallback? onClearPlayerFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribed = ref.watch(
      featureAccessStateProvider.select((s) => s.isSubscribed),
    );
    final locked = !subscribed;
    final now = this.now ?? DateTime.now();
    final query = mostLikedActiveQuery(ref, now: now);
    final result = ref.watch(mostLikedProvider(query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        result.when(
          data: (value) => _PageBody(
            result: value,
            query: query,
            view: view,
            isCurrent: query.isCurrent(now),
            isToday: query.isFree(now),
            locked: locked,
            onUpgrade: () => unlockThen(
              context,
              ref,
              () => ref.invalidate(mostLikedProvider(query)),
              featureId: 'most_liked_rankings',
              returnTo: discoveryReturnTo('most_liked'),
            ),
            onRetry: () => ref.invalidate(mostLikedProvider(query)),
            playerFilter: playerFilter,
            onPickPlayer: onPickPlayer,
            onClearPlayerFilter: onClearPlayerFilter,
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

class _PageBody extends ConsumerWidget {
  const _PageBody({
    required this.result,
    required this.query,
    required this.view,
    required this.isCurrent,
    required this.isToday,
    required this.locked,
    required this.onUpgrade,
    required this.onRetry,
    this.playerFilter,
    this.onPickPlayer,
    this.onClearPlayerFilter,
  });

  final MostLikedResult result;
  final MostLikedQuery query;
  final MostLikedView view;
  final MostLikedPlayer? playerFilter;
  final ValueChanged<MostLikedPlayer>? onPickPlayer;
  final VoidCallback? onClearPlayerFilter;

  /// The ranking is the current period's, so its unfinished games can move.
  final bool isCurrent;

  /// The ranking is the current day's (not an earlier day's).
  final bool isToday;

  /// Opening games in every period requires Premium access.
  final bool locked;
  final VoidCallback onUpgrade;
  final VoidCallback onRetry;

  Future<bool> _access(BuildContext context) async =>
      ensurePremiumGameAccess(
        context,
        featureId: 'most_liked_rankings',
        returnTo: discoveryReturnTo('most_liked'),
      );

  Future<void> _openRankedGame(
    BuildContext context,
    WidgetRef ref,
    List<GamesTourModel> games,
    int index,
  ) async {
    if (!await _access(context) || !context.mounted) return;
    openDiscoveryGame(context, ref, games, index);
  }

  List<LibraryMenuAction> _gameMenu(
    BuildContext context,
    WidgetRef ref,
    List<GamesTourModel> games,
    int index,
  ) {
    final game = games[index];
    final draft = gameSpaceShortcutDraft(game);
    final space = draft == null
        ? null
        : spaceMenuAction(context: context, ref: ref, draft: draft);
    return [
      LibraryMenuAction(
        icon: Icons.open_in_new_rounded,
        label: 'Open game',
        onSelected: () => _openRankedGame(context, ref, games, index),
      ),
      LibraryMenuAction(
        icon: Icons.ios_share_rounded,
        label: 'Share',
        onSelected: () async {
          if (!await _access(context) || !context.mounted) return;
          await showGameShareOverlay(context, ref, game);
        },
      ),
      if (space != null)
        LibraryMenuAction(
          icon: space.icon,
          label: space.label,
          enabled: space.enabled,
          visible: space.visible,
          onSelected: () async {
            if (!await _access(context) || !context.mounted) return;
            await space.onSelected();
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (result.status) {
      case MostLikedStatus.notLive:
        // Premium would unlock the same notice, so nothing is sold until the
        // ranking is live.
        return const DiscoveryNotice(text: kMostLikedNotLive);
      case MostLikedStatus.premiumRequired:
        // The server refused a Premium window. A subscriber seeing this has
        // an entitlement that has not reached the server yet.
        return locked
            ? DiscoveryUpgradeLine(
                label: kMostLikedUpgradeCta,
                onTap: onUpgrade,
              )
            : DiscoveryNotice(
                text: 'Your Premium is still syncing',
                actionLabel: 'Retry',
                onAction: onRetry,
              );
      case MostLikedStatus.ranked:
        break;
    }

    final entries = result.entries;
    final narrowed = playerFilter;

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
          : MostLikedPlayersList(players: players, onPick: onPickPlayer);
    } else {
      final visible = narrowed == null
          ? entries
          : [
              for (final e in entries)
                if (_hasPlayer(e, narrowed)) e,
            ];
      if (visible.isEmpty && narrowed != null) {
        list = DiscoveryNotice(
          text: 'No ranked games for ${narrowed.player.name} here',
        );
      } else {
        final games = [for (final e in visible) e.game];
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
          onOpen: (games, index) => _openRankedGame(context, ref, games, index),
          // Identical controls, with the same tap-time gate before any
          // PGN share lookup or shortcut write.
          menuActionsFor: (menuContext, index) =>
              _gameMenu(context, ref, games, index),
          badgeFor: (i, boardSize) => _heart(visible[i], boardSize),
          rowLabelFor: (i) => _likesMeta(visible[i]),
          streamEnabled: isCurrent,
          liveBatchKeyFor: (i) => batches[games[i].gameId],
          allowStockfishFallback: false,
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (narrowed != null && view == MostLikedView.games)
          _NarrowedBanner(
            name: narrowed.player.name,
            onClear: onClearPlayerFilter,
          ),
        list,
      ],
    );
  }
}

/// Whether [entry] has [picked] on either side: same FIDE id, same Gamebase
/// id, or the same name once spellings are normalized.
bool _hasPlayer(MostLikedEntry entry, MostLikedPlayer picked) {
  final want = picked.player;
  final wantName = want.name.trim().toLowerCase();
  for (final side in [entry.game.whitePlayer, entry.game.blackPlayer]) {
    if (want.fideId != null && want.fideId! > 0 && side.fideId == want.fideId) {
      return true;
    }
    if (want.gamebasePlayerId != null &&
        want.gamebasePlayerId!.isNotEmpty &&
        side.gamebasePlayerId == want.gamebasePlayerId) {
      return true;
    }
    if (wantName.isNotEmpty && side.name.trim().toLowerCase() == wantName) {
      return true;
    }
  }
  return false;
}

/// "Games by X" with a dismiss: the Games tab is narrowed to one player.
class _NarrowedBanner extends StatelessWidget {
  const _NarrowedBanner({required this.name, this.onClear});

  final String name;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(discoveryGutter, 0, discoveryGutter, 8.w),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Games by $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: discoveryType(context, DiscoveryType.label),
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticFeedbackService.cardTap();
              onClear?.call();
            },
            child: Padding(
              padding: EdgeInsets.all(4.w),
              child: Icon(
                Icons.close,
                size: 18.sp,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
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

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_controls.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/board_like_heart.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// The Premium outcome Most Liked sells, word for word from the spec.
const String kMostLikedUpgradeCta = 'View weekly, monthly, and yearly rankings';

/// The honest line while the ranking function is not deployed.
const String kMostLikedNotLive = 'Most Liked starts once ranking is live';

/// Whether the viewer may see Premium periods. Debug builds pass the premium
/// guard for everyone, so they may pick any period too; otherwise a picked
/// Premium period that the account no longer has falls back to Today.
bool _canSeePremiumPeriods(bool subscribed) => subscribed || kDebugMode;

/// Most Liked: the community ranking of games by how many people liked them.
/// Today is free; Week, Month and Year sit behind the Premium boundary, and
/// so do the date control's earlier periods and the Players view (everyone
/// with a game in the ranking). Every period is a calendar one the date
/// control walks: a day, a Monday-to-Sunday week, a month, a year.
///
/// The games sit on one rail of the app's grid cards in rank order, each
/// under one meta line (rank, likes, event). A game with no real position to
/// draw goes to a compact card below the rail instead of a made-up board.
/// Under the games, the faces of the players in the ranking open the Players
/// list in place.
class MostLikedSection extends ConsumerWidget {
  const MostLikedSection({super.key});

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

  Future<void> _selectView(
    BuildContext context,
    WidgetRef ref,
    MostLikedView view,
  ) async {
    if (!view.isPremium) {
      ref.read(mostLikedViewProvider.notifier).state = view;
      return;
    }
    await unlockThen(
      context,
      ref,
      () {
        ref.read(mostLikedViewProvider.notifier).state = view;
      },
      featureId: 'most_liked_players',
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
    final picked = ref.watch(mostLikedPeriodProvider);
    final period = picked.isPremium && !premium
        ? MostLikedPeriod.today
        : picked;
    final pickedView = ref.watch(mostLikedViewProvider);
    final view = pickedView.isPremium && !premium
        ? MostLikedView.games
        : pickedView;
    // A walked-back day is Premium too: without it the ranking is today's.
    final pickedDay = ref.watch(mostLikedDayProvider);
    final now = DateTime.now();
    final query = MostLikedQuery(period, (premium ? pickedDay : null) ?? now);
    final result = ref.watch(mostLikedProvider(query));
    final previous = query.previous;
    final next = query.next(now);
    final locked = !subscribed;

    // With the ranking function missing there is nothing to rank in any
    // period, so nothing is offered: no periods, no date to walk, no paywall.
    // Only the honest notice shows, never a muted control that answers no
    // tap.
    final notLive = result.valueOrNull?.status == MostLikedStatus.notLive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DiscoverySectionHeader(
          title: 'Most liked',
          trailingReachesEdge: true,
          trailing: notLive
              ? null
              : MostLikedDateControl(
                  query: query,
                  now: now,
                  locked: locked,
                  edgeInset: discoveryGutter,
                  onPrevious: previous == null
                      ? null
                      : () => _walk(context, ref, previous, locked),
                  onNext: next == null
                      ? null
                      : () => _walk(context, ref, next, false),
                ),
        ),
        if (notLive)
          SizedBox(height: 8.w)
        else ...[
          DiscoverySegments<MostLikedPeriod>(
            values: MostLikedPeriod.values,
            selected: period,
            label: (p) => p.label,
            locked: (p) => p.isPremium && locked,
            semanticsPrefix: 'Most liked',
            onSelect: (p) => _select(context, ref, p),
          ),
          SizedBox(height: 12.w),
        ],
        result.when(
          data: (value) => _Body(
            result: value,
            period: period,
            view: view,
            isToday: query.isFree(now),
            locked: locked,
            onUpgrade: () => _select(context, ref, MostLikedPeriod.week),
            onToggleView: () => _selectView(
              context,
              ref,
              view == MostLikedView.players
                  ? MostLikedView.games
                  : MostLikedView.players,
            ),
            onRetry: () => ref.invalidate(mostLikedProvider(query)),
          ),
          loading: () => const _MostLikedSkeleton(),
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

class _Body extends StatelessWidget {
  const _Body({
    required this.result,
    required this.period,
    required this.view,
    required this.isToday,
    required this.locked,
    required this.onUpgrade,
    required this.onToggleView,
    required this.onRetry,
  });

  final MostLikedResult result;
  final MostLikedPeriod period;
  final MostLikedView view;

  /// The ranking is the current day's (not an earlier day's).
  final bool isToday;

  /// Premium periods, days and the players list are behind the boundary.
  final bool locked;
  final VoidCallback onUpgrade;
  final VoidCallback onToggleView;
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
    final upgrade = locked && period == MostLikedPeriod.today
        ? DiscoveryUpgradeLine(label: kMostLikedUpgradeCta, onTap: onUpgrade)
        : null;

    if (entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DiscoveryNotice(
            text: isToday
                ? 'No games liked yet today'
                : period == MostLikedPeriod.today
                ? 'No games liked that day'
                : 'No games liked in this period',
          ),
          ?upgrade,
        ],
      );
    }

    final players = aggregateMostLikedPlayers(entries);
    final expanded = view == MostLikedView.players;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Ranking(entries: entries),
        if (players.isNotEmpty) ...[
          SizedBox(height: 4.w),
          _PlayersRow(
            key: const ValueKey('most_liked_players_row'),
            players: players,
            expanded: expanded,
            locked: locked,
            onTap: onToggleView,
          ),
          if (expanded) MostLikedPlayersList(players: players),
        ],
        ?upgrade,
      ],
    );
  }
}

/// The ranking in rank order, listed as an event's Games tab lists its
/// games, each board carrying its like count in a heart (a list row says it
/// under the players). The first ten show; the rest open in place. One list
/// behind every card, so the board's previous/next walks the ranking.
class _Ranking extends StatefulWidget {
  const _Ranking({required this.entries});

  final List<MostLikedEntry> entries;

  static const int _initial = 10;

  @override
  State<_Ranking> createState() => _RankingState();
}

class _RankingState extends State<_Ranking> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final shown =
        _all || entries.length <= _Ranking._initial
            ? entries
            : entries.take(_Ranking._initial).toList(growable: false);
    final rest = entries.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DiscoveryGameList(
          games: [for (final e in shown) e.game],
          badgeFor:
              (i, boardSize) => LikeCountHeart(
                likes: shown[i].likes,
                size: likeHeartSizeFor(boardSize),
              ),
          footerFor: (i) => discoveryLikes(shown[i].likes),
        ),
        if (rest > 0) ...[
          SizedBox(height: 4.w),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
            child: Align(
              alignment: Alignment.centerLeft,
              child: DiscoveryAction(
                label: rest == 1 ? 'Show 1 more' : 'Show $rest more',
                onTap: () => setState(() => _all = true),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Who is in this ranking, at a glance: the first faces stacked, the count,
/// and a disclosure that opens the full list under it (Premium for free
/// accounts, shown by the padlock). The chevron turns with the list on a
/// motor spring, and simply flips under reduced motion.
class _PlayersRow extends StatelessWidget {
  const _PlayersRow({
    super.key,
    required this.players,
    required this.expanded,
    required this.locked,
    required this.onTap,
  });

  final List<MostLikedPlayer> players;
  final bool expanded;
  final bool locked;
  final VoidCallback onTap;

  static const int _faces = 4;

  @override
  Widget build(BuildContext context) {
    final n = players.length;
    final label = n == 1
        ? '1 player in this ranking'
        : '$n players in this ranking';
    final ink = context.colors.accentText;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: Semantics(
        container: true,
        button: true,
        expanded: expanded,
        label: locked ? '$label, Premium' : label,
        onTap: onTap,
        excludeSemantics: true,
        child: WallPressable(
          pressScale: 0.98,
          onTap: onTap,
          // Collapsed, the row is the section's last line for a subscriber:
          // the room under the faces is not counted in the gap below it.
          child: DiscoveryInkFloor(
            minHeight: 44.w,
            endsSection: true,
            child: Row(
              children: [
                _FaceStack(players: players.take(_faces).toList()),
                SizedBox(width: 10.w),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: discoveryType(
                      context,
                      DiscoveryType.label,
                      weight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                ),
                if (locked) ...[
                  SizedBox(width: DiscoveryPadlock.gap),
                  const DiscoveryPadlock(),
                ],
                SizedBox(width: 6.w),
                SingleMotionBuilder(
                  motion: const CupertinoMotion.snappy(),
                  value: expanded ? 1.0 : 0.0,
                  active: !MediaQuery.disableAnimationsOf(context),
                  builder: (context, t, _) => DiscoveryChevron(
                    color: ink,
                    // Down when closed, up when open.
                    turns: 1 + 2 * t,
                    width: 6,
                    height: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to four faces, each tucked under the one before and ringed in the page
/// colour so every edge reads as a cut, not an outline.
class _FaceStack extends ConsumerWidget {
  const _FaceStack({required this.players});

  final List<MostLikedPlayer> players;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final face = 26.w;
    final ring = 2.w;
    final slot = face + ring * 2;
    // Enough overlap to read as one group, little enough that a face's
    // initials (when there is no photo) stay whole.
    final step = slot - 8.w;
    return ExcludeSemantics(
      child: SizedBox(
        width: slot + step * (players.length - 1),
        height: slot,
        child: Stack(
          children: [
            // The first face on top, the rest tucked under it.
            for (var i = players.length - 1; i >= 0; i--)
              Positioned(
                left: step * i,
                top: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.background,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(ring),
                    child: _Face(player: players[i].player, size: face),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Face extends ConsumerWidget {
  const _Face({required this.player, required this.size});

  final PlayerCard player;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(playerPhotoProvider(player.fideId)).valueOrNull;
    return MediaQuery.withNoTextScaling(
      child: PlayerInitialsAvatar(
        photoUrl: photo,
        initials: wallInitials(player.name),
        size: size,
        isCircular: true,
      ),
    );
  }
}

class _MostLikedSkeleton extends StatelessWidget {
  const _MostLikedSkeleton();

  @override
  Widget build(BuildContext context) {
    final card = discoveryGridCardWidth(context);
    // One meta line (16) and its gap (8) over the card and its player rows.
    return DiscoverySkeletonRail(width: card, height: card + 48.w + 24.w);
  }
}

import 'dart:async';

import 'package:chessever2/repository/library/library_game_event.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show discoveryHeartInk;
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart'
    show virtualBroadcastId;
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_hub_providers.dart';
import 'package:chessever2/screens/my_space/widgets/space_avatar.dart';
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// My Likes in the event view's frame (back, a centred title, segments that
/// swipe), as Favorites and Countrymen open from Today: the liked games
/// (every search, filter, tag and export My Likes always had), the players
/// in them and the events they came from. A player or an event opens the
/// Games page narrowed to it.
class MyLikesHubScreen extends ConsumerStatefulWidget {
  const MyLikesHubScreen({super.key, this.initialTab = 0});

  final int initialTab;

  static const List<String> tabs = ['Games', 'Players', 'Events'];

  @override
  ConsumerState<MyLikesHubScreen> createState() => _MyLikesHubScreenState();
}

class _MyLikesHubScreenState extends ConsumerState<MyLikesHubScreen> {
  final _tabs = EventViewController();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Opens the Games page narrowed to [query] (a player's or an event's
  /// name).
  void _showGames(String query) {
    HapticFeedbackService.selection();
    ref.read(myLikesFilterProvider.notifier).searchGames(query);
    _tabs.showTab(0);
  }

  @override
  Widget build(BuildContext context) {
    // Held for the hub's lifetime: the pages share one search and filter,
    // whichever of them is on screen.
    ref.watch(myLikesFilterProvider);
    return EventViewShell(
      title: 'My Likes',
      tabs: MyLikesHubScreen.tabs,
      initialTab: widget.initialTab,
      controller: _tabs,
      pageBuilder: (context, index) => switch (index) {
        0 => const MyLikesGamesPage(key: PageStorageKey('my_likes_games')),
        1 => MyLikesPlayersPage(
          key: const PageStorageKey('my_likes_players'),
          onPick: _showGames,
        ),
        _ => MyLikesEventsPage(
          key: const PageStorageKey('my_likes_events'),
          onPick: _showGames,
        ),
      },
    );
  }
}

// ------------------------------------------------------------------ players

/// One player across the liked games.
@immutable
class MyLikesPlayer {
  const MyLikesPlayer({
    required this.name,
    required this.games,
    this.key = '',
    this.fideId,
    this.title,
    this.federation,
    this.rating,
  });

  /// The aggregation's identity: `f<fideId>`, or `n<name>` without one.
  final String key;
  final String name;
  final int games;
  final int? fideId;
  final String? title;
  final String? federation;
  final int? rating;
}

String? _tag(SavedAnalysis a, String key) {
  final v = a.chessGame.metadata[key]?.toString().trim();
  return v == null || v.isEmpty || v == '?' || v == '-' ? null : v;
}

/// A name with its parts in a fixed order, so "Carlsen, Magnus" and
/// "Magnus Carlsen" are one person.
String _nameKey(String name) {
  final parts = name
      .toLowerCase()
      .replaceAll(RegExp(r'[,.]'), ' ')
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList()
    ..sort();
  return parts.join(' ');
}

/// The players of [likes], most liked first (then by name): one entry per
/// FIDE id (or per name without one), with the newest rating seen. A game
/// that names a player without the FIDE id another game carries counts for
/// that same player.
List<MyLikesPlayer> myLikesPlayers(List<SavedAnalysis> likes) {
  final byKey = <String, MyLikesPlayer>{};
  final order = <String>[];
  for (final a in likes) {
    for (final side in const ['White', 'Black']) {
      final name = _tag(a, side);
      if (name == null) continue;
      final fide = int.tryParse(_tag(a, '${side}FideId') ?? '');
      final key = fide != null && fide > 0 ? 'f$fide' : 'n${_nameKey(name)}';
      final seen = byKey[key];
      if (seen == null) order.add(key);
      byKey[key] = MyLikesPlayer(
        key: key,
        name: seen?.name ?? name,
        games: (seen?.games ?? 0) + 1,
        fideId: fide != null && fide > 0 ? fide : null,
        title: seen?.title ?? _tag(a, '${side}Title'),
        federation: seen?.federation ?? _tag(a, '${side}Fed'),
        rating: seen?.rating ?? int.tryParse(_tag(a, '${side}Elo') ?? ''),
      );
    }
  }
  // Fold a name-only entry into the FIDE entry with the same name.
  final byName = <String, String>{
    for (final k in order)
      if (k.startsWith('f')) _nameKey(byKey[k]!.name): k,
  };
  for (final k in [...order]) {
    if (!k.startsWith('n')) continue;
    final into = byName[k.substring(1)];
    if (into == null) continue;
    final a = byKey[into]!;
    final b = byKey.remove(k)!;
    order.remove(k);
    byKey[into] = MyLikesPlayer(
      key: into,
      name: a.name,
      games: a.games + b.games,
      fideId: a.fideId,
      title: a.title ?? b.title,
      federation: a.federation ?? b.federation,
      rating: a.rating ?? b.rating,
    );
  }
  final list = [for (final k in order) byKey[k]!];
  list.sort((a, b) {
    final byGames = b.games.compareTo(a.games);
    return byGames != 0 ? byGames : a.name.compareTo(b.name);
  });
  return list;
}

/// The likes this viewer can open: every one with Premium, else the free
/// window (their latest [kFreeMyLikesVisibleLimit]). The Players and Events
/// pages count only these, so a count never promises games the Games page
/// holds behind the paywall.
List<SavedAnalysis> myLikesVisible(WidgetRef ref, List<SavedAnalysis> likes) {
  if (likes.length <= kFreeMyLikesVisibleLimit) return likes;
  final window = freeLikesWindow(
    likes,
    unlimited: ref.watch(myLikesUnlimitedProvider),
  );
  if (window == null) return likes;
  return [
    for (final a in likes)
      if (!isLikedGameLocked(a.id, window: window)) a,
  ];
}

/// Everyone in the liked games, as faces and names; picking one shows their
/// liked games.
class MyLikesPlayersPage extends ConsumerWidget {
  const MyLikesPlayersPage({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likes = ref.watch(likedGamesProvider);
    final list = likes.valueOrNull;
    if (list == null) {
      return likes.hasError
          ? const _Quiet(text: "Couldn't load your likes")
          : const _Loading();
    }
    final players = myLikesPlayers(myLikesVisible(ref, list));
    if (players.isEmpty) return const _LikesEmpty();
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(gutter, 12.h, gutter, 32.h),
      itemCount: players.length,
      separatorBuilder: (_, _) => SizedBox(height: 8.h),
      itemBuilder: (context, i) => _PlayerRow(
        key: ValueKey<String>('my_likes_player_${players[i].key}'),
        player: players[i],
        onPick: onPick,
      ),
    );
  }
}

class _PlayerRow extends ConsumerWidget {
  const _PlayerRow({super.key, required this.player, required this.onPick});

  final MyLikesPlayer player;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final p = player;
    final photo = p.fideId == null
        ? null
        : ref.watch(playerPhotoProvider(p.fideId)).valueOrNull;
    final draft = spacePlayerDraft(
      playerName: p.name,
      fideId: p.fideId,
      title: p.title,
      federation: p.federation,
      rating: p.rating,
    );
    final standing = [
      if (p.title != null) p.title!,
      if (p.rating != null && p.rating! > 0) '${p.rating}',
    ].join(' ');
    final count = p.games == 1 ? '1 liked game' : '${p.games} liked games';
    void pick() => onPick(p.name);

    final row = Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12.br),
        border: context.isLightTheme
            ? Border.all(color: colors.divider.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          SpacePlayerAvatar(
            size: 48.w,
            name: p.name,
            photoUrl: photo,
            title: p.title,
            federation: p.federation,
            ring: colors.surface,
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
                  style: AppTypography.textSmMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  standing.isEmpty ? count : '$standing · $count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textXsMedium.copyWith(
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 20.ic,
            color: colors.iconSecondary,
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: '${p.name}, $count',
      excludeSemantics: true,
      onTap: pick,
      child: TappableScale(
        onTap: pick,
        child: CardContextMenu(
          onPreviewTap: pick,
          actions: (menuContext) => [
            LibraryMenuAction(
              icon: Icons.favorite_border_rounded,
              label: 'Show liked games',
              onSelected: pick,
            ),
            LibraryMenuAction(
              icon: Icons.person_outline_rounded,
              label: 'Open profile',
              onSelected: () => openSpaceShortcut(context, ref, draft),
            ),
            spaceMenuAction(context: menuContext, ref: ref, draft: draft),
          ],
          child: row,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ events

/// One event across the liked games.
@immutable
class MyLikesEvent {
  const MyLikesEvent({required this.name, required this.games});

  final String name;
  final int games;
}

/// The events of [likes], most liked first (then newest), by the name the
/// My Likes card shows.
List<MyLikesEvent> myLikesEvents(List<SavedAnalysis> likes) {
  final counts = <String, int>{};
  final newest = <String, DateTime>{};
  for (final a in likes) {
    final md = a.chessGame.metadata;
    final name = chooseLibraryEventName(
      canonicalEventName: md['BroadcastName']?.toString(),
      metadataEvent: md['Event']?.toString(),
      site: md['Site']?.toString(),
      whiteName: a.whiteName,
      blackName: a.blackName,
    );
    if (name == null || name.trim().isEmpty) continue;
    counts[name] = (counts[name] ?? 0) + 1;
    final seen = newest[name];
    if (seen == null || a.createdAt.isAfter(seen)) newest[name] = a.createdAt;
  }
  final list = [
    for (final e in counts.entries) MyLikesEvent(name: e.key, games: e.value),
  ];
  list.sort((a, b) {
    final byGames = b.games.compareTo(a.games);
    if (byGames != 0) return byGames;
    return newest[b.name]!.compareTo(newest[a.name]!);
  });
  return list;
}

/// How many of the liked events are looked up as broadcasts, most liked
/// first; the rest draw by name alone.
const int kMyLikesEventLookups = 200;

/// The broadcasts among the liked events, read by name in batches (a long
/// list never makes one enormous query), kept 5 minutes.
final myLikesEventBroadcastsProvider = FutureProvider.autoDispose
    .family<List<GroupBroadcast>, SpaceIds>((ref, names) async {
      if (names.isEmpty) return const <GroupBroadcast>[];
      final link = ref.keepAlive();
      Timer? release;
      ref.onCancel(
        () => release = Timer(const Duration(minutes: 5), link.close),
      );
      ref.onResume(() => release?.cancel());
      ref.onDispose(() => release?.cancel());
      try {
        return await ref
            .read(groupBroadcastRepositoryProvider)
            .getGroupBroadcastsByNames(names.ids);
      } catch (_) {
        link.close();
        rethrow;
      }
    });

/// The events the liked games came from, as the Events list draws them
/// when the event is a broadcast ChessEver knows (read in one query by
/// name), else by name alone. Picking one shows its liked games.
class MyLikesEventsPage extends ConsumerWidget {
  const MyLikesEventsPage({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likes = ref.watch(likedGamesProvider);
    final list = likes.valueOrNull;
    if (list == null) {
      return likes.hasError
          ? const _Quiet(text: "Couldn't load your likes")
          : const _Loading();
    }
    final events = myLikesEvents(myLikesVisible(ref, list));
    if (events.isEmpty) return const _LikesEmpty();
    // By name only, the most liked first and at most a few hundred: the
    // rest draw by name alone.
    final names = SpaceIds([
      for (final e in events.take(kMyLikesEventLookups)) e.name,
    ]);
    final broadcasts =
        ref.watch(myLikesEventBroadcastsProvider(names)).valueOrNull ??
        const [];
    final liveIds =
        ref.watch(liveGroupBroadcastIdsProvider).valueOrNull ??
        const <String>[];
    final byName = {
      for (final b in broadcasts)
        b.name.trim().toLowerCase(): GroupEventCardModel.fromGroupBroadcast(
          b,
          liveIds,
        ),
    };
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(gutter, 12.h, gutter, 32.h),
      itemCount: events.length,
      separatorBuilder: (_, _) => SizedBox(height: 12.sp),
      itemBuilder: (context, i) {
        final e = events[i];
        final model = byName[e.name.trim().toLowerCase()];
        final count = _LikedCount(games: e.games);
        if (model == null) {
          return _NamedEventRow(event: e, onPick: onPick, trailing: count);
        }
        return EventCard(
          key: ValueKey<String>('my_likes_event_${model.id}'),
          tourEventCardModel: model,
          forceCompactLayout: true,
          heroTagSuffix: '_my_likes',
          trailingWidget: count,
          onTap: () => onPick(e.name),
        );
      },
    );
  }
}

/// "♥ 3": how many liked games came from an event, on one line where the
/// Events list keeps its star, so the card's own meta keeps its width.
class _LikedCount extends StatelessWidget {
  const _LikedCount({required this.games});

  final int games;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: games == 1 ? '1 liked game' : '$games liked games',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(left: 8.w, right: 6.w),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpaceGlyph(
              SpaceGlyphKind.heart,
              size: 12.w,
              ink: discoveryHeartInk(context),
            ),
            SizedBox(width: 4.w),
            Text(
              '$games',
              maxLines: 1,
              style: AppTypography.textXsMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An event ChessEver has no broadcast for (an archive game's tournament):
/// the compact event card's anatomy and height, with the Events pixel
/// object on its plate where a broadcast keeps its photo. Held, it lifts
/// into the focus menu with its liked games and My Space (the database
/// event, which opens where a database event tapped anywhere else does).
class _NamedEventRow extends ConsumerWidget {
  const _NamedEventRow({
    required this.event,
    required this.onPick,
    required this.trailing,
  });

  final MyLikesEvent event;
  final ValueChanged<String> onPick;
  final Widget trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final light = context.isLightTheme;
    final plateWidth = 108.w;
    void pick() => onPick(event.name);
    final draft = SpaceShortcut.draft(
      kind: SpaceShortcutKind.event,
      targetId: virtualBroadcastId(event.name),
      title: event.name,
      params: const {'category': 'completed'},
    );
    final row = Container(
      padding: EdgeInsets.all(6.sp),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        border: light
            ? Border.all(color: colors.divider.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          // The face an event card gives an event with no photo or flag,
          // so these rows match the resolved events around them.
          ClipRRect(
            borderRadius: BorderRadius.circular(6.br),
            child: SizedBox(
              width: plateWidth,
              height: plateWidth * 4 / 5,
              child: EventFallbackArtwork(title: event.name),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              event.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmMedium.copyWith(
                fontSize: 14.f,
                height: 1.2,
                color: colors.textPrimary,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
    return Semantics(
      button: true,
      label: '${event.name}, ${event.games} liked',
      excludeSemantics: true,
      onTap: pick,
      child: TappableScale(
        onTap: pick,
        child: CardContextMenu(
          onPreviewTap: pick,
          actions: (menuContext) => [
            LibraryMenuAction(
              icon: Icons.favorite_border_rounded,
              label: 'Show liked games',
              onSelected: pick,
            ),
            LibraryMenuAction(
              icon: Icons.open_in_new_rounded,
              label: 'Open event',
              onSelected: () => openSpaceShortcut(context, ref, draft),
            ),
            spaceMenuAction(context: menuContext, ref: ref, draft: draft),
          ],
          child: row,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ states

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: 28.w,
        child: CircularProgressIndicator(
          color: context.colors.textPrimary,
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: AppTypography.textSmRegular.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

/// Nothing liked yet: the My Likes heart and one line.
class _LikesEmpty extends StatelessWidget {
  const _LikesEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 88.w,
              child: const HubPixelArtwork(section: SpaceSection.likes),
            ),
            SizedBox(height: 20.h),
            Text(
              'The players and events of the games you like gather here.',
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
                height: 20 / 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

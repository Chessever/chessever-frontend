import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/library/library_game_event.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart'
    show countryRankingsFetcherProvider;
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartEventSpaceDraft;
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart'
    show kFreeMyLikesVisibleLimit;
import 'package:chessever2/screens/my_space/library/space_library_bridge.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_game_card.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/game_space_shortcut.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show eventSpaceDraft;
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How many suggestions each row carries at most.
const Map<SpaceSection, int> kSpaceAutoCaps = {
  SpaceSection.players: 12,
  SpaceSection.events: 10,
  SpaceSection.games: 8,
  SpaceSection.smartEvents: 6,
};

/// The keys of every pinned shortcut, as one value: rows recompute their
/// suggestions only when the pins themselves change, never on a reorder or
/// an open.
final _spacePinnedKeysProvider = Provider.autoDispose<Set<String>>((ref) {
  final keys = ref.watch(
    spaceShortcutsProvider.select(
      (a) => (a.valueOrNull ?? const <SpaceShortcut>[])
          .map((s) => s.key)
          .join('\u0001'),
    ),
  );
  return keys.isEmpty ? const <String>{} : keys.split('\u0001').toSet();
});

/// What one My Space row shows besides its pins: the Library and My Likes
/// mirrors, and the defaults that follow the user (followed players, live
/// events, today's most liked games, saved Smart Events). The
/// one seam the rows and "See all" read; tests override it.
final spaceAutoRowProvider = Provider.autoDispose
    .family<SpaceAutoRow, SpaceSection>((ref, section) {
      final pinned = ref.watch(_spacePinnedKeysProvider);
      final hidden = ref.watch(spaceHiddenAutoKeysProvider);
      final cap = kSpaceAutoCaps[section] ?? 12;
      SpaceAutoRow suggest(List<SpaceShortcut> drafts, {bool settled = true}) =>
          composeSpaceAutoRow(
            trailing: [
              for (final d in drafts)
                SpaceAutoItem(shortcut: d, origin: SpaceAutoOrigin.suggested),
            ],
            pinned: pinned,
            hidden: hidden,
            trailingCap: cap,
            settled: settled,
          );

      switch (section) {
        case SpaceSection.library:
          final library = ref.watch(spaceLibraryFoldersProvider);
          return composeSpaceAutoRow(
            leading: [
              for (final folder in library.folders)
                SpaceAutoItem(
                  shortcut: spaceLibraryFolderDraft(folder),
                  origin: SpaceAutoOrigin.library,
                  folder: folder,
                ),
            ],
            settled: library.settled,
          );
        case SpaceSection.likes:
          final liked = ref.watch(likedGamesProvider);
          final all = liked.valueOrNull ?? const <SavedAnalysis>[];
          final shown = all.take(kFreeMyLikesVisibleLimit);
          final leading = [
            for (final a in shown)
              SpaceAutoItem(
                shortcut: spaceLikedGameFace(a),
                origin: SpaceAutoOrigin.liked,
                analysis: a,
              ),
          ];
          return composeSpaceAutoRow(
            leading: leading,
            hiddenPinKeys: leading.isEmpty
                ? const {}
                : {SpaceShortcut.keyFor(SpaceShortcutKind.likes, 'me')},
            total: all.isEmpty ? null : all.length,
            settled: liked.hasValue || liked.hasError,
          );
        case SpaceSection.players:
          final favorites = ref.watch(favoritePlayersProviderNew);
          final list = favorites.valueOrNull ?? const <FavoritePlayer>[];
          if (list.isNotEmpty) {
            return suggest([for (final f in list) spaceFavoriteDraft(f)]);
          }
          if (!favorites.hasValue && !favorites.hasError) {
            return const SpaceAutoRow(settled: false);
          }
          final top = ref.watch(spaceCountryTopPlayersProvider);
          return suggest([
            for (final p in top.valueOrNull ?? const <ChessPlayer>[])
              spacePlayerDraft(
                playerName: p.name,
                fideId: p.fideid,
                title: p.title,
                rating: p.rating,
                federation: p.country,
              ),
          ], settled: top.hasValue || top.hasError);
        case SpaceSection.events:
          final events = ref.watch(
            forYouEventsProvider.select((s) => s.events),
          );
          final loading = ref.watch(
            forYouEventsProvider.select((s) => s.isLoading),
          );
          final favoriteIds = <String>{
            for (final f
                in ref.watch(favoriteEventsProvider).valueOrNull ?? const [])
              f.eventId,
          };
          return suggest(
            spaceCurrentEventDrafts(events, favoriteIds),
            settled: !loading || events.isNotEmpty,
          );
        case SpaceSection.games:
          final query = MostLikedQuery(MostLikedPeriod.today, DateTime.now());
          final ranked = ref.watch(mostLikedProvider(query));
          final result = ranked.valueOrNull;
          return suggest([
            if (result != null && result.status == MostLikedStatus.ranked)
              for (final entry in result.entries)
                if (gameSpaceShortcutDraft(
                      entry.game,
                      subtitle: entry.eventName,
                      params: spaceGameCardParams(entry.game),
                    )
                    case final draft?)
                  draft,
          ], settled: ranked.hasValue || ranked.hasError);
        case SpaceSection.smartEvents:
          final favorites = ref.watch(favoriteEventsProvider);
          return suggest([
            for (final f in favorites.valueOrNull ?? const [])
              if (isSmartFavoriteEvent(f))
                smartEventSpaceDraft(SmartEventRequest.fromFavoriteEvent(f)),
          ], settled: favorites.hasValue || favorites.hasError);
        case SpaceSection.openings:
        case SpaceSection.links:
          return SpaceAutoRow.empty;
      }
    });

/// A followed player as the shortcut My Space pins for them.
SpaceShortcut spaceFavoriteDraft(FavoritePlayer f) {
  final md = f.metadata;
  String? text(String key) {
    final v = md[key]?.toString().trim() ?? '';
    return v.isEmpty ? null : v;
  }

  final rating = md['rating'];
  return spacePlayerDraft(
    playerName: f.playerName,
    fideId: int.tryParse(f.fideId ?? ''),
    title: text('title'),
    federation: text('countryCode'),
    rating: rating is num ? rating.toInt() : int.tryParse('${rating ?? ''}'),
    gamebasePlayerId: text('gamebasePlayerId'),
    memorialSourceIdentity: text('memorialSourceIdentity'),
    memorialRouteId: text('memorialRouteId'),
  );
}

/// The face of a liked game on the My Likes row: the same shortcut the game's
/// own "Add to My Space" builds when it has a source game, else a face drawn
/// from the saved copy alone (it opens the copy either way). Either carries
/// the game card's snapshot of the saved copy at its final position, so the
/// tile shows the players and the board as the card does, with no lookup.
SpaceShortcut spaceLikedGameFace(SavedAnalysis analysis) {
  final game = spaceGameFromAnalysis(analysis);
  final card = spaceGameCardParams(game);
  final md = analysis.chessGame.metadata;
  final event = chooseLibraryEventName(
    canonicalEventName: md['BroadcastName']?.toString(),
    metadataEvent: md['Event']?.toString(),
    site: md['Site']?.toString(),
    whiteName: game.whitePlayer.name,
    blackName: game.blackPlayer.name,
  );
  final draft = gameSpaceShortcutDraft(
    game,
    subtitle: event,
    params: {...card, 'analysisId': analysis.id},
  );
  if (draft != null) return draft;
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.game,
    targetId: 'analysis:${analysis.id}',
    title: analysis.title,
    subtitle: event,
    params: {
      'white': game.whitePlayer.name,
      'black': game.blackPlayer.name,
      if (game.fen?.trim().isNotEmpty ?? false) 'fen': game.fen,
      ...card,
      'analysisId': analysis.id,
    },
  );
}

/// Live and upcoming events from the For You feed, followed ones first.
/// Events the database invented (no broadcast behind them) are left out:
/// they cannot be reopened later. Following only orders the list; it never
/// adds an event the feed does not carry.
List<GroupEventCardModel> spaceCurrentEvents(
  List<GroupEventCardModel> events,
  Set<String> favoriteIds,
) {
  const current = {
    TourEventCategory.live,
    TourEventCategory.ongoing,
    TourEventCategory.upcoming,
  };
  final eligible = [
    for (final e in events)
      if (current.contains(e.tourEventCategory) &&
          e.id.trim().isNotEmpty &&
          !isVirtualGamebaseId(e.id))
        e,
  ];
  return [
    for (final e in eligible)
      if (favoriteIds.contains(e.id)) e,
    for (final e in eligible)
      if (!favoriteIds.contains(e.id)) e,
  ];
}

/// [spaceCurrentEvents] as the same shortcut the event card pins.
List<SpaceShortcut> spaceCurrentEventDrafts(
  List<GroupEventCardModel> events,
  Set<String> favoriteIds,
) => [
  for (final e in spaceCurrentEvents(events, favoriteIds)) eventSpaceDraft(e),
];

/// The strongest active classical players of the user's country, for a
/// Players row with nobody followed yet. Read once a session.
final spaceCountryTopPlayersProvider =
    FutureProvider.autoDispose<List<ChessPlayer>>((ref) async {
      final country = ref.watch(countryDropdownProvider).valueOrNull;
      if (country == null) return const [];
      final fetch = ref.watch(countryRankingsFetcherProvider);
      final players = await fetch(
        countryCode: CountryUtils.toFideCode(country.countryCode),
        filters: RankingFilters.defaults,
        searchQuery: '',
        limit: 8,
        offset: 0,
      );
      ref.keepAlive();
      return players;
    });

/// Suggestions the user hid from a row, on this device (per account). A hidden
/// suggestion stays gone until pinned from elsewhere or unhidden with Undo.
final spaceHiddenAutoKeysProvider =
    NotifierProvider<SpaceHiddenAutoKeys, Set<String>>(SpaceHiddenAutoKeys.new);

class SpaceHiddenAutoKeys extends Notifier<Set<String>> {
  static const _prefix = 'my_space_hidden_auto_v1:';

  String? _userId;

  String get _storageKey => '$_prefix${_userId ?? 'guest'}';

  @override
  Set<String> build() {
    _userId = ref.watch(currentUserProvider.select((u) => u?.id));
    try {
      final stored = SharedPreferencesService.instance.prefsOrNull
          ?.getStringList(_storageKey);
      return stored == null ? const <String>{} : stored.toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  void hide(String key) {
    if (state.contains(key)) return;
    state = {...state, key};
    unawaited(_persist());
  }

  void unhide(String key) {
    if (!state.contains(key)) return;
    state = {...state}..remove(key);
    unawaited(_persist());
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      await prefs?.setStringList(_storageKey, state.toList());
    } catch (e) {
      debugPrint('[MySpace] hidden suggestions not saved: $e');
    }
  }
}

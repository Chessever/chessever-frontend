import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_group_expansion.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_priority_matching.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_stable_order_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart'
    show standingsSearchQueryProvider;
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One category's games as list models, for the Combined list.
///
/// Reads the same [gamesTourProvider] the single-category view uses, so the
/// games are fetched, cached and polled once however the event is viewed. A
/// model is rebuilt only for a board whose list inputs changed; an identical
/// poll publishes nothing, so the combined list does not regroup on every
/// safety-net tick of every category.
final combinedTourGamesProvider = StateNotifierProvider.autoDispose
    .family<
      CombinedTourGamesNotifier,
      AsyncValue<List<GamesTourModel>>,
      String
    >((ref, tourId) => CombinedTourGamesNotifier(ref: ref, tourId: tourId));

class CombinedTourGamesNotifier
    extends StateNotifier<AsyncValue<List<GamesTourModel>>> {
  CombinedTourGamesNotifier({required Ref ref, required String tourId})
    : super(const AsyncValue.loading()) {
    ref.listen<AsyncValue<List<Games>>>(
      gamesTourProvider(tourId),
      (_, next) => _apply(next),
      fireImmediately: true,
    );
  }

  final Map<String, (Games, GamesTourModel)> _modelsByGameId =
      <String, (Games, GamesTourModel)>{};

  void _apply(AsyncValue<List<Games>> next) {
    if (!mounted) return;
    final games = next.valueOrNull;
    if (games == null) {
      // A failed refresh keeps the boards already on screen.
      if (next.hasError && !state.hasValue) {
        state = AsyncValue.error(
          next.error!,
          next.stackTrace ?? StackTrace.current,
        );
      }
      return;
    }

    final current = state.valueOrNull;
    var changed = current == null;
    final models = <GamesTourModel>[];
    final nextModels = <String, (Games, GamesTourModel)>{};
    for (final game in games) {
      final cached = _modelsByGameId[game.id];
      final GamesTourModel model;
      if (cached != null && _hasSameListInputs(cached.$1, game)) {
        model = cached.$2;
      } else {
        try {
          model = GamesTourModel.fromGameIndex(game);
        } catch (_) {
          // A board without two named players cannot be drawn.
          continue;
        }
        changed = true;
      }
      nextModels[game.id] = (game, model);
      models.add(model);
    }

    if (!changed && current != null) {
      changed = current.length != models.length;
      for (var i = 0; !changed && i < models.length; i++) {
        changed = !identical(current[i], models[i]);
      }
    }
    _modelsByGameId
      ..clear()
      ..addAll(nextModels);
    if (changed) {
      state = AsyncValue.data(List<GamesTourModel>.unmodifiable(models));
    }
  }
}

/// The fields a list model is built from. Clock-only changes are left to the
/// visible card's own live stream.
bool _hasSameListInputs(Games a, Games b) {
  if (identical(a, b)) return true;
  return a.id == b.id &&
      a.roundId == b.roundId &&
      a.roundSlug == b.roundSlug &&
      a.status == b.status &&
      a.boardNr == b.boardNr &&
      a.lastMove == b.lastMove &&
      a.fen == b.fen &&
      a.isPgnDeferred == b.isPgnDeferred &&
      (identical(a.pgn, b.pgn) || a.pgn == b.pgn) &&
      haveSameRawGamePriorityInputs(a, b);
}

/// Round names and start times for every combined category, in one request.
/// Keyed by the joined tour ids so the same event reuses one result.
final combinedRoundsProvider = FutureProvider.autoDispose
    .family<Map<String, List<Round>>, String>((ref, tourIdsKey) {
      final tourIds = tourIdsKey.split(',');
      return ref.watch(roundRepositoryProvider).getRoundsByTourIds(tourIds);
    });

String combinedRoundsKey(List<String> tourIds) => tourIds.join(',');

/// The combined rounds, before they are laid out as list rows.
///
/// Kept apart from the layout on purpose: folding a round or switching the
/// card style re-flows the rows, but must not regroup and re-sort every board
/// of every category.
class CombinedRoundSections {
  const CombinedRoundSections({
    required this.isLoading,
    required this.error,
    required this.sections,
    required this.pinnedGameIds,
    required this.searchQuery,
    required this.hasUnscheduledRounds,
  });

  static const empty = CombinedRoundSections(
    isLoading: false,
    error: null,
    sections: <CombinedRoundSection>[],
    pinnedGameIds: <String>[],
    searchQuery: '',
    hasUnscheduledRounds: false,
  );

  static const loading = CombinedRoundSections(
    isLoading: true,
    error: null,
    sections: <CombinedRoundSection>[],
    pinnedGameIds: <String>[],
    searchQuery: '',
    hasUnscheduledRounds: false,
  );

  final bool isLoading;

  /// Set only when no category could be loaded at all.
  final Object? error;
  final List<CombinedRoundSection> sections;
  final List<String> pinnedGameIds;
  final String searchQuery;

  /// A board belongs to a round the schedule did not return: a round created
  /// after the schedule was read. The screen re-reads the schedule.
  final bool hasUnscheduledRounds;
}

final combinedRoundSectionsProvider =
    Provider.autoDispose<CombinedRoundSections>((ref) {
      final categories = ref.watch(combinedCategoriesProvider);
      if (!categories.canCombine) return CombinedRoundSections.empty;
      final tourIds = categories.tourIds;

      final gamesByTourId = <String, List<GamesTourModel>>{};
      var pending = false;
      Object? firstError;
      for (final tourId in tourIds) {
        final games = ref.watch(combinedTourGamesProvider(tourId));
        final value = games.valueOrNull;
        if (value != null) {
          gamesByTourId[tourId] = value;
        } else if (games.hasError) {
          firstError ??= games.error;
        } else {
          pending = true;
        }
      }

      final roundsAsync = ref.watch(
        combinedRoundsProvider(combinedRoundsKey(tourIds)),
      );
      final roundsByTourId = roundsAsync.valueOrNull;

      // First paint waits for every category and the schedule, so the list is
      // laid out once instead of reshuffling as each category arrives. A
      // category that failed is skipped rather than blocking the rest.
      if (pending || (roundsByTourId == null && roundsAsync.isLoading)) {
        return CombinedRoundSections.loading;
      }
      if (gamesByTourId.isEmpty && firstError != null) {
        return CombinedRoundSections(
          isLoading: false,
          error: firstError,
          sections: const <CombinedRoundSection>[],
          pinnedGameIds: const <String>[],
          searchQuery: '',
          hasUnscheduledRounds: false,
        );
      }

      // Joined, so an unrelated pin-state change (an auto-pin refresh that
      // lands on the same boards) compares equal and regroups nothing.
      final pinnedGameIds = <String>{};
      for (final tourId in tourIds) {
        final pins = ref.watch(
          gamesPinprovider(
            tourId,
          ).select((state) => state.allPins.join(_pinSeparator)),
        );
        if (pins.isNotEmpty) pinnedGameIds.addAll(pins.split(_pinSeparator));
      }

      final query = ref.watch(standingsSearchQueryProvider).trim();
      final visibleGamesByTourId = query.isEmpty
          ? gamesByTourId
          : <String, List<GamesTourModel>>{
              for (final entry in gamesByTourId.entries)
                entry.key: filterCombinedGames(entry.value, query),
            };

      final sections = buildCombinedRoundSections(
        categories: categories.items,
        gamesByTourId: visibleGamesByTourId,
        roundsByTourId: roundsByTourId ?? const <String, List<Round>>{},
        liveRoundIds:
            ref.watch(liveRoundsIdProvider).valueOrNull ?? const <String>[],
        pinnedGameIds: pinnedGameIds,
      );

      final scheduledRoundIds = <String>{
        if (roundsByTourId != null)
          for (final rounds in roundsByTourId.values)
            for (final round in rounds) round.id,
      };

      return CombinedRoundSections(
        isLoading: false,
        error: null,
        sections: sections,
        pinnedGameIds: List<String>.unmodifiable(pinnedGameIds),
        searchQuery: query,
        hasUnscheduledRounds: sections.any(
          (section) => !scheduledRoundIds.contains(section.round.id),
        ),
      );
    });

/// Whether "Live games first" is on for Combined: on for every one of
/// [tourIds], read from the same per-category setting the regular tab uses.
bool combinedLiveGamesFirst(
  T Function<T>(ProviderListenable<T>) read,
  Iterable<String> tourIds,
) {
  final ids = tourIds.toList();
  return ids.isNotEmpty &&
      ids.every(
        (tourId) =>
            read(gameDisplayModeProvider(tourId)) ==
            GameDisplayMode.hideFinishedGames,
      );
}

/// The id of a Combined round card.
String combinedRoundCardId(String roundKey) => 'combined:$roundKey';

/// Never part of a game id.
const String _pinSeparator = '\n';

/// Everything the Combined Games tab paints.
class CombinedGamesPresentation {
  CombinedGamesPresentation({
    required this.source,
    required this.gamesByRound,
    required this.layout,
    this.cardTitles = const <String, String>{},
  });

  final CombinedRoundSections source;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesTourFlattenedLayout layout;

  /// Each round card's title, by card id: what its categories share, then
  /// the round ("Group Stage · Round 4", "Blitz Tiebreak · Round 9").
  final Map<String, String> cardTitles;

  bool get isLoading => source.isLoading;
  Object? get error => source.error;
  List<String> get pinnedGameIds => source.pinnedGameIds;
  String get searchQuery => source.searchQuery;
  bool get isSearchMode => source.searchQuery.isNotEmpty;

  /// The ids of the round cards on screen (`combined:<round key>`), which is
  /// what round expansion is keyed by. Not the categories' own round ids.
  List<String> get roundIds => [
    for (final key in {
      for (final section in source.sections) combinedRoundKey(section),
    })
      combinedRoundCardId(key),
  ];
}

final combinedGamesPresentationProvider =
    Provider.autoDispose<CombinedGamesPresentation>((ref) {
      final source = ref.watch(combinedRoundSectionsProvider);
      if (source.sections.isEmpty) {
        return CombinedGamesPresentation(
          source: source,
          gamesByRound: const <String, List<GamesTourModel>>{},
          layout: GamesTourFlattenedLayout.empty,
        );
      }

      // One card per round, every category's boards under it, in the order
      // buildCombinedRoundSections already gave the sections.
      final groups = <String, List<CombinedRoundSection>>{};
      for (final section in source.sections) {
        (groups[combinedRoundKey(section)] ??= <CombinedRoundSection>[]).add(
          section,
        );
      }
      // "Live games first", set per category exactly like the single-category
      // tab (gameDisplayModeProvider), applies when every merged category has
      // it on, so one toggle in the menu reads the same for all of them.
      final liveFirst = combinedLiveGamesFirst(ref.watch, {
        for (final section in source.sections) section.category.tourId,
      });
      List<GamesTourModel> ordered(List<GamesTourModel> games) =>
          liveFirst ? applyCurrentLiveFocusOrder(games: games) : games;

      final rounds = <GamesAppBarModel>[];
      final gamesByRound = <String, List<GamesTourModel>>{};
      final sourcesByRound = <String, List<GamesTourSourceSection>>{};
      final cardTitles = <String, String>{};
      for (final entry in groups.entries) {
        final standIn = combinedStandInRound(entry.key, entry.value);
        final round = GamesAppBarModel(
          id: combinedRoundCardId(entry.key),
          name: standIn.name,
          startsAt: standIn.startsAt,
          roundStatus: standIn.roundStatus,
          sourceRoundIds: standIn.sourceRoundIds,
        );
        rounds.add(round);
        final shared = combinedCardLabel([
          for (final section in entry.value) section.category.label,
        ]);
        cardTitles[round.id] = shared == null
            ? round.name
            : '$shared · ${round.name}';
        gamesByRound[round.id] = [
          for (final section in entry.value) ...ordered(section.games),
        ];
        sourcesByRound[round.id] = [
          for (final section in entry.value)
            GamesTourSourceSection(
              roundId: section.round.id,
              label: section.category.label,
              games: ordered(section.games),
            ),
        ];
      }
      final isSearchMode = source.searchQuery.isNotEmpty;
      return CombinedGamesPresentation(
        source: source,
        gamesByRound: gamesByRound,
        cardTitles: cardTitles,
        layout: buildGamesTourFlattenedLayout(
          rounds: rounds,
          gamesByRound: gamesByRound,
          sourceSectionsByRound: sourcesByRound,
          sourceExpansionState: isSearchMode
              ? const <String, bool>{}
              : ref.watch(combinedGroupExpansionProvider),
          mode: ref.watch(gamesListViewModeProvider),
          matchExpansionState: const <String, bool>{},
          // A search shows every hit, whatever was folded before it.
          roundExpansionState: isSearchMode
              ? const <String, bool>{}
              : ref.watch(roundExpansionProvider),
          isKnockoutTournament: false,
          displayMode: liveFirst
              ? GameDisplayMode.hideFinishedGames
              : GameDisplayMode.all,
          isSearchMode: isSearchMode,
        ),
      );
    });

/// What a round card's categories have in common, for its title: the one
/// category's label ("Blitz Tiebreak"), or the leading part every label
/// shares up to a separator ("Group Stage" for "Group Stage | A" and
/// "Group Stage | B"). Null when they share nothing.
@visibleForTesting
String? combinedCardLabel(List<String> labels) {
  final distinct = labels.toSet().toList();
  if (distinct.isEmpty) return null;
  if (distinct.length == 1) return distinct.single;
  var shared = distinct.first;
  for (final other in distinct.skip(1)) {
    var i = 0;
    while (i < shared.length && i < other.length && shared[i] == other[i]) {
      i++;
    }
    shared = shared.substring(0, i);
  }
  // Cut back to the last separator, so "Group Stage | " never shows as a
  // half word.
  final cut = shared.lastIndexOf(RegExp(r'\s*[|:–—]\s*'));
  if (cut <= 0) return null;
  final head = shared.substring(0, cut).trim();
  return head.isEmpty ? null : head;
}

/// Player search inside Combined: every word of [query] must appear in the
/// pairing's names, titles or federations.
@visibleForTesting
List<GamesTourModel> filterCombinedGames(
  List<GamesTourModel> games,
  String query,
) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return games;
  return [
    for (final game in games)
      if (_matches(game, words)) game,
  ];
}

bool _matches(GamesTourModel game, List<String> words) {
  final white = game.whitePlayer;
  final black = game.blackPlayer;
  final haystack =
      '${white.name} ${white.title} ${white.federation} ${white.countryCode} '
              '${black.name} ${black.title} ${black.federation} '
              '${black.countryCode}'
          .toLowerCase();
  return words.every(haystack.contains);
}

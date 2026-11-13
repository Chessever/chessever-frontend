import 'combined_hall_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_buckets.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart'
    show standingsSearchQueryProvider;
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

      final key = combinedRoundsKey(tourIds);
      ref.watch(combinedHallProvider(key));
      final hall = ref.read(combinedHallProvider(key).notifier);
      final gamesByTourId = hall.gamesByTour;
      final roundsByTourId = hall.loader.catalogs;
      if (hall.loader.isLoading) return CombinedRoundSections.loading;
      if (roundsByTourId.isEmpty && hall.loader.failures.isNotEmpty) {
        return CombinedRoundSections(
          isLoading: false,
          error: StateError(
            'Combined rounds could not be loaded. Pull to retry.',
          ),
          sections: const [],
          pinnedGameIds: const [],
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
        roundsByTourId: roundsByTourId,
        includeEmptyRounds: query.isEmpty,
        liveRoundIds:
            ref.watch(liveRoundsIdProvider).valueOrNull ?? const <String>[],
        pinnedGameIds: pinnedGameIds,
      );

      final scheduledRoundIds = <String>{
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

/// Never part of a game id.
const String _pinSeparator = '\n';

/// Everything the Combined Games tab paints.
class CombinedGamesPresentation {
  CombinedGamesPresentation({
    required this.source,
    required this.gamesByRound,
    required this.layout,
  });

  final CombinedRoundSections source;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesTourFlattenedLayout layout;

  bool get isLoading => source.isLoading;
  Object? get error => source.error;
  List<String> get pinnedGameIds => source.pinnedGameIds;
  String get searchQuery => source.searchQuery;
  bool get isSearchMode => source.searchQuery.isNotEmpty;

  List<String> get roundIds => [
    for (final entry in layout.entries)
      if (entry is GamesTourRoundHeaderEntry) entry.round.id,
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

      final hall = ref.read(
        combinedHallProvider(
          combinedRoundsKey(ref.watch(combinedCategoriesProvider).tourIds),
        ).notifier,
      );
      final buckets = buildCombinedRoundBuckets(
        source.sections,
        eventId: ref.watch(combinedCategoryGroupIdProvider) ?? '',
        loadedRoundIds: hall.loader.loaded,
        failedRoundIds: {
          for (final key in hall.loader.failures)
            if (key.startsWith('round:')) key.substring(6),
        },
      );
      if (buckets.isNotEmpty && source.searchQuery.isEmpty) {
        hall.initiallyExpandedRoundId ??= buckets.first.round.id;
      }
      final gamesByRound = <String, List<GamesTourModel>>{
        for (final bucket in buckets) bucket.round.id: bucket.games,
        for (final section in source.sections) section.round.id: section.games,
      };
      final isSearchMode = source.searchQuery.isNotEmpty;
      return CombinedGamesPresentation(
        source: source,
        gamesByRound: gamesByRound,
        layout: buildGamesTourFlattenedLayout(
          rounds: <GamesAppBarModel>[
            for (final bucket in buckets) bucket.round,
          ],
          gamesByRound: gamesByRound,
          sourceSectionsByRound: {
            for (final bucket in buckets) bucket.round.id: bucket.sources,
          },
          mode: ref.watch(gamesListViewModeProvider),
          matchExpansionState: const <String, bool>{},
          // A search shows every hit, whatever was folded before it.
          roundExpansionState: isSearchMode
              ? const <String, bool>{}
              : {
                  for (final bucket in buckets)
                    bucket.round.id:
                        ref.watch(roundExpansionProvider)[bucket.round.id] ??
                        (bucket.round.id == hall.initiallyExpandedRoundId),
                },
          isKnockoutTournament: false,
          displayMode: GameDisplayMode.all,
          isSearchMode: isSearchMode,
        ),
      );
    });

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

import 'package:chessever2/screens/standings/player_standing_sections_provider.dart';
import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/standings/standings_search_text.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provides player standings for the tournament detail "Players" tab.
/// Uses [AutoDisposeAsyncNotifier] so the heavy computation only runs when needed
/// and automatically refreshes when any dependency changes.
/// Provides a merged list of games for the tournament, automatically combining
/// games across pagination-purposed categories (e.g. "Boards 1-66" and "Boards 67-126").
/// This ensures components like the ScoreCardScreen have the full context.
final mergedTournamentGamesProvider = AutoDisposeProvider<List<GamesTourModel>>(
  (ref) {
    final tourDetailAsync = ref.watch(tourDetailScreenProvider);
    final gamesTourAsync = ref.watch(gamesTourScreenProvider);

    if (tourDetailAsync.isLoading ||
        tourDetailAsync.hasError ||
        gamesTourAsync.isLoading ||
        gamesTourAsync.hasError) {
      return const [];
    }

    final tourDetail = tourDetailAsync.value!;
    final aboutTourModel = tourDetail.aboutTourModel;
    if (aboutTourModel.id.isEmpty) {
      return const [];
    }

    // The screen model is a presentation list: text search swaps it for the
    // query's hits and "Show Finished Games" drops live boards. A score card
    // opened from one of those rows must still see every game, so rebuild
    // from the raw tour list whenever the screen list is filtered. Otherwise
    // the screen list *is* that raw list, already parsed off the main thread,
    // so reuse it rather than re-parsing every PGN here.
    List<GamesTourModel> fullTournamentGames() {
      final screen = gamesTourAsync.valueOrNull;
      final complete = ref.watch(completeGamesTourProvider(aboutTourModel.id));
      if (!complete.hasValue) return const <GamesTourModel>[];
      if (screen != null &&
          !screen.isFiltered &&
          screen.gamesTourModels.length == complete.value!.length) {
        return screen.gamesTourModels;
      }
      final rawGames = ref
          .watch(completeGamesTourProvider(aboutTourModel.id))
          .valueOrNull;
      if (rawGames == null) {
        return const <GamesTourModel>[];
      }
      final models = <GamesTourModel>[];
      for (final game in rawGames) {
        try {
          models.add(GamesTourModel.fromGameIndex(game));
        } catch (_) {}
      }
      return models;
    }

    final allGames = <GamesTourModel>[];

    if (isBoardPaginationCategory(aboutTourModel.name)) {
      final relatedTours = standingsToursFor(
        tourDetail.tours,
        tourId: aboutTourModel.id,
        tourName: aboutTourModel.name,
      );

      if (relatedTours.length > 1) {
        for (final tourModel in relatedTours) {
          final tourGamesAsync = ref.watch(
            completeGamesTourProvider(tourModel.tour.id),
          );
          if (tourGamesAsync.hasValue) {
            for (final g in tourGamesAsync.value!) {
              try {
                allGames.add(GamesTourModel.fromGameIndex(g));
              } catch (_) {}
            }
          }
        }
      } else {
        allGames.addAll(fullTournamentGames());
      }
    } else {
      allGames.addAll(fullTournamentGames());
    }

    return allGames;
  },
);

final RegExp _boardPagination = RegExp(
  r'Boards?\s+\d+[\-\+]?\d*\+?$',
  caseSensitive: false,
);
final RegExp _boardPaginationSuffix = RegExp(
  r'\s*Boards?\s+\d+[\-\+]?\d*\+?$',
  caseSensitive: false,
);

/// Identifies categories like "Boards 1-66", "Boards 67-126", "Boards 252+":
/// one tournament an organizer split over several tours.
bool isBoardPaginationCategory(String name) => _boardPagination.hasMatch(name);

/// The name before the pagination suffix ("Open | Boards 1-50" -> "Open |").
String boardPaginationBaseName(String name) =>
    name.replaceAll(_boardPaginationSuffix, '').trim();

/// The tours one standings table is computed from: [tourId] alone, or every
/// tour of the board-paginated tournament it is a page of.
List<TourModel> standingsToursFor(
  List<TourModel> tours, {
  required String tourId,
  required String tourName,
}) {
  if (isBoardPaginationCategory(tourName)) {
    final baseName = boardPaginationBaseName(tourName);
    return tours
        .where(
          (t) =>
              isBoardPaginationCategory(t.tour.name) &&
              boardPaginationBaseName(t.tour.name) == baseName,
        )
        .toList();
  }
  return tours.where((t) => t.tour.id == tourId).toList();
}

/// One standings table: [relatedTours] ranked together, with the official
/// section chosen for [sectionTourId] applied. Empty when nothing can be
/// ranked yet.
///
/// Shared by the selected category's Standings tab and by every section of
/// the Combined one, so a category reads the same either way.
///
/// [onResultsOnly] recomputes the table when a result, a pairing or a player
/// changes, and not on every move of a live game. The Combined tab keeps a
/// table per category, so it cannot afford the selected category's habit of
/// recomputing on each emission.
Future<List<PlayerStandingModel>> buildRankedStandingsForTours(
  Ref ref, {
  required List<TourModel> relatedTours,
  required String sectionTourId,
  bool onResultsOnly = false,
}) async {
  final catalogs = [
    for (final tour in relatedTours)
      onResultsOnly
          ? _completeGamesOnResultChange(ref, tour.tour.id)
          : ref.watch(completeGamesTourFutureProvider(tour.tour.id).future),
  ];
  final allGames = <GamesTourModel>[];
  for (final games in await Future.wait(catalogs)) {
    for (final game in games) {
      try {
        allGames.add(GamesTourModel.fromGameIndex(game));
      } catch (_) {}
    }
  }

  final allPlayers = <TournamentPlayer>[];
  for (final tourModel in relatedTours) {
    allPlayers.addAll(tourModel.tour.players);
  }

  final sections = relatedTours.length == 1
      ? relatedTours.first.tour.info.playerStandingSections
      : const <OfficialPlayerSection>[];
  final section = selectedOfficialPlayerSection(
    sections,
    ref.watch(selectedPlayerStandingSectionProvider(sectionTourId)),
  );
  if (section != null) {
    allPlayers
      ..clear()
      ..addAll(section.players);
  }
  final scopedGames = section == null
      ? allGames
      : scopeOfficialSectionGames(section, allGames);

  // Trust the server-side standings order only when scope is a single tour
  // that the data hub has flagged as canonically sorted (currently from
  // chess-results.com). Multi-tour pagination categories (e.g. "Boards 1-66"
  // + "Boards 67-126") interleave players from independent standings, so the
  // concatenation is not meaningful — fall back to client-side sort there.
  final useExternalOrder =
      relatedTours.length == 1 &&
      (section != null || relatedTours.first.tour.usesExternalStandings);

  // Use the app singleton client (same session/headers as Games), not the
  // secondary [supabaseProvider] client. A second anonymous client on the
  // release HTTP stack was implicated in Standings-only infinite loading
  // while every other tab (which go through Supabase.instance) worked.
  final builtStandings = await buildStandingsFromData(
    supabase: Supabase.instance.client,
    tournamentPlayers: allPlayers,
    gamesTourModels: scopedGames,
    useExternalOrder: useExternalOrder,
    singleTourScope: relatedTours.length == 1,
  );
  if (builtStandings.isEmpty) return const <PlayerStandingModel>[];

  // Assign 1-based ranks in unfiltered order. These stay attached to each
  // player so in-widget filter preserves the overall standing position.
  return assignOverallRanks(builtStandings);
}

/// The complete catalog of [tourId], depended on through
/// [standingsGamesSignature] alone: moves and clock ticks change the games
/// list but not the signature, so they do not rerun the caller.
Future<List<Games>> _completeGamesOnResultChange(Ref ref, String tourId) {
  ref.watch(completeGamesTourProvider(tourId).select(standingsGamesSignature));
  final complete = ref.read(completeGamesTourProvider(tourId));
  if (complete.hasValue) return Future.value(complete.requireValue);
  if (complete.hasError) {
    return Future.error(
      complete.error!,
      complete.stackTrace ?? StackTrace.current,
    );
  }
  // Still loading: the preview never resolves this, so a partial catalog
  // cannot become a table of partial totals. Completion changes the
  // signature, which reruns the caller with the full list.
  return ref.read(gamesTourProvider(tourId).notifier).waitForCompleteCatalog();
}

/// Player standings of one category of the open event, whichever category
/// is selected. The Combined Standings tab shows one of these per category;
/// the selected category alone keeps using [playerTourScreenProvider].
///
/// Keyed by tour id. A page of a board-paginated tournament resolves to the
/// whole tournament, exactly like the selected category does.
final categoryStandingsProvider = FutureProvider.autoDispose
    .family<List<PlayerStandingModel>, String>((ref, tourId) async {
      final tours = ref.watch(
        tourDetailScreenProvider.select((state) => state.valueOrNull?.tours),
      );
      if (tourId.isEmpty || tours == null) {
        return const <PlayerStandingModel>[];
      }
      // The selected category already has its table: one computation, and
      // one answer, for the Combined section and everything else that reads
      // the selected category (score cards, shares, the team table).
      final selectedTourId = ref.watch(
        tourDetailScreenProvider.select(
          (state) => state.valueOrNull?.aboutTourModel.id,
        ),
      );
      if (tourId == selectedTourId) {
        return ref.watch(playerTourScreenProvider.future);
      }
      final tour = tours.where((t) => t.tour.id == tourId).firstOrNull;
      if (tour == null) return const <PlayerStandingModel>[];
      return buildRankedStandingsForTours(
        ref,
        relatedTours: standingsToursFor(
          tours,
          tourId: tourId,
          tourName: tour.tour.name,
        ),
        sectionTourId: tourId,
        onResultsOnly: true,
      );
    });

/// Every game of one category as list models, with the other pages of a
/// board-paginated tournament merged in. What a score card opened from a
/// Combined standings row reads, since [mergedTournamentGamesProvider] only
/// knows the selected category.
final categoryGamesProvider = Provider.autoDispose
    .family<AsyncValue<List<GamesTourModel>>, String>((ref, tourId) {
      final tours = ref.watch(
        tourDetailScreenProvider.select((state) => state.valueOrNull?.tours),
      );
      final tour = tours?.where((t) => t.tour.id == tourId).firstOrNull;
      final related = tour == null
          ? const <TourModel>[]
          : standingsToursFor(tours!, tourId: tourId, tourName: tour.tour.name);
      final tourIds = related.isEmpty
          ? <String>[tourId]
          : [for (final item in related) item.tour.id];

      final models = <GamesTourModel>[];
      var pending = false;
      Object? firstError;
      for (final id in tourIds) {
        final games = ref.watch(completeGamesTourProvider(id));
        final value = games.valueOrNull;
        if (value == null) {
          if (games.hasError) {
            firstError ??= games.error;
          } else {
            pending = true;
          }
          continue;
        }
        for (final game in value) {
          try {
            models.add(GamesTourModel.fromGameIndex(game));
          } catch (_) {}
        }
      }
      if (models.isEmpty && pending) return const AsyncValue.loading();
      if (models.isEmpty && firstError != null) {
        return AsyncValue.error(firstError, StackTrace.current);
      }
      return AsyncValue.data(models);
    });

/// Search query for the standings tab
final standingsSearchQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

List<PlayerStandingModel> assignOverallRanks(
  List<PlayerStandingModel> standings,
) {
  return [
    for (var i = 0; i < standings.length; i++)
      standings[i].copyWith(overallRank: standings[i].overallRank ?? i + 1),
  ];
}

List<PlayerStandingModel> filterStandingsByQuery(
  List<PlayerStandingModel> standings,
  String rawQuery,
) {
  if (standingsSearchForms(rawQuery).isEmpty) return standings;

  return standings
      .where((player) {
        final searchable = [
          player.name,
          player.title ?? '',
          player.countryCode,
        ].join(' ');
        return matchesStandingsSearch(searchable, rawQuery);
      })
      .toList(growable: false);
}

final playerTourScreenProvider =
    AutoDisposeAsyncNotifierProvider<
      PlayerTourScreenNotifier,
      List<PlayerStandingModel>
    >(PlayerTourScreenNotifier.new);

class PlayerTourScreenNotifier
    extends AutoDisposeAsyncNotifier<List<PlayerStandingModel>> {
  String? _lastBroadcastId;
  String? _lastTourId;
  List<PlayerStandingModel>? _lastGoodStandings;

  @override
  Future<List<PlayerStandingModel>> build() async {
    // Keep provider alive while the page is visible to avoid eager disposal
    ref.keepAlive();

    // IMPORTANT: build() intentionally does NOT watch
    // `standingsSearchQueryProvider`. The full ranked standings are
    // recomputed only when the tour / games / broadcast change; search
    // filtering is applied cheaply in-widget so typing doesn't re-run the
    // (expensive) FIDE-Elo fetch and enrichment pass on every keystroke.
    final selectedBroadcast = ref.watch(selectedBroadcastModelProvider);

    if (selectedBroadcast == null || selectedBroadcast.id.isEmpty) {
      return const [];
    }

    final tourDetailAsync = ref.watch(tourDetailScreenProvider);
    if (tourDetailAsync.hasError) {
      final last = _lastGoodForBroadcast(selectedBroadcast.id);
      if (last != null) {
        return last;
      }
      Error.throwWithStackTrace(
        tourDetailAsync.error!,
        tourDetailAsync.stackTrace ?? StackTrace.current,
      );
    }

    final tourDetail = tourDetailAsync.valueOrNull;
    if (tourDetail == null) {
      return _lastGoodForBroadcast(selectedBroadcast.id) ?? const [];
    }
    final aboutTourModel = tourDetail.aboutTourModel;
    if (aboutTourModel.id.isEmpty) {
      return _lastGoodFor(
            broadcastId: selectedBroadcast.id,
            tourId: aboutTourModel.id,
          ) ??
          const [];
    }

    // A pagination-purposed category (e.g. "Boards 1-66") ranks every page
    // of its tournament together.
    final relatedTours = standingsToursFor(
      tourDetail.tours,
      tourId: aboutTourModel.id,
      tourName: aboutTourModel.name,
    );

    final rankedStandings = await buildRankedStandingsForTours(
      ref,
      relatedTours: relatedTours,
      sectionTourId: aboutTourModel.id,
    );

    if (rankedStandings.isEmpty) {
      return _lastGoodFor(
            broadcastId: selectedBroadcast.id,
            tourId: aboutTourModel.id,
          ) ??
          const [];
    }

    _rememberGoodStandings(
      broadcastId: selectedBroadcast.id,
      tourId: aboutTourModel.id,
      standings: rankedStandings,
    );
    return rankedStandings;
  }

  List<PlayerStandingModel>? _lastGoodFor({
    required String broadcastId,
    required String tourId,
  }) {
    if (_lastBroadcastId != broadcastId || _lastTourId != tourId) {
      return null;
    }
    return _lastGoodStandings;
  }

  List<PlayerStandingModel>? _lastGoodForBroadcast(String broadcastId) {
    if (_lastBroadcastId != broadcastId) {
      return null;
    }
    return _lastGoodStandings;
  }

  void _rememberGoodStandings({
    required String broadcastId,
    required String tourId,
    required List<PlayerStandingModel> standings,
  }) {
    _lastBroadcastId = broadcastId;
    _lastTourId = tourId;
    _lastGoodStandings = standings;
  }
}

/// Version counter to force refreshes when favorites change
final favoritesVersionProvider = StateProvider<int>((ref) => 0);

final tournamentFavoritePlayersProvider =
    FutureProvider<List<PlayerStandingModel>>((ref) async {
      // Watch the version to make this provider reactive to favorite changes
      ref.watch(favoritesVersionProvider);

      final favoritesService = ref.read(favoriteStandingsPlayerService);
      return favoritesService.getFavoritePlayers();
    });

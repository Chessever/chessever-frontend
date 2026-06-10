import 'package:chessever2/repository/supabase/supabase.dart';
import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

    bool isPaginationCategory(String name) {
      return RegExp(
        r'Boards?\s+\d+[\-\+]?\d*\+?$',
        caseSensitive: false,
      ).hasMatch(name);
    }

    String getCategoryBaseName(String name) {
      return name
          .replaceAll(
            RegExp(r'\s*Boards?\s+\d+[\-\+]?\d*\+?$', caseSensitive: false),
            '',
          )
          .trim();
    }

    final allGames = <GamesTourModel>[];

    if (isPaginationCategory(aboutTourModel.name)) {
      final baseName = getCategoryBaseName(aboutTourModel.name);
      final relatedTours =
          tourDetail.tours
              .where(
                (t) =>
                    isPaginationCategory(t.tour.name) &&
                    getCategoryBaseName(t.tour.name) == baseName,
              )
              .toList();

      if (relatedTours.length > 1) {
        for (final tourModel in relatedTours) {
          final tourGamesAsync = ref.watch(
            gamesTourProvider(tourModel.tour.id),
          );
          if (tourGamesAsync.hasValue) {
            for (final g in tourGamesAsync.value!) {
              try {
                allGames.add(GamesTourModel.fromGame(g));
              } catch (_) {}
            }
          }
        }
      } else {
        allGames.addAll(gamesTourAsync.value?.gamesTourModels ?? []);
      }
    } else {
      allGames.addAll(gamesTourAsync.value?.gamesTourModels ?? []);
    }

    return allGames;
  },
);

/// Search query for the standings tab
final standingsSearchQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

List<PlayerStandingModel> assignOverallRanks(
  List<PlayerStandingModel> standings,
) {
  return [
    for (var i = 0; i < standings.length; i++)
      standings[i].copyWith(overallRank: i + 1),
  ];
}

List<PlayerStandingModel> filterStandingsByQuery(
  List<PlayerStandingModel> standings,
  String rawQuery,
) {
  final query = _normalizeStandingSearch(rawQuery);
  if (query.isEmpty) return standings;

  return standings
      .where((player) {
        final searchable = [
          player.name,
          player.title ?? '',
          player.countryCode,
        ].join(' ');
        return _matchesStandingSearch(searchable, query);
      })
      .toList(growable: false);
}

String _normalizeStandingSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ');
}

bool _matchesStandingSearch(String value, String normalizedQuery) {
  final normalizedValue = _normalizeStandingSearch(value);
  if (normalizedValue.isEmpty) return false;
  if (normalizedValue.contains(normalizedQuery)) return true;

  final queryTokens = normalizedQuery.split(' ');
  return queryTokens.every(normalizedValue.contains);
}

final playerTourScreenProvider = AutoDisposeAsyncNotifierProvider<
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

    // Detect if this is a pagination-purposed category (e.g. "Boards 1-66")
    final List<TourModel> relatedTours;
    if (_isPaginationCategory(aboutTourModel.name)) {
      final baseName = _getCategoryBaseName(aboutTourModel.name);
      relatedTours =
          tourDetail.tours
              .where(
                (t) =>
                    _isPaginationCategory(t.tour.name) &&
                    _getCategoryBaseName(t.tour.name) == baseName,
              )
              .toList();
    } else {
      relatedTours =
          tourDetail.tours
              .where((e) => e.tour.id == aboutTourModel.id)
              .toList();
    }

    // Watch only the part of live games that can change standings. Move/clock
    // ticks should not rebuild this provider, but new games or result changes
    // should update scores gracefully while the list keeps its scroll offset.
    final allGames = _watchStandingsGamesForTours(relatedTours);

    final allPlayers = <TournamentPlayer>[];
    for (final tourModel in relatedTours) {
      allPlayers.addAll(tourModel.tour.players);
    }

    // Trust the server-side standings order only when scope is a single tour
    // that the data hub has flagged as canonically sorted (currently from
    // chess-results.com). Multi-tour pagination categories (e.g. "Boards 1-66"
    // + "Boards 67-126") interleave players from independent standings, so the
    // concatenation is not meaningful — fall back to client-side sort there.
    final useExternalOrder =
        relatedTours.length == 1 &&
        relatedTours.first.tour.usesExternalStandings;

    final builtStandings = await buildStandingsFromData(
      supabase: ref.read(supabaseProvider),
      tournamentPlayers: allPlayers,
      gamesTourModels: allGames,
      useExternalOrder: useExternalOrder,
      singleTourScope: relatedTours.length == 1,
    );

    if (builtStandings.isEmpty) {
      return _lastGoodFor(
            broadcastId: selectedBroadcast.id,
            tourId: aboutTourModel.id,
          ) ??
          const [];
    }

    // Assign 1-based ranks in unfiltered order. These stay attached to each
    // player so in-widget filter preserves the overall standing position.
    final rankedStandings = assignOverallRanks(builtStandings);
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

  List<GamesTourModel> _watchStandingsGamesForTours(
    List<TourModel> relatedTours,
  ) {
    final allGames = <GamesTourModel>[];

    for (final tourModel in relatedTours) {
      final tourId = tourModel.tour.id;
      ref.watch(gamesTourProvider(tourId).select(standingsGamesSignature));
      final games = ref.read(gamesTourProvider(tourId)).valueOrNull;
      if (games == null || games.isEmpty) continue;

      for (final game in games) {
        try {
          allGames.add(GamesTourModel.fromGame(game));
        } catch (_) {
          // Skip malformed rows to keep standings resilient during live ingest.
        }
      }
    }

    return allGames;
  }

  /// Identifies categories like "Boards 1-66", "Boards 67-126", "Boards 252+"
  bool _isPaginationCategory(String name) {
    return RegExp(
      r'Boards?\s+\d+[\-\+]?\d*\+?$',
      caseSensitive: false,
    ).hasMatch(name);
  }

  /// Extracts the base name before the pagination suffix (e.g. "Open | Boards 1-50" -> "Open |")
  String _getCategoryBaseName(String name) {
    return name
        .replaceAll(
          RegExp(r'\s*Boards?\s+\d+[\-\+]?\d*\+?$', caseSensitive: false),
          '',
        )
        .trim();
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

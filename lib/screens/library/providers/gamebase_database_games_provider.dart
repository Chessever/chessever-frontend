import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_search_provider.dart';
import 'package:chessever2/screens/library/utils/gamebase_game_to_games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Loads full `GamebaseGame` records for the current
/// `gamebaseDatabaseSearchProvider` rows and maps them to `GamesTourModel`.
///
/// This is used to render proper game cards (names/event/eco) since the
/// `/api/search/query` endpoint typically returns only IDs + a small subset
/// of columns.
final gamebaseDatabaseGamesProvider =
    FutureProvider.autoDispose<List<GamesTourModel>>((ref) async {
      final query = ref.watch(
        gamebaseDatabaseSearchProvider.select(
          (value) => value.valueOrNull?.query ?? '',
        ),
      );
      final filtersCount = ref.watch(
        gamebaseDatabaseSearchProvider.select(
          (value) => value.valueOrNull?.filters.length ?? 0,
        ),
      );
      final primaryKey = ref.watch(
        gamebaseDatabaseSearchProvider.select(
          (value) => value.valueOrNull?.resource.primaryKey ?? 'id',
        ),
      );
      final rows = ref.watch(
        gamebaseDatabaseSearchProvider.select(
          (value) => value.valueOrNull?.rows ?? const <Map<String, dynamic>>[],
        ),
      );

      final hasIntent = query.trim().isNotEmpty || filtersCount > 0;
      if (!hasIntent) return const <GamesTourModel>[];

      if (rows.isEmpty) return const <GamesTourModel>[];

      final ids =
          rows
              .map(
                (row) =>
                    ((row[primaryKey] ?? row['id'])?.toString() ?? '').trim(),
              )
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toList();

      if (ids.isEmpty) return const <GamesTourModel>[];

      final repo = ref.read(gamebaseRepositoryProvider);
      final games = await Future.wait(ids.map(repo.getGameById), eagerError: false);

      final mapped = <GamesTourModel>[];
      for (final game in games) {
        if (game == null) continue;
        mapped.add(mapGamebaseGameToGamesTourModel(game));
      }

      return mapped;
    });

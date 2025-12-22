import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/gamebase_filter_provider.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider for the library search query.
/// Updated from library screen when search text changes.
final librarySearchQueryProvider = StateProvider<String>((ref) => '');

/// Maps Gamebase search results into `GamesTourModel`s.
///
/// Uses the new simplified filter system via `gamebaseFilterProvider` and
/// passes filter parameters directly to the Gamebase API.
final gamebaseDatabaseGamesProvider = FutureProvider.autoDispose<
  List<GamesTourModel>
>((ref) async {
  final query = ref.watch(librarySearchQueryProvider);
  final filter = ref.watch(gamebaseFilterProvider);

  // If no query and no active filters, return empty
  if (query.trim().isEmpty && !filter.hasActiveFilters) {
    return const <GamesTourModel>[];
  }

  final repo = ref.read(gamebaseRepositoryProvider);

  try {
    // Call globalSearch with filter parameters
    final response = await repo.globalSearch(
      query: query.trim().isEmpty ? '*' : query.trim(),
      pageNumber: 1,
      pageSize: 50,
      result: filter.resultApiValue,
      color: filter.colorApiValue,
      timeControl: filter.timeControlApiValue,
      yearFrom: filter.minYear != 1800 ? filter.minYear : null,
      yearTo: filter.maxYear != DateTime.now().year ? filter.maxYear : null,
      ratingFrom: filter.minRating > 0 ? filter.minRating : null,
      ratingTo: filter.maxRating < 3500 ? filter.maxRating : null,
    );

    // Extract game results
    final gameResults = response.results
        .where((r) => r.resource == 'game')
        .toList();

    if (gameResults.isEmpty) {
      return const <GamesTourModel>[];
    }

    // Collect player IDs for enrichment
    final playerIds = <String>{};
    for (final result in gameResults) {
      final preview = result.preview ?? const <String, dynamic>{};
      final w = preview['whitePlayerId']?.toString().trim();
      final b = preview['blackPlayerId']?.toString().trim();
      if (w != null && w.isNotEmpty) playerIds.add(w);
      if (b != null && b.isNotEmpty) playerIds.add(b);
    }

    // Fetch player details for enrichment
    final playerDetails = <String, GamebasePlayer>{};
    if (playerIds.isNotEmpty) {
      final fetched = await Future.wait(
        playerIds.map(repo.getPlayerById),
        eagerError: false,
      );
      for (final p in fetched.whereType<GamebasePlayer>()) {
        playerDetails[p.id] = GamebasePlayer(
          id: p.id,
          fideId: p.fideId,
          name: p.name,
          gender: p.gender,
          fed: p.fed,
          title: ChessTitleUtils.normalize(p.title),
          ratingClassical: p.ratingClassical,
          ratingRapid: p.ratingRapid,
          ratingBlitz: p.ratingBlitz,
        );
      }
    }

    int ratingFor(GamebasePlayer? p, String? timeControl) {
      if (p == null) return 0;
      final tc = (timeControl ?? '').toUpperCase();
      switch (tc) {
        case 'RAPID':
          return p.ratingRapid ?? p.highestRating ?? 0;
        case 'BLITZ':
          return p.ratingBlitz ?? p.highestRating ?? 0;
        case 'CLASSICAL':
        default:
          return p.ratingClassical ?? p.highestRating ?? 0;
      }
    }

    DateTime? parseDate(Object? raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    String coalesceName(Map<String, dynamic> row, String keyA, String keyB) {
      final a = (row[keyA]?.toString() ?? '').trim();
      if (a.isNotEmpty) return a;
      final b = (row[keyB]?.toString() ?? '').trim();
      return b.isNotEmpty ? b : (keyA.startsWith('white') ? 'White' : 'Black');
    }

    return gameResults.map((result) {
      final row = <String, dynamic>{
        'id': result.id,
        'label': result.label,
        'snippet': result.snippet,
        ...?result.preview,
      };

      final id = (row['id']?.toString() ?? '').trim();
      final safeId = id.isNotEmpty ? id : 'unknown';
      final timeControl = row['timeControl']?.toString();
      final date = parseDate(row['date']);
      final resultStr = row['result']?.toString() ?? '*';

      final whiteName = coalesceName(row, 'white', 'whiteName');
      final blackName = coalesceName(row, 'black', 'blackName');

      final whitePlayerId = row['whitePlayerId']?.toString().trim();
      final blackPlayerId = row['blackPlayerId']?.toString().trim();
      final whitePlayer = (whitePlayerId != null) ? playerDetails[whitePlayerId] : null;
      final blackPlayer = (blackPlayerId != null) ? playerDetails[blackPlayerId] : null;

      final whiteTitle = ChessTitleUtils.normalize(
        row['whiteTitle']?.toString() ?? whitePlayer?.title,
      );
      final blackTitle = ChessTitleUtils.normalize(
        row['blackTitle']?.toString() ?? blackPlayer?.title,
      );

      final eco = row['eco']?.toString() ?? '';
      final opening = row['opening']?.toString() ?? '';
      final variation = row['variation']?.toString() ?? '';
      final event = row['event']?.toString() ?? 'Gamebase';
      final site = row['site']?.toString();

      final pgn = buildHeaderOnlyPgn(
        whiteName: whiteName,
        blackName: blackName,
        result: resultStr,
        event: event,
        site: site,
        date: date,
        eco: eco,
        opening: opening,
        variation: variation,
      );

      final whiteCard = PlayerCard(
        name: whiteName,
        federation: '',
        title: whiteTitle,
        rating: ratingFor(whitePlayer, timeControl),
        countryCode: whitePlayer?.fed ?? '',
        team: null,
        fideId: int.tryParse(whitePlayer?.fideId ?? ''),
      );

      final blackCard = PlayerCard(
        name: blackName,
        federation: '',
        title: blackTitle,
        rating: ratingFor(blackPlayer, timeControl),
        countryCode: blackPlayer?.fed ?? '',
        team: null,
        fideId: int.tryParse(blackPlayer?.fideId ?? ''),
      );

      final formatCode = (eco.trim().isNotEmpty) ? eco.trim() : (timeControl ?? '');

      return GamesTourModel(
        gameId: safeId,
        whitePlayer: whiteCard,
        blackPlayer: blackCard,
        whiteTimeDisplay: '--:--',
        blackTimeDisplay: '--:--',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: GameStatus.fromString(resultStr),
        roundId: 'gamebase_search',
        roundSlug: formatCode.isNotEmpty ? formatCode : null,
        tourId: event.trim().isNotEmpty ? event.trim() : 'Gamebase',
        pgn: pgn,
        lastMoveTime: date,
      );
    }).toList(growable: false);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[GamebaseDatabaseGames] Error: $e');
      debugPrintStack(stackTrace: st);
    }
    return const <GamesTourModel>[];
  }
});

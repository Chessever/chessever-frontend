import 'dart:convert';
import 'dart:math' as math;

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/chessboard/game_review/saved_game_report.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_access.dart';
import 'package:chessever2/screens/library/utils/gamebase_game_to_games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/time_control_bonus.dart';
import 'package:dartchess/dartchess.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final discoveryRepositoryProvider = Provider.autoDispose<DiscoveryRepository>((
  ref,
) {
  return DiscoveryRepository(
    client: () => Supabase.instance.client,
    games: ref.watch(gameRepositoryProvider),
    tours: ref.watch(tourRepositoryProvider),
    gamebase: ref.watch(gamebaseRepositoryProvider),
  );
});

/// How many ranked games one Most Liked read asks for: the lead card plus a
/// rail. Kept small because every one of them resolves to a game row.
const int kMostLikedLimit = 12;

/// How far back Analyzed Games looks. The hourly report prewarm annotates
/// the strongest finished games of a rolling day, so three days holds a few
/// dozen of them.
const Duration kAnalyzedGamesWindow = Duration(days: 3);

/// Read-only data behind the Discovery page. Every method stands alone so a
/// failing section never takes another one down with it.
class DiscoveryRepository {
  DiscoveryRepository({
    required this.client,
    required this.games,
    required this.tours,
    required this.gamebase,
  });

  final SupabaseClient Function() client;
  final GameRepository games;
  final TourRepository tours;
  final GamebaseRepository gamebase;

  // -------------------------------------------------------------- Most Liked

  /// The community ranking for [query] (one calendar day, week, month or
  /// year), resolved to real games.
  ///
  /// A backend without the ranking function answers
  /// [MostLikedResult.notLive], and a refused Premium window answers
  /// [MostLikedResult.premiumRequired]; every other failure is thrown for
  /// the section to show.
  Future<MostLikedResult> fetchMostLiked(
    MostLikedQuery query, {
    int limit = kMostLikedLimit,
  }) async {
    final window = query.window;
    final Object? rows;
    try {
      rows = await client().rpc(
        'most_liked_games',
        params: {
          'p_from': window.from.toUtc().toIso8601String(),
          'p_to': window.to.toUtc().toIso8601String(),
          'p_limit': limit,
        },
      );
    } catch (e) {
      switch (classifyMostLikedError(e)) {
        case MostLikedFailure.missingFunction:
          return const MostLikedResult.notLive();
        case MostLikedFailure.premiumRequired:
          return const MostLikedResult.premiumRequired();
        case MostLikedFailure.other:
          rethrow;
      }
    }

    final counts = parseMostLikedRows(rows);
    if (counts.isEmpty) return const MostLikedResult.ranked([]);

    final gamesById = await _resolveGames(
      counts.map((c) => c.gameId).toList(growable: false),
    );
    final eventNames = await _eventNames(gamesById.values);
    return MostLikedResult.ranked(
      assembleMostLikedEntries(
        counts: counts,
        gamesById: gamesById,
        eventNamesByTourId: eventNames,
      ),
    );
  }

  /// Broadcast games first (one batched read of `games`), then whatever is
  /// left through the Gamebase archive, where Miniatures and explorer games
  /// live. An id neither knows is left out.
  Future<Map<String, GamesTourModel>> _resolveGames(List<String> ids) async {
    final byId = <String, GamesTourModel>{};
    try {
      for (final row in await _broadcastGames(ids)) {
        try {
          byId[row.id] = GamesTourModel.fromGame(row);
        } catch (e) {
          // A row without two named players cannot be drawn; skip it.
          talker.debug('[Discovery] skipped unreadable game ${row.id}: $e');
        }
      }
    } catch (e, st) {
      talker.handle(e, st, '[Discovery] most liked games lookup failed');
    }

    final missing = ids.where((id) => !byId.containsKey(id)).toList();
    if (missing.isEmpty) return byId;

    final archived = await Future.wait(
      missing.map((id) async {
        try {
          final game = await gamebase.getGameById(id);
          return game == null ? null : mapGamebaseGameToGamesTourModel(game);
        } catch (_) {
          return null;
        }
      }),
    );
    for (var i = 0; i < missing.length; i++) {
      final game = archived[i];
      if (game != null) byId[missing[i]] = game;
    }
    return byId;
  }

  /// The broadcast rows for [ids], the PGN left out: a finished game's
  /// columns already hold what its card, board preview and My Space
  /// snapshot show. The PGN is read afterwards, in one batch, only for the
  /// rows whose columns fall short ([discoveryGameNeedsPgn]), so every game
  /// comes out as the full read made it. When that second read fails, the
  /// rows stay as they are rather than drop out of the ranking.
  Future<List<Games>> _broadcastGames(List<String> ids) async {
    final rows = [
      for (final raw
          in await client()
              .from('games')
              .select(_gameListColumnsWithoutPgn)
              .inFilter('id', ids))
        Games.fromJson(Map<String, dynamic>.from(raw)),
    ];
    final needPgn = [
      for (final game in rows)
        if (discoveryGameNeedsPgn(game)) game.id,
    ];
    if (needPgn.isEmpty) return rows;

    final pgnById = <String, String>{};
    try {
      final pgnRows = await client()
          .from('games')
          .select('id,pgn')
          .inFilter('id', needPgn);
      for (final raw in pgnRows) {
        final id = raw['id']?.toString();
        final pgn = raw['pgn'];
        if (id != null && pgn is String && pgn.isNotEmpty) pgnById[id] = pgn;
      }
    } catch (e, st) {
      talker.handle(e, st, '[Discovery] most liked PGN fallback failed');
    }
    return [
      for (final game in rows)
        if (pgnById[game.id] case final pgn?) game.copyWith(pgn: pgn) else game,
    ];
  }

  /// Tour names for broadcast games, keyed by tour id. Decoration only: a
  /// failed lookup leaves the event line empty.
  Future<Map<String, String>> _eventNames(
    Iterable<GamesTourModel> games,
  ) async {
    final tourIds = games
        .where((g) => g.source == GameSource.supabase)
        .map((g) => g.tourId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (tourIds.isEmpty) return const {};
    try {
      final rows = await tours.getToursByIds(tourIds);
      return {
        for (final tour in rows)
          if (tour.name.trim().isNotEmpty) tour.id: tour.name.trim(),
      };
    } catch (e, st) {
      talker.handle(e, st, '[Discovery] event names lookup failed');
      return const {};
    }
  }

  // --------------------------------------------------------- Analyzed games

  /// A small recent preview for older Discovery surfaces. The Reports screen
  /// uses [fetchAnalyzedGamesPage] and has no age or total-result limit.
  Future<List<GamesTourModel>> fetchAnalyzedGames({
    int limit = 10,
    DateTime? now,
  }) async {
    if (limit <= 0) return const [];
    final since = (now ?? DateTime.now()).subtract(kAnalyzedGamesWindow);
    final page = await fetchAnalyzedGamesPage(
      pageSize: limit * 3,
      since: since,
    );
    return rankAnalyzedGames(page.items).take(limit).toList(growable: false);
  }

  /// Saved ChessEver reports, newest first, using only existing game columns.
  /// The cursor advances over raw candidates even if none pass PGN validation.
  /// Null timestamps follow dated games; id breaks ties in both groups.
  /// These predicates/order match `games_saved_reports_page_idx`: changing
  /// either requires checking the database plan, not only mocked HTTP tests.
  Future<AnalyzedGamesPage> fetchAnalyzedGamesPage({
    int pageSize = 30,
    AnalyzedGamesCursor? after,
    DateTime? since,
    ReportGameType? gameType,
  }) async {
    if (pageSize <= 0) return const AnalyzedGamesPage(items: []);
    // All keeps its exact existing query, including on older backends. The
    // optional RPC filters the entire archive and excludes metadata whose PGN
    // changed. It returns SETOF games, preserving embedded tour relationships.
    final source = gameType == null
        ? client().from('games').select(_analyzedGameColumns)
        : client().rpc<List<Map<String, dynamic>>>(
            'report_games_by_type',
            params: {'p_type': gameType.key},
            get: true,
          );
    var query = source
        .inFilter('status', _kFinalStatuses.toList(growable: false))
        .like('pgn', r'%[\%eval %')
        .or(r'pgn.like.%$24%,pgn.ilike.%chessever_annotation%');
    if (since != null) {
      query = query.gte('last_move_time', since.toUtc().toIso8601String());
    }
    if (after != null) {
      final time = after.lastMoveTime;
      if (time == null) {
        query = query.isFilter('last_move_time', null).gt('id', after.gameId);
      } else {
        // Quoted PostgREST literals keep punctuation in ids/timestamps from
        // changing the filter grammar. This OR is ANDed with the report filter.
        final timestamp = jsonEncode(time);
        final id = jsonEncode(after.gameId);
        query = query.or(
          'last_move_time.lt.$timestamp,'
          'and(last_move_time.eq.$timestamp,id.gt.$id),'
          'last_move_time.is.null',
        );
      }
    }
    final stopwatch = Stopwatch()..start();
    final List<Map<String, dynamic>> rows;
    try {
      final selected = gameType == null
          ? query
          : query.select(_analyzedGameColumns);
      rows = await selected
          .order('last_move_time', ascending: false)
          .order('id', ascending: true)
          .limit(pageSize)
          // The list has an explicit Retry action. Bound a stalled connection
          // and avoid repeating unavailable-server requests behind the loader.
          .retry(enabled: false, requestTimeout: const Duration(seconds: 10));
    } catch (error) {
      if (gameType != null &&
          error is PostgrestException &&
          (error.code == 'PGRST202' || error.code == '42883')) {
        throw const ReportGameTypesUnavailable();
      }
      final cause = error is PostgrestException
          ? 'database ${error.code ?? 'unknown'}'
          : error.runtimeType.toString();
      talker.warning(
        '[Reports] Page request failed: $cause '
        '(${stopwatch.elapsedMilliseconds} ms)',
      );
      rethrow;
    }

    final finished = <GamesTourModel>[];
    for (final raw in rows) {
      try {
        if (!_kFinalStatuses.contains(raw['status']) ||
            !hasSavedGameReport(raw['pgn'])) {
          continue;
        }
        final game = GamesTourModel.fromGame(
          Games.fromJson(Map<String, dynamic>.from(raw)),
        );
        if (game.gameStatus.isFinished) finished.add(game);
      } catch (e) {
        talker.debug('[Discovery] skipped unreadable analyzed game: $e');
      }
    }
    return AnalyzedGamesPage(
      items: finished,
      nextCursor: rows.length < pageSize
          ? null
          : (
              lastMoveTime: rows.last['last_move_time'] as String?,
              gameId: rows.last['id'] as String,
            ),
    );
  }

  /// White-side engine evaluation after every annotated move of [gameId],
  /// read from its stored PGN. Empty when it carries none. Only the `pgn`
  /// column is read: the curve needs nothing else from the row.
  Future<List<int>> fetchEvalCurve(String gameId) async {
    return parseEvalCurve(await games.getGamePgn(gameId));
  }

  // -------------------------------------------------------------- Miniatures

  /// Today's miniatures from the community index, strongest first. Only
  /// games a free account may open are kept (the Miniatures Today rule), so
  /// nothing on the rail leads to a paywall.
  Future<List<DiscoveryMiniature>> fetchTodayMiniatures({
    int limit = 12,
    DateTime? now,
  }) async => (await fetchTodayMiniaturesDay(limit: limit, now: now)).items;

  /// [fetchTodayMiniatures], with how many miniatures today holds in all:
  /// the index counts the whole day while only the first [limit] are read.
  Future<({List<DiscoveryMiniature> items, int total})>
  fetchTodayMiniaturesDay({int limit = 12, DateTime? now}) async {
    final page = await gamebase.getMiniatures(
      filter: MiniatureGamesFilter.defaultFilter.copyWith(
        window: MiniatureGamesWindow.today,
      ),
      limit: limit,
    );
    final reference = now ?? DateTime.now();
    final items = orderMiniaturesByDayAndAverageRating(page.items)
        .where(
          (item) => !isMiniatureGameLocked(
            item.date,
            isSubscribed: false,
            subscriptionLoading: false,
            now: reference,
          ),
        )
        .map(
          (item) => DiscoveryMiniature(
            game: item.toGamesTourModel(),
            moves: item.finalMoveNumber,
          ),
        )
        .toList(growable: false);
    return (items: items, total: math.max(page.total, items.length));
  }
}

/// Strongest first by the two players' average rating, then most recent,
/// then id, so the order never shuffles between reads.
List<GamesTourModel> rankAnalyzedGames(List<GamesTourModel> games) {
  int avg(GamesTourModel g) => discoveryAverageRating(g) ?? 0;

  final sorted = List<GamesTourModel>.of(games);
  sorted.sort((a, b) {
    final byRating = avg(b).compareTo(avg(a));
    if (byRating != 0) return byRating;
    final at = a.lastMoveTime;
    final bt = b.lastMoveTime;
    if (at != null && bt != null && at != bt) return bt.compareTo(at);
    return a.gameId.compareTo(b.gameId);
  });
  return sorted;
}

/// Statuses a game ends on. Anything else may still be moving, so its
/// columns can trail its PGN.
const Set<String> _kFinalStatuses = {'1-0', '0-1', '1/2-1/2'};

/// Whether the PGN changes anything [GamesTourModel.fromGame] makes of
/// [game] or that is drawn from it afterwards: the card, its board preview
/// ([discoveryHasRealPosition]) and the My Space snapshot
/// (`spaceGameCardParams`). Each place the model falls back to the PGN is
/// checked here: a game still in play, a missing last move, a position the
/// PGN replay would write differently, a clock the columns do not carry, a
/// second time period (topped up from the PGN's clock history) and an
/// unknown opening. A finished game whose columns hold all of it needs no
/// PGN at all.
bool discoveryGameNeedsPgn(Games game) {
  if (!_kFinalStatuses.contains(game.status?.trim())) return true;
  final players = game.players;
  // A row the model refuses anyway: the PGN would not rescue it.
  if (players == null ||
      players.length < 2 ||
      players[0].name.isEmpty ||
      players[1].name.isEmpty) {
    return false;
  }
  final lastMove = game.lastMove?.trim() ?? '';
  if (lastMove.isEmpty) return true;
  if (!_fenShowsMove(game.fen, lastMove)) return true;
  for (final (seconds, player) in [
    (game.lastClockWhite, players[0]),
    (game.lastClockBlack, players[1]),
  ]) {
    final clock = GamesTourModel.normalizeClockSeconds(
      clockSeconds: seconds,
      clockCentiseconds: player.clock,
    );
    if (clock == null) return true;
  }
  if (parseSecondaryTimePeriod(game.timeControlText) != null) return true;
  return !_knownOpening(game.eco) || !_knownOpening(game.openingName);
}

/// Whether [fen] already shows [lastMove] played (the mover's piece on its
/// target square, its origin empty) and is written exactly as a PGN replay
/// writes a position. Only then is the column the very string the model
/// would otherwise take from the PGN's final position, so the lean read and
/// the full one agree to the character.
bool _fenShowsMove(String? fen, String lastMove) {
  final raw = fen?.trim() ?? '';
  if (raw.isEmpty || lastMove.length < 4) return false;
  try {
    final position = Chess.fromSetup(Setup.parseFen(raw));
    if (position.fen != raw) return false;
    final move = Move.parse(lastMove.toLowerCase());
    if (move is! NormalMove) return false;
    final moved = position.board.pieceAt(move.to);
    return moved != null &&
        moved.color == position.turn.opposite &&
        position.board.pieceAt(move.from) == null;
  } catch (_) {
    return false;
  }
}

/// The model's own test for a usable ECO code or opening name.
bool _knownOpening(String? value) {
  final v = value?.trim().toUpperCase() ?? '';
  return v.isNotEmpty && v != '?' && v != 'UNKNOWN';
}

/// The broadcast game list columns, as `GameRepository` selects them, minus
/// the PGN and the `search` terms (neither is read to build a card).
const String _gameListColumnsWithoutPgn = '''
          id,
          round_id,
          round_slug,
          tour_id,
          tour_slug,
          name,
          fen,
          players,
          last_move,
          think_time,
          status,
          lichess_id,
          player_white,
          player_black,
          date_start,
          time_start,
          board_nr,
          last_move_time,
          game_day,
          last_clock_white,
          last_clock_black,
          eco,
          opening_name,
          tours!games_tour_id_fkey(
            avg_elo,
            tc:info->>tc,
            group_broadcasts!tours_group_broadcast_id_fkey(time_control)
          )
        ''';

/// Broadcast card metadata and the existing PGN used to recognize saved reports.
const String _analyzedGameColumns = '''
          id,
          pgn,
          round_id,
          round_slug,
          tour_id,
          tour_slug,
          name,
          fen,
          players,
          last_move,
          think_time,
          status,
          search,
          lichess_id,
          player_white,
          player_black,
          date_start,
          time_start,
          board_nr,
          last_move_time,
          game_day,
          last_clock_white,
          last_clock_black,
          eco,
          opening_name,
          tours!games_tour_id_fkey(
            name,
            avg_elo,
            tc:info->>tc,
            group_broadcasts!tours_group_broadcast_id_fkey(name, time_control)
          )
        ''';

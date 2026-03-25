import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart'
    show GamebasePlayer;
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/twic_player_enrichment.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TwicScorecardEventGamesRequest {
  const TwicScorecardEventGamesRequest({
    required this.playerId,
    required this.event,
  });

  final String playerId;
  final String event;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TwicScorecardEventGamesRequest &&
          other.playerId == playerId &&
          other.event == event;

  @override
  int get hashCode => Object.hash(playerId, event);
}

final twicScorecardEventGamesProvider = FutureProvider.family.autoDispose<
  List<GamesTourModel>,
  TwicScorecardEventGamesRequest
>((ref, request) async {
  final repository = ref.read(gamebaseRepositoryProvider);
  final rows = <Map<String, dynamic>>[];

  var page = 0;
  while (true) {
    final response = await repository.getPlayerGames(
      playerId: request.playerId,
      event: request.event,
      pageNumber: page,
      pageSize: 100,
    );

    final data = response['data'];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          rows.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final metadata = response['metadata'];
    final hasMore = metadata is Map ? metadata['hasMore'] == true : false;
    if (!hasMore) break;
    if (data is! List || data.isEmpty) break;
    page += 1;
    if (page >= 1000) break;
  }

  final gamebasePlayersById = <String, GamebasePlayer>{};
  final playerIds = <String>{};
  for (final row in rows) {
    final whitePlayerId = row['whitePlayerId']?.toString().trim();
    final blackPlayerId = row['blackPlayerId']?.toString().trim();
    if (whitePlayerId != null && whitePlayerId.isNotEmpty) {
      playerIds.add(whitePlayerId);
    }
    if (blackPlayerId != null && blackPlayerId.isNotEmpty) {
      playerIds.add(blackPlayerId);
    }
  }
  if (playerIds.isNotEmpty) {
    final fetched = await Future.wait(
      playerIds.map(repository.getPlayerById),
      eagerError: false,
    );
    for (final player in fetched.whereType<GamebasePlayer>()) {
      gamebasePlayersById[player.id] = player;
    }
  }

  var games = rows
      .map((row) => _mapPlayerGameRowToModel(row, gamebasePlayersById))
      .toList(growable: false);
  final fideIds = collectFideIdsFromGames(games);
  if (fideIds.isNotEmpty) {
    final playersByFideId = await ref
        .read(chessPlayerRepositoryProvider)
        .getPlayersByFideIds(fideIds);
    games = enrichGamesWithChessPlayers(games, playersByFideId);
  }
  final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
  games.sort((a, b) {
    final aTime = a.lastMoveTime ?? epochFallback;
    final bTime = b.lastMoveTime ?? epochFallback;
    return bTime.compareTo(aTime);
  });

  if (kDebugMode) {
    debugPrint(
      '[twicScorecardEventGamesProvider] loaded ${games.length} games for player=${request.playerId} event="${request.event}"',
    );
  }

  return games;
});

GamesTourModel _mapPlayerGameRowToModel(
  Map<String, dynamic> row,
  Map<String, GamebasePlayer> gamebasePlayersById,
) {
  final id = row['id']?.toString().trim();
  final gameId = (id != null && id.isNotEmpty) ? id : 'unknown';

  final result = row['result']?.toString() ?? '*';
  final timeControl = row['timeControl']?.toString();
  final date = _parseDate(row['date']);

  final eco = row['eco']?.toString();
  final opening = row['opening']?.toString();
  final variation = row['variation']?.toString();
  final site = row['site']?.toString();

  final event = (row['event']?.toString() ?? 'Gamebase').trim();

  final whiteName =
      (row['white']?.toString() ?? row['whiteName']?.toString() ?? 'White')
          .trim();
  final blackName =
      (row['black']?.toString() ?? row['blackName']?.toString() ?? 'Black')
          .trim();

  final pgn = buildHeaderOnlyPgn(
    whiteName: whiteName,
    blackName: blackName,
    result: result,
    event: event.isNotEmpty ? event : 'Gamebase',
    site: site,
    date: date,
    eco: eco,
    opening: opening,
    variation: variation,
    fen:
        row['fen']?.toString() ??
        row['finalFen']?.toString() ??
        row['positionFen']?.toString(),
  );

  final whitePlayerId = row['whitePlayerId']?.toString().trim();
  final blackPlayerId = row['blackPlayerId']?.toString().trim();
  final whitePlayer =
      (whitePlayerId != null && whitePlayerId.isNotEmpty)
          ? gamebasePlayersById[whitePlayerId]
          : null;
  final blackPlayer =
      (blackPlayerId != null && blackPlayerId.isNotEmpty)
          ? gamebasePlayersById[blackPlayerId]
          : null;
  final whiteFideId =
      _parseFide(row['whiteFideId']) ?? int.tryParse(whitePlayer?.fideId ?? '');
  final blackFideId =
      _parseFide(row['blackFideId']) ?? int.tryParse(blackPlayer?.fideId ?? '');
  final whiteFed =
      (row['whiteFed']?.toString().trim().isNotEmpty ?? false)
          ? row['whiteFed'].toString().trim()
          : (whitePlayer?.fed ?? '');
  final blackFed =
      (row['blackFed']?.toString().trim().isNotEmpty ?? false)
          ? row['blackFed'].toString().trim()
          : (blackPlayer?.fed ?? '');
  final whiteEloRaw = (row['whiteElo'] as num?)?.toInt() ?? 0;
  final blackEloRaw = (row['blackElo'] as num?)?.toInt() ?? 0;
  final whiteElo =
      whiteEloRaw > 0 ? whiteEloRaw : _ratingFor(whitePlayer, timeControl);
  final blackElo =
      blackEloRaw > 0 ? blackEloRaw : _ratingFor(blackPlayer, timeControl);

  final whiteCard = PlayerCard(
    name: whiteName,
    federation: '',
    title: _normalizeTitle(row['whiteTitle'] ?? whitePlayer?.title),
    rating: whiteElo,
    countryCode: whiteFed,
    team: null,
    fideId: whiteFideId,
    gamebasePlayerId:
        (whitePlayerId != null && whitePlayerId.isNotEmpty)
            ? whitePlayerId
            : whitePlayer?.id,
  );

  final blackCard = PlayerCard(
    name: blackName,
    federation: '',
    title: _normalizeTitle(row['blackTitle'] ?? blackPlayer?.title),
    rating: blackElo,
    countryCode: blackFed,
    team: null,
    fideId: blackFideId,
    gamebasePlayerId:
        (blackPlayerId != null && blackPlayerId.isNotEmpty)
            ? blackPlayerId
            : blackPlayer?.id,
  );

  final round = row['round']?.toString().trim();

  return GamesTourModel(
    gameId: gameId,
    source: GameSource.twic,
    whitePlayer: whiteCard,
    blackPlayer: blackCard,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.fromString(result),
    roundId: (round != null && round.isNotEmpty) ? round : 'twic_event',
    roundSlug:
        (round != null && round.isNotEmpty)
            ? round
            : ((eco != null && eco.trim().isNotEmpty)
                ? eco.trim()
                : (timeControl ?? '')),
    tourId: event.isNotEmpty ? event : 'Gamebase',
    tourSlug: event.isNotEmpty ? event : 'Gamebase',
    lastMove: row['lastMove']?.toString(),
    fen:
        row['fen']?.toString() ??
        row['finalFen']?.toString() ??
        row['positionFen']?.toString(),
    pgn: pgn,
    lastMoveTime: date,
    eco: (eco != null && eco.trim().isNotEmpty) ? eco.trim() : null,
    openingName:
        (opening != null && opening.trim().isNotEmpty) ? opening.trim() : null,
    timeControl: timeControl,
  );
}

DateTime? _parseDate(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString());
}

int? _parseFide(Object? raw) {
  if (raw == null) return null;
  return int.tryParse(raw.toString());
}

String _normalizeTitle(Object? raw) {
  final text = raw?.toString();
  if (text == null || text.trim().isEmpty) return '';
  return ChessTitleUtils.normalize(text);
}

int _ratingFor(GamebasePlayer? player, String? timeControl) {
  if (player == null) return 0;
  final tc = (timeControl ?? '').toUpperCase();
  switch (tc) {
    case 'RAPID':
      return player.ratingRapid ?? player.highestRating ?? 0;
    case 'BLITZ':
      return player.ratingBlitz ?? player.highestRating ?? 0;
    case 'CLASSICAL':
    default:
      return player.ratingClassical ?? player.highestRating ?? 0;
  }
}

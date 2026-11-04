import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/chess_title_utils.dart';

int? parseFideIdFromRaw(Object? raw) {
  if (raw == null) return null;
  final parsed = int.tryParse(raw.toString().trim());
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

Set<int> collectFideIdsFromRows(List<Map<String, dynamic>> rows) {
  final ids = <int>{};
  for (final row in rows) {
    final whiteId = parseFideIdFromRaw(row['whiteFideId']);
    final blackId = parseFideIdFromRaw(row['blackFideId']);
    if (whiteId != null) ids.add(whiteId);
    if (blackId != null) ids.add(blackId);
  }
  return ids;
}

Set<int> collectFideIdsFromGames(Iterable<GamesTourModel> games) {
  final ids = <int>{};
  for (final game in games) {
    final whiteId = game.whitePlayer.fideId;
    final blackId = game.blackPlayer.fideId;
    if (whiteId != null && whiteId > 0) ids.add(whiteId);
    if (blackId != null && blackId > 0) ids.add(blackId);
  }
  return ids;
}

/// Fills a card's missing name, title, federation and rating from
/// `chess_players` (today's data). [fillTitle] is false when the game's titles
/// are already the ones held at the time ([ChessTitleUtils.titlesSettled]).
PlayerCard enrichPlayerCardFromChessPlayers(
  PlayerCard card,
  Map<int, ChessPlayer> playersByFideId, {
  bool fillTitle = true,
}) {
  final fideId = card.fideId;
  if (fideId == null || fideId <= 0) return card;

  final player = playersByFideId[fideId];
  if (player == null) return card;

  final mergedTitle = ChessTitleUtils.normalize(
    card.title.trim().isNotEmpty || !fillTitle ? card.title : player.title,
  );
  final mergedCountry =
      card.countryCode.trim().isNotEmpty
          ? card.countryCode.trim()
          : (player.country?.trim() ?? '');
  final mergedRating = card.rating > 0 ? card.rating : (player.rating ?? 0);
  final mergedName =
      card.name.trim().isNotEmpty ? card.name : player.name.trim();

  return card.copyWith(
    name: mergedName.isNotEmpty ? mergedName : card.name,
    title: mergedTitle,
    countryCode: mergedCountry,
    rating: mergedRating,
  );
}

GamesTourModel enrichGameWithChessPlayers(
  GamesTourModel game,
  Map<int, ChessPlayer> playersByFideId,
) {
  // An archive game whose titles are settled keeps an empty side empty: that
  // player was untitled when the game was played.
  final fillTitle =
      game.source == GameSource.supabase ||
      !ChessTitleUtils.titlesSettled(
        game.whitePlayer.title,
        game.blackPlayer.title,
      );
  final white = enrichPlayerCardFromChessPlayers(
    game.whitePlayer,
    playersByFideId,
    fillTitle: fillTitle,
  );
  final black = enrichPlayerCardFromChessPlayers(
    game.blackPlayer,
    playersByFideId,
    fillTitle: fillTitle,
  );
  if (white == game.whitePlayer && black == game.blackPlayer) return game;
  return game.copyWith(whitePlayer: white, blackPlayer: black);
}

List<GamesTourModel> enrichGamesWithChessPlayers(
  List<GamesTourModel> games,
  Map<int, ChessPlayer> playersByFideId,
) {
  if (games.isEmpty || playersByFideId.isEmpty) return games;
  return games
      .map((game) => enrichGameWithChessPlayers(game, playersByFideId))
      .toList(growable: false);
}

Map<String, dynamic> enrichSearchRowWithChessPlayers(
  Map<String, dynamic> row,
  Map<int, ChessPlayer> playersByFideId,
) {
  if (playersByFideId.isEmpty) return row;

  final whiteFideId = parseFideIdFromRaw(row['whiteFideId']);
  final blackFideId = parseFideIdFromRaw(row['blackFideId']);
  final whitePlayer = whiteFideId != null ? playersByFideId[whiteFideId] : null;
  final blackPlayer = blackFideId != null ? playersByFideId[blackFideId] : null;

  if (whitePlayer == null && blackPlayer == null) return row;

  final enriched = Map<String, dynamic>.from(row);
  // Gamebase settles a row's titles as held at the time; see titlesSettled.
  final titlesSettled = ChessTitleUtils.titlesSettled(
    row['whiteTitle']?.toString(),
    row['blackTitle']?.toString(),
  );

  if (whitePlayer != null) {
    final currentTitle = (enriched['whiteTitle']?.toString() ?? '').trim();
    if (currentTitle.isEmpty && !titlesSettled) {
      enriched['whiteTitle'] = ChessTitleUtils.normalize(whitePlayer.title);
    }
    final currentFed = (enriched['whiteFed']?.toString() ?? '').trim();
    if (currentFed.isEmpty) {
      enriched['whiteFed'] = (whitePlayer.country ?? '').trim();
    }
    final currentElo = (enriched['whiteElo'] as num?)?.toInt() ?? 0;
    if (currentElo <= 0 && (whitePlayer.rating ?? 0) > 0) {
      enriched['whiteElo'] = whitePlayer.rating;
    }
  }

  if (blackPlayer != null) {
    final currentTitle = (enriched['blackTitle']?.toString() ?? '').trim();
    if (currentTitle.isEmpty && !titlesSettled) {
      enriched['blackTitle'] = ChessTitleUtils.normalize(blackPlayer.title);
    }
    final currentFed = (enriched['blackFed']?.toString() ?? '').trim();
    if (currentFed.isEmpty) {
      enriched['blackFed'] = (blackPlayer.country ?? '').trim();
    }
    final currentElo = (enriched['blackElo'] as num?)?.toInt() ?? 0;
    if (currentElo <= 0 && (blackPlayer.rating ?? 0) > 0) {
      enriched['blackElo'] = blackPlayer.rating;
    }
  }

  return enriched;
}

List<Map<String, dynamic>> enrichSearchRowsWithChessPlayers(
  List<Map<String, dynamic>> rows,
  Map<int, ChessPlayer> playersByFideId,
) {
  if (rows.isEmpty || playersByFideId.isEmpty) return rows;
  return rows
      .map((row) => enrichSearchRowWithChessPlayers(row, playersByFideId))
      .toList(growable: false);
}

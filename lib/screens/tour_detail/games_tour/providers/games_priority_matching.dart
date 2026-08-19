import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/favorite_player_identity.dart';

typedef GamePriorityPlayerIdentity =
    ({String name, int? fideId, String countryCode, String federation});

typedef GamePriorityIdentity =
    ({
      String gameId,
      GamePriorityPlayerIdentity whitePlayer,
      GamePriorityPlayerIdentity blackPlayer,
    });

/// Extracts only the fields used by favorite/country priority matching.
///
/// This deliberately avoids [GamesTourModel.fromGame], whose PGN/clock parsing
/// would be wasted work when all we need is player identity and federation.
List<GamePriorityIdentity> gamePriorityIdentitiesFromRawGames(
  Iterable<Games> games,
) {
  final identities = <GamePriorityIdentity>[];
  for (final game in games) {
    final players = game.players;
    if (players == null || players.length < 2) continue;
    final white = players[0];
    final black = players[1];
    if (white.name.trim().isEmpty || black.name.trim().isEmpty) continue;
    identities.add((
      gameId: game.id,
      whitePlayer: _priorityIdentityFromRawPlayer(white),
      blackPlayer: _priorityIdentityFromRawPlayer(black),
    ));
  }
  return identities;
}

List<GamePriorityIdentity> gamePriorityIdentitiesFromModels(
  Iterable<GamesTourModel> games,
) {
  return <GamePriorityIdentity>[
    for (final game in games)
      (
        gameId: game.gameId,
        whitePlayer: _priorityIdentityFromPlayerCard(game.whitePlayer),
        blackPlayer: _priorityIdentityFromPlayerCard(game.blackPlayer),
      ),
  ];
}

/// True only when membership inputs changed. Clock, move, result, rating, and
/// other live-card updates do not trigger another auto-pin scan.
bool didRawGamePriorityInputsChange(List<Games> previous, List<Games> next) {
  if (previous.length != next.length) return true;

  final previousById = <String, Games>{
    for (final game in previous) game.id: game,
  };
  if (previousById.length != previous.length) return true;

  for (final game in next) {
    final previousGame = previousById[game.id];
    if (previousGame == null ||
        !haveSameRawGamePriorityInputs(previousGame, game)) {
      return true;
    }
  }
  return false;
}

bool haveSameRawGamePriorityInputs(Games first, Games second) {
  if (first.id != second.id) return false;
  final firstPlayers = first.players;
  final secondPlayers = second.players;
  if (firstPlayers == null || secondPlayers == null) {
    return firstPlayers == null && secondPlayers == null;
  }
  if (firstPlayers.length < 2 || secondPlayers.length < 2) {
    return firstPlayers.length == secondPlayers.length;
  }
  return _haveSameRawPlayerPriorityInputs(firstPlayers[0], secondPlayers[0]) &&
      _haveSameRawPlayerPriorityInputs(firstPlayers[1], secondPlayers[1]);
}

bool didModelGamePriorityInputsChange(
  List<GamesTourModel> previous,
  List<GamesTourModel> next,
) {
  if (previous.length != next.length) return true;

  final previousById = <String, GamesTourModel>{
    for (final game in previous) game.gameId: game,
  };
  if (previousById.length != previous.length) return true;

  for (final game in next) {
    final previousGame = previousById[game.gameId];
    if (previousGame == null ||
        !_haveSamePlayerCardPriorityInputs(
          previousGame.whitePlayer,
          game.whitePlayer,
        ) ||
        !_haveSamePlayerCardPriorityInputs(
          previousGame.blackPlayer,
          game.blackPlayer,
        )) {
      return true;
    }
  }
  return false;
}

/// Resolves the games containing at least one favorite player in one linear
/// pass. Positive FIDE ids are authoritative; normalized full names are only
/// a compatibility fallback for legacy or still-hydrating rows.
Set<String> favoritePlayerGameIdsForGames({
  required Iterable<GamesTourModel> games,
  required Iterable<FavoritePlayer> favorites,
}) {
  return favoritePlayerGameIdsForIdentities(
    games: gamePriorityIdentitiesFromModels(games),
    favorites: favorites,
  );
}

Set<String> favoritePlayerGameIdsForIdentities({
  required Iterable<GamePriorityIdentity> games,
  required Iterable<FavoritePlayer> favorites,
}) {
  final favoriteList = favorites.toList(growable: false);
  if (favoriteList.isEmpty) return <String>{};

  bool isFavorite(GamePriorityPlayerIdentity player) {
    final playerCountry =
        player.countryCode.trim().isNotEmpty
            ? player.countryCode
            : player.federation;
    for (final favorite in favoriteList) {
      if (favoriteMatchesPlayer(
        favorite: favorite,
        playerName: player.name,
        playerFideId: player.fideId,
        playerCountry: playerCountry,
      )) {
        return true;
      }
    }
    return false;
  }

  final gameIds = <String>{};
  for (final game in games) {
    if (isFavorite(game.whitePlayer) || isFavorite(game.blackPlayer)) {
      gameIds.add(game.gameId);
    }
  }
  return gameIds;
}

/// Resolves games containing a player from [selectedCountryCode]. The saved
/// selection is ISO-2 while tournament feeds use FIDE federation codes, which
/// deliberately differ from ISO alpha-3 for countries such as Germany.
Set<String> countrymanGameIdsForGames({
  required Iterable<GamesTourModel> games,
  required String selectedCountryCode,
}) {
  return countrymanGameIdsForIdentities(
    games: gamePriorityIdentitiesFromModels(games),
    selectedCountryCode: selectedCountryCode,
  );
}

Set<String> countrymanGameIdsForIdentities({
  required Iterable<GamePriorityIdentity> games,
  required String selectedCountryCode,
}) {
  final selected = selectedCountryCode.trim().toUpperCase();
  final selectedIso2 =
      selected.length == 2 ? selected : CountryUtils.toIso2Code(selected);
  if (selectedIso2.isEmpty) return <String>{};

  final selectedFideCode = CountryUtils.toFideCode(selectedIso2);

  bool isCountryman(GamePriorityPlayerIdentity player) {
    final rawCode =
        (player.countryCode.trim().isNotEmpty
                ? player.countryCode
                : player.federation)
            .trim()
            .toUpperCase();
    if (rawCode.isEmpty) return false;
    if (rawCode == selectedIso2 || rawCode == selectedFideCode) return true;
    return CountryUtils.toIso2Code(rawCode) == selectedIso2;
  }

  final gameIds = <String>{};
  for (final game in games) {
    if (isCountryman(game.whitePlayer) || isCountryman(game.blackPlayer)) {
      gameIds.add(game.gameId);
    }
  }
  return gameIds;
}

GamePriorityPlayerIdentity _priorityIdentityFromRawPlayer(Player player) => (
  name: player.name,
  fideId: player.fideId > 0 ? player.fideId : null,
  countryCode: player.fed,
  federation: player.fed,
);

GamePriorityPlayerIdentity _priorityIdentityFromPlayerCard(PlayerCard player) =>
    (
      name: player.name,
      fideId: player.fideId,
      countryCode: player.countryCode,
      federation: player.federation,
    );

bool _haveSameRawPlayerPriorityInputs(Player first, Player second) {
  return first.name == second.name &&
      first.fideId == second.fideId &&
      first.fed == second.fed;
}

bool _haveSamePlayerCardPriorityInputs(PlayerCard first, PlayerCard second) {
  return first.name == second.name &&
      first.fideId == second.fideId &&
      first.countryCode == second.countryCode &&
      first.federation == second.federation;
}

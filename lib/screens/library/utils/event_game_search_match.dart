import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';

/// Whether [game], one of a picked event's games from `GET /api/event`,
/// matches the ChessEver database search the event chip was counted under.
///
/// Mirrors gamebase's game search: free text against the words it indexes
/// (players, FIDE ids, ECO, opening; one alphanumeric word of four or more
/// letters is a prefix, otherwise every word must appear), then the filters
/// an event game carries: result, ECO, year and rating. Time control and
/// online/OTB are not in the event view; the chip was already counted under
/// them, so they are not re-checked here.
bool eventGameMatchesSearch(
  GamebaseEventGame game, {
  required String query,
  required GamebaseFilter filter,
}) {
  return _matchesText(game, query) &&
      _matchesResult(game, filter) &&
      _matchesEco(game, filter.eco) &&
      _matchesYear(game, filter) &&
      _matchesRating(game, filter);
}

final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _singleToken = RegExp(r'^[A-Za-z0-9]+$');
final _ecoCode = RegExp(r'^[A-E][0-9]{1,2}$', caseSensitive: false);

Iterable<String> _words(String? text) => (text ?? '')
    .toLowerCase()
    .split(_nonWord)
    .where((word) => word.isNotEmpty);

bool _matchesText(GamebaseEventGame game, String query) {
  final trimmed = query.trim();
  final raw = trimmed == '*' ? '' : trimmed;
  // The server ignores text under three letters once a filter (here the
  // event) is set, unless it is an ECO code.
  if (raw.isEmpty || (raw.length < 3 && !_ecoCode.hasMatch(raw))) return true;

  final indexed = <String>{
    ..._words(game.white.name),
    ..._words(game.black.name),
    ..._words(game.white.fideId),
    ..._words(game.black.fideId),
    ..._words(game.eco),
    ..._words(game.opening),
  };
  if (_singleToken.hasMatch(raw) && raw.length >= 4) {
    final prefix = raw.toLowerCase();
    return indexed.any((word) => word.startsWith(prefix));
  }
  return _words(raw).every(indexed.contains);
}

bool _matchesResult(GamebaseEventGame game, GamebaseFilter filter) {
  final wanted = switch (filter.resultApiValue) {
    'W' => '1-0',
    'B' => '0-1',
    'D' => '1/2-1/2',
    _ => null,
  };
  return wanted == null || game.result == wanted;
}

bool _matchesEco(GamebaseEventGame game, GameEcoFilter eco) {
  if (eco.isAll) return true;
  final stored = (game.eco ?? '').trim().toUpperCase();
  if (eco.isUnknownEco) return stored == GameEcoFilter.unknownEcoCode;
  return eco.ecoPrefixes.any(
    (prefix) => stored.startsWith(prefix.toUpperCase()),
  );
}

bool _matchesYear(GamebaseEventGame game, GamebaseFilter filter) {
  final from =
      filter.minYear != GameFilter.absoluteMinYear ? filter.minYear : null;
  final to = filter.maxYear != DateTime.now().year ? filter.maxYear : null;
  if (from == null && to == null) return true;
  final year = game.date?.year;
  if (year == null) return false;
  return (from == null || year >= from) && (to == null || year <= to);
}

bool _matchesRating(GamebaseEventGame game, GamebaseFilter filter) {
  final hasMin = filter.minRating > GameFilter.absoluteMinRating;
  final hasMax = filter.maxRating < GameFilter.absoluteMaxRating;
  if (!hasMin && !hasMax) return true;
  final min = hasMin ? filter.minRating : 0;
  final max = hasMax ? filter.maxRating : 4000;
  bool within(int? elo) => elo != null && elo >= min && elo <= max;

  return switch (filter.colorApiValue) {
    'white' => within(game.white.elo),
    'black' => within(game.black.elo),
    _ => within(_averageElo(game.white.elo, game.black.elo) ?? 0),
  };
}

int? _averageElo(int? white, int? black) {
  if (white != null && black != null) return (white + black) ~/ 2;
  return white ?? black;
}

import 'package:chessever2/repository/supabase/game/games.dart';

String gameResultSearchText(Games game) {
  final status = game.status?.trim();
  if (_isSupportedPgnResult(status)) return status!;

  final pgn = game.pgn;
  if (pgn == null || pgn.isEmpty) return '';

  final match = RegExp(
    r'\[Result\s+"([^"]+)"\]',
    caseSensitive: false,
  ).firstMatch(pgn);
  final result = match?.group(1)?.trim();
  return _isSupportedPgnResult(result) ? result! : '';
}

bool gameResultMatchesSearchQuery(Games game, String query) {
  final normalizedQuery = query.toLowerCase().trim();
  if (normalizedQuery.isEmpty) return false;

  final resultText = gameResultSearchText(game).toLowerCase();
  if (resultText.isEmpty) return false;

  final queryTokens =
      normalizedQuery.split(' ').where((token) => token.isNotEmpty).toList();
  for (final token in queryTokens) {
    if (!resultText.contains(token)) return false;
  }
  return true;
}

bool _isSupportedPgnResult(String? value) {
  return value == '1-0' || value == '0-1' || value == '1/2-1/2';
}

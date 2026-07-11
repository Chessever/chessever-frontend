import 'package:chessever2/repository/supabase/game/games.dart';

enum BracketGameResult {
  whiteWin,
  blackWin,
  draw,
  doubleForfeit,
  undecided;

  bool get isDecided => this != BracketGameResult.undecided;

  String get displayText => switch (this) {
    BracketGameResult.whiteWin => '1-0',
    BracketGameResult.blackWin => '0-1',
    BracketGameResult.draw => '½-½',
    BracketGameResult.doubleForfeit => '0-0',
    BracketGameResult.undecided => '',
  };
}

/// Parses the effective result shared by bracket scoring and leg presentation.
///
/// Lichess/FIDE forfeit encodings are valid decided results. Feeds can also
/// leave the row status at `*` after the PGN's Result tag is final, so the tag
/// is the fallback whenever status is blank or undecided.
BracketGameResult bracketGameResult(Games game) {
  var value = game.status?.trim() ?? '';
  if (value.isEmpty || value == '*') {
    final pgnResult = RegExp(
      r'\[Result\s+"([^"]+)"\]',
      caseSensitive: false,
    ).firstMatch(game.pgn ?? '');
    value = pgnResult?.group(1)?.trim() ?? value;
  }

  return switch (value.toUpperCase()) {
    '1-0' || 'W' || '+:-' => BracketGameResult.whiteWin,
    '0-1' || 'B' || '-:+' => BracketGameResult.blackWin,
    '1/2-1/2' ||
    '1/2' ||
    '½-½' ||
    '½' ||
    '0.5-0.5' ||
    'D' ||
    'DRAW' ||
    '=:=' => BracketGameResult.draw,
    '0-0' => BracketGameResult.doubleForfeit,
    _ => BracketGameResult.undecided,
  };
}

import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';

/// What a classified move means, whichever way it was classified: a game
/// report verdict (`$240`–`$247`), a hand-applied annotation, or a standard
/// PGN move glyph (`$1`–`$6`). Every classified move gets its own ElevenLabs
/// sound (which wins over the ordinary move sound) and a landing animation on
/// its destination square. Unclassified moves keep the board's usual sounds.
enum MoveClass {
  /// `!!` — $3, or the ChessEver brilliant verdict $240.
  brilliant,

  /// `!` — $1, or the ChessEver "Great" verdict $241.
  great,

  /// Engine's top move — $242.
  best,

  /// `!?` — $5. No report verdict maps here; only hand/PGN glyphs.
  interesting,

  /// `?!` — $6, or the ChessEver inaccuracy verdict $244.
  inaccuracy,

  /// `?` — $2, or the ChessEver mistake verdict $245.
  mistake,

  /// `??` — $4, or the ChessEver blunder verdict $246.
  blunder,

  /// A winning continuation was missed — $243.
  missedWin,

  /// Opening theory — $247.
  book,
}

extension MoveClassX on MoveClass {
  /// The glyph shown for hand/PGN annotations.
  String get glyph => switch (this) {
    MoveClass.brilliant => '!!',
    MoveClass.great => '!',
    MoveClass.best => '★',
    MoveClass.interesting => '!?',
    MoveClass.inaccuracy => '?!',
    MoveClass.mistake => '?',
    MoveClass.blunder => '??',
    MoveClass.missedWin => '✕',
    MoveClass.book => '≡',
  };

  /// True for verdicts that praise the move.
  bool get isPositive =>
      this == MoveClass.brilliant ||
      this == MoveClass.great ||
      this == MoveClass.best ||
      this == MoveClass.interesting;

  /// True for verdicts that criticise the move.
  bool get isNegative =>
      this == MoveClass.inaccuracy ||
      this == MoveClass.mistake ||
      this == MoveClass.blunder ||
      this == MoveClass.missedWin;
}

/// Report verdict → move class.
MoveClass moveClassFromClassification(GameMoveClassification c) => switch (c) {
  GameMoveClassification.brilliant => MoveClass.brilliant,
  GameMoveClassification.goodMove => MoveClass.great,
  GameMoveClassification.bestMove => MoveClass.best,
  GameMoveClassification.missedWin => MoveClass.missedWin,
  GameMoveClassification.inaccuracy => MoveClass.inaccuracy,
  GameMoveClassification.mistake => MoveClass.mistake,
  GameMoveClassification.blunder => MoveClass.blunder,
  GameMoveClassification.bookMove => MoveClass.book,
};

/// Standard PGN move-assessment glyph NAG ($1–$6) → move class.
MoveClass? moveClassFromGlyphNag(int nag) => switch (nag) {
  1 => MoveClass.great,
  2 => MoveClass.mistake,
  3 => MoveClass.brilliant,
  4 => MoveClass.blunder,
  5 => MoveClass.interesting,
  6 => MoveClass.inaccuracy,
  _ => null,
};

/// The move class a move's NAGs carry. A ChessEver verdict ($240–$247) wins
/// over a standard glyph, because it is what the board already badges.
MoveClass? moveClassFromNags(Iterable<int>? nags) {
  if (nags == null) return null;
  final verdict = classificationFromNags(nags);
  if (verdict != null) return moveClassFromClassification(verdict);
  for (final nag in nags) {
    final c = moveClassFromGlyphNag(nag);
    if (c != null) return c;
  }
  return null;
}

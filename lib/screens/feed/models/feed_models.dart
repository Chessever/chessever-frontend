import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';

/// Why a ply matters in Feed. Ordered roughly by how loud Feed reacts.
enum FeedMomentType {
  checkmate,
  brilliant,
  blunder,
  sacrifice,
  missedWin,
  mistake,
  promotion,
  check,
  capture,
  castle,
  inaccuracy,
  gameEnd,
}

@immutable
class FeedMoment {
  const FeedMoment({
    required this.type,
    required this.label,
    this.severity = 1,
  });

  final FeedMomentType type;

  /// Short on-board caption, e.g. "Brilliant", "Blunder", "Sacrifice".
  final String label;

  /// 1 (subtle) .. 3 (headline). Drives sound loudness and whether playback
  /// briefly lingers on the ply so the viewer can see it.
  final int severity;

  bool get isHeadline => severity >= 3;
}

/// One position in a Feed clip. Index 0 is the start position (no move).
@immutable
class FeedPly {
  const FeedPly({
    required this.fen,
    this.san,
    this.uci,
    this.cp,
    this.mate,
    this.moment,
    this.moveClass,
  });

  final String fen;

  /// Move that produced [fen]; null for the start position.
  final String? san;
  final String? uci;

  /// White-POV centipawns after the move, when known.
  final int? cp;
  final int? mate;
  final FeedMoment? moment;

  /// What the PGN itself called this move: a ChessEver report verdict
  /// (`$240`–`$247`) or a standard glyph NAG (`$1`–`$6`). Null when the PGN
  /// says nothing about it.
  final MoveClass? moveClass;

  /// The move's class for sound, badge and landing: the PGN's own verdict,
  /// else the judgement Feed read off the eval swing (same lichess table the
  /// board uses for broadcast games). Null for an ordinary move.
  MoveClass? get effectiveClass => moveClass ?? feedMomentClass(moment);
}

/// The move class a Feed moment stands for, when it is a verdict on the move.
/// Board events (check, capture, castle, mate, a sacrifice read off material)
/// are not verdicts and keep the board's ordinary sounds.
MoveClass? feedMomentClass(FeedMoment? moment) => switch (moment?.type) {
  FeedMomentType.brilliant => MoveClass.brilliant,
  FeedMomentType.blunder => MoveClass.blunder,
  FeedMomentType.mistake => MoveClass.mistake,
  FeedMomentType.inaccuracy => MoveClass.inaccuracy,
  FeedMomentType.missedWin => MoveClass.missedWin,
  _ => null,
};

/// What earns a game its one mark in the post header, beside the event and
/// the opening. Generic captions ("Brilliant finish", "Top board") are not
/// signals: the board says those itself.
enum FeedSignalKind {
  /// A player the viewer follows is at the board ([FeedSignal.name]).
  favorite,

  /// The winner is on a live winning run ([FeedSignal.name],
  /// [FeedSignal.count] wins).
  streak,

  /// A Gamebase miniature.
  miniature,

  /// One of today's most liked games ([FeedSignal.count] distinct likes).
  liked,

  /// The lower-rated player won by [FeedSignal.count] rating points.
  upset,
}

@immutable
class FeedSignal {
  const FeedSignal(this.kind, {this.name, this.count});

  final FeedSignalKind kind;

  /// The followed player or the streak holder, as the app displays names
  /// ("Fabiano Caruana").
  final String? name;

  /// Wins in the streak.
  final int? count;

  @override
  bool operator ==(Object other) =>
      other is FeedSignal &&
      other.kind == kind &&
      other.name == name &&
      other.count == count;

  @override
  int get hashCode => Object.hash(kind, name, count);
}

/// One game in the Feed, ready to play with no further fetch.
@immutable
class FeedItem {
  const FeedItem({
    required this.game,
    required this.plies,
    required this.reason,
    this.eventLabel,
    this.result,
    this.hasEvals = false,
    this.signal,
  });

  final GamesTourModel game;
  final List<FeedPly> plies;

  /// Why this game is in the feed: "Brilliant finish", "Today's miniature",
  /// "Because you follow Ding Liren". Kept for the cache and older readers;
  /// the post header shows [signal] instead.
  final String reason;
  final String? eventLabel;

  /// The one mark the post header carries, when the game earned one.
  final FeedSignal? signal;

  /// "1-0", "0-1", "½-½" or null while live.
  final String? result;

  /// True when per-ply evals are present, so the scrub bar can draw the
  /// report chart instead of a plain progress line.
  final bool hasEvals;

  int get plyCount => plies.length - 1;

  FeedItem copyWith({String? reason, FeedSignal? signal}) => FeedItem(
    game: game,
    plies: plies,
    reason: reason ?? this.reason,
    eventLabel: eventLabel,
    result: result,
    hasEvals: hasEvals,
    signal: signal ?? this.signal,
  );

  /// Plies Feed should linger on (headline moments).
  Iterable<int> get headlineIndexes sync* {
    for (var i = 0; i < plies.length; i++) {
      if (plies[i].moment?.isHeadline ?? false) yield i;
    }
  }
}

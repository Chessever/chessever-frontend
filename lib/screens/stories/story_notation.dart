import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart'
    show classificationFromNags, legacyClassificationFromComments;
import 'package:chessever2/screens/feed/logic/feed_pgn.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// The playable mainline and the PGN branches beside its moves. A branch is
/// replayed only when the reader opens it, including any branches of its own.
@immutable
class StoryNotation {
  StoryNotation(FeedPgnGame game, PgnNode<PgnNodeData>? root)
    : mainline = _mainline(game, root);

  final List<StoryNotationMove> mainline;

  static List<StoryNotationMove> _mainline(
    FeedPgnGame game,
    PgnNode<PgnNodeData>? node,
  ) {
    final moves = <StoryNotationMove>[];
    for (final move in game.moves) {
      final children = node?.children;
      moves.add(
        StoryNotationMove._(
          move,
          children == null || children.length <= 1
              ? const []
              : children.sublist(1),
          mainlineIndex: moves.length,
        ),
      );
      node = children == null || children.isEmpty ? null : children.first;
    }
    return List.unmodifiable(moves);
  }
}

@immutable
class StoryNotationMove {
  StoryNotationMove._(this.ply, this._branches, {this.mainlineIndex});

  final FeedPgnMove ply;
  final List<PgnChildNode<PgnNodeData>> _branches;
  final int? mainlineIndex;

  String get number => ply.mover == Side.white
      ? '${ply.before.fullmoves}.'
      : '${ply.before.fullmoves}…';

  late final List<StoryNotationVariation> variations = List.unmodifiable([
    for (final branch in _branches)
      if (_playableMove(ply.before, branch.data.san) case final move?)
        StoryNotationVariation._(branch, ply.before, move),
  ]);
}

@immutable
class StoryNotationVariation {
  const StoryNotationVariation._(this._root, this._before, this._firstMove);

  final PgnChildNode<PgnNodeData> _root;
  final Position _before;
  final Move _firstMove;

  String get san => _root.data.san;
  Move get firstMove => _firstMove;

  List<StoryNotationMove> readLine() {
    final moves = <StoryNotationMove>[];
    var node = _root;
    var before = _before;
    Move? move = _firstMove;
    List<PgnChildNode<PgnNodeData>> branches = const [];
    while (move != null) {
      final after = before.play(move);
      final data = node.data;
      final nags = data.nags ?? const <int>[];
      final comments = [...?data.startingComments, ...?data.comments];
      final recorded = parseFlowEval(comments);
      moves.add(
        StoryNotationMove._(
          FeedPgnMove(
            ply: moves.length + 1,
            before: before,
            after: after,
            move: move,
            san: data.san,
            uci: move.uci,
            cp: recorded.cp,
            mate: recorded.mate,
            nags: nags,
            comments: comments,
            classification:
                classificationFromNags(nags) ??
                legacyClassificationFromComments(comments),
          ),
          branches,
        ),
      );
      if (node.children.isEmpty) break;
      branches = node.children.length > 1 ? node.children.sublist(1) : const [];
      node = node.children.first;
      before = after;
      move = _playableMove(before, node.data.san);
    }
    return moves;
  }
}

Move? _playableMove(Position before, String san) {
  try {
    return before.parseSan(san);
  } catch (_) {
    return null;
  }
}

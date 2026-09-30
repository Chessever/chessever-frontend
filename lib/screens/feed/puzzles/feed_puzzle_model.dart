import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// One player of the game a puzzle was cut from. Only puzzles cached before
/// the Feed moved to ChessEver's puzzle service carry players; the service
/// does not send them.
@immutable
class FeedPuzzlePlayer {
  const FeedPuzzlePlayer({required this.name, this.rating, this.title});

  final String name;
  final int? rating;

  /// FIDE/Lichess title ("GM", "IM", "BOT"), when the account carries one.
  final String? title;

  Map<String, Object?> toJson() => {
    'name': name,
    if (rating != null) 'rating': rating,
    if (title != null) 'title': title,
  };

  static FeedPuzzlePlayer? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final rating = json['rating'];
    final title = json['title'];
    return FeedPuzzlePlayer(
      name: name,
      rating: rating is int ? rating : null,
      title: title is String && title.isNotEmpty ? title : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FeedPuzzlePlayer &&
      other.name == name &&
      other.rating == rating &&
      other.title == title;

  @override
  int get hashCode => Object.hash(name, rating, title);
}

/// A puzzle for the Feed, served by ChessEver's own puzzle service from
/// Lichess's CC0 puzzle database.
@immutable
class FeedPuzzle {
  const FeedPuzzle({
    required this.id,
    required this.fen,
    required this.solution,
    this.initialMoveUci,
    this.rating,
    this.themes = const [],
    this.gameUrl,
    this.sourceId,
    this.openingTags = const [],
    this.plays,
    this.perfName,
    this.white,
    this.black,
  });

  /// Stable id within the Feed (cache, finished list, page keys).
  final String id;

  /// Position BEFORE [initialMoveUci] (the opponent's move that sets up the
  /// puzzle); the solver plays [solution][0] after it.
  final String fen;
  final String? initialMoveUci;

  /// UCI moves alternating solver / opponent, starting with the solver.
  final List<String> solution;
  final int? rating;
  final List<String> themes;

  /// The source game on Lichess, at the puzzle's position. Kept with the
  /// puzzle as data only: the page never shows it or links to it (the
  /// puzzle database is CC0, so no credit is owed), and the app sends
  /// Lichess no request for puzzles.
  final String? gameUrl;

  /// The puzzle's id in Lichess's puzzle database, when the service knows it.
  final String? sourceId;

  /// Lichess opening tags ("Sicilian_Defense", then more specific ones).
  final List<String> openingTags;

  /// Fields below come only from puzzles cached before the puzzle service:
  /// how often it was played, "Blitz"/"Rapid" of the source game, players.
  final int? plays;
  final String? perfName;
  final FeedPuzzlePlayer? white;
  final FeedPuzzlePlayer? black;

  /// The side the viewer plays: the one to move once [initialMoveUci] has
  /// been played on [fen].
  Side get solver {
    final turn = Setup.parseFen(fen).turn;
    return initialMoveUci == null ? turn : turn.opposite;
  }

  /// Cache form (the app's own shape).
  Map<String, Object?> toJson() => {
    'id': id,
    'fen': fen,
    'solution': solution,
    if (initialMoveUci != null) 'initialMove': initialMoveUci,
    if (rating != null) 'rating': rating,
    'themes': themes,
    if (gameUrl != null) 'gameUrl': gameUrl,
    if (sourceId != null) 'sourceId': sourceId,
    if (openingTags.isNotEmpty) 'openings': openingTags,
    if (plays != null) 'plays': plays,
    if (perfName != null) 'perf': perfName,
    if (white != null) 'white': white!.toJson(),
    if (black != null) 'black': black!.toJson(),
  };

  /// Reads [toJson]'s shape back, including entries cached by earlier
  /// versions (a `daily` flag is ignored); null when the entry is unusable.
  static FeedPuzzle? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final fen = json['fen'];
    final solution = json['solution'];
    if (id is! String || id.isEmpty || fen is! String || solution is! List) {
      return null;
    }
    final moves = solution.whereType<String>().toList(growable: false);
    if (moves.isEmpty || moves.length != solution.length) return null;
    final initialMove = json['initialMove'];
    final rating = json['rating'];
    final gameUrl = json['gameUrl'];
    final sourceId = json['sourceId'];
    final plays = json['plays'];
    final perf = json['perf'];
    return FeedPuzzle(
      id: id,
      fen: fen,
      solution: moves,
      initialMoveUci: initialMove is String ? initialMove : null,
      rating: rating is int ? rating : null,
      themes: _strings(json['themes']),
      gameUrl: gameUrl is String ? gameUrl : null,
      sourceId: sourceId is String && sourceId.isNotEmpty ? sourceId : null,
      openingTags: _strings(json['openings']),
      plays: plays is int ? plays : null,
      perfName: perf is String ? perf : null,
      white: FeedPuzzlePlayer.fromJson(json['white']),
      black: FeedPuzzlePlayer.fromJson(json['black']),
    );
  }

  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  @override
  bool operator ==(Object other) =>
      other is FeedPuzzle &&
      other.id == id &&
      other.fen == fen &&
      other.initialMoveUci == initialMoveUci &&
      listEquals(other.solution, solution);

  @override
  int get hashCode =>
      Object.hash(id, fen, initialMoveUci, Object.hashAll(solution));

  @override
  String toString() => 'FeedPuzzle($id)';
}

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:dartchess/dartchess.dart';

/// Holds the analyses the explorer may read, keyed by profile id, and
/// answers the explorer's tree, position-games and game lookups for
/// `prep:<profileId>` ids from them.
abstract final class PrepLocalGamebase {
  static final Map<String, PrepAnalysis> _byProfile = {};
  static final Map<String, String> _finalFen = {};

  /// The explorer player id for a profile.
  static String playerIdFor(String profileId) => 'prep:$profileId';

  static void publish(PrepAnalysis analysis) {
    _byProfile[analysis.profileId] = analysis;
    _finalFen.removeWhere((key, _) => key.startsWith('prep:${analysis.profileId}:'));
    LocalPlayerOpeningTrees.resolver = _tree;
    GamebaseLocalGames.gameResolver = _game;
    GamebaseLocalGames.positionResolver = _positionGames;
  }

  static void forget(String profileId) {
    _byProfile.remove(profileId);
  }

  static PrepAnalysis? _analysisForPlayer(String playerId) {
    if (!playerId.startsWith('prep:')) return null;
    return _byProfile[playerId.substring(5)];
  }

  static PlayerOpeningTreeIndex? _tree(String playerId) =>
      _analysisForPlayer(playerId)?.tree;

  /// `prep:<profileId>:<index>`; profile ids never contain a colon.
  static (PrepAnalysis, int)? _resolveGame(String id) {
    final parts = id.split(':');
    if (parts.length != 3 || parts.first != 'prep') return null;
    final analysis = _byProfile[parts[1]];
    final index = int.tryParse(parts[2]);
    if (analysis == null || index == null) return null;
    if (index < 0 || index >= analysis.games.length) return null;
    return (analysis, index);
  }

  static GamebaseGameWithPgn? _game(String id) {
    final resolved = _resolveGame(id);
    if (resolved == null) return null;
    final (analysis, index) = resolved;
    final game = analysis.games[index];
    return GamebaseGameWithPgn(
      id: id,
      date: game.date ?? DateTime.fromMillisecondsSinceEpoch(0),
      result: switch (game.result) {
        '1-0' => GameResult.whiteWins,
        '0-1' => GameResult.blackWins,
        _ => GameResult.draw,
      },
      timeControl: _timeControl(game.speed),
      pgn: analysis.pgns[index],
      eco: game.eco,
      opening: game.opening,
      whiteName: game.white,
      blackName: game.black,
      whiteElo: game.whiteElo,
      blackElo: game.blackElo,
    );
  }

  static TimeControl _timeControl(PrepTimeControl? speed) =>
      switch (prepExplorerTimeControl(speed)) {
        'rapid' => TimeControl.rapid,
        'classical' => TimeControl.classical,
        _ => TimeControl.blitz,
      };

  static GamebaseSearchQueryResponse? _positionGames(
    GamebaseLocalPositionQuery query,
  ) {
    final analysis = _analysisForPlayer(query.playerId);
    if (analysis == null) return null;
    final key = query.fen.trim().split(RegExp(r'\s+')).take(4).join(' ');
    final hits = analysis.positions[key] ?? const <PrepPositionHit>[];
    final color = query.color?.toLowerCase();
    final tc = query.timeControl?.name;
    final uci = query.uci?.toLowerCase();
    final matching = <PrepGame>[];
    final seen = <int>{};
    for (final hit in hits) {
      if (uci != null && hit.uci != uci) continue;
      if (!seen.add(hit.game)) continue;
      final game = analysis.games[hit.game];
      if (color == 'white' && game.playerIsWhite != true) continue;
      if (color == 'black' && game.playerIsWhite != false) continue;
      if (tc != null && prepExplorerTimeControl(game.speed) != tc) continue;
      matching.add(game);
    }
    int compare(PrepGame a, PrepGame b) => switch (query.sortBy) {
      GamebaseSortField.whiteElo => (a.whiteElo ?? 0).compareTo(b.whiteElo ?? 0),
      GamebaseSortField.blackElo => (a.blackElo ?? 0).compareTo(b.blackElo ?? 0),
      GamebaseSortField.avgElo =>
        ((a.whiteElo ?? 0) + (a.blackElo ?? 0)).compareTo(
          (b.whiteElo ?? 0) + (b.blackElo ?? 0),
        ),
      GamebaseSortField.date => (a.date ?? DateTime(0)).compareTo(
        b.date ?? DateTime(0),
      ),
    };
    matching.sort(
      query.sortDirection == GamebaseSortDirection.asc
          ? compare
          : (a, b) => compare(b, a),
    );
    final start = query.pageNumber * query.pageSize;
    final page = matching.skip(start).take(query.pageSize);
    return GamebaseSearchQueryResponse(
      status: 'success',
      data: [for (final g in page) _row(analysis, g)],
      metadata: GamebasePaginationMetadata(
        pageNumber: query.pageNumber,
        pageSize: query.pageSize,
        totalCount: matching.length,
        hasMoreValue: start + query.pageSize < matching.length,
      ),
    );
  }

  static Map<String, dynamic> _row(PrepAnalysis analysis, PrepGame g) {
    final id = analysis.gameId(g.index);
    final (fen, lastMove) = _ending(id, analysis.pgns[g.index]);
    return {
      'id': id,
      'date': g.date?.toIso8601String(),
      'result': g.result,
      'timeControl': prepExplorerTimeControl(g.speed)?.toUpperCase(),
      'eco': g.eco,
      'opening': g.opening,
      'event': g.source.label,
      'white': g.white,
      'black': g.black,
      'whiteElo': g.whiteElo,
      'blackElo': g.blackElo,
      'fen': fen,
      'lastMove': lastMove,
    };
  }

  /// A game's final position and last move, worked out once per game.
  static (String?, String?) _ending(String id, String pgn) {
    final cached = _finalFen[id];
    if (cached != null) {
      final parts = cached.split('|');
      return (parts[0], parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null);
    }
    try {
      final game = PgnGame.parsePgn(pgn);
      Position position = Chess.initial;
      String? last;
      for (final node in game.moves.mainline()) {
        final move = position.parseSan(node.san);
        if (move == null) break;
        last = move.uci;
        position = position.play(move);
      }
      _finalFen[id] = '${position.fen}|${last ?? ''}';
      return (position.fen, last);
    } catch (_) {
      return (null, null);
    }
  }
}

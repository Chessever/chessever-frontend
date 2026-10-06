import 'dart:isolate';

import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart'
    show splitPrepPgn, prepGameKey;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// How deep the device-built opening tree reaches, as the server's does.
const int kPrepTreeMaxPly = 24;

/// The outcome of one game from the prepared player's chair.
enum PrepOutcome { win, draw, loss, unknown }

/// One downloaded game, light enough to keep thousands in memory. The full
/// PGN stays in [PrepAnalysis.pgns] at the same index.
@immutable
class PrepGame {
  const PrepGame({
    required this.index,
    required this.source,
    required this.white,
    required this.black,
    required this.result,
    required this.plies,
    this.whiteElo,
    this.blackElo,
    this.date,
    this.speed,
    this.timeControlText,
    this.eco,
    this.opening,
    this.url,
    this.playerIsWhite,
  });

  final int index;
  final PrepSource source;
  final String white;
  final String black;

  /// `1-0`, `0-1`, `1/2-1/2` or `*`.
  final String result;
  final int plies;
  final int? whiteElo;
  final int? blackElo;
  final DateTime? date;
  final PrepTimeControl? speed;
  final String? timeControlText;
  final String? eco;
  final String? opening;
  final String? url;

  /// Which side the prepared player had; null when neither name matched.
  final bool? playerIsWhite;

  String get opponent => playerIsWhite == false ? white : black;
  int? get opponentElo => playerIsWhite == false ? whiteElo : blackElo;
  int? get playerElo => playerIsWhite == false ? blackElo : whiteElo;

  PrepOutcome get outcome {
    final white = playerIsWhite;
    if (white == null) return PrepOutcome.unknown;
    return switch (result) {
      '1-0' => white ? PrepOutcome.win : PrepOutcome.loss,
      '0-1' => white ? PrepOutcome.loss : PrepOutcome.win,
      '1/2-1/2' => PrepOutcome.draw,
      _ => PrepOutcome.unknown,
    };
  }

  /// The family name of the opening, without its variation.
  String get openingFamily {
    final name = opening;
    if (name == null || name.isEmpty) return eco ?? 'Unknown opening';
    return name.split(RegExp(r'[:,]')).first.trim();
  }
}

/// A position a game passed through and the move it played there.
@immutable
class PrepPositionHit {
  const PrepPositionHit(this.game, this.uci);
  final int game;
  final String? uci;
}

/// Everything My Prep shows for a profile, computed once from its PGNs.
@immutable
class PrepAnalysis {
  const PrepAnalysis({
    required this.profileId,
    required this.games,
    required this.pgns,
    required this.tree,
    required this.positions,
  });

  final String profileId;

  /// Newest first.
  final List<PrepGame> games;
  final List<String> pgns;
  final PlayerOpeningTreeIndex tree;

  /// Opening-tree position (first four FEN fields) → games through it.
  final Map<String, List<PrepPositionHit>> positions;

  static PrepAnalysis empty(String profileId) => PrepAnalysis(
    profileId: profileId,
    games: const [],
    pgns: const [],
    tree: const PlayerOpeningTreeIndex.empty(),
    positions: const {},
  );

  String gameId(int index) => 'prep:$profileId:$index';
}

/// Inputs for one analysis run, all sendable to an isolate.
@immutable
class PrepAnalysisRequest {
  const PrepAnalysisRequest({
    required this.profileId,
    required this.aliases,
    required this.sources,
  });

  final String profileId;
  final Set<String> aliases;

  /// Each account's source and its stored PGN text.
  final List<(PrepSource, String)> sources;
}

Future<PrepAnalysis> analyzePrepGames(PrepAnalysisRequest request) =>
    Isolate.run(() => buildPrepAnalysis(request));

/// Parses every stored game and builds the stats, tree and position index.
/// Public for tests; call [analyzePrepGames] from UI code.
PrepAnalysis buildPrepAnalysis(PrepAnalysisRequest request) {
  final raw = <(PrepSource, String)>[];
  final seen = <String>{};
  for (final (source, text) in request.sources) {
    for (final pgn in splitPrepPgn(text)) {
      final key = prepGameKey(pgn);
      if (key != null && !seen.add(key)) continue;
      raw.add((source, pgn));
    }
  }

  final parsed = <({PrepGame game, String pgn, List<(String, String)> line})>[];
  for (final (source, pgn) in raw) {
    final game = _parse(source, pgn, request.aliases);
    if (game != null) parsed.add(game);
  }
  // Newest first; undated games last.
  parsed.sort((a, b) {
    final ad = a.game.date;
    final bd = b.game.date;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });

  final games = <PrepGame>[];
  final pgns = <String>[];
  final tree = _TreeBuilder(request.profileId);
  final positions = <String, List<PrepPositionHit>>{};
  for (var i = 0; i < parsed.length; i++) {
    final entry = parsed[i];
    final game = _withIndex(entry.game, i);
    games.add(game);
    pgns.add(entry.pgn);
    tree.add(game, entry.line, gameId: 'prep:${request.profileId}:$i');
    for (var ply = 0; ply < entry.line.length; ply++) {
      final (fenKey, uci) = entry.line[ply];
      (positions[fenKey] ??= <PrepPositionHit>[]).add(
        PrepPositionHit(i, uci.isEmpty ? null : uci),
      );
    }
  }

  return PrepAnalysis(
    profileId: request.profileId,
    games: List.unmodifiable(games),
    pgns: List.unmodifiable(pgns),
    tree: tree.build(),
    positions: Map.unmodifiable(positions),
  );
}

PrepGame _withIndex(PrepGame g, int index) => PrepGame(
  index: index,
  source: g.source,
  white: g.white,
  black: g.black,
  result: g.result,
  plies: g.plies,
  whiteElo: g.whiteElo,
  blackElo: g.blackElo,
  date: g.date,
  speed: g.speed,
  timeControlText: g.timeControlText,
  eco: g.eco,
  opening: g.opening,
  url: g.url,
  playerIsWhite: g.playerIsWhite,
);

/// One game's headers, its move count, and the opening line as
/// (position before the move, move) pairs, ending with the position after
/// the last tree ply paired with an empty move.
({PrepGame game, String pgn, List<(String, String)> line})? _parse(
  PrepSource source,
  String pgn,
  Set<String> aliases,
) {
  final PgnGame<PgnNodeData> game;
  try {
    game = PgnGame.parsePgn(pgn);
  } catch (_) {
    return null;
  }
  final h = game.headers;
  String? tag(String key) {
    final value = h[key]?.trim();
    return value == null || value.isEmpty || value == '?' ? null : value;
  }

  final variant = tag('Variant')?.toLowerCase();
  if (variant != null && variant != 'standard' && variant != 'chess') {
    return null;
  }
  final sans = [for (final node in game.moves.mainline()) node.san];
  if (sans.isEmpty) return null;

  final white = tag('White') ?? 'White';
  final black = tag('Black') ?? 'Black';
  final whiteKey = white.toLowerCase();
  final blackKey = black.toLowerCase();
  final bool? playerIsWhite = aliases.contains(whiteKey)
      ? true
      : aliases.contains(blackKey)
      ? false
      : null;

  final line = <(String, String)>[];
  final startFen = tag('FEN');
  if (startFen == null) {
    Position position = Chess.initial;
    for (var ply = 0; ply < sans.length && ply < kPrepTreeMaxPly; ply++) {
      final move = position.parseSan(sans[ply]);
      if (move == null) break;
      line.add((_fenKey(position.fen), _standardUci(position, move)));
      position = position.play(move);
    }
    if (line.length == sans.length || line.length == kPrepTreeMaxPly) {
      line.add((_fenKey(position.fen), ''));
    }
  }

  return (
    game: PrepGame(
      index: 0,
      source: source,
      white: white,
      black: black,
      result: tag('Result') ?? '*',
      plies: sans.length,
      whiteElo: int.tryParse(tag('WhiteElo') ?? ''),
      blackElo: int.tryParse(tag('BlackElo') ?? ''),
      date: _date(tag('UTCDate') ?? tag('Date') ?? tag('EndDate')),
      speed: prepSpeedOf(
        source: source,
        timeControl: tag('TimeControl'),
        timeClass: tag('TimeClass'),
        event: tag('Event'),
      ),
      timeControlText: tag('TimeControl'),
      eco: tag('ECO'),
      opening: tag('Opening') ?? _ecoUrlName(tag('ECOUrl')),
      url: tag('Link') ?? (tag('Site')?.startsWith('http') == true ? tag('Site') : null),
      playerIsWhite: playerIsWhite,
    ),
    pgn: pgn,
    line: line,
  );
}

/// Castling written king-to-destination, as the server's trees write it.
String _standardUci(Position position, Move move) {
  if (move is NormalMove) {
    final piece = position.board.pieceAt(move.from);
    if (piece?.role == Role.king) {
      final from = move.from.name;
      final to = move.to.name;
      final castle = switch ('$from$to') {
        'e1h1' => 'e1g1',
        'e1a1' => 'e1c1',
        'e8h8' => 'e8g8',
        'e8a8' => 'e8c8',
        _ => null,
      };
      if (castle != null) return castle;
    }
  }
  return move.uci;
}

String _fenKey(String fen) => fen.split(' ').take(4).join(' ');

DateTime? _date(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^(\d{4})\.(\d{2})\.(\d{2})').firstMatch(raw);
  if (m == null) return null;
  final year = int.parse(m.group(1)!);
  final month = int.tryParse(m.group(2)!) ?? 1;
  final day = int.tryParse(m.group(3)!) ?? 1;
  if (year < 1800) return null;
  return DateTime.utc(year, month.clamp(1, 12), day.clamp(1, 31));
}

/// Chess.com names the opening only in its ECOUrl slug.
String? _ecoUrlName(String? url) {
  final slug = url?.split('/').lastOrNull;
  if (slug == null || slug.isEmpty) return null;
  final words = slug.split('-');
  final cut = words.indexWhere((w) => RegExp(r'^\d').hasMatch(w));
  final name = (cut <= 0 ? words : words.sublist(0, cut)).join(' ');
  return name.isEmpty ? null : name;
}

/// The clock category of a game. Chess.com's own TimeClass is
/// authoritative; Lichess games use its estimated-duration bands.
PrepTimeControl? prepSpeedOf({
  required PrepSource source,
  String? timeControl,
  String? timeClass,
  String? event,
}) {
  switch (timeClass?.toLowerCase()) {
    case 'bullet':
      return PrepTimeControl.bullet;
    case 'blitz':
      return PrepTimeControl.blitz;
    case 'rapid':
      return PrepTimeControl.rapid;
    case 'daily':
      return PrepTimeControl.correspondence;
  }
  final tc = timeControl?.trim();
  if (tc == null || tc.isEmpty) return null;
  if (tc == '-' || tc.contains('/')) return PrepTimeControl.correspondence;
  final parts = tc.split('+');
  final base = int.tryParse(parts.first);
  if (base == null) return null;
  final inc = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final estimate = base + 40 * inc;
  if (source == PrepSource.lichess && estimate < 30) {
    return PrepTimeControl.ultrabullet;
  }
  if (estimate < 180) return PrepTimeControl.bullet;
  if (estimate < 480) return PrepTimeControl.blitz;
  if (estimate < 1500) return PrepTimeControl.rapid;
  return PrepTimeControl.classical;
}

/// The explorer's three clock filters, which fold the fast and slow ends in.
String? prepExplorerTimeControl(PrepTimeControl? speed) => switch (speed) {
  PrepTimeControl.ultrabullet ||
  PrepTimeControl.bullet ||
  PrepTimeControl.blitz => 'blitz',
  PrepTimeControl.rapid => 'rapid',
  PrepTimeControl.classical || PrepTimeControl.correspondence => 'classical',
  null => null,
};

class _MoveTally {
  int white = 0;
  int black = 0;
  int draws = 0;
  int total = 0;
  DateTime? lastPlayed;
  String? sampleGameId;
  int? child;
  final buckets = <String, List<int>>{}; // key → [total, white, black, draws]
}

class _TreeBuilder {
  _TreeBuilder(this.profileId);

  final String profileId;
  final _ids = <String, int>{};
  final _ply = <String, int>{};
  final _moves = <String, Map<String, _MoveTally>>{};

  int _node(String fenKey, int ply) {
    return _ids.putIfAbsent(fenKey, () {
      _ply[fenKey] = ply;
      return _ids.length;
    });
  }

  void add(PrepGame game, List<(String, String)> line, {required String gameId}) {
    final color = switch (game.playerIsWhite) {
      true => 'white',
      false => 'black',
      null => null,
    };
    final tc = prepExplorerTimeControl(game.speed);
    for (var ply = 0; ply < line.length; ply++) {
      final (fenKey, uci) = line[ply];
      _node(fenKey, ply);
      if (uci.isEmpty || ply + 1 >= line.length) continue;
      final childKey = line[ply + 1].$1;
      final child = _node(childKey, ply + 1);
      final tally = (_moves[fenKey] ??= {})[uci] ??= _MoveTally();
      tally.child = child;
      tally.total++;
      switch (game.result) {
        case '1-0':
          tally.white++;
        case '0-1':
          tally.black++;
        case '1/2-1/2':
          tally.draws++;
      }
      final date = game.date;
      if (date != null &&
          (tally.lastPlayed == null || date.isAfter(tally.lastPlayed!))) {
        tally.lastPlayed = date;
      }
      tally.sampleGameId ??= gameId;
      final bucket = tally.buckets['${color ?? ''}|${tc ?? ''}'] ??= [0, 0, 0, 0];
      bucket[0]++;
      switch (game.result) {
        case '1-0':
          bucket[1]++;
        case '0-1':
          bucket[2]++;
        case '1/2-1/2':
          bucket[3]++;
      }
    }
  }

  PlayerOpeningTreeIndex build() {
    final byId = <int, PlayerOpeningTreeNode>{};
    final byFen = <String, PlayerOpeningTreeNode>{};
    for (final entry in _ids.entries) {
      final moves = <PlayerOpeningTreeMove>[];
      for (final m in (_moves[entry.key] ?? const {}).entries) {
        final t = m.value;
        moves.add(
          PlayerOpeningTreeMove(
            uci: m.key,
            childNodeId: t.child ?? 0,
            white: t.white,
            black: t.black,
            draws: t.draws,
            total: t.total,
            lastPlayed: t.lastPlayed,
            sampleGameId: t.total == 1 ? t.sampleGameId : null,
            filterBuckets: [
              for (final b in t.buckets.entries)
                PlayerOpeningTreeFilterBucket.fromCompactTuple([
                  b.key.split('|')[0],
                  b.key.split('|')[1],
                  '1',
                  ...b.value,
                ])!,
            ],
          ),
        );
      }
      final node = PlayerOpeningTreeNode(
        id: entry.value,
        fenKey: entry.key,
        ply: _ply[entry.key] ?? 0,
        moves: List.unmodifiable(moves),
      );
      byId[node.id] = node;
      byFen[node.fenKey] = node;
    }
    return PlayerOpeningTreeIndex(
      treeId: 'prep:$profileId',
      playerId: 'prep:$profileId',
      maxPly: kPrepTreeMaxPly,
      rootNodeId: 0,
      generatedAt: DateTime.now(),
      nodesById: Map.unmodifiable(byId),
      nodesByFenKey: Map.unmodifiable(byFen),
    );
  }
}

// ------------------------------------------------------------------ stats

/// Wins, draws and losses for some slice of the games.
@immutable
class PrepTally {
  const PrepTally({this.wins = 0, this.draws = 0, this.losses = 0});

  final int wins;
  final int draws;
  final int losses;

  int get total => wins + draws + losses;

  /// Points per game, 0..1.
  double? get score => total == 0 ? null : (wins + draws / 2) / total;

  PrepTally operator +(PrepOutcome outcome) => switch (outcome) {
    PrepOutcome.win => PrepTally(wins: wins + 1, draws: draws, losses: losses),
    PrepOutcome.draw => PrepTally(wins: wins, draws: draws + 1, losses: losses),
    PrepOutcome.loss => PrepTally(wins: wins, draws: draws, losses: losses + 1),
    PrepOutcome.unknown => this,
  };
}

@immutable
class PrepOpeningLine {
  const PrepOpeningLine(this.name, this.eco, this.tally);
  final String name;
  final String? eco;
  final PrepTally tally;
}

@immutable
class PrepOpponentLine {
  const PrepOpponentLine(this.name, this.rating, this.tally);
  final String name;
  final int? rating;
  final PrepTally tally;
}

/// The Overview numbers for a filtered set of games.
@immutable
class PrepStats {
  const PrepStats({
    required this.games,
    required this.overall,
    required this.asWhite,
    required this.asBlack,
    required this.whiteOpenings,
    required this.blackOpenings,
    required this.opponents,
    required this.byYear,
    required this.lengths,
    this.peakRating,
    this.currentRating,
    this.performance,
    this.averageOpponent,
  });

  final int games;
  final PrepTally overall;
  final PrepTally asWhite;
  final PrepTally asBlack;
  final List<PrepOpeningLine> whiteOpenings;
  final List<PrepOpeningLine> blackOpenings;
  final List<PrepOpponentLine> opponents;
  final List<(int, PrepTally)> byYear;

  /// Games ending within each 20-move band: ≤20, 21–40, 41–60, 61–80, 80+.
  final List<int> lengths;
  final int? peakRating;
  final int? currentRating;
  final int? performance;
  final int? averageOpponent;

  static PrepStats of(Iterable<PrepGame> games) {
    var overall = const PrepTally();
    var white = const PrepTally();
    var black = const PrepTally();
    final whiteOpenings = <String, (String?, PrepTally)>{};
    final blackOpenings = <String, (String?, PrepTally)>{};
    final opponents = <String, (String, int?, PrepTally)>{};
    final years = <int, PrepTally>{};
    final lengths = List<int>.filled(5, 0);
    int? peak;
    int? current;
    var opponentSum = 0;
    var opponentCount = 0;
    var count = 0;
    for (final g in games) {
      count++;
      final outcome = g.outcome;
      overall += outcome;
      if (g.playerIsWhite == true) white += outcome;
      if (g.playerIsWhite == false) black += outcome;
      final table = g.playerIsWhite == false ? blackOpenings : whiteOpenings;
      if (g.playerIsWhite != null) {
        final name = g.openingFamily;
        final prior = table[name];
        table[name] = (prior?.$1 ?? g.eco, (prior?.$2 ?? const PrepTally()) + outcome);
        final opp = g.opponent;
        final key = opp.toLowerCase();
        final seen = opponents[key];
        opponents[key] = (
          seen?.$1 ?? opp,
          seen?.$2 ?? g.opponentElo,
          (seen?.$3 ?? const PrepTally()) + outcome,
        );
        final mine = g.playerElo;
        if (mine != null && mine > 0) {
          current ??= mine; // games are newest first
          if (peak == null || mine > peak) peak = mine;
        }
        final theirs = g.opponentElo;
        if (theirs != null && theirs > 0 && outcome != PrepOutcome.unknown) {
          opponentSum += theirs;
          opponentCount++;
        }
      }
      final year = g.date?.year;
      if (year != null) years[year] = (years[year] ?? const PrepTally()) + outcome;
      final moves = (g.plies + 1) ~/ 2;
      lengths[moves <= 20
          ? 0
          : moves <= 40
          ? 1
          : moves <= 60
          ? 2
          : moves <= 80
          ? 3
          : 4]++;
    }

    List<PrepOpeningLine> top(Map<String, (String?, PrepTally)> table) {
      final lines = [
        for (final e in table.entries) PrepOpeningLine(e.key, e.value.$1, e.value.$2),
      ]..sort((a, b) => b.tally.total.compareTo(a.tally.total));
      return lines.take(8).toList();
    }

    final average = opponentCount == 0 ? null : opponentSum / opponentCount;
    final decided = overall.total;
    final performance = average == null || decided == 0
        ? null
        : (average + 400 * (overall.wins - overall.losses) / decided).round();
    final opponentLines = [
      for (final o in opponents.values) PrepOpponentLine(o.$1, o.$2, o.$3),
    ]..sort((a, b) => b.tally.total.compareTo(a.tally.total));

    return PrepStats(
      games: count,
      overall: overall,
      asWhite: white,
      asBlack: black,
      whiteOpenings: top(whiteOpenings),
      blackOpenings: top(blackOpenings),
      opponents: opponentLines.take(8).toList(),
      byYear: [
        for (final y in years.keys.toList()..sort()) (y, years[y]!),
      ],
      lengths: lengths,
      peakRating: peak,
      currentRating: current,
      performance: performance,
      averageOpponent: average?.round(),
    );
  }
}

import 'package:chessever2/utils/pgn_clock_utils.dart';
import 'package:chessever2/utils/time_control_bonus.dart';
import 'package:dartchess/dartchess.dart';

/// Presentation-only selection for the Reports Missed Chance topic. The caller
/// must first bind the stored story to this exact PGN/result. Neither the story
/// nor normal report verdicts/annotations are changed.
///
/// An opportunity is the position BEFORE its missed move (one-based `ply`).
/// PGN %clk is the mover's remaining time AFTER that move, including increment.
/// At the opportunity's start the two clocks are therefore on plies ply-2 and
/// ply-1, not on the missed move or the final board. Their earned increments
/// already belong to the available thinking time; do not subtract/add them.
({bool include, int? ply}) missedChanceTopicSelection(
  Object? classification,
  String pgn, {
  String? timeControlText,
}) {
  final evidence = classification is Map ? classification['evidence'] : null;
  final candidates = <int>{};
  if (evidence is List) {
    for (final item in evidence) {
      if (item is Map && item['type'] == 'missed_chance') {
        final ply = item['fromPly'];
        if (ply is int && ply > 0) candidates.add(ply);
      }
    }
  }
  final fallback = candidates.firstOrNull;
  // Absent evidence is not evidence of a mutual time scramble.
  if (fallback == null) return (include: true, ply: null);

  try {
    final parsed = PgnGame.parseMultiGamePgn(pgn);
    if (parsed.length != 1) return (include: true, ply: fallback);
    final game = parsed.single;
    var position = PgnGame.startingPosition(game.headers);
    // The stored whole-game story supports complete standard-start games only.
    if (position.fen != Chess.initial.fen) {
      return (include: true, ply: fallback);
    }
    final moves = game.moves.mainline().toList(growable: false);
    final clocks = <Duration?>[];
    final scores = <int?>[null];
    for (final move in moves) {
      final legal = position.parseSan(move.san);
      if (legal == null) return (include: true, ply: fallback);
      position = position.play(legal);
      clocks.add(_clock(move.comments));
      scores.add(
        _score(move.comments, whiteToMove: position.turn == Side.white),
      );
    }

    // Older stored stories record ONLY the first miss. Recover later chances
    // from the existing evaluations using the story's same +3 -> <=+0.5 rule,
    // so filtering that first miss never discards an otherwise useful game.
    final result = classification is Map ? classification['result'] : null;
    final winner = result == '1-0'
        ? 1
        : result == '0-1'
        ? -1
        : 0;
    for (var ply = 2; ply <= moves.length; ply++) {
      final before = scores[ply - 1];
      final after = scores[ply];
      final side = ply.isOdd ? 1 : -1;
      if (side != winner &&
          before != null &&
          after != null &&
          before * side >= 300 &&
          after * side <= 50) {
        candidates.add(ply);
      }
    }

    // Reuse the broadcast's guarded secondary-period correction, but retain
    // the original subsecond precision for the exact ten-second boundary.
    final displays = [
      for (final clock in clocks)
        clock == null
            ? '-:--:--'
            : formatClockDisplayFromSeconds(clock.inSeconds),
    ];
    final adjusted = applySecondaryBonusToMoveClocks(
      displays,
      parseSecondaryTimePeriod(timeControlText),
    );
    bool low(int index) {
      if (index < 0 || index >= clocks.length) return false;
      final clock = clocks[index];
      final seconds = parsePgnClockToSeconds(adjusted[index]);
      return clock != null &&
          clock <= const Duration(seconds: 10) &&
          seconds != null &&
          seconds <= 10;
    }

    for (final ply in candidates.toList()..sort()) {
      // No stale/future sample fallback: either immediately preceding clock
      // missing/invalid makes the opportunity eligible, never excluded.
      if (ply > moves.length || !(low(ply - 3) && low(ply - 2))) {
        return (include: true, ply: ply);
      }
    }
    return (include: false, ply: null);
  } catch (_) {
    return (include: true, ply: fallback);
  }
}

final _clockTag = RegExp(r'\[%clk\b[^\]]*\]');
final _clockValue = RegExp(
  r'^\[%clk\s+(?:(\d{1,5}):)?(\d{1,5}):(\d{1,2})(?:\.(\d{1,6}))?\]$',
);

Duration? _clock(List<String>? comments) {
  final tags = [
    for (final comment in comments ?? <String>[])
      ..._clockTag.allMatches(comment),
  ];
  // Duplicate or malformed readings are unknown, not a reason to hide a game.
  if (tags.length != 1) return null;
  final match = _clockValue.firstMatch(tags.single.group(0)!);
  if (match == null) return null;
  final hours = int.parse(match.group(1) ?? '0');
  final minutes = int.tryParse(match.group(2)!);
  final seconds = int.parse(match.group(3)!);
  if (minutes == null ||
      (match.group(1) != null && minutes >= 60) ||
      seconds >= 60) {
    return null;
  }
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    microseconds: int.parse((match.group(4) ?? '').padRight(6, '0')),
  );
}

final _eval = RegExp(r'\[%eval ([^\]]+)\]');

int? _score(List<String>? comments, {required bool whiteToMove}) {
  String? raw;
  for (final comment in comments ?? <String>[]) {
    final match = _eval.firstMatch(comment);
    if (match != null) raw = match.group(1)?.trim();
  }
  if (raw == null) return null;
  if (raw.startsWith('#')) {
    final mate = int.tryParse(raw.substring(1));
    if (mate == null) return null;
    if (mate == 0) return whiteToMove ? -100000 : 100000;
    return mate > 0 ? 100000 : -100000;
  }
  final pawns = double.tryParse(raw);
  return pawns != null && pawns.isFinite ? (pawns * 100).round() : null;
}

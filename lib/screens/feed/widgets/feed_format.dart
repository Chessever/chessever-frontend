import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter/material.dart';

/// Pure formatting for the Feed player: labels, evals and colours derived from
/// a [FeedItem]. Kept free of widgets so the player, the scrub chart and the
/// tests all read the same numbers.

/// Lichess win-chance curve mapped to -1..1 from White's side.
double feedWinChance(int cp) => 2 / (1 + math.exp(-0.00368208 * cp)) - 1;

/// The eval that applies to ply [i]: its own when present, otherwise the
/// nearest earlier ply that carried one. Null when nothing before it did.
({int? cp, int? mate})? feedEvalAt(FeedItem item, int i) {
  if (item.plies.isEmpty) return null;
  for (var k = i.clamp(0, item.plies.length - 1); k >= 0; k--) {
    final p = item.plies[k];
    if (p.mate != null && p.mate != 0) return (cp: null, mate: p.mate);
    if (p.cp != null) return (cp: p.cp, mate: null);
  }
  return null;
}

bool feedIsMateAt(FeedItem item, int i) {
  if (i <= 0 || i >= item.plies.length) return false;
  final p = item.plies[i];
  return p.moment?.type == FeedMomentType.checkmate ||
      (p.san?.endsWith('#') ?? false);
}

/// White's share of the eval bar at ply [i] (0..1), or null when unknown.
double? feedWhiteShare(FeedItem item, int i) {
  if (feedIsMateAt(item, i)) {
    // The side that just moved delivered mate.
    return feedPlyIsWhite(item, i) ? 1 : 0;
  }
  final e = feedEvalAt(item, i);
  if (e == null) return null;
  final mate = e.mate;
  if (mate != null) return mate > 0 ? 1 : 0;
  return (1 + feedWinChance(e.cp!)) / 2;
}

/// "+0.4", "−1.2", "+M3", "#" or '' when the ply has no eval yet.
String feedEvalText(FeedItem item, int i) {
  if (feedIsMateAt(item, i)) return '#';
  final e = feedEvalAt(item, i);
  if (e == null) return '';
  final mate = e.mate;
  if (mate != null) return mate > 0 ? '+M$mate' : '−M${-mate}';
  final v = e.cp! / 100;
  return v >= 0
      ? '+${v.toStringAsFixed(1)}'
      : '−${v.abs().toStringAsFixed(1)}';
}

/// Side to move and fullmove number of the clip's start position.
({bool whiteFirst, int fullmove}) _startCounters(FeedItem item) {
  if (item.plies.isEmpty) return (whiteFirst: true, fullmove: 1);
  final parts = item.plies.first.fen.split(' ');
  final whiteFirst = parts.length < 2 || parts[1] != 'b';
  final fullmove = parts.length >= 6 ? int.tryParse(parts[5]) ?? 1 : 1;
  return (whiteFirst: whiteFirst, fullmove: math.max(1, fullmove));
}

/// Whether ply [i] (1-based) was White's move.
bool feedPlyIsWhite(FeedItem item, int i) {
  final start = _startCounters(item);
  final k = i - 1 + (start.whiteFirst ? 0 : 1);
  return k.isEven;
}

/// "Start", "15. Nf3" or "15... Nf6".
String feedMoveLabel(FeedItem item, int i) {
  if (i <= 0 || i >= item.plies.length) return 'Start';
  final start = _startCounters(item);
  final k = i - 1 + (start.whiteFirst ? 0 : 1);
  final number = start.fullmove + k ~/ 2;
  final san = item.plies[i].san ?? '';
  return k.isEven ? '$number. $san' : '$number... $san';
}

/// The move number shown before ply [i] in the notation strip: "15." before
/// White's move, "15..." before Black's when it [opensRun] (the first move
/// shown), otherwise null — the way a scoresheet reads.
String? feedMoveNumberLabel(FeedItem item, int i, {bool opensRun = false}) {
  if (i <= 0 || i >= item.plies.length) return null;
  final start = _startCounters(item);
  final k = i - 1 + (start.whiteFirst ? 0 : 1);
  final number = start.fullmove + k ~/ 2;
  if (k.isEven) return '$number.';
  return opensRun ? '$number...' : null;
}

/// "move 12 of 31".
String feedPlyText(FeedItem item, int i) {
  final total = math.max(1, (item.plyCount + 1) ~/ 2);
  final current = math.max(1, (math.max(i, 1) + 1) ~/ 2);
  return 'move ${math.min(current, total)} of $total';
}

/// Report-classification moments the info row and chart mark with a colour.
LichessMoveAnnotationType? feedJudgmentType(FeedMoment? moment) {
  return switch (moment?.type) {
    FeedMomentType.brilliant => LichessMoveAnnotationType.brilliant,
    FeedMomentType.blunder => LichessMoveAnnotationType.blunder,
    FeedMomentType.mistake => LichessMoveAnnotationType.mistake,
    FeedMomentType.inaccuracy => LichessMoveAnnotationType.inaccuracy,
    FeedMomentType.missedWin => LichessMoveAnnotationType.missedWin,
    _ => null,
  };
}

Color? feedJudgmentColor(FeedMoment? moment) {
  final type = feedJudgmentType(moment);
  return type == null ? null : moveAnnotationColor(type);
}

/// Only the three error classes get a dot on the report chart.
bool feedIsChartDot(FeedMoment? moment) => switch (moment?.type) {
  FeedMomentType.blunder ||
  FeedMomentType.mistake ||
  FeedMomentType.inaccuracy => true,
  _ => false,
};

/// "Carlsen, Magnus" → "Carlsen"; "Magnus Carlsen" → "Carlsen". A trailing
/// initial never stands for the name: "Gukesh D" → "Gukesh",
/// "Praggnanandhaa R." → "Praggnanandhaa".
String feedSurname(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  final comma = trimmed.indexOf(',');
  if (comma > 0) return trimmed.substring(0, comma).trim();
  final tokens = trimmed.split(RegExp(r'\s+'));
  // One letter ("D", "R.") or two capitals written as initials ("R.B.",
  // "RB"); a real two-letter surname ("So", "Li") is not one.
  bool initial(String t) {
    final letters = t.replaceAll('.', '');
    if (letters.length == 1) return true;
    return letters.length == 2 &&
        (t.contains('.') || letters == letters.toUpperCase());
  }

  for (var i = tokens.length - 1; i >= 0; i--) {
    if (!initial(tokens[i]) || i == 0) return tokens[i];
  }
  return tokens.last;
}

GameStatus feedResultStatus(FeedItem item) {
  final fromResult = GameStatus.fromString(item.result);
  if (fromResult.isFinished) return fromResult;
  return item.game.gameStatus;
}

/// "1–0", "0–1", "½–½" or '' while unknown.
String feedResultLabel(FeedItem item) {
  return switch (feedResultStatus(item)) {
    GameStatus.whiteWins => '1–0',
    GameStatus.blackWins => '0–1',
    GameStatus.draw => '½–½',
    _ => '',
  };
}

/// "Checkmate · Carlsen wins", "Carlsen wins", "Draw", or "Latest position"
/// for a game whose result is not in yet.
String feedResultDetail(FeedItem item) {
  final status = feedResultStatus(item);
  final mate = feedIsMateAt(item, item.plyCount);
  switch (status) {
    case GameStatus.whiteWins:
    case GameStatus.blackWins:
      final winner =
          status == GameStatus.whiteWins
              ? item.game.whitePlayer.name
              : item.game.blackPlayer.name;
      final wins = '${feedSurname(winner)} wins';
      return mate ? 'Checkmate · $wins' : wins;
    case GameStatus.draw:
      return 'Draw';
    case GameStatus.ongoing:
    case GameStatus.unknown:
      return 'Latest position';
  }
}

/// "C65 · Ruy Lopez: Berlin Defense", or '' when neither is known.
String feedOpeningLine(GamesTourModel game) {
  final eco = game.eco?.trim() ?? '';
  final name = game.openingName?.trim() ?? '';
  if (eco.isEmpty) return name;
  if (name.isEmpty) return eco;
  return '$eco · $name';
}

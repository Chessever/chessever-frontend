import 'package:chessever2/repository/supabase/tour/tour.dart';

/// Event-scoped team scoring, matching broadcasting `tours.info.teamScoring`
/// and Lichess `customScoring`.
///
/// Board points prefer per-game `customPoints` when the ingest stamped them.
/// These rules are the fallback for a decided board that has no stamp, and
/// they always supply match points (Lichess never published those).
class TeamScoringRules {
  final double whiteWin;
  final double blackWin;
  final double draw;
  final double loss;
  final int matchWin;
  final int matchDraw;
  final int matchLoss;

  const TeamScoringRules({
    required this.whiteWin,
    required this.blackWin,
    required this.draw,
    required this.loss,
    required this.matchWin,
    required this.matchDraw,
    required this.matchLoss,
  });

  static const standard = TeamScoringRules(
    whiteWin: 1,
    blackWin: 1,
    draw: 0.5,
    loss: 0,
    matchWin: 2,
    matchDraw: 1,
    matchLoss: 0,
  );

  factory TeamScoringRules.fromTourInfo(TourInfo? info) {
    if (info == null) return standard;
    final team = info.teamScoring;
    final game = _map(team?['gamePoints']);
    final match = _map(team?['matchPoints']);
    final whiteWin = _score(game?['whiteWin']);
    final blackWin = _score(game?['blackWin']);
    final draw = _score(game?['draw']);
    final loss = _score(game?['loss']);
    final matchWin = _score(match?['win']);
    final matchDraw = _score(match?['draw']);
    final matchLoss = _score(match?['loss']);
    if (whiteWin != null &&
        blackWin != null &&
        draw != null &&
        loss != null &&
        matchWin != null &&
        matchDraw != null &&
        matchLoss != null) {
      return TeamScoringRules(
        whiteWin: whiteWin,
        blackWin: blackWin,
        draw: draw,
        loss: loss,
        matchWin: matchWin.round(),
        matchDraw: matchDraw.round(),
        matchLoss: matchLoss.round(),
      );
    }

    final custom = info.customScoring;
    final white = _map(custom?['white']);
    final black = _map(custom?['black']);
    final customWhiteWin = _score(white?['win']);
    final customBlackWin = _score(black?['win']);
    final customDraw = _score(white?['draw']);
    if (customWhiteWin != null &&
        customBlackWin != null &&
        customDraw != null) {
      return TeamScoringRules(
        whiteWin: customWhiteWin,
        blackWin: customBlackWin,
        draw: customDraw,
        loss: 0,
        matchWin: standard.matchWin,
        matchDraw: standard.matchDraw,
        matchLoss: standard.matchLoss,
      );
    }
    return standard;
  }

  static Map<String, dynamic>? _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static double? _score(dynamic value) {
    if (value is num && value.isFinite && value >= 0) return value.toDouble();
    return null;
  }
}

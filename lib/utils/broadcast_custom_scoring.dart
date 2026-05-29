import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

String formatBroadcastScore(double score) {
  return score % 1 == 0 ? score.toInt().toString() : score.toStringAsFixed(1);
}

double? standardResultValueForSide(GameStatus status, {required bool isWhite}) {
  switch (status) {
    case GameStatus.whiteWins:
      return isWhite ? 1.0 : 0.0;
    case GameStatus.blackWins:
      return isWhite ? 0.0 : 1.0;
    case GameStatus.draw:
      return 0.5;
    case GameStatus.ongoing:
    case GameStatus.unknown:
      return null;
  }
}

String? standardResultLabelForSide(GameStatus status, {required bool isWhite}) {
  final value = standardResultValueForSide(status, isWhite: isWhite);
  if (value == null) return null;
  if (value == 0.5) return '½';
  return formatBroadcastScore(value);
}

String? customAwareResultLabelForSide(
  GameStatus status, {
  required bool isWhite,
  double? customPoints,
}) {
  final standardValue = standardResultValueForSide(status, isWhite: isWhite);
  if (standardValue == null) return null;

  if (customPoints != null &&
      customPoints != 0.0 &&
      customPoints != standardValue) {
    return formatBroadcastScore(customPoints);
  }

  return standardValue == 0.5 ? '½' : formatBroadcastScore(standardValue);
}

bool isArmageddonGame(GamesTourModel game) {
  return _containsArmageddon(game.roundSlug) ||
      _containsArmageddon(game.roundId) ||
      _containsArmageddon(game.tourSlug);
}

bool _containsArmageddon(String? value) {
  return value?.toLowerCase().contains('armageddon') ?? false;
}

String? boardResultLabelForSide(GamesTourModel game, {required bool isWhite}) {
  if (isArmageddonGame(game)) {
    return standardResultLabelForSide(game.gameStatus, isWhite: isWhite);
  }

  return customAwareResultLabelForSide(
    game.gameStatus,
    isWhite: isWhite,
    customPoints:
        isWhite ? game.whitePlayer.customPoints : game.blackPlayer.customPoints,
  );
}

({double? score, int played}) resolveBroadcastStandingScore({
  required double? sourceScore,
  required int sourcePlayed,
  required double calculatedScore,
  required int calculatedPlayed,
  bool preserveSourceScore = true,
}) {
  if (preserveSourceScore && sourceScore != null) {
    return (
      score: sourceScore,
      played: sourcePlayed > calculatedPlayed ? sourcePlayed : calculatedPlayed,
    );
  }

  return (score: calculatedScore, played: calculatedPlayed);
}

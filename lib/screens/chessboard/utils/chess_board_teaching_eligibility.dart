import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

bool shouldShowChessBoardTeachingsForGame(GamesTourModel game) {
  switch (game.source) {
    case GameSource.supabase:
    case GameSource.gamebase:
    case GameSource.twic:
    case GameSource.savedAnalysis:
      return true;
    case GameSource.openingExplorer:
    case GameSource.boardEditor:
    case GameSource.localAnalysis:
      return false;
  }
}

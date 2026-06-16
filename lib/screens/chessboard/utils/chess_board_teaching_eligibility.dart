import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';

bool shouldShowChessBoardTeachingsForGame(
  GamesTourModel game, {
  DateTime? now,
}) {
  if (game.source != GameSource.supabase) return false;
  return GameFilterHelper.isLiveNow(game, now: now);
}

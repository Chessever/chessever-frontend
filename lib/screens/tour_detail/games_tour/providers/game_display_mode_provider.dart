import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Survives recreations of `gamesTourScreenProvider` and `gamesAppBarProvider`,
// so toggling Focus on live games / Show all games sticks across tab swipes
// and category dropdown changes (both of which republish tourDetailScreenProvider
// and tear down the screen notifier).
final gameDisplayModeProvider = StateProvider<GameDisplayMode>(
  (ref) => GameDisplayMode.all,
);

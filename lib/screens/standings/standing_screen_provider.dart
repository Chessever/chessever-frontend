import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Provider for the standings state
final standingScreenProvider =
    StateNotifierProvider<StandingScreenNotifier, List<PlayerStandingModel>>((
      ref,
    ) {
      final roundId = ref.watch(gamesAppBarProvider).value?.selectedId;
      final aboutTourModel =
          ref.watch(tourDetailScreenProvider).value!.aboutTourModel;
      return StandingScreenNotifier(
        ref: ref,
        tourId: aboutTourModel.id,
        roundId: roundId,
      );
    });

class StandingScreenNotifier extends StateNotifier<List<PlayerStandingModel>> {
  StandingScreenNotifier({
    required this.ref,
    required this.tourId,
    required this.roundId,
  }) : super([]) {
    // Initialize with test data
    loadTestData();
  }

  final Ref ref;
  final String tourId;
  final String? roundId;

  Future<void> loadTestData() async {
    final allGames = await ref.read(gamesLocalStorage).getGames(tourId);

    print("All Games:");
    for (final game in allGames) {
      print('''
  ▶ Game ID: ${game.id}
  ▶ Round ID: ${game.roundId}
  ▶ fen: ${game.fen}
  
  ''');
    }

    final selectedGames =
        roundId != null
            ? allGames.where((e) => e.roundId.contains(roundId!)).toList()
            : allGames;

    var players = <Player>[];

    for (var a = 0; a < selectedGames.length; a++) {
      if (selectedGames[a].players != null) {
        for (var b = 0; b < selectedGames[a].players!.length; b++) {
          players.add(selectedGames[a].players![b]);
        }
      }
    }

    players = players.toSet().toList();

    players.sort((a, b) {
      final aRating = a.rating ?? 0; // Handle null ratings
      final bRating = b.rating ?? 0;

      return bRating.compareTo(aRating); // Descending order (highest first)
    });

    state = players.map((e) => PlayerStandingModel.fromPlayer(e)).toList();
  }
}

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../controllers/tournament_controller.dart';

part 'tournament_provider.g.dart';

@riverpod
class TournamentNotifier extends _$TournamentNotifier {
  @override
  Future<Map<String, List<Map<String, dynamic>>>> build() async {
    // Initial data load
    final controller = ref.read(tournamentControllerProvider);
    await controller.fetchTournaments();

    return {
      'live': controller.getLiveTournaments(),
      'completed': controller.getCompletedTournaments(),
      'upcoming': controller.getUpcomingTournaments(),
    };
  }

  // Get filtered tournaments based on search query and tab selection
  List<Map<String, dynamic>> getFilteredTournaments(
    String query,
    bool upcomingOnly,
  ) {
    final controller = ref.read(tournamentControllerProvider);
    return controller.searchTournaments(query, upcomingOnly);
  }
}

@riverpod
TournamentController tournamentController(TournamentControllerRef ref) {
  return TournamentController();
}

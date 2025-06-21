import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../services/favorites_service.dart';

part 'tournament_favorites_provider.g.dart';

// Model class for a tournament
class Tournament {
  final String title;
  final String dates;
  final String location;
  final int playerCount;
  final int elo;
  final bool isFavorite;

  Tournament({
    required this.title,
    required this.dates,
    required this.location,
    required this.playerCount,
    required this.elo,
    this.isFavorite = false,
  });

  Tournament copyWith({
    String? title,
    String? dates,
    String? location,
    int? playerCount,
    int? elo,
    bool? isFavorite,
  }) {
    return Tournament(
      title: title ?? this.title,
      dates: dates ?? this.dates,
      location: location ?? this.location,
      playerCount: playerCount ?? this.playerCount,
      elo: elo ?? this.elo,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

@riverpod
class TournamentFavoritesNotifier extends _$TournamentFavoritesNotifier {
  @override
  Future<List<Tournament>> build() async {
    // Initialize and load starred_repository tournaments when provider is created
    final favoriteTournaments =
        await FavoritesService.getAllFavoriteTournaments();

    return favoriteTournaments
        .map(
          (tournament) => Tournament(
            title: tournament['title'],
            dates: tournament['dates'],
            location: tournament['location'],
            playerCount: tournament['playerCount'],
            elo: tournament['elo'],
            isFavorite: true,
          ),
        )
        .toList();
  }

  // Check if a tournament is in favorites
  Future<bool> isFavorite(String title) async {
    final state = await future;
    return state.any((tournament) => tournament.title == title);
  }

  // Toggle tournament starred_repository status
  Future<void> toggleFavorite(Tournament tournament) async {
    final currentState = await future;

    // Check if tournament is already in favorites
    final isFavorite = currentState.any((t) => t.title == tournament.title);

    // Create new state with updated starred_repository status (optimistic update)
    final updatedState = currentState.toList();

    if (isFavorite) {
      // Remove from favorites
      updatedState.removeWhere((t) => t.title == tournament.title);
    } else {
      // Add to favorites
      updatedState.add(tournament.copyWith(isFavorite: true));
    }

    // Update state immediately (optimistic update)
    state = AsyncData(updatedState);

    // Then update backend service
    await FavoritesService.toggleTournamentFavorite(
      tournament.title,
      tournament.dates,
      tournament.location,
      tournament.playerCount,
      tournament.elo,
    );
  }
}

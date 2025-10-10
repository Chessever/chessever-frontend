import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// Represents a tournament group with its games
class TournamentGamesGroup {
  final String tourId;
  final String tourName;
  final String tourSlug;
  final String? tourImage;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<GamesTourModel> games;

  TournamentGamesGroup({
    required this.tourId,
    required this.tourName,
    required this.tourSlug,
    this.tourImage,
    this.startDate,
    this.endDate,
    required this.games,
  });

  TournamentGamesGroup copyWith({
    String? tourId,
    String? tourName,
    String? tourSlug,
    String? tourImage,
    DateTime? startDate,
    DateTime? endDate,
    List<GamesTourModel>? games,
  }) {
    return TournamentGamesGroup(
      tourId: tourId ?? this.tourId,
      tourName: tourName ?? this.tourName,
      tourSlug: tourSlug ?? this.tourSlug,
      tourImage: tourImage ?? this.tourImage,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      games: games ?? this.games,
    );
  }
}

/// State for player games screen
class PlayerGamesState {
  final List<TournamentGamesGroup> tournamentGroups;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;

  const PlayerGamesState({
    this.tournamentGroups = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 0,
    this.error,
  });

  PlayerGamesState copyWith({
    List<TournamentGamesGroup>? tournamentGroups,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) {
    return PlayerGamesState(
      tournamentGroups: tournamentGroups ?? this.tournamentGroups,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
    );
  }

  /// Get total games count across all tournaments
  int get totalGamesCount {
    return tournamentGroups.fold(0, (sum, group) => sum + group.games.length);
  }
}

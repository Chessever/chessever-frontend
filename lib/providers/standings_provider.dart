import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/player_standing.dart';

class StandingsNotifier extends StateNotifier<List<PlayerStanding>> {
  StandingsNotifier() : super([]) {
    // Initialize with test data
    loadTestData();
  }

  void loadTestData() {
    // This is for testing purposes only - in a real app, you would fetch from an API
    state = [
      const PlayerStanding(
        countryCode: 'NO',
        title: 'GM',
        name: 'Magnus, Carlsen',
        score: 2837,
        scoreChange: 4,
        matchScore: '2.5/3',
      ),
      const PlayerStanding(
        countryCode: 'US',
        title: 'GM',
        name: 'Hikaru, Nakamura',
        score: 2748,
        scoreChange: 6,
        matchScore: '2.5/3',
      ),
      const PlayerStanding(
        countryCode: 'CN',
        title: 'GM',
        name: 'Ding, Liren',
        score: 2791,
        scoreChange: 2,
        matchScore: '2/3',
      ),
      const PlayerStanding(
        countryCode: 'RU',
        title: 'GM',
        name: 'Ian, Nepomniachtchi',
        score: 2782,
        scoreChange: 3,
        matchScore: '2/3',
      ),
      const PlayerStanding(
        countryCode: 'US',
        title: 'GM',
        name: 'Fabiano, Caruana',
        score: 2776,
        scoreChange: 3,
        matchScore: '2/3',
      ),
      const PlayerStanding(
        countryCode: 'RU',
        title: 'GM',
        name: 'Esipenko, Andrey',
        score: 2712,
        scoreChange: 5,
        matchScore: '1.5/3',
      ),
      const PlayerStanding(
        countryCode: 'NL',
        title: 'GM',
        name: 'Anish, Giri',
        score: 2764,
        scoreChange: 7,
        matchScore: '1.5/3',
      ),
      const PlayerStanding(
        countryCode: 'US',
        title: 'GM',
        name: 'Wesley, So',
        score: 2761,
        scoreChange: 0,
        matchScore: '1.5/3',
      ),
      const PlayerStanding(
        countryCode: 'IR',
        title: 'GM',
        name: 'Firouzja, Alireza',
        score: 2755,
        scoreChange: 6,
        matchScore: '1.5/3',
      ),
    ];
  }

  // Method to load standings data for a specific round
  Future<void> loadStandingsForRound(int round) async {
    // In a real app, you would fetch data from an API here
    // For now, we'll just simulate a delay
    await Future.delayed(const Duration(milliseconds: 500));

    // For testing, we'll just reload the same data
    loadTestData();

    // In a real implementation, you might adjust the data based on the round
    // Example: Fetch from API with round parameter
    // final response = await apiService.fetchStandingsForRound(round);
    // state = response.map((data) => PlayerStanding.fromJson(data)).toList();
  }
}

// Provider for the standings state
final standingsProvider =
    StateNotifierProvider<StandingsNotifier, List<PlayerStanding>>((ref) {
      return StandingsNotifier();
    });

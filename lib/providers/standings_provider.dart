import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

//todo: Create a View_model

@immutable
class PlayerStanding {
  final String countryCode;
  final String? title;
  final String name;
  final int score;
  final int scoreChange;
  final String matchScore;

  const PlayerStanding({
    required this.countryCode,
    this.title,
    required this.name,
    required this.score,
    required this.scoreChange,
    required this.matchScore,
  });

  // Copy with method to create a new instance with some changes
  PlayerStanding copyWith({
    String? countryCode,
    String? title,
    String? name,
    int? score,
    int? scoreChange,
    String? matchScore,
  }) {
    return PlayerStanding(
      countryCode: countryCode ?? this.countryCode,
      title: title ?? this.title,
      name: name ?? this.name,
      score: score ?? this.score,
      scoreChange: scoreChange ?? this.scoreChange,
      matchScore: matchScore ?? this.matchScore,
    );
  }

  // Factory method to create a PlayerStanding object from JSON
  factory PlayerStanding.fromJson(Map<String, dynamic> json) {
    return PlayerStanding(
      countryCode: json['countryCode'] as String,
      title: json['title'] as String?,
      name: json['name'] as String,
      score: json['score'] as int,
      scoreChange: json['scoreChange'] as int,
      matchScore: json['matchScore'] as String,
    );
  }

  // Method to convert PlayerStanding object to JSON
  Map<String, dynamic> toJson() {
    return {
      'countryCode': countryCode,
      'title': title,
      'name': name,
      'score': score,
      'scoreChange': scoreChange,
      'matchScore': matchScore,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlayerStanding &&
        other.countryCode == countryCode &&
        other.title == title &&
        other.name == name &&
        other.score == score &&
        other.scoreChange == scoreChange &&
        other.matchScore == matchScore;
  }

  @override
  int get hashCode {
    return Object.hash(
      countryCode,
      title,
      name,
      score,
      scoreChange,
      matchScore,
    );
  }
}

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

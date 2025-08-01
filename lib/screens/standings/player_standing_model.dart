import 'package:chessever2/repository/supabase/game/games.dart';

class PlayerStandingModel {
  final String countryCode;
  final String? title;
  final String name;
  final int score;
  final int scoreChange;
  final String matchScore;

  const PlayerStandingModel({
    required this.countryCode,
    this.title,
    required this.name,
    required this.score,
    required this.scoreChange,
    required this.matchScore,
  });

  factory PlayerStandingModel.fromPlayer(Player player) {
    return PlayerStandingModel(
      countryCode: player.fed,
      name: player.name,
      score: player.rating,
      scoreChange: 0,
      matchScore: '0',
    );
  }

  // Copy with method to create a new instance with some changes
  PlayerStandingModel copyWith({
    String? countryCode,
    String? title,
    String? name,
    int? score,
    int? scoreChange,
    String? matchScore,
  }) {
    return PlayerStandingModel(
      countryCode: countryCode ?? this.countryCode,
      title: title ?? this.title,
      name: name ?? this.name,
      score: score ?? this.score,
      scoreChange: scoreChange ?? this.scoreChange,
      matchScore: matchScore ?? this.matchScore,
    );
  }

  // Factory method to create a PlayerStanding object from JSON
  factory PlayerStandingModel.fromJson(Map<String, dynamic> json) {
    return PlayerStandingModel(
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
    return other is PlayerStandingModel &&
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

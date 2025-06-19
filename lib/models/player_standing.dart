import 'package:flutter/foundation.dart';

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

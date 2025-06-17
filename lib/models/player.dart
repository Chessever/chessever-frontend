import 'package:flutter/foundation.dart';

@immutable
class Player {
  final String id;
  final String name;
  final String countryCode;
  final int elo;
  final int age;
  final bool isFavorite;

  // Optional fields that could be added in the future
  final String? title; // GM, IM, FM, etc.
  final String? profileImageUrl;

  const Player({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.elo,
    required this.age,
    this.isFavorite = false,
    this.title,
    this.profileImageUrl,
  });

  // Copy with method to create a new instance with some changes
  Player copyWith({
    String? id,
    String? name,
    String? countryCode,
    int? elo,
    int? age,
    bool? isFavorite,
    String? title,
    String? profileImageUrl,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      countryCode: countryCode ?? this.countryCode,
      elo: elo ?? this.elo,
      age: age ?? this.age,
      isFavorite: isFavorite ?? this.isFavorite,
      title: title ?? this.title,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }

  // Factory method to create a Player object from JSON
  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      countryCode: json['countryCode'] as String,
      elo: json['elo'] as int,
      age: json['age'] as int,
      isFavorite: json['isFavorite'] as bool? ?? false,
      title: json['title'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
    );
  }

  // Method to convert Player object to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'countryCode': countryCode,
      'elo': elo,
      'age': age,
      'isFavorite': isFavorite,
      if (title != null) 'title': title,
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
    };
  }

  // For debugging
  @override
  String toString() {
    return 'Player{id: $id, name: $name, countryCode: $countryCode, elo: $elo, age: $age, isFavorite: $isFavorite}';
  }

  // Equality
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Player &&
        other.id == id &&
        other.name == name &&
        other.countryCode == countryCode &&
        other.elo == elo &&
        other.age == age &&
        other.isFavorite == isFavorite &&
        other.title == title &&
        other.profileImageUrl == profileImageUrl;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      countryCode,
      elo,
      age,
      isFavorite,
      title,
      profileImageUrl,
    );
  }
}

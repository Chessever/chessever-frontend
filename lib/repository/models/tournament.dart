import 'package:flutter/foundation.dart';

@immutable
class Clock {
  final int limit;
  final int increment;

  const Clock({required this.limit, required this.increment});

  factory Clock.fromJson(Map<String, dynamic> json) {
    return Clock(
      limit: (json['limit'] as int?) ?? 0,
      increment: (json['increment'] as int?) ?? 0,
    );
  }
}

@immutable
class Variant {
  final String key;
  final String name;
  final String short;

  const Variant({required this.key, required this.name, required this.short});

  factory Variant.fromJson(Map<String, dynamic> json) {
    return Variant(
      key: (json['key'] as String?) ?? 'unknown',
      name: (json['name'] as String?) ?? 'Unknown',
      short: (json['short'] as String?) ?? '?',
    );
  }
}

@immutable
class Perf {
  final String key;
  final String name;

  const Perf({required this.key, required this.name});

  factory Perf.fromJson(Map<String, dynamic> json) {
    return Perf(
      key: (json['key'] as String?) ?? 'unknown',
      name: (json['name'] as String?) ?? 'Unknown',
    );
  }
}

@immutable
class Tournament {
  final String id;
  final String name;
  final String slug;
  final List<Round> rounds;

  final List<String> players = const [
    'player1',
    'player2',
    'player3',
    'player4',
    'player5',
  ];
  final String description = 'description of tournaments';
  final String imageUrl =
      'https://t3.ftcdn.net/jpg/13/67/90/12/360_F_1367901267_J9ZdpJ6ZpJ2d0rLJSfP0q8qEsWvVdUq7.jpg';

  const Tournament({
    required this.id,
    required this.name,
    required this.slug,
    required this.rounds,
  });

  factory Tournament.fromJson(Map<String, dynamic> json) {
    final tour = json['tour'] as Map<String, dynamic>;

    // Parse rounds (if missing or null, fall back to empty list)
    final roundsJson = json['rounds'] as List<dynamic>? ?? [];
    final rounds =
        roundsJson
            .map((r) => Round.fromJson(r as Map<String, dynamic>))
            .toList();

    return Tournament(
      id: tour['id'] as String,
      name: tour['name'] as String,
      slug: tour['slug'] as String,
      rounds: rounds,
    );
  }

  @override
  String toString() => 'Tournament($id, $name, rounds: ${rounds.length})';
}

@immutable
class Round {
  final String id;
  final String slug;

  const Round({required this.id, required this.slug});

  factory Round.fromJson(Map<String, dynamic> json) {
    return Round(id: json['id'] as String, slug: json['slug'] as String);
  }

  @override
  String toString() => 'Round($id, $slug)';

  static String _parseArenaStatus(int status) {
    switch (status) {
      case 10:
        return 'created';
      case 20:
        return 'started';
      case 30:
        return 'finished';
      default:
        return 'unknown ($status)';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tournament && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

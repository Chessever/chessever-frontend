import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'memorial_player.dart';
import 'memorial_player_local_search.dart';

const _aboutAsset = 'assets/data/memorial-player-about.json';

Future<Map<String, MemorialPlayerAbout>>? _aboutFuture;

class MemorialPlayerAchievement {
  const MemorialPlayerAchievement({required this.year, required this.label});

  final String year;
  final String label;

  factory MemorialPlayerAchievement.fromJson(Map<String, dynamic> json) {
    return MemorialPlayerAchievement(
      year: json['year']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
    );
  }
}

class MemorialPlayerAbout {
  const MemorialPlayerAbout({
    this.birthPlace,
    this.deathPlace,
    this.summary = const [],
    this.achievements = const [],
  });

  final String? birthPlace;
  final String? deathPlace;
  final List<String> summary;
  final List<MemorialPlayerAchievement> achievements;

  factory MemorialPlayerAbout.fromJson(Map<String, dynamic> json) {
    return MemorialPlayerAbout(
      birthPlace: _nonEmpty(json['birthPlace']),
      deathPlace: _nonEmpty(json['deathPlace']),
      summary: (json['summary'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      achievements: (json['achievements'] as List<dynamic>? ??
              const <dynamic>[])
          .map(
            (value) => MemorialPlayerAchievement.fromJson(
              Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
            ),
          )
          .where(
            (achievement) =>
                achievement.year.isNotEmpty && achievement.label.isNotEmpty,
          )
          .toList(growable: false),
    );
  }
}

class MemorialPlayerOverview {
  const MemorialPlayerOverview({required this.player, this.about});

  final MemorialPlayer player;
  final MemorialPlayerAbout? about;
}

Future<MemorialPlayerOverview?> loadBundledMemorialPlayerOverview(
  String sourceIdentity,
) async {
  final player = await findBundledMemorialPlayerBySourceIdentity(
    sourceIdentity,
  );
  if (player == null) return null;
  final aboutByRoute = await (_aboutFuture ??= _loadAbout());
  return MemorialPlayerOverview(
    player: player,
    about: aboutByRoute[player.routeId],
  );
}

Future<Map<String, MemorialPlayerAbout>> _loadAbout() async {
  try {
    final source = await rootBundle.loadString(_aboutAsset);
    final decoded = await compute(_decodeAbout, source);
    return Map<String, MemorialPlayerAbout>.unmodifiable(
      decoded.map(
        (routeId, value) =>
            MapEntry(routeId, MemorialPlayerAbout.fromJson(value)),
      ),
    );
  } catch (error) {
    debugPrint('[Memorial about] Bundled biographies unavailable: $error');
    return const <String, MemorialPlayerAbout>{};
  }
}

Map<String, Map<String, dynamic>> _decodeAbout(String source) {
  final rows = jsonDecode(source) as List<dynamic>;
  return <String, Map<String, dynamic>>{
    for (final raw in rows)
      if ((raw as Map<dynamic, dynamic>)['routeId']?.toString().isNotEmpty ==
          true)
        raw['routeId'].toString(): Map<String, dynamic>.from(
          raw['about'] as Map<dynamic, dynamic>? ?? const {},
        ),
  };
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

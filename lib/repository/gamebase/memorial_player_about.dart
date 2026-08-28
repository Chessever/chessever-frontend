import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'memorial_player.dart';
import 'memorial_player_local_search.dart';

const _aboutAsset = 'assets/data/memorial-player-about.json';
const _historyAsset = 'assets/data/memorial-player-history.json';

Future<Map<String, MemorialPlayerAbout>>? _aboutFuture;
Future<Map<String, MemorialPlayerHistory>>? _historyFuture;

class MemorialPlayerSource {
  const MemorialPlayerSource({required this.label, required this.url});

  final String label;
  final String url;

  factory MemorialPlayerSource.fromJson(Map<String, dynamic> json) {
    return MemorialPlayerSource(
      label: json['label']?.toString().trim() ?? '',
      url: json['url']?.toString().trim() ?? '',
    );
  }
}

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
    this.sources = const [],
  });

  final String? birthPlace;
  final String? deathPlace;
  final List<String> summary;
  final List<MemorialPlayerAchievement> achievements;
  final List<MemorialPlayerSource> sources;

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
      sources: (json['sources'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (value) =>
                MemorialPlayerSource.fromJson(Map<String, dynamic>.from(value)),
          )
          .where((source) => source.label.isNotEmpty && source.url.isNotEmpty)
          .toList(growable: false),
    );
  }
}

enum MemorialRatingType { classical, rapid, blitz }

class MemorialRatingHistoryPoint {
  const MemorialRatingHistoryPoint({
    required this.numericPeriod,
    this.classical,
    this.rapid,
    this.blitz,
    this.classicalGames,
    this.rapidGames,
    this.blitzGames,
  });

  final int numericPeriod;
  final int? classical;
  final int? rapid;
  final int? blitz;
  final int? classicalGames;
  final int? rapidGames;
  final int? blitzGames;

  int get year => numericPeriod ~/ 100;
  int get month => numericPeriod % 100;

  int? ratingFor(MemorialRatingType type) => switch (type) {
    MemorialRatingType.classical => classical,
    MemorialRatingType.rapid => rapid,
    MemorialRatingType.blitz => blitz,
  };

  int? gamesFor(MemorialRatingType type) => switch (type) {
    MemorialRatingType.classical => classicalGames,
    MemorialRatingType.rapid => rapidGames,
    MemorialRatingType.blitz => blitzGames,
  };

  factory MemorialRatingHistoryPoint.fromCompact(List<dynamic> row) {
    int? at(int index) =>
        index < row.length ? (row[index] as num?)?.toInt() : null;
    return MemorialRatingHistoryPoint(
      numericPeriod: at(0) ?? 0,
      classical: at(1),
      rapid: at(2),
      blitz: at(3),
      classicalGames: at(4),
      rapidGames: at(5),
      blitzGames: at(6),
    );
  }
}

class MemorialRatingListSpan {
  const MemorialRatingListSpan({
    required this.firstPeriod,
    required this.lastPeriod,
  });

  final String firstPeriod;
  final String lastPeriod;

  factory MemorialRatingListSpan.fromJson(Map<String, dynamic> json) {
    return MemorialRatingListSpan(
      firstPeriod: json['firstPeriod']?.toString().trim() ?? '',
      lastPeriod: json['lastPeriod']?.toString().trim() ?? '',
    );
  }
}

class MemorialPlayerHistory {
  const MemorialPlayerHistory({
    this.peakPeriod,
    this.peakRapidPeriod,
    this.peakBlitzPeriod,
    this.ratingListSpan,
    this.points = const [],
    this.sources = const [],
  });

  final String? peakPeriod;
  final String? peakRapidPeriod;
  final String? peakBlitzPeriod;
  final MemorialRatingListSpan? ratingListSpan;
  final List<MemorialRatingHistoryPoint> points;
  final List<MemorialPlayerSource> sources;

  String? peakPeriodFor(MemorialRatingType type) => switch (type) {
    MemorialRatingType.classical => peakPeriod,
    MemorialRatingType.rapid => peakRapidPeriod,
    MemorialRatingType.blitz => peakBlitzPeriod,
  };

  List<MemorialRatingHistoryPoint> pointsFor(MemorialRatingType type) => points
      .where((point) => (point.ratingFor(type) ?? 0) > 0)
      .toList(growable: false);

  factory MemorialPlayerHistory.fromJson(Map<String, dynamic> json) {
    final rawSpan = json['ratingListSpan'];
    return MemorialPlayerHistory(
      peakPeriod: _nonEmpty(json['peakPeriod']),
      peakRapidPeriod: _nonEmpty(json['peakRapidPeriod']),
      peakBlitzPeriod: _nonEmpty(json['peakBlitzPeriod']),
      ratingListSpan:
          rawSpan is Map
              ? MemorialRatingListSpan.fromJson(
                Map<String, dynamic>.from(rawSpan),
              )
              : null,
      points: (json['history'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<List>()
          .map((row) => MemorialRatingHistoryPoint.fromCompact(row))
          .where((point) => point.numericPeriod > 0)
          .toList(growable: false),
      sources: (json['sources'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (value) =>
                MemorialPlayerSource.fromJson(Map<String, dynamic>.from(value)),
          )
          .where((source) => source.label.isNotEmpty && source.url.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class MemorialPlayerOverview {
  const MemorialPlayerOverview({
    required this.player,
    this.about,
    this.history,
  });

  final MemorialPlayer player;
  final MemorialPlayerAbout? about;
  final MemorialPlayerHistory? history;

  List<MemorialPlayerSource> get sources {
    final byUrl = <String, MemorialPlayerSource>{};
    for (final source in <MemorialPlayerSource>[
      ...?history?.sources,
      ...?about?.sources,
    ]) {
      byUrl.putIfAbsent(source.url, () => source);
    }
    return List<MemorialPlayerSource>.unmodifiable(byUrl.values);
  }
}

Future<MemorialPlayerOverview?> loadBundledMemorialPlayerOverview(
  String sourceIdentity,
) async {
  final player = await findBundledMemorialPlayerBySourceIdentity(
    sourceIdentity,
  );
  if (player == null) return null;
  final aboutFuture = _aboutFuture ??= _loadAbout();
  final historyFuture = _historyFuture ??= _loadHistory();
  final loaded = await Future.wait<Object>([aboutFuture, historyFuture]);
  final aboutByRoute = loaded[0] as Map<String, MemorialPlayerAbout>;
  final historyByRoute = loaded[1] as Map<String, MemorialPlayerHistory>;
  return MemorialPlayerOverview(
    player: player,
    about: aboutByRoute[player.routeId],
    history: historyByRoute[player.routeId],
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

Future<Map<String, MemorialPlayerHistory>> _loadHistory() async {
  try {
    final source = await rootBundle.loadString(_historyAsset);
    final decoded = await compute(_decodeHistory, source);
    return Map<String, MemorialPlayerHistory>.unmodifiable(
      decoded.map(
        (routeId, value) =>
            MapEntry(routeId, MemorialPlayerHistory.fromJson(value)),
      ),
    );
  } catch (error) {
    debugPrint('[Memorial history] Bundled rating history unavailable: $error');
    return const <String, MemorialPlayerHistory>{};
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

Map<String, Map<String, dynamic>> _decodeHistory(String source) {
  final decoded = jsonDecode(source) as Map<String, dynamic>;
  final rows = decoded['profiles'] as List<dynamic>? ?? const <dynamic>[];
  return <String, Map<String, dynamic>>{
    for (final raw in rows.whereType<Map>())
      if (raw['routeId']?.toString().isNotEmpty == true)
        raw['routeId'].toString(): Map<String, dynamic>.from(raw),
  };
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

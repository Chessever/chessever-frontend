import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:dio/dio.dart';
import 'package:chessever2/main.dart';
import 'package:logarte/logarte.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:dartchess/dartchess.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models_extra.dart';

part 'gamebase_repository.mapper.dart';

@MappableClass()
class GamebaseResponse with GamebaseResponseMappable {
  const GamebaseResponse({required this.status, required this.data});

  final String status;
  final GamebaseData data;

  static const fromJson = GamebaseResponseMapper.fromJson;
}

@MappableClass()
class GamebaseData with GamebaseDataMappable {
  const GamebaseData({required this.moves});

  final List<MoveAggregate> moves;

  static const fromJson = GamebaseDataMapper.fromJson;
}

/// Date window supported by `GET /api/miniatures`.
enum MiniatureGamesWindow {
  today,
  week,
  all;

  String get apiValue => name;
}

/// Primary sort supported by `GET /api/miniatures`.
enum MiniatureGamesSort {
  rating,
  moves,
  recent;

  String get apiValue => name;
}

enum MiniatureGamesSortOrder {
  asc,
  desc;

  String get apiValue => name;
}

/// Miniatures are decisive, so the backend only serves white or black wins.
enum MiniatureGameResult {
  whiteWins,
  blackWins;

  String get apiValue => switch (this) {
    MiniatureGameResult.whiteWins => 'W',
    MiniatureGameResult.blackWins => 'B',
  };

  static MiniatureGameResult fromApiValue(Object? value) {
    final normalized =
        _readRequiredMiniatureString(value, 'result').toUpperCase();
    return switch (normalized) {
      'W' => MiniatureGameResult.whiteWins,
      'B' => MiniatureGameResult.blackWins,
      _ =>
        throw FormatException(
          'Invalid miniatures field "result": expected W or B.',
        ),
    };
  }
}

enum MiniatureGameTimeControl {
  classical,
  rapid,
  blitz;

  String get apiValue => name.toUpperCase();

  static MiniatureGameTimeControl fromApiValue(Object? value) {
    final normalized =
        _readRequiredMiniatureString(value, 'timeControl').toUpperCase();
    return switch (normalized) {
      'CLASSICAL' => MiniatureGameTimeControl.classical,
      'RAPID' => MiniatureGameTimeControl.rapid,
      'BLITZ' => MiniatureGameTimeControl.blitz,
      _ =>
        throw FormatException(
          'Invalid miniatures field "timeControl": $normalized.',
        ),
    };
  }
}

/// Typed tri-state used by both filters and returned miniature rows.
///
/// [all] is only a filter value and is omitted from the request. Parsed rows
/// always contain either [online] or [offline].
enum MiniatureGameOnlineStatus {
  all,
  online,
  offline;

  bool? get apiValue => switch (this) {
    MiniatureGameOnlineStatus.all => null,
    MiniatureGameOnlineStatus.online => true,
    MiniatureGameOnlineStatus.offline => false,
  };

  static MiniatureGameOnlineStatus fromApiValue(Object? value) {
    return _readRequiredMiniatureBool(value, 'isOnline')
        ? MiniatureGameOnlineStatus.online
        : MiniatureGameOnlineStatus.offline;
  }
}

/// Canonical source represented by a miniature summary.
enum GamebaseMiniatureSource { gamebase }

/// Stable identity needed to hydrate a miniature through `/api/game/{id}`.
///
/// Miniature list rows intentionally contain no PGN or moves. Keeping this as
/// an explicit reference prevents summary metadata from being mistaken for a
/// complete game document.
class GamebaseMiniatureSourceMetadata {
  const GamebaseMiniatureSourceMetadata({
    required this.gameId,
    this.source = GamebaseMiniatureSource.gamebase,
    this.requiresFullGameHydration = true,
    this.whitePlayerId,
    this.blackPlayerId,
  });

  final String gameId;
  final GamebaseMiniatureSource source;
  final bool requiresFullGameHydration;
  final String? whitePlayerId;
  final String? blackPlayerId;
}

/// Complete filter and sort contract for `GET /api/miniatures`.
class MiniatureGamesFilter {
  const MiniatureGamesFilter({
    this.window = MiniatureGamesWindow.all,
    this.sort = MiniatureGamesSort.rating,
    this.order = MiniatureGamesSortOrder.desc,
    this.search,
    this.results = const <MiniatureGameResult>{},
    this.eco,
    this.ecoCategories = const <String>{},
    this.opening,
    this.variation,
    this.timeControls = const <MiniatureGameTimeControl>{},
    this.onlineStatus = MiniatureGameOnlineStatus.all,
    this.minRating,
    this.maxRating,
    this.minMoves,
    this.maxMoves,
    this.dateFrom,
    this.dateTo,
    this.player,
    this.playerId,
  });

  static const defaultFilter = MiniatureGamesFilter();

  final MiniatureGamesWindow window;
  final MiniatureGamesSort sort;
  final MiniatureGamesSortOrder order;
  final String? search;
  final Set<MiniatureGameResult> results;
  final String? eco;
  final Set<String> ecoCategories;
  final String? opening;
  final String? variation;
  final Set<MiniatureGameTimeControl> timeControls;
  final MiniatureGameOnlineStatus onlineStatus;
  final int? minRating;
  final int? maxRating;
  final int? minMoves;
  final int? maxMoves;
  final String? dateFrom;
  final String? dateTo;
  final String? player;
  final String? playerId;

  Map<String, dynamic> queryParameters({
    required int limit,
    required int offset,
  }) {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    if (offset < 0 || offset > 1000000) {
      throw RangeError.range(offset, 0, 1000000, 'offset');
    }

    final query = <String, dynamic>{
      'window': window.apiValue,
      'sort': sort.apiValue,
      'order': order.apiValue,
      'limit': limit,
      'offset': offset,
    };

    final normalizedSearch = _cleanMiniatureText(search);
    if (normalizedSearch != null) query['q'] = normalizedSearch;

    if (results.isNotEmpty) {
      query['result'] = results.map((result) => result.apiValue).join(',');
    }

    final normalizedEco = _cleanMiniatureCsv(eco, uppercase: true);
    if (normalizedEco != null) query['eco'] = normalizedEco;

    final normalizedCategories = _cleanMiniatureValues(
      ecoCategories,
      uppercase: true,
    );
    if (normalizedCategories.isNotEmpty) {
      query['ecoCategory'] = normalizedCategories.join(',');
    }

    final normalizedOpening = _cleanMiniatureText(opening);
    if (normalizedOpening != null) query['opening'] = normalizedOpening;

    final normalizedVariation = _cleanMiniatureText(variation);
    if (normalizedVariation != null) {
      query['variation'] = normalizedVariation;
    }

    if (timeControls.isNotEmpty) {
      query['timeControl'] = timeControls
          .map((control) => control.apiValue)
          .join(',');
    }

    final isOnline = onlineStatus.apiValue;
    if (isOnline != null) query['isOnline'] = isOnline;

    if (minRating != null) query['minRating'] = minRating;
    if (maxRating != null) query['maxRating'] = maxRating;
    if (minMoves != null) query['minMoves'] = minMoves;
    if (maxMoves != null) query['maxMoves'] = maxMoves;

    final (:from, :to) = _cleanMiniatureDateRange(
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    if (from != null) query['dateFrom'] = from;
    if (to != null) query['dateTo'] = to;

    final normalizedPlayer = _cleanMiniatureText(player);
    if (normalizedPlayer != null) query['player'] = normalizedPlayer;

    final normalizedPlayerId = _cleanMiniatureText(playerId);
    if (normalizedPlayerId != null) query['playerId'] = normalizedPlayerId;

    return query;
  }
}

class GamebaseMiniaturesPage {
  const GamebaseMiniaturesPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<GamebaseMiniature> items;
  final int total;
  final int limit;
  final int offset;

  /// Advance by rows actually received so a short page never creates a gap.
  int get nextOffset => offset + items.length;

  /// An empty page is terminal even if a stale backend total says otherwise.
  bool get hasMore => items.isNotEmpty && nextOffset < total;

  factory GamebaseMiniaturesPage.fromJson(Map<String, dynamic> json) {
    final payload = _readMiniaturesPagePayload(json);
    final rawItems = payload['items'];
    if (rawItems is! List) {
      throw const FormatException(
        'Invalid miniatures payload: "items" must be a list.',
      );
    }

    final total = _readRequiredMiniatureInt(payload['total'], 'total');
    final limit = _readRequiredMiniatureInt(payload['limit'], 'limit');
    final offset = _readRequiredMiniatureInt(payload['offset'], 'offset');
    if (total < 0) {
      throw const FormatException(
        'Invalid miniatures payload: "total" cannot be negative.',
      );
    }
    if (limit < 1) {
      throw const FormatException(
        'Invalid miniatures payload: "limit" must be positive.',
      );
    }
    if (offset < 0) {
      throw const FormatException(
        'Invalid miniatures payload: "offset" cannot be negative.',
      );
    }

    final items = <GamebaseMiniature>[];
    for (var index = 0; index < rawItems.length; index++) {
      final rawItem = rawItems[index];
      if (rawItem is! Map) {
        throw FormatException(
          'Invalid miniatures payload: item at index $index is not an object.',
        );
      }
      try {
        items.add(
          GamebaseMiniature.fromJson(Map<String, dynamic>.from(rawItem)),
        );
      } on FormatException catch (error) {
        throw FormatException(
          'Invalid miniatures payload item at index $index: ${error.message}',
        );
      }
    }

    return GamebaseMiniaturesPage(
      items: List<GamebaseMiniature>.unmodifiable(items),
      total: total,
      limit: limit,
      offset: offset,
    );
  }
}

/// Lightweight Miniatures row. It is not a complete Gamebase game.
class GamebaseMiniature {
  const GamebaseMiniature({
    required this.gameId,
    this.avgRating,
    required this.plyCount,
    required this.finalMoveNumber,
    required this.result,
    required this.timeControl,
    required this.onlineStatus,
    this.date,
    this.event,
    this.eco,
    this.ecoCategory,
    this.opening,
    this.variation,
    this.whiteName,
    this.blackName,
    this.whiteElo,
    this.blackElo,
    this.whitePlayerId,
    this.blackPlayerId,
    this.whiteFed,
    this.blackFed,
  });

  final String gameId;
  final int? avgRating;
  final int plyCount;
  final int finalMoveNumber;
  final MiniatureGameResult result;
  final MiniatureGameTimeControl timeControl;
  final MiniatureGameOnlineStatus onlineStatus;
  final DateTime? date;
  final String? event;
  final String? eco;
  final String? ecoCategory;
  final String? opening;
  final String? variation;
  final String? whiteName;
  final String? blackName;
  final int? whiteElo;
  final int? blackElo;
  final String? whitePlayerId;
  final String? blackPlayerId;
  final String? whiteFed;
  final String? blackFed;

  String get canonicalGameId => gameId;
  String get sourceGameId => gameId;
  bool get isOnline => onlineStatus == MiniatureGameOnlineStatus.online;

  GamebaseMiniatureSourceMetadata get sourceMetadata =>
      GamebaseMiniatureSourceMetadata(
        gameId: gameId,
        whitePlayerId: whitePlayerId,
        blackPlayerId: blackPlayerId,
      );

  factory GamebaseMiniature.fromJson(Map<String, dynamic> json) {
    return GamebaseMiniature(
      gameId: _readRequiredMiniatureString(json['gameId'], 'gameId'),
      avgRating: _readOptionalMiniatureInt(json['avgRating'], 'avgRating'),
      plyCount: _readRequiredMiniatureInt(json['plyCount'], 'plyCount'),
      finalMoveNumber: _readRequiredMiniatureInt(
        json['finalMoveNumber'],
        'finalMoveNumber',
      ),
      result: MiniatureGameResult.fromApiValue(json['result']),
      timeControl: MiniatureGameTimeControl.fromApiValue(json['timeControl']),
      onlineStatus: MiniatureGameOnlineStatus.fromApiValue(json['isOnline']),
      date: _readOptionalMiniatureDate(json['date'], 'date'),
      event: _readOptionalMiniatureString(json['event'], 'event'),
      eco: _readOptionalMiniatureString(json['eco'], 'eco'),
      ecoCategory: _readOptionalMiniatureString(
        json['ecoCategory'],
        'ecoCategory',
      ),
      opening: _readOptionalMiniatureString(json['opening'], 'opening'),
      variation: _readOptionalMiniatureString(json['variation'], 'variation'),
      whiteName: _readOptionalMiniatureString(json['whiteName'], 'whiteName'),
      blackName: _readOptionalMiniatureString(json['blackName'], 'blackName'),
      whiteElo: _readOptionalMiniatureInt(json['whiteElo'], 'whiteElo'),
      blackElo: _readOptionalMiniatureInt(json['blackElo'], 'blackElo'),
      whitePlayerId: _readOptionalMiniatureString(
        json['whitePlayerId'],
        'whitePlayerId',
      ),
      blackPlayerId: _readOptionalMiniatureString(
        json['blackPlayerId'],
        'blackPlayerId',
      ),
      whiteFed: _readOptionalMiniatureString(json['whiteFed'], 'whiteFed'),
      blackFed: _readOptionalMiniatureString(json['blackFed'], 'blackFed'),
    );
  }
}

Map<String, dynamic> _readMiniaturesPagePayload(Map<String, dynamic> json) {
  if (json.containsKey('data')) {
    final status = json['status'];
    if (status is! String || status.trim().toLowerCase() != 'success') {
      throw const FormatException(
        'Invalid miniatures envelope: expected status "success".',
      );
    }
    final data = json['data'];
    if (data is! Map) {
      throw const FormatException(
        'Invalid miniatures envelope: "data" must be an object.',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  // Historical clients received the page payload directly.
  if (!json.containsKey('items') || !json.containsKey('total')) {
    throw const FormatException(
      'Invalid miniatures envelope: missing page payload.',
    );
  }
  final status = json['status'];
  if (status != null &&
      (status is! String || status.trim().toLowerCase() != 'success')) {
    throw const FormatException(
      'Invalid miniatures envelope: expected status "success".',
    );
  }
  return json;
}

String _readRequiredMiniatureString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'Invalid miniatures field "$field": expected a non-empty string.',
    );
  }
  return value.trim();
}

String? _readOptionalMiniatureString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException(
      'Invalid miniatures field "$field": expected a string or null.',
    );
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _readRequiredMiniatureInt(Object? value, String field) {
  final parsed = _parseMiniatureInt(value);
  if (parsed == null) {
    throw FormatException(
      'Invalid miniatures field "$field": expected an integer.',
    );
  }
  return parsed;
}

int? _readOptionalMiniatureInt(Object? value, String field) {
  if (value == null) return null;
  final parsed = _parseMiniatureInt(value);
  if (parsed == null) {
    throw FormatException(
      'Invalid miniatures field "$field": expected an integer or null.',
    );
  }
  return parsed;
}

int? _parseMiniatureInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.truncate()) {
    return value.toInt();
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

bool _readRequiredMiniatureBool(Object? value, String field) {
  if (value is bool) return value;
  if (value == 1 || value == '1') return true;
  if (value == 0 || value == '0') return false;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  throw FormatException(
    'Invalid miniatures field "$field": expected a boolean.',
  );
}

DateTime? _readOptionalMiniatureDate(Object? value, String field) {
  final raw = _readOptionalMiniatureString(value, field);
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException(
      'Invalid miniatures field "$field": expected an ISO-8601 date.',
    );
  }
  return parsed;
}

String? _cleanMiniatureText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _cleanMiniatureCsv(String? value, {bool uppercase = false}) {
  final values = _cleanMiniatureValues(
    value?.split(',') ?? const <String>[],
    uppercase: uppercase,
  );
  return values.isEmpty ? null : values.join(',');
}

List<String> _cleanMiniatureValues(
  Iterable<String> values, {
  bool uppercase = false,
}) {
  final result = <String>[];
  for (final value in values) {
    var normalized = value.trim();
    if (uppercase) normalized = normalized.toUpperCase();
    if (normalized.isNotEmpty && !result.contains(normalized)) {
      result.add(normalized);
    }
  }
  return result;
}

String? _cleanMiniatureDate(String? value) {
  final trimmed = _cleanMiniatureText(value);
  if (trimmed == null) return null;
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed) ? trimmed : null;
}

({String? from, String? to}) _cleanMiniatureDateRange({
  required String? dateFrom,
  required String? dateTo,
}) {
  final from = _cleanMiniatureDate(dateFrom);
  final to = _cleanMiniatureDate(dateTo);
  if (from != null && to != null && from.compareTo(to) > 0) {
    return (from: to, to: from);
  }
  return (from: from, to: to);
}

enum GamebaseStudySort {
  score,
  recent,
  name,
  chapters,
  created;

  String get apiValue => switch (this) {
    GamebaseStudySort.score => 'score',
    GamebaseStudySort.recent => 'recent',
    GamebaseStudySort.name => 'name',
    GamebaseStudySort.chapters => 'chapters',
    GamebaseStudySort.created => 'created',
  };
}

enum GamebaseStudySortOrder {
  asc,
  desc;

  String get apiValue => name;
}

enum GamebaseStudyStatus {
  active,
  gone;

  static GamebaseStudyStatus fromApiValue(Object? value) {
    final normalized = _readRequiredStudyString(value, 'status').toLowerCase();
    return switch (normalized) {
      'active' => GamebaseStudyStatus.active,
      'gone' => GamebaseStudyStatus.gone,
      _ =>
        throw GamebaseStudyContractException(
          'Invalid Study field "status": $normalized.',
        ),
    };
  }
}

enum GamebaseStudySource { lichess }

/// Current redistribution knowledge for mirrored Study chapter content.
///
/// The existing API supplies no explicit rights metadata, so current responses
/// always use [unknown]. A future backend contract must opt into any stronger
/// capability explicitly.
enum GamebaseStudyRedistributionCapability { unknown, allowed, prohibited }

/// Version and rights facts required before mirrored chapter content can open.
class GamebaseStudyContentCapabilities {
  const GamebaseStudyContentCapabilities({
    required this.contentVersion,
    required this.rights,
    required this.redistribution,
    required this.canOpenMirroredChapterInApp,
  });

  static const unavailable = GamebaseStudyContentCapabilities(
    contentVersion: null,
    rights: null,
    redistribution: GamebaseStudyRedistributionCapability.unknown,
    canOpenMirroredChapterInApp: false,
  );

  final String? contentVersion;
  final String? rights;
  final GamebaseStudyRedistributionCapability redistribution;
  final bool canOpenMirroredChapterInApp;
}

class GamebaseStudyContractException implements Exception {
  const GamebaseStudyContractException(this.message);

  final String message;

  @override
  String toString() => 'GamebaseStudyContractException: $message';
}

class GamebaseStudyRequestException implements Exception {
  const GamebaseStudyRequestException({
    required this.operation,
    required this.message,
    this.statusCode,
    this.cause,
  });

  final String operation;
  final String message;
  final int? statusCode;
  final Object? cause;

  bool get isNotFound => statusCode == 404;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'GamebaseStudyRequestException: $operation$status: $message';
  }
}

/// Exact current filter contract for `GET /api/studies`.
class GamebaseStudiesFilter {
  const GamebaseStudiesFilter({
    this.sort = GamebaseStudySort.score,
    this.order = GamebaseStudySortOrder.desc,
    this.search,
    this.ecos = const <String>{},
    this.ecoCategories = const <String>{},
    this.openings = const <String>{},
    this.variants = const <String>{},
    this.chapterModes = const <String>{},
    this.players = const <String>{},
    this.gamebook,
    this.customPositions,
    this.hasAnnotations,
    this.minViews,
    this.minChapters,
  });

  static const defaultFilter = GamebaseStudiesFilter();

  final GamebaseStudySort sort;
  final GamebaseStudySortOrder order;
  final String? search;
  final Set<String> ecos;
  final Set<String> ecoCategories;
  final Set<String> openings;
  final Set<String> variants;
  final Set<String> chapterModes;
  final Set<String> players;
  final bool? gamebook;
  final bool? customPositions;
  final bool? hasAnnotations;
  final int? minViews;
  final int? minChapters;

  Map<String, dynamic> queryParameters({
    required int limit,
    required int offset,
  }) {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    if (offset < 0 || offset > 1000000) {
      throw RangeError.range(offset, 0, 1000000, 'offset');
    }
    final normalizedMinViews = minViews;
    if (normalizedMinViews != null && normalizedMinViews < 0) {
      throw RangeError.value(
        normalizedMinViews,
        'minViews',
        'Must be non-negative.',
      );
    }
    final normalizedMinChapters = minChapters;
    if (normalizedMinChapters != null && normalizedMinChapters < 0) {
      throw RangeError.value(
        normalizedMinChapters,
        'minChapters',
        'Must be non-negative.',
      );
    }

    final query = <String, dynamic>{
      'sort': sort.apiValue,
      'order': order.apiValue,
      'limit': limit,
      'offset': offset,
    };

    final normalizedSearch = _cleanStudyText(search);
    if (normalizedSearch != null) query['q'] = normalizedSearch;

    void addCsv(String key, Iterable<String> values, {bool uppercase = false}) {
      final normalized = _cleanStudyQueryValues(values, uppercase: uppercase);
      if (normalized.isNotEmpty) query[key] = normalized.join(',');
    }

    addCsv('eco', ecos, uppercase: true);
    addCsv('ecoCategory', ecoCategories, uppercase: true);
    addCsv('opening', openings);
    addCsv('variant', variants);
    addCsv('chapterMode', chapterModes);
    addCsv('player', players);

    if (gamebook != null) query['gamebook'] = gamebook;
    if (customPositions != null) {
      query['customPositions'] = customPositions;
    }
    if (hasAnnotations != null) {
      query['hasAnnotations'] = hasAnnotations;
    }
    if (minViews != null) query['minViews'] = minViews;
    if (minChapters != null) query['minChapters'] = minChapters;

    return query;
  }
}

class GamebaseStudySummary {
  const GamebaseStudySummary({
    required this.lichessStudyId,
    required this.authorUsername,
    required this.name,
    required this.views,
    required this.lichessCreatedAt,
    required this.lichessUpdatedAt,
    required this.chapterCount,
    required this.plyTotal,
    required this.hasAnnotations,
    required this.ecos,
    required this.ecoCategories,
    required this.openings,
    required this.variants,
    required this.chapterModes,
    required this.players,
    required this.isGamebook,
    required this.hasCustomPositions,
    required this.credibilityScore,
    required this.passedGate,
    required this.status,
    required this.syncedAt,
    this.contentCapabilities = GamebaseStudyContentCapabilities.unavailable,
  });

  final String lichessStudyId;
  final String? authorUsername;
  final String name;
  final int views;
  final DateTime? lichessCreatedAt;
  final DateTime lichessUpdatedAt;
  final int chapterCount;
  final int plyTotal;
  final bool hasAnnotations;
  final List<String> ecos;
  final List<String> ecoCategories;
  final List<String> openings;
  final List<String> variants;
  final List<String> chapterModes;
  final List<String> players;
  final bool isGamebook;
  final bool hasCustomPositions;
  final double credibilityScore;
  final bool passedGate;
  final GamebaseStudyStatus status;
  final DateTime syncedAt;
  final GamebaseStudyContentCapabilities contentCapabilities;

  String get id => lichessStudyId;
  String get canonicalStudyId => lichessStudyId;
  GamebaseStudySource get source => GamebaseStudySource.lichess;
  String? get contentVersion => contentCapabilities.contentVersion;
  String? get rights => contentCapabilities.rights;
  GamebaseStudyRedistributionCapability get redistribution =>
      contentCapabilities.redistribution;
  bool get canOpenMirroredChapterInApp =>
      contentCapabilities.canOpenMirroredChapterInApp;
  Uri get sourceUrl => Uri(
    scheme: 'https',
    host: 'lichess.org',
    pathSegments: <String>['study', lichessStudyId],
  );
  Uri get canonicalSourceUrl => sourceUrl;

  factory GamebaseStudySummary.fromJson(Map<String, dynamic> json) {
    final views = _readRequiredStudyInt(json['views'], 'views');
    final chapterCount = _readRequiredStudyInt(
      json['chapterCount'],
      'chapterCount',
    );
    final plyTotal = _readRequiredStudyInt(json['plyTotal'], 'plyTotal');
    if (views < 0 || chapterCount < 0 || plyTotal < 0) {
      throw const GamebaseStudyContractException(
        'Invalid Study summary: counts cannot be negative.',
      );
    }

    return GamebaseStudySummary(
      lichessStudyId: _readLichessStudyId(json['id']),
      authorUsername: _readOptionalStudyString(
        json['authorUsername'],
        'authorUsername',
      ),
      name: _readRequiredStudyString(json['name'], 'name'),
      views: views,
      lichessCreatedAt: _readOptionalStudyDate(
        json['lichessCreatedAt'],
        'lichessCreatedAt',
      ),
      lichessUpdatedAt: _readRequiredStudyDate(
        json['lichessUpdatedAt'],
        'lichessUpdatedAt',
      ),
      chapterCount: chapterCount,
      plyTotal: plyTotal,
      hasAnnotations: _readRequiredStudyBool(
        json['hasAnnotations'],
        'hasAnnotations',
      ),
      ecos: _readRequiredStudyStringList(json['ecos'], 'ecos'),
      ecoCategories: _readRequiredStudyStringList(
        json['ecoCategories'],
        'ecoCategories',
      ),
      openings: _readRequiredStudyStringList(json['openings'], 'openings'),
      variants: _readRequiredStudyStringList(json['variants'], 'variants'),
      chapterModes: _readRequiredStudyStringList(
        json['chapterModes'],
        'chapterModes',
      ),
      players: _readRequiredStudyStringList(json['players'], 'players'),
      isGamebook: _readRequiredStudyBool(json['isGamebook'], 'isGamebook'),
      hasCustomPositions: _readRequiredStudyBool(
        json['hasCustomPositions'],
        'hasCustomPositions',
      ),
      credibilityScore: _readRequiredStudyDouble(
        json['credibilityScore'],
        'credibilityScore',
      ),
      passedGate: _readRequiredStudyBool(json['passedGate'], 'passedGate'),
      status: GamebaseStudyStatus.fromApiValue(json['status']),
      syncedAt: _readRequiredStudyDate(json['syncedAt'], 'syncedAt'),
    );
  }
}

class GamebaseStudiesPage {
  const GamebaseStudiesPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<GamebaseStudySummary> items;
  final int total;
  final int limit;
  final int offset;

  int get nextOffset => offset + items.length;
  bool get hasMore => items.isNotEmpty && nextOffset < total;

  factory GamebaseStudiesPage.fromJson(Map<String, dynamic> json) {
    final payload = _readStudyEnvelopeData(json, operation: 'list Studies');
    final rawItems = payload['items'];
    if (rawItems is! List) {
      throw const GamebaseStudyContractException(
        'Invalid Studies payload: "items" must be a list.',
      );
    }

    final total = _readRequiredStudyInt(payload['total'], 'total');
    final limit = _readRequiredStudyInt(payload['limit'], 'limit');
    final offset = _readRequiredStudyInt(payload['offset'], 'offset');
    if (total < 0 || offset < 0 || limit < 1) {
      throw const GamebaseStudyContractException(
        'Invalid Studies pagination metadata.',
      );
    }

    final items = <GamebaseStudySummary>[];
    for (var index = 0; index < rawItems.length; index++) {
      final item = _readStudyMap(rawItems[index], 'items[$index]');
      try {
        items.add(GamebaseStudySummary.fromJson(item));
      } on GamebaseStudyContractException catch (error) {
        throw GamebaseStudyContractException(
          'Invalid Study at index $index: ${error.message}',
        );
      }
    }

    return GamebaseStudiesPage(
      items: List<GamebaseStudySummary>.unmodifiable(items),
      total: total,
      limit: limit,
      offset: offset,
    );
  }
}

class GamebaseStudyChapterMetadata {
  const GamebaseStudyChapterMetadata({
    required this.lichessStudyId,
    required this.lichessChapterId,
    required this.name,
    required this.plyCount,
    required this.orderIndex,
    required this.eco,
    required this.opening,
    required this.variant,
    required this.result,
    required this.chapterMode,
    required this.isSetup,
    required this.whiteName,
    required this.blackName,
    required this.whiteElo,
    required this.blackElo,
    required this.hasAnnotations,
    this.contentCapabilities = GamebaseStudyContentCapabilities.unavailable,
  });

  final String lichessStudyId;
  final String lichessChapterId;
  final String? name;
  final int plyCount;
  final int orderIndex;
  final String? eco;
  final String? opening;
  final String? variant;
  final String? result;
  final String? chapterMode;
  final bool isSetup;
  final String? whiteName;
  final String? blackName;
  final int? whiteElo;
  final int? blackElo;
  final bool hasAnnotations;
  final GamebaseStudyContentCapabilities contentCapabilities;

  String get studyId => lichessStudyId;
  String get chapterId => lichessChapterId;
  String get canonicalStudyId => lichessStudyId;
  String get canonicalChapterId => lichessChapterId;
  GamebaseStudySource get source => GamebaseStudySource.lichess;
  String? get contentVersion => contentCapabilities.contentVersion;
  String? get rights => contentCapabilities.rights;
  GamebaseStudyRedistributionCapability get redistribution =>
      contentCapabilities.redistribution;
  bool get canOpenMirroredChapterInApp =>
      contentCapabilities.canOpenMirroredChapterInApp;
  Uri get sourceUrl => Uri(
    scheme: 'https',
    host: 'lichess.org',
    pathSegments: <String>['study', lichessStudyId, lichessChapterId],
  );
  Uri get canonicalSourceUrl => sourceUrl;

  factory GamebaseStudyChapterMetadata.fromJson(
    Map<String, dynamic> json, {
    required String lichessStudyId,
  }) {
    final plyCount = _readRequiredStudyInt(json['plyCount'], 'plyCount');
    final orderIndex = _readRequiredStudyInt(json['orderIndex'], 'orderIndex');
    if (plyCount < 0 || orderIndex < 0) {
      throw const GamebaseStudyContractException(
        'Invalid Study chapter: plyCount and orderIndex cannot be negative.',
      );
    }

    // `json['id']` is the mirror's internal row UUID. It is deliberately not
    // read into this model; only the source chapterId is a user-facing identity.
    return GamebaseStudyChapterMetadata(
      lichessStudyId: lichessStudyId,
      lichessChapterId: _readLichessChapterId(json['chapterId']),
      name: _readOptionalStudyString(json['name'], 'name'),
      plyCount: plyCount,
      orderIndex: orderIndex,
      eco: _readOptionalStudyString(json['eco'], 'eco'),
      opening: _readOptionalStudyString(json['opening'], 'opening'),
      variant: _readOptionalStudyString(json['variant'], 'variant'),
      result: _readOptionalStudyString(json['result'], 'result'),
      chapterMode: _readOptionalStudyString(json['chapterMode'], 'chapterMode'),
      isSetup: _readRequiredStudyBool(json['isSetup'], 'isSetup'),
      whiteName: _readOptionalStudyString(json['whiteName'], 'whiteName'),
      blackName: _readOptionalStudyString(json['blackName'], 'blackName'),
      whiteElo: _readOptionalStudyInt(json['whiteElo'], 'whiteElo'),
      blackElo: _readOptionalStudyInt(json['blackElo'], 'blackElo'),
      hasAnnotations: _readRequiredStudyBool(
        json['hasAnnotations'],
        'hasAnnotations',
      ),
    );
  }
}

class GamebaseStudyDetail {
  const GamebaseStudyDetail({required this.study, required this.chapters});

  final GamebaseStudySummary study;
  final List<GamebaseStudyChapterMetadata> chapters;

  String get canonicalStudyId => study.canonicalStudyId;
  Uri get sourceUrl => study.sourceUrl;
  GamebaseStudyContentCapabilities get contentCapabilities =>
      study.contentCapabilities;
  String? get contentVersion => contentCapabilities.contentVersion;
  String? get rights => contentCapabilities.rights;
  GamebaseStudyRedistributionCapability get redistribution =>
      contentCapabilities.redistribution;
  bool get canOpenMirroredChapterInApp =>
      contentCapabilities.canOpenMirroredChapterInApp;

  factory GamebaseStudyDetail.fromJson(Map<String, dynamic> json) {
    final payload = _readStudyEnvelopeData(json, operation: 'get Study');
    final study = GamebaseStudySummary.fromJson(
      _readStudyMap(payload['study'], 'study'),
    );
    final rawChapters = payload['chapters'];
    if (rawChapters is! List) {
      throw const GamebaseStudyContractException(
        'Invalid Study detail: "chapters" must be a list.',
      );
    }

    final chapters = <GamebaseStudyChapterMetadata>[];
    for (var index = 0; index < rawChapters.length; index++) {
      final chapter = _readStudyMap(rawChapters[index], 'chapters[$index]');
      try {
        chapters.add(
          GamebaseStudyChapterMetadata.fromJson(
            chapter,
            lichessStudyId: study.lichessStudyId,
          ),
        );
      } on GamebaseStudyContractException catch (error) {
        throw GamebaseStudyContractException(
          'Invalid Study chapter at index $index: ${error.message}',
        );
      }
    }
    chapters.sort((left, right) => left.orderIndex.compareTo(right.orderIndex));

    return GamebaseStudyDetail(
      study: study,
      chapters: List<GamebaseStudyChapterMetadata>.unmodifiable(chapters),
    );
  }
}

Map<String, dynamic> _readStudyEnvelopeData(
  Map<String, dynamic> json, {
  required String operation,
}) {
  final status = json['status'];
  if (status is! String || status.trim().toLowerCase() != 'success') {
    throw GamebaseStudyContractException(
      'Invalid $operation envelope: expected status "success".',
    );
  }
  return _readStudyMap(json['data'], 'data');
}

Map<String, dynamic> _readStudyMap(Object? value, String field) {
  if (value is! Map) {
    throw GamebaseStudyContractException(
      'Invalid Study field "$field": expected an object.',
    );
  }
  try {
    return Map<String, dynamic>.from(value);
  } catch (_) {
    throw GamebaseStudyContractException(
      'Invalid Study field "$field": expected string keys.',
    );
  }
}

String _readRequiredStudyString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw GamebaseStudyContractException(
      'Invalid Study field "$field": expected a non-empty string.',
    );
  }
  return value.trim();
}

String _readLichessStudyId(Object? value) {
  final id = _readRequiredStudyString(value, 'id');
  if (!RegExp(r'^[A-Za-z0-9]{8}$').hasMatch(id)) {
    throw const GamebaseStudyContractException(
      'Invalid Study field "id": expected an external Lichess Study ID.',
    );
  }
  return id;
}

String _readLichessChapterId(Object? value) {
  final id = _readRequiredStudyString(value, 'chapterId');
  if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) {
    throw const GamebaseStudyContractException(
      'Invalid Study field "chapterId": expected an external Lichess chapter ID.',
    );
  }
  return id;
}

String? _readOptionalStudyString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) {
    throw GamebaseStudyContractException(
      'Invalid Study field "$field": expected a string or null.',
    );
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _readRequiredStudyInt(Object? value, String field) {
  final parsed = _parseStudyInt(value);
  if (parsed == null) {
    throw GamebaseStudyContractException(
      'Invalid Study field "$field": expected an integer.',
    );
  }
  return parsed;
}

int? _readOptionalStudyInt(Object? value, String field) {
  if (value == null) return null;
  final parsed = _parseStudyInt(value);
  if (parsed == null) {
    throw GamebaseStudyContractException(
      'Invalid Study field "$field": expected an integer or null.',
    );
  }
  return parsed;
}

int? _parseStudyInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.truncate()) {
    return value.toInt();
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double _readRequiredStudyDouble(Object? value, String field) {
  final parsed = switch (value) {
    num number when number.isFinite => number.toDouble(),
    String raw => double.tryParse(raw.trim()),
    _ => null,
  };
  if (parsed == null || !parsed.isFinite) {
    throw GamebaseStudyContractException(
      'Invalid Study field "$field": expected a finite number.',
    );
  }
  return parsed;
}

bool _readRequiredStudyBool(Object? value, String field) {
  if (value is bool) return value;
  if (value == 1 || value == '1') return true;
  if (value == 0 || value == '0') return false;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  throw GamebaseStudyContractException(
    'Invalid Study field "$field": expected a boolean.',
  );
}

DateTime _readRequiredStudyDate(Object? value, String field) {
  final parsed = _parseStudyDate(value);
  if (parsed == null) {
    throw GamebaseStudyContractException(
      'Invalid Study field "$field": expected an ISO-8601 date.',
    );
  }
  return parsed;
}

DateTime? _readOptionalStudyDate(Object? value, String field) {
  if (value == null) return null;
  final parsed = _parseStudyDate(value);
  if (parsed == null) {
    throw GamebaseStudyContractException(
      'Invalid Study field "$field": expected an ISO-8601 date or null.',
    );
  }
  return parsed;
}

DateTime? _parseStudyDate(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim());
}

List<String> _readRequiredStudyStringList(Object? value, String field) {
  if (value is! List) {
    throw GamebaseStudyContractException(
      'Invalid Study field "$field": expected a string list.',
    );
  }
  final result = <String>[];
  for (var index = 0; index < value.length; index++) {
    final item = value[index];
    if (item is! String) {
      throw GamebaseStudyContractException(
        'Invalid Study field "$field[$index]": expected a string.',
      );
    }
    final normalized = item.trim();
    if (normalized.isNotEmpty) result.add(normalized);
  }
  return List<String>.unmodifiable(result);
}

String? _cleanStudyText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

List<String> _cleanStudyQueryValues(
  Iterable<String> values, {
  bool uppercase = false,
}) {
  final result = <String>[];
  for (final value in values) {
    var normalized = value.trim();
    if (uppercase) normalized = normalized.toUpperCase();
    if (normalized.isNotEmpty && !result.contains(normalized)) {
      result.add(normalized);
    }
  }
  return result;
}

class MissingGamebaseApiKeyException implements Exception {
  const MissingGamebaseApiKeyException();

  @override
  String toString() {
    return 'Missing GAMEBASE_API_KEY. Generate a personal developer key from '
        'https://chessever.com/developers and pass it with --dart-define or '
        '--dart-define-from-file.';
  }
}

class GamebaseRepository {
  final Dio _dio;
  final String _apiKey;
  final String _baseUrl;

  GamebaseRepository(this._dio, {String? baseUrl, String? apiKey})
    : _baseUrl = baseUrl ?? 'https://service.chessever.com',
      _apiKey = (apiKey ?? _resolveApiKey()).trim();

  static String _resolveApiKey() {
    const releaseKey = String.fromEnvironment(
      'GAMEBASE_API_KEY',
      defaultValue: '',
    );

    if (releaseKey.isNotEmpty) {
      return releaseKey;
    }

    if (kDebugMode) {
      final envKey = dotenv.env['GAMEBASE_API_KEY']?.trim();
      if (envKey != null && envKey.isNotEmpty) return envKey;
    } else {
      if (releaseKey.isNotEmpty) return releaseKey;
    }
    return '';
  }

  bool get hasApiKey => _apiKey.isNotEmpty;

  Map<String, String> get _headers {
    if (!hasApiKey) throw const MissingGamebaseApiKeyException();
    return {'X-API-Key': _apiKey, 'Accept': 'application/json'};
  }

  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    List<String> moves = const [],
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? color,
    String? result,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) async {
    try {
      final normalizedFen = _normalizeFenForLookup(fen);
      final normalizedMoves = _sanitizeMovesForFen(normalizedFen, moves);

      if (kDebugMode &&
          moves.isNotEmpty &&
          normalizedMoves.length != moves.length) {
        debugPrint(
          '[GamebaseRepository] Dropping mismatched move path for aggregates query',
        );
      }

      final body = <String, dynamic>{
        'fen': normalizedFen,
        'moves': normalizedMoves,
        if (playerId != null && playerId.isNotEmpty) 'playerId': playerId,
        if (timeControl != null) 'timeControl': timeControl.name.toUpperCase(),
        if (minRating != null) 'minRating': minRating,
        if (maxRating != null) 'maxRating': maxRating,
        if (color != null) 'color': color,
        if (result != null) 'result': result,
        if (yearFrom != null) 'yearFrom': yearFrom,
        if (yearTo != null) 'yearTo': yearTo,
        if (isOnline != null) 'isOnline': isOnline,
      };

      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getMoveAggregates:');
        debugPrint('  URL: $_baseUrl/api/game-position/aggregates/query');
        debugPrint(
          '  Body: ${{
            ...body,
            // Avoid dumping huge move lists in logs
            if (moves.length > 8) 'moves': '[${moves.length} moves]',
          }}',
        );
      }

      // Use POST /aggregates/query so the backend can compute deep move trees
      // beyond the pre-indexed opening window.
      final response = await _dio.post(
        '$_baseUrl/api/game-position/aggregates/query',
        data: body,
        options: Options(headers: _headers),
      );

      if (kDebugMode) {
        final moves = response.data['data']?['moves'] as List?;
        debugPrint('  Response: ${moves?.length ?? 0} moves returned');
      }

      return GamebaseResponseMapper.fromMap(response.data);
    } on DioException catch (e) {
      // Treat "no data for this position" as an empty result, not an error.
      // This is common for uncommon/midgame positions.
      if (e.response?.statusCode == 404) {
        return const GamebaseResponse(
          status: 'success',
          data: GamebaseData(moves: []),
        );
      }
      throw Exception('Failed to load gamebase stats: $e');
    } catch (e) {
      throw Exception('Failed to load gamebase stats: $e');
    }
  }

  /// Canonicalize FEN for Gamebase lookups.
  ///
  /// The API expects a standard 6-field FEN. Some callers may provide only the
  /// first 4 fields (piece placement, side to move, castling rights, en
  /// passant). In that case, append halfmove/fullmove counters.
  ///
  /// When counters are present, preserve them. Some backends index/look up
  /// positions using the full FEN string; clamping counters can cause misses
  /// for progressed positions.
  static String _normalizeFenForLookup(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return fen.trim();

    if (parts.length == 4) return '${parts.join(' ')} 0 1';
    return parts.take(6).join(' ');
  }

  static String _positionKey(String fen) =>
      fen.trim().split(RegExp(r'\s+')).take(4).join(' ');

  static NormalMove? _normalMoveFromUci(String uci) {
    if (uci.length < 4) return null;

    final from = Square.fromName(uci.substring(0, 2));
    final to = Square.fromName(uci.substring(2, 4));

    Role? promotion;
    if (uci.length > 4) {
      promotion = Role.fromChar(uci[4]);
      if (promotion == null) return null;
    }

    return NormalMove(from: from, to: to, promotion: promotion);
  }

  static List<String> _sanitizeMovesForFen(String fen, List<String> moves) {
    if (moves.isEmpty) return const [];

    final normalizedMoves = moves
        .map((m) => m.trim().toLowerCase())
        .where((m) => RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(m))
        .toList(growable: false);

    if (normalizedMoves.isEmpty) return const [];

    try {
      Position position = Chess.initial;
      final replayed = <String>[];
      for (final uci in normalizedMoves) {
        final move = _normalMoveFromUci(uci);
        if (move == null || !position.isLegal(move)) {
          return const [];
        }
        // dartchess encodes castling king-to-rook (e1h1), but the backend
        // (chess.js) only accepts the standard king-to-g/c UCI. Emit the
        // standard form so deep-path queries (ply > indexed boundary) can
        // replay the move line server-side.
        replayed.add(_toStandardCastlingUci(position, move));
        position = position.play(move);
      }

      // Only require the replayed position to match the target FEN (first 4
      // fields — piece placement / turn / castling / en passant). Do NOT
      // compare move count against _pliesFromFen: variation paths that
      // replace a mainline move result in a move list shorter than the FEN's
      // fullmove-derived ply count, and the old strict equality silently
      // dropped the whole line at depth ≥ 21, collapsing the backend to the
      // position-only path which returns empty past the indexed boundary.
      return _positionKey(position.fen) == _positionKey(fen)
          ? List<String>.unmodifiable(replayed)
          : const [];
    } catch (_) {
      return const [];
    }
  }

  /// Returns the standard king-to-target UCI for a castling move, or the
  /// original [move]'s UCI for any non-castling move.
  ///
  /// dartchess normalizes castling to the Chess960 king-to-rook form (e.g.
  /// `e1h1`), but the Gamebase backend uses chess.js which only recognizes the
  /// classical king-to-g/c form (`e1g1`, `e1c1`, `e8g8`, `e8c8`). Without this
  /// rewrite, any move line containing a castle fails server-side replay and
  /// deep-path queries return empty aggregates.
  static String _toStandardCastlingUci(Position position, NormalMove move) {
    final piece = position.board.pieceAt(move.from);
    if (piece == null || piece.role != Role.king) return move.uci;

    final fromFile = move.from.file;
    final toFile = move.to.file;
    final fileDelta = (fromFile - toFile).abs();

    final targetPiece = position.board.pieceAt(move.to);
    final capturesOwnRook =
        targetPiece != null &&
        targetPiece.role == Role.rook &&
        targetPiece.color == piece.color;

    // File delta of 2+ (standard e1→g1/c1) or capturing own rook (Chess960
    // form e1→h1/a1) both indicate castling. For everything else (e1→f1,
    // e1→e2, etc.) fall through to the original UCI.
    if (fileDelta < 2 && !capturesOwnRook) return move.uci;

    final isKingSide = toFile > fromFile;
    final targetFile = isKingSide ? File.g : File.c;
    final targetSquare = Square.fromCoords(targetFile, move.from.rank);
    return move.from.name + targetSquare.name;
  }

  /// Search players by name.
  /// Note: pageNumber is 0-indexed per the API spec.
  Future<List<GamebasePlayer>> getPlayers({
    String? name,
    String? fideId,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = {
        'pageNumber': pageNumber,
        'pageSize': pageSize,
        if (name != null && name.isNotEmpty) 'name': name,
        if (fideId != null && fideId.isNotEmpty) 'fideId': fideId,
      };

      if (kDebugMode) {
        debugPrint(
          '[GamebaseRepository] getPlayers: name="$name" page=$pageNumber',
        );
      }

      final response = await _dio.get(
        '$_baseUrl/api/player',
        queryParameters: queryParams,
        options: Options(headers: _headers),
      );

      final List data = response.data['data'] ?? [];
      return data.map((e) => GamebasePlayer.fromJson(e)).toList();
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getPlayers DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
        debugPrint('  Response: ${e.response?.data}');
      }
      throw Exception(
        'Failed to search players: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to search players: $e');
    }
  }

  Future<GamebasePlayer?> getPlayerById(String id) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/player/$id',
        options: Options(headers: _headers),
      );

      return GamebasePlayer.fromJson(response.data['data']);
    } catch (e) {
      return null;
    }
  }

  Future<GamebaseGame?> getGameById(String id) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/game/$id',
        options: Options(headers: _headers),
      );

      return GamebaseGame.fromJson(response.data['data']);
    } catch (e) {
      return null;
    }
  }

  /// Fetch a game by ID with full PGN included.
  /// Returns a [GamebaseGameWithPgn] containing the game data and raw PGN.
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async {
    if (kDebugMode) {
      debugPrint('[GamebaseRepository] getGameWithPgn called with id: $id');
    }
    try {
      final response = await _dio.get(
        '$_baseUrl/api/game/$id',
        queryParameters: {'includePgn': true},
        options: Options(headers: _headers),
      );

      final data = response.data['data'];
      if (data == null) {
        if (kDebugMode) {
          debugPrint('[GamebaseRepository] API returned null data for id: $id');
        }
        return null;
      }

      if (kDebugMode) {
        final dataMap = Map<String, dynamic>.from(data);
        debugPrint(
          '[GamebaseRepository] API response keys: ${dataMap.keys.toList()}',
        );
        debugPrint(
          '[GamebaseRepository] pgn present: ${dataMap['pgn'] != null}, length: ${(dataMap['pgn'] as String?)?.length ?? 0}',
        );
        debugPrint(
          '[GamebaseRepository] data field present: ${dataMap['data'] != null}',
        );
        if (dataMap['data'] != null) {
          final innerData = dataMap['data'];
          if (innerData is Map) {
            debugPrint(
              '[GamebaseRepository] inner data keys: ${innerData.keys.toList()}',
            );
          }
        }
      }

      return GamebaseGameWithPgn.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getGameWithPgn DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
        debugPrint('  URL: $_baseUrl/api/game/$id');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getGameWithPgn error: $e');
      }
      return null;
    }
  }

  /// Fetch decisive short-game summaries from the canonical Gamebase index.
  ///
  /// The response is offset-paginated. Returned rows intentionally omit PGN;
  /// use [getGameWithPgn] with [GamebaseMiniature.canonicalGameId] before
  /// opening a row as a complete game.
  Future<GamebaseMiniaturesPage> getMiniatures({
    MiniatureGamesFilter filter = MiniatureGamesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/miniatures',
        queryParameters: filter.queryParameters(limit: limit, offset: offset),
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw const FormatException(
          'Invalid miniatures response: expected a JSON object.',
        );
      }
      return GamebaseMiniaturesPage.fromJson(Map<String, dynamic>.from(data));
    } on FormatException {
      rethrow;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getMiniatures DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
        debugPrint('  Response: ${e.response?.data}');
      }
      throw Exception(
        'Failed to load miniatures: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to load miniatures: $e');
    }
  }

  /// List credibility-gated, active Lichess Study summaries from Gamebase.
  Future<GamebaseStudiesPage> getStudies({
    GamebaseStudiesFilter filter = GamebaseStudiesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = filter.queryParameters(limit: limit, offset: offset);
    try {
      final response = await _dio.get(
        '$_baseUrl/api/studies',
        queryParameters: query,
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw const GamebaseStudyContractException(
          'Invalid list Studies response: expected a JSON object.',
        );
      }
      return GamebaseStudiesPage.fromJson(Map<String, dynamic>.from(data));
    } on GamebaseStudyContractException {
      rethrow;
    } on DioException catch (error) {
      throw GamebaseStudyRequestException(
        operation: 'list Studies',
        message: error.message ?? 'Network request failed.',
        statusCode: error.response?.statusCode,
        cause: error,
      );
    } catch (error) {
      throw GamebaseStudyRequestException(
        operation: 'list Studies',
        message: 'Unexpected request failure.',
        cause: error,
      );
    }
  }

  /// Fetch Study metadata and ordered chapter metadata without PGN bodies.
  Future<GamebaseStudyDetail> getStudy(String lichessStudyId) async {
    final normalizedId = lichessStudyId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(
        lichessStudyId,
        'lichessStudyId',
        'Must not be empty.',
      );
    }

    try {
      final response = await _dio.get(
        '$_baseUrl/api/studies/${Uri.encodeComponent(normalizedId)}',
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw const GamebaseStudyContractException(
          'Invalid get Study response: expected a JSON object.',
        );
      }
      return GamebaseStudyDetail.fromJson(Map<String, dynamic>.from(data));
    } on GamebaseStudyContractException {
      rethrow;
    } on DioException catch (error) {
      throw GamebaseStudyRequestException(
        operation: 'get Study',
        message: error.message ?? 'Network request failed.',
        statusCode: error.response?.statusCode,
        cause: error,
      );
    } catch (error) {
      throw GamebaseStudyRequestException(
        operation: 'get Study',
        message: 'Unexpected request failure.',
        cause: error,
      );
    }
  }

  Future<CloudEval?> getEvalByFen(String fen) async {
    try {
      final normalizedFen = _normalizeEvalFenForLookup(fen);
      final response = await _dio.get(
        '$_baseUrl/api/eval',
        queryParameters: {'fen': normalizedFen},
        options: Options(headers: _headers),
      );

      if (response.data['status'] == 'success') {
        return CloudEval.fromJson(
          Map<String, dynamic>.from(response.data['data']),
        );
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getEvalByFen error: $e');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getEvalByFen error: $e');
      }
      return null;
    }
  }

  /// Canonicalize FEN for the eval endpoint.
  ///
  /// The backend accepts either 6-field or normalized 4-field FENs, but the
  /// client always sends the canonical 4-field form for stable cache keys.
  ///
  /// The eval service keys positions by the first four FEN fields only:
  /// board, side to move, castling rights, en passant square.
  static String _normalizeEvalFenForLookup(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return fen.trim();
    return parts.take(4).join(' ');
  }

  Future<GamebaseSearchMetadata> getSearchMetadata() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/search/metadata',
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }

      final map = Map<String, dynamic>.from(data);
      // The backend returns { status: "success", data: { resources: [...] } }
      // So we need to dig into 'data' first.
      final payload = map['data'];
      if (payload is! Map) {
        throw Exception('Unexpected response payload');
      }

      return GamebaseSearchMetadata.fromJson(
        Map<String, dynamic>.from(payload),
      );
    } catch (e) {
      throw Exception('Failed to load search metadata: $e');
    }
  }

  Future<GamebaseSearchQueryResponse> queryResource({
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/api/search/query',
        data: body,
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseSearchQueryResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } catch (e) {
      throw Exception('Failed to query resource: $e');
    }
  }

  /// Fetch the synthesized event view for an exact event [name] from the
  /// gamebase (`GET /api/event`). Returns null when the event has no games.
  /// [refresh] forces a server-side rebuild + cache rewarm — used while
  /// verifying the view before the one-week cache is trusted.
  Future<GamebaseEventView?> getEventView(
    String name, {
    String? site,
    String? slug,
    bool refresh = false,
  }) async {
    try {
      final trimmedSite = site?.trim();
      final trimmedSlug = slug?.trim();
      final response = await _dio.get(
        '$_baseUrl/api/event',
        queryParameters: {
          'name': name,
          if (trimmedSite != null && trimmedSite.isNotEmpty)
            'site': trimmedSite,
          if (trimmedSlug != null && trimmedSlug.isNotEmpty)
            'slug': trimmedSlug,
          if (refresh) 'refresh': true,
        },
        options: Options(headers: _headers),
      );

      final body = response.data;
      if (body is! Map) return null;
      final data = body['data'];
      if (data is! Map) return null;
      return GamebaseEventView.fromData(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      // 404 = event not present in the gamebase. Treat as "no view".
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<GamebaseGlobalSearchResponse> globalSearch({
    required String query,
    List<String>? resources,
    int pageNumber = 1,
    int pageSize = 20,
    String? result,
    String? color,
    String? timeControl,
    int? yearFrom,
    int? yearTo,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
  }) async {
    try {
      final queryParams = {
        'q': query,
        'pageNumber': pageNumber,
        'pageSize': pageSize,
        if (resources != null) 'resources': resources,
        if (result != null) 'result': result,
        if (color != null) 'color': color,
        if (timeControl != null) 'timeControl': timeControl,
        if (yearFrom != null) 'yearFrom': yearFrom,
        if (yearTo != null) 'yearTo': yearTo,
        if (ratingFrom != null) 'ratingFrom': ratingFrom,
        if (ratingTo != null) 'ratingTo': ratingTo,
        if (isOnline != null) 'isOnline': isOnline,
      };

      if (kDebugMode) {
        debugPrint(
          '[GamebaseRepository] globalSearch: q="$query" page=$pageNumber',
        );
      }

      final response = await _dio.get(
        '$_baseUrl/api/search',
        queryParameters: queryParams,
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseGlobalSearchResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] globalSearch DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
        debugPrint('  Response: ${e.response?.data}');
      }
      throw Exception(
        'Failed to perform global search: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to perform global search: $e');
    }
  }

  Future<GamebaseEventSearchResponse> searchEvents({
    required String query,
    int pageNumber = 1,
    int pageSize = 20,
    String? result,
    String? color,
    String? timeControl,
    int? yearFrom,
    int? yearTo,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
  }) async {
    try {
      final queryParams = {
        'q': query,
        'pageNumber': pageNumber,
        'pageSize': pageSize,
        if (result != null) 'result': result,
        if (color != null) 'color': color,
        if (timeControl != null) 'timeControl': timeControl,
        if (yearFrom != null) 'yearFrom': yearFrom,
        if (yearTo != null) 'yearTo': yearTo,
        if (ratingFrom != null) 'ratingFrom': ratingFrom,
        if (ratingTo != null) 'ratingTo': ratingTo,
        if (isOnline != null) 'isOnline': isOnline,
      };

      final response = await _dio.get(
        '$_baseUrl/api/search/events',
        queryParameters: queryParams,
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseEventSearchResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] searchEvents DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
        debugPrint('  Response: ${e.response?.data}');
      }
      throw Exception(
        'Failed to search events: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to search events: $e');
    }
  }

  /// Fetch events for a specific player using player-id scoped aggregation.
  /// Maps to GET /api/player/{playerId}/events.
  ///
  /// [pageNumber] is 0-indexed, matching the other player endpoints.
  Future<GamebaseEventSearchResponse> getPlayerEvents({
    required String playerId,
    String? q,
    String color = 'all',
    String? timeControl,
    String? outcome,
    String? eco,
    String? opening,
    String? variation,
    String? event,
    String? site,
    String? dateFrom,
    String? dateTo,
    String? opponentId,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
    int pageNumber = 0,
    int pageSize = 24,
  }) async {
    final queryParams = <String, dynamic>{
      'color': color,
      if (q != null && q.isNotEmpty) 'q': q,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
      if (timeControl != null) 'timeControl': timeControl,
      if (outcome != null) 'outcome': outcome,
      if (eco != null) 'eco': eco,
      if (opening != null) 'opening': opening,
      if (variation != null) 'variation': variation,
      if (event != null) 'event': event,
      if (site != null) 'site': site,
      if (dateFrom != null) 'dateFrom': dateFrom,
      if (dateTo != null) 'dateTo': dateTo,
      if (opponentId != null) 'opponentId': opponentId,
      if (ratingFrom != null) 'ratingFrom': ratingFrom,
      if (ratingTo != null) 'ratingTo': ratingTo,
      if (isOnline != null) 'isOnline': isOnline,
    };

    if (kDebugMode) {
      debugPrint(
        '[GamebaseRepository] getPlayerEvents: playerId=$playerId filters=$queryParams',
      );
    }

    try {
      final response = await _dio.get(
        '$_baseUrl/api/player/$playerId/events',
        queryParameters: queryParams,
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseEventSearchResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getPlayerEvents DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
        debugPrint('  Response: ${e.response?.data}');
      }
      throw Exception(
        'Failed to load player events: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to load player events: $e');
    }
  }

  /// Fetch games for a specific player with server-side filtering.
  /// Maps to GET /api/player/{playerId}/games.
  ///
  /// [pageNumber] is 0-indexed (unlike globalSearch which is 1-indexed).
  /// [outcome] uses 'win'/'loss'/'draw' (player perspective, not W/B/D).
  Future<Map<String, dynamic>> getPlayerGames({
    required String playerId,
    String? q,
    String color = 'all',
    String? timeControl,
    String? outcome,
    String? eco,
    String? opening,
    String? variation,
    String? event,
    String? site,
    String? dateFrom,
    String? dateTo,
    String? opponentId,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
    int pageNumber = 0,
    int pageSize = 100,
  }) async {
    final queryParams = <String, dynamic>{
      'color': color,
      if (q != null && q.isNotEmpty) 'q': q,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
      if (timeControl != null) 'timeControl': timeControl,
      if (outcome != null) 'outcome': outcome,
      if (eco != null) 'eco': eco,
      if (opening != null) 'opening': opening,
      if (variation != null) 'variation': variation,
      if (event != null) 'event': event,
      if (site != null) 'site': site,
      if (dateFrom != null) 'dateFrom': dateFrom,
      if (dateTo != null) 'dateTo': dateTo,
      if (opponentId != null) 'opponentId': opponentId,
      if (ratingFrom != null) 'ratingFrom': ratingFrom,
      if (ratingTo != null) 'ratingTo': ratingTo,
      if (isOnline != null) 'isOnline': isOnline,
    };

    if (kDebugMode) {
      debugPrint(
        '[GamebaseRepository] getPlayerGames: playerId=$playerId filters=$queryParams',
      );
    }

    final response = await _dio.get(
      '$_baseUrl/api/player/$playerId/games',
      queryParameters: queryParams,
      options: Options(headers: _headers),
    );

    return Map<String, dynamic>.from(response.data);
  }

  /// Fetch exact aggregated stats for a specific player with server-side filters.
  /// Maps to GET /api/player/{playerId}/stats.
  Future<Map<String, dynamic>> getPlayerStats({
    required String playerId,
    String? q,
    String color = 'all',
    String? timeControl,
    String? outcome,
    String? eco,
    String? opening,
    String? variation,
    String? event,
    String? site,
    String? dateFrom,
    String? dateTo,
    String? opponentId,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
  }) async {
    final queryParams = <String, dynamic>{
      'color': color,
      if (q != null && q.isNotEmpty) 'q': q,
      if (timeControl != null) 'timeControl': timeControl,
      if (outcome != null) 'outcome': outcome,
      if (eco != null) 'eco': eco,
      if (opening != null) 'opening': opening,
      if (variation != null) 'variation': variation,
      if (event != null) 'event': event,
      if (site != null) 'site': site,
      if (dateFrom != null) 'dateFrom': dateFrom,
      if (dateTo != null) 'dateTo': dateTo,
      if (opponentId != null) 'opponentId': opponentId,
      if (ratingFrom != null) 'ratingFrom': ratingFrom,
      if (ratingTo != null) 'ratingTo': ratingTo,
      if (isOnline != null) 'isOnline': isOnline,
    };

    final response = await _dio.get(
      '$_baseUrl/api/player/$playerId/stats',
      queryParameters: queryParams,
      options: Options(headers: _headers),
    );

    return Map<String, dynamic>.from(response.data);
  }

  /// Start or reuse a backend-built player opening tree.
  Future<Map<String, dynamic>> startPlayerOpeningTreeBuild({
    required String playerId,
    int maxPly = 24,
    bool forceRebuild = false,
  }) async {
    final response = await _dio.post(
      '$_baseUrl/api/player/$playerId/opening-tree/build',
      data: <String, dynamic>{'maxPly': maxPly, 'forceRebuild': forceRebuild},
      options: Options(headers: _headers),
    );
    return Map<String, dynamic>.from(response.data);
  }

  /// Poll the backend player opening tree build status.
  Future<Map<String, dynamic>> getPlayerOpeningTreeStatus({
    required String playerId,
    required String treeId,
  }) async {
    final response = await _dio.get(
      '$_baseUrl/api/player/$playerId/opening-tree/status',
      queryParameters: <String, dynamic>{'treeId': treeId},
      options: Options(headers: _headers),
    );
    return Map<String, dynamic>.from(response.data);
  }

  /// Download a ready backend player opening tree.
  ///
  /// Returns `null` when the backend responds with HTTP 202, meaning the tree is
  /// still being prepared.
  Future<Map<String, dynamic>?> getPlayerOpeningTree({
    required String playerId,
    required String treeId,
  }) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/player/$playerId/opening-tree',
        queryParameters: <String, dynamic>{'treeId': treeId},
        options: Options(headers: _headers),
      );
      if (response.statusCode == 202) return null;
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 202) return null;
      rethrow;
    }
  }

  /// List example games for a given position (and optionally a specific move from that position).
  ///
  /// Pagination is 0-indexed per the API spec for this endpoint.
  Future<GamebaseSearchQueryResponse> getPositionGames({
    required String fen,
    List<String> moves = const [],
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    try {
      final normalizedFen = _normalizeFenForLookup(fen);
      final normalizedMoves = _sanitizeMovesForFen(normalizedFen, moves);

      if (kDebugMode &&
          moves.isNotEmpty &&
          normalizedMoves.length != moves.length) {
        debugPrint(
          '[GamebaseRepository] Dropping mismatched move path for games query',
        );
      }

      final orderBy =
          sortBy != null
              ? [
                {
                  'field': sortBy.name,
                  'direction':
                      sortDirection == GamebaseSortDirection.asc
                          ? 'asc'
                          : 'desc',
                },
              ]
              : null;

      final response =
          normalizedMoves.isNotEmpty
              ? await _dio.post(
                '$_baseUrl/api/game-position/games/query',
                data: {
                  'fen': normalizedFen,
                  'moves': normalizedMoves,
                  'pageNumber': pageNumber,
                  'pageSize': pageSize,
                  if (uci != null && uci.trim().isNotEmpty) 'uci': uci.trim(),
                  if (playerId != null && playerId.trim().isNotEmpty)
                    'playerId': playerId.trim(),
                  if (timeControl != null)
                    'timeControl': timeControl.name.toUpperCase(),
                  if (minRating != null) 'minRating': minRating,
                  if (maxRating != null) 'maxRating': maxRating,
                  if (color != null) 'color': color,
                  if (result != null) 'result': result,
                  if (yearFrom != null) 'yearFrom': yearFrom,
                  if (yearTo != null) 'yearTo': yearTo,
                  if (isOnline != null) 'isOnline': isOnline,
                  if (orderBy != null) 'orderBy': orderBy,
                  if (sortBy != null) 'sortBy': sortBy.name,
                  if (sortDirection != null)
                    'sortDirection': sortDirection.name,
                },
                options: Options(headers: _headers),
              )
              : await _dio.get(
                '$_baseUrl/api/game-position/games',
                queryParameters: {
                  'fen': normalizedFen,
                  'pageNumber': pageNumber,
                  'pageSize': pageSize,
                  if (uci != null && uci.trim().isNotEmpty) 'uci': uci.trim(),
                  if (playerId != null && playerId.trim().isNotEmpty)
                    'playerId': playerId.trim(),
                  if (timeControl != null)
                    'timeControl': timeControl.name.toUpperCase(),
                  if (minRating != null) 'minRating': minRating,
                  if (maxRating != null) 'maxRating': maxRating,
                  if (color != null) 'color': color,
                  if (result != null) 'result': result,
                  if (yearFrom != null) 'yearFrom': yearFrom,
                  if (yearTo != null) 'yearTo': yearTo,
                  if (isOnline != null) 'isOnline': isOnline,
                  if (sortBy != null) 'sortBy': sortBy.name,
                  if (sortDirection != null)
                    'sortDirection': sortDirection.name,
                },
                options: Options(headers: _headers),
              );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseSearchQueryResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } catch (e) {
      throw Exception('Failed to load position games: $e');
    }
  }

  /// List games containing the exact FEN position, independent of move order.
  ///
  /// Uses the FEN-specific endpoint so pasted/custom positions can be searched
  /// directly without requiring a move aggregate or next-move selection. Filter
  /// and sort surface mirrors `getPositionGames` — see the OpenAPI spec for
  /// `/api/game-position/fen/games` (and the POST `/query` variant for
  /// multi-key sort via `orderBy`).
  Future<GamebaseSearchQueryResponse> getFenPositionGames({
    required String fen,
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    try {
      final normalizedFen = _normalizeFenForLookup(fen);
      final response = await _dio.get(
        '$_baseUrl/api/game-position/fen/games',
        queryParameters: {
          'fen': normalizedFen,
          'pageNumber': pageNumber,
          'pageSize': pageSize,
          if (uci != null && uci.trim().isNotEmpty) 'uci': uci.trim(),
          if (playerId != null && playerId.trim().isNotEmpty)
            'playerId': playerId.trim(),
          if (timeControl != null)
            'timeControl': timeControl.name.toUpperCase(),
          if (minRating != null) 'minRating': minRating,
          if (maxRating != null) 'maxRating': maxRating,
          if (color != null) 'color': color,
          if (result != null) 'result': result,
          if (yearFrom != null) 'yearFrom': yearFrom,
          if (yearTo != null) 'yearTo': yearTo,
          if (isOnline != null) 'isOnline': isOnline,
          if (sortBy != null) 'sortBy': sortBy.name,
          if (sortDirection != null) 'sortDirection': sortDirection.name,
        },
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseSearchQueryResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return GamebaseSearchQueryResponse(
          status: 'success',
          data: const [],
          metadata: GamebasePaginationMetadata(
            pageNumber: pageNumber,
            pageSize: pageSize,
            hasMoreValue: false,
          ),
        );
      }
      throw Exception('Failed to load FEN position games: $e');
    } catch (e) {
      throw Exception('Failed to load FEN position games: $e');
    }
  }
}

final gamebaseRepositoryProvider = Provider<GamebaseRepository>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  dio.interceptors.add(LogarteDioInterceptor(logarte));
  return GamebaseRepository(dio);
});

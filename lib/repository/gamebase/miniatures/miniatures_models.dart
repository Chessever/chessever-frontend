import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// Models for the community Miniatures database (`GET /api/miniatures`).
///
/// Ported from the desktop app's miniatures implementation so mobile mirrors
/// its capabilities 1:1: window, sort/order, free-text search, and the full
/// filter set (result, ECO/opening/variation, time control, rating, move
/// count, date range).

enum MiniatureGamesWindow {
  today,
  week,
  all;

  String get apiValue => name;

  String get label {
    return switch (this) {
      MiniatureGamesWindow.today => 'Today',
      MiniatureGamesWindow.week => 'Week',
      MiniatureGamesWindow.all => 'All time',
    };
  }
}

enum MiniatureGamesSort {
  rating,
  moves,
  recent;

  String get apiValue => name;

  String get label {
    return switch (this) {
      MiniatureGamesSort.rating => 'Strongest',
      MiniatureGamesSort.moves => 'Fewest moves',
      MiniatureGamesSort.recent => 'Most recent',
    };
  }
}

enum MiniatureGamesSortOrder {
  asc,
  desc;

  String get apiValue => name;
}

enum MiniatureGameResult {
  whiteWins,
  blackWins;

  String get apiValue {
    return switch (this) {
      MiniatureGameResult.whiteWins => 'W',
      MiniatureGameResult.blackWins => 'B',
    };
  }

  String get label {
    return switch (this) {
      MiniatureGameResult.whiteWins => 'White wins',
      MiniatureGameResult.blackWins => 'Black wins',
    };
  }
}

enum MiniatureGameTimeControl {
  classical,
  rapid,
  blitz;

  String get apiValue => name.toUpperCase();

  String get label {
    return switch (this) {
      MiniatureGameTimeControl.classical => 'Classical',
      MiniatureGameTimeControl.rapid => 'Rapid',
      MiniatureGameTimeControl.blitz => 'Blitz',
    };
  }
}

class MiniatureGamesFilter {
  const MiniatureGamesFilter({
    this.window = MiniatureGamesWindow.all,
    this.sort = MiniatureGamesSort.recent,
    this.order = MiniatureGamesSortOrder.desc,
    this.search,
    this.results = const <MiniatureGameResult>{},
    this.eco,
    this.opening,
    this.variation,
    this.ecoCategories = const <String>{},
    this.timeControls = const <MiniatureGameTimeControl>{},
    this.isOnline,
    this.minRating,
    this.maxRating,
    this.minMoves,
    this.maxMoves,
    this.dateFrom,
    this.dateTo,
    this.player,
  });

  final MiniatureGamesWindow window;
  final MiniatureGamesSort sort;
  final MiniatureGamesSortOrder order;
  final String? search;
  final Set<MiniatureGameResult> results;
  final String? eco;
  final String? opening;
  final String? variation;
  final Set<String> ecoCategories;
  final Set<MiniatureGameTimeControl> timeControls;
  final bool? isOnline;
  final int? minRating;
  final int? maxRating;
  final int? minMoves;
  final int? maxMoves;
  final String? dateFrom;
  final String? dateTo;
  final String? player;

  static const defaultFilter = MiniatureGamesFilter();

  bool get hasActiveFilters => activeFilterCount > 0;

  /// Count of everything that narrows the backend query (desktop parity).
  int get activeFilterCount {
    var count = 0;
    if (window != MiniatureGamesWindow.all) count += 1;
    if (results.isNotEmpty) count += 1;
    if (_cleanCsv(eco) != null) count += 1;
    if (_cleanText(opening) != null) count += 1;
    if (_cleanText(variation) != null) count += 1;
    if (ecoCategories.isNotEmpty) count += 1;
    if (timeControls.isNotEmpty) count += 1;
    if (isOnline != null) count += 1;
    if (minRating != null || maxRating != null) count += 1;
    if (minMoves != null || maxMoves != null) count += 1;
    if (_cleanDate(dateFrom) != null || _cleanDate(dateTo) != null) count += 1;
    if (_cleanText(player) != null) count += 1;
    return count;
  }

  /// Count shown on the filter-dialog badge. The window has its own segmented
  /// control on mobile, so it is excluded here.
  int get dialogFilterCount {
    final windowActive = window != MiniatureGamesWindow.all ? 1 : 0;
    return activeFilterCount - windowActive;
  }

  MiniatureGamesFilter copyWith({
    MiniatureGamesWindow? window,
    MiniatureGamesSort? sort,
    MiniatureGamesSortOrder? order,
    String? search,
    bool clearSearch = false,
    Set<MiniatureGameResult>? results,
    String? eco,
    bool clearEco = false,
    String? opening,
    bool clearOpening = false,
    String? variation,
    bool clearVariation = false,
    Set<String>? ecoCategories,
    Set<MiniatureGameTimeControl>? timeControls,
    bool? isOnline,
    bool clearOnline = false,
    int? minRating,
    int? maxRating,
    bool clearRating = false,
    int? minMoves,
    int? maxMoves,
    bool clearMoves = false,
    String? dateFrom,
    String? dateTo,
    bool clearDates = false,
    String? player,
    bool clearPlayer = false,
  }) {
    return MiniatureGamesFilter(
      window: window ?? this.window,
      sort: sort ?? this.sort,
      order: order ?? this.order,
      search: clearSearch ? null : (search ?? this.search),
      results: results ?? this.results,
      eco: clearEco ? null : (eco ?? this.eco),
      opening: clearOpening ? null : (opening ?? this.opening),
      variation: clearVariation ? null : (variation ?? this.variation),
      ecoCategories: ecoCategories ?? this.ecoCategories,
      timeControls: timeControls ?? this.timeControls,
      isOnline: clearOnline ? null : (isOnline ?? this.isOnline),
      minRating: clearRating ? null : (minRating ?? this.minRating),
      maxRating: clearRating ? null : (maxRating ?? this.maxRating),
      minMoves: clearMoves ? null : (minMoves ?? this.minMoves),
      maxMoves: clearMoves ? null : (maxMoves ?? this.maxMoves),
      dateFrom: clearDates ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDates ? null : (dateTo ?? this.dateTo),
      player: clearPlayer ? null : (player ?? this.player),
    );
  }

  Map<String, dynamic> queryParameters({
    required int limit,
    required int offset,
  }) {
    final query = <String, dynamic>{
      'window': window.apiValue,
      'sort': sort.apiValue,
      'order': order.apiValue,
      'limit': limit,
      'offset': offset,
    };

    final normalizedSearch = _cleanText(search);
    if (normalizedSearch != null) query['q'] = normalizedSearch;
    if (results.isNotEmpty) {
      query['result'] = results.map((result) => result.apiValue).join(',');
    }
    final normalizedEco = _cleanCsv(eco);
    if (normalizedEco != null) query['eco'] = normalizedEco;
    final normalizedOpening = _cleanText(opening);
    if (normalizedOpening != null) query['opening'] = normalizedOpening;
    final normalizedVariation = _cleanText(variation);
    if (normalizedVariation != null) query['variation'] = normalizedVariation;
    if (ecoCategories.isNotEmpty) {
      query['ecoCategory'] = ecoCategories
          .map((c) => c.toUpperCase())
          .join(',');
    }
    if (timeControls.isNotEmpty) {
      query['timeControl'] = timeControls
          .map((control) => control.apiValue)
          .join(',');
    }
    if (isOnline != null) query['isOnline'] = isOnline;
    if (minRating != null) query['minRating'] = minRating;
    if (maxRating != null) query['maxRating'] = maxRating;
    if (minMoves != null) query['minMoves'] = minMoves;
    if (maxMoves != null) query['maxMoves'] = maxMoves;
    final (:from, :to) = _cleanDateRange(dateFrom: dateFrom, dateTo: dateTo);
    if (from != null) query['dateFrom'] = from;
    if (to != null) query['dateTo'] = to;
    final normalizedPlayer = _cleanText(player);
    if (normalizedPlayer != null) query['player'] = normalizedPlayer;

    return query;
  }

  static String? _cleanText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _cleanCsv(String? value) {
    final parts =
        value
            ?.split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    return parts.isEmpty ? null : parts.join(',');
  }

  static String? _cleanDate(String? value) {
    final trimmed = _cleanText(value);
    if (trimmed == null) return null;
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed) ? trimmed : null;
  }

  static ({String? from, String? to}) _cleanDateRange({
    required String? dateFrom,
    required String? dateTo,
  }) {
    final from = _cleanDate(dateFrom);
    final to = _cleanDate(dateTo);
    if (from != null && to != null && from.compareTo(to) > 0) {
      return (from: to, to: from);
    }
    return (from: from, to: to);
  }

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MiniatureGamesFilter &&
        other.window == window &&
        other.sort == sort &&
        other.order == order &&
        other.search == search &&
        _setEquals(other.results, results) &&
        other.eco == eco &&
        other.opening == opening &&
        other.variation == variation &&
        _setEquals(other.ecoCategories, ecoCategories) &&
        _setEquals(other.timeControls, timeControls) &&
        other.isOnline == isOnline &&
        other.minRating == minRating &&
        other.maxRating == maxRating &&
        other.minMoves == minMoves &&
        other.maxMoves == maxMoves &&
        other.dateFrom == dateFrom &&
        other.dateTo == dateTo &&
        other.player == player;
  }

  @override
  int get hashCode => Object.hash(
    window,
    sort,
    order,
    search,
    Object.hashAllUnordered(results),
    eco,
    opening,
    variation,
    Object.hashAllUnordered(ecoCategories),
    Object.hashAllUnordered(timeControls),
    isOnline,
    minRating,
    maxRating,
    minMoves,
    maxMoves,
    dateFrom,
    dateTo,
    player,
  );
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

  bool get hasMore => offset + items.length < total;

  factory GamebaseMiniaturesPage.fromJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json['data'] as Map? ?? const {});
    return GamebaseMiniaturesPage(
      items:
          (data['items'] as List?)
              ?.whereType<Map>()
              .map(
                (item) =>
                    GamebaseMiniature.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false) ??
          const <GamebaseMiniature>[],
      total: _readInt(data['total']),
      limit: _readInt(data['limit']),
      offset: _readInt(data['offset']),
    );
  }
}

class GamebaseMiniature {
  const GamebaseMiniature({
    required this.gameId,
    this.avgRating,
    required this.plyCount,
    required this.finalMoveNumber,
    required this.result,
    required this.timeControl,
    required this.isOnline,
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

  /// Decisive result only: 'W' (white wins) or 'B' (black wins).
  final String result;
  final String timeControl; // CLASSICAL | RAPID | BLITZ
  final bool isOnline;
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

  factory GamebaseMiniature.fromJson(Map<String, dynamic> json) {
    return GamebaseMiniature(
      gameId: _readString(json['gameId']),
      avgRating: _readNullableInt(json['avgRating']),
      plyCount: _readInt(json['plyCount']),
      finalMoveNumber: _readInt(json['finalMoveNumber']),
      result: _readString(json['result']),
      timeControl: _readString(json['timeControl']),
      isOnline: _readBool(json['isOnline']),
      date: _readDate(json['date']),
      event: _readNullableString(json['event']),
      eco: _readNullableString(json['eco']),
      ecoCategory: _readNullableString(json['ecoCategory']),
      opening: _readNullableString(json['opening']),
      variation: _readNullableString(json['variation']),
      whiteName: _readNullableString(json['whiteName']),
      blackName: _readNullableString(json['blackName']),
      whiteElo: _readNullableInt(json['whiteElo']),
      blackElo: _readNullableInt(json['blackElo']),
      whitePlayerId: _readNullableString(json['whitePlayerId']),
      blackPlayerId: _readNullableString(json['blackPlayerId']),
      whiteFed: _readNullableString(json['whiteFed']),
      blackFed: _readNullableString(json['blackFed']),
    );
  }

  GameStatus get status => GameStatus.fromString(result);

  String? get openingDisplayName {
    final openingClean = (opening ?? '').trim();
    final variationClean = (variation ?? '').trim();
    if (openingClean.isEmpty) return null;
    if (variationClean.isEmpty) return openingClean;
    return '$openingClean: $variationClean';
  }

  /// Builds the board-ready model. Source is [GameSource.gamebase] so the
  /// viewer treats it as a master-database game; the full PGN is fetched by
  /// [gameId] on open, with this header-only PGN as a fallback (mirrors the
  /// desktop `_miniatureToGame` mapping).
  GamesTourModel toGamesTourModel() {
    final ecoClean = (eco ?? '').trim();
    final eventClean = (event ?? '').trim();
    final whiteClean = (whiteName ?? '').trim();
    final blackClean = (blackName ?? '').trim();

    final fallbackPgn = buildHeaderOnlyPgn(
      whiteName: whiteClean,
      blackName: blackClean,
      result: result,
      event: eventClean.isNotEmpty ? eventClean : 'Miniatures',
      date: date,
      eco: ecoClean.isNotEmpty ? ecoClean : null,
      opening: opening,
      variation: variation,
    );

    return GamesTourModel(
      gameId: gameId,
      source: GameSource.gamebase,
      whitePlayer: PlayerCard(
        name: whiteClean.isNotEmpty ? whiteClean : 'White',
        federation: whiteFed ?? '',
        title: '',
        rating: whiteElo ?? 0,
        countryCode: whiteFed ?? '',
        team: null,
        gamebasePlayerId: whitePlayerId,
      ),
      blackPlayer: PlayerCard(
        name: blackClean.isNotEmpty ? blackClean : 'Black',
        federation: blackFed ?? '',
        title: '',
        rating: blackElo ?? 0,
        countryCode: blackFed ?? '',
        team: null,
        gamebasePlayerId: blackPlayerId,
      ),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: status,
      roundId: 'gamebase-miniatures',
      roundSlug: ecoClean.isNotEmpty ? ecoClean : null,
      tourId: eventClean.isNotEmpty ? eventClean : 'Miniatures',
      tourSlug: null,
      pgn: fallbackPgn,
      // Miniatures have no event board number; reuse this sortable slot for
      // the final move number (desktop does the same).
      boardNr: finalMoveNumber > 0 ? finalMoveNumber : null,
      lastMoveTime: date,
      dateStart: date,
      gameDay: date,
      eco: ecoClean.isNotEmpty ? ecoClean : null,
      openingName: openingDisplayName,
      timeControl: timeControl.trim().isNotEmpty ? timeControl.trim() : null,
      avgElo: avgRating,
      isOnline: isOnline,
    );
  }
}

String _readString(Object? value) => value?.toString().trim() ?? '';

String? _readNullableString(Object? value) {
  final trimmed = _readString(value);
  return trimmed.isEmpty ? null : trimmed;
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _readNullableInt(Object? value) {
  if (value == null) return null;
  return _readInt(value);
}

bool _readBool(Object? value) {
  if (value is bool) return value;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1';
}

DateTime? _readDate(Object? value) {
  final raw = _readNullableString(value);
  return raw == null ? null : DateTime.tryParse(raw);
}

import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/gamebase/memorial_player_local_search.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _recentSearchesStorageKey = 'home_search_recent_destinations_v1';
const _recentSearchesLimit = 6;

enum RecentSearchKind { tournament, player, opening }

@immutable
class RecentSearchEntry {
  const RecentSearchEntry({
    required this.kind,
    required this.targetId,
    required this.title,
    required this.subtitle,
    this.data = const {},
  });

  factory RecentSearchEntry.tournament(GroupEventCardModel tournament) {
    return RecentSearchEntry(
      kind: RecentSearchKind.tournament,
      targetId: tournament.id,
      title: tournament.title,
      subtitle: tournament.dates,
      data: {
        'maxAvgElo': tournament.maxAvgElo,
        'timeUntilStart': tournament.timeUntilStart,
        'tourEventCategory': tournament.tourEventCategory.name,
        'timeControl': tournament.timeControl,
        'endDate': tournament.endDate?.toIso8601String(),
        'startDate': tournament.startDate?.toIso8601String(),
        'location': tournament.location,
        'searchTerms': tournament.searchTerms,
        'eventSource': tournament.eventSource.name,
        'isMajorUpcoming': tournament.isMajorUpcoming,
      },
    );
  }

  factory RecentSearchEntry.player(SearchPlayer player) {
    final fideId = player.fideId;
    final memorialRouteId = player.memorialRouteId?.trim();
    return RecentSearchEntry(
      kind: RecentSearchKind.player,
      targetId:
          memorialRouteId?.isNotEmpty == true
              ? 'memorial:$memorialRouteId'
              : fideId != null && fideId > 0
              ? 'fide:$fideId'
              : 'name:${player.name.trim().toLowerCase()}',
      title: player.name,
      subtitle: [
        if (player.title?.isNotEmpty == true) player.title!,
        if (player.rating != null) '${player.rating}',
        if (player.fed?.isNotEmpty == true) player.fed!,
      ].join(' · '),
      data: {
        'id': player.id,
        'title': player.title,
        'rating': player.rating,
        'fideId': player.fideId,
        'fed': player.fed,
        'tournamentId': player.tournamentId,
        'tournamentName': player.tournamentName,
        'gameId': player.gameId,
        'roundId': player.roundId,
        'isWhitePlayer': player.isWhitePlayer,
        'gamebasePlayerId': player.gamebasePlayerId,
        'memorialSourceIdentity': player.memorialSourceIdentity,
        'memorialRouteId': player.memorialRouteId,
      },
    );
  }

  factory RecentSearchEntry.opening(GameEcoFilter eco) {
    return RecentSearchEntry.openingSelection(
      OpeningSearchSelection.forFilter(eco),
    );
  }

  factory RecentSearchEntry.openingSelection(OpeningSearchSelection opening) {
    final eco = opening.filter;
    final code = eco.code!;
    final family = EcoOpenings.getFamily(code);
    return RecentSearchEntry(
      kind: RecentSearchKind.opening,
      targetId: code,
      title:
          opening.hierarchyLabel.isEmpty
              ? eco.openingName ?? code
              : opening.hierarchyLabel,
      subtitle:
          family == null
              ? code
              : family.codePrefixes.length == 1
              ? '$code · ${family.rangeLabel}'
              : family.rangeLabel,
      data: {
        'hierarchyLabel': opening.hierarchyLabel,
        'movePath': opening.movePath,
        'isAggregate': opening.isAggregate,
      },
    );
  }

  factory RecentSearchEntry.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind']?.toString();
    final kind = RecentSearchKind.values.where((item) => item.name == kindName);
    if (kind.isEmpty) throw const FormatException('Unknown recent search kind');

    final targetId = json['targetId']?.toString().trim() ?? '';
    final title = json['title']?.toString().trim() ?? '';
    if (targetId.isEmpty || title.isEmpty) {
      throw const FormatException('Incomplete recent search destination');
    }

    final rawData = json['data'];
    return RecentSearchEntry(
      kind: kind.first,
      targetId: targetId,
      title: title,
      subtitle: json['subtitle']?.toString() ?? '',
      data:
          rawData is Map
              ? rawData.map((key, value) => MapEntry(key.toString(), value))
              : const {},
    );
  }

  final RecentSearchKind kind;
  final String targetId;
  final String title;
  final String subtitle;
  final Map<String, dynamic> data;

  String get identity {
    if (kind == RecentSearchKind.player) {
      final routeId = _storedMemorialRouteId(data);
      if (routeId != null) return '${kind.name}:memorial:$routeId';
    }
    return '${kind.name}:$targetId';
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'targetId': targetId,
    'title': title,
    'subtitle': subtitle,
    if (data.isNotEmpty) 'data': data,
  };

  GroupEventCardModel? toTournament() {
    if (kind != RecentSearchKind.tournament) return null;
    final sourceName = data['eventSource']?.toString();
    final source = EventSource.values.firstWhere(
      (item) => item.name == sourceName,
      orElse: () => EventSource.lichessBroadcast,
    );
    final categoryName = data['tourEventCategory']?.toString();
    final category = TourEventCategory.values.firstWhere(
      (item) => item.name == categoryName,
      orElse: () => TourEventCategory.completed,
    );
    return GroupEventCardModel(
      id: targetId,
      title: title,
      dates: subtitle,
      maxAvgElo: _readInt(data['maxAvgElo']) ?? 0,
      timeUntilStart: data['timeUntilStart']?.toString() ?? '',
      tourEventCategory: category,
      timeControl: data['timeControl']?.toString() ?? '',
      endDate: _readDateTime(data['endDate']),
      startDate: _readDateTime(data['startDate']),
      location: _readNullableString(data['location']),
      searchTerms: _readStringList(data['searchTerms']),
      eventSource: source,
      isMajorUpcoming: _readBool(data['isMajorUpcoming'], fallback: false),
    );
  }

  SearchPlayer? toPlayer() {
    if (kind != RecentSearchKind.player) return null;
    return SearchPlayer(
      id: data['id']?.toString() ?? targetId,
      name: title,
      title: data['title']?.toString(),
      rating: _readInt(data['rating']),
      fideId: _readInt(data['fideId']),
      fed: _readNullableString(data['fed']),
      tournamentId: data['tournamentId']?.toString() ?? '',
      tournamentName: data['tournamentName']?.toString() ?? '',
      gameId: _readNullableString(data['gameId']),
      roundId: _readNullableString(data['roundId']),
      isWhitePlayer: _readBool(data['isWhitePlayer'], fallback: true),
      gamebasePlayerId: _readNullableString(data['gamebasePlayerId']),
      memorialSourceIdentity: _readNullableString(
        data['memorialSourceIdentity'],
      ),
      memorialRouteId: _readNullableString(data['memorialRouteId']),
    );
  }

  GameEcoFilter? toOpening() {
    return toOpeningSelection()?.filter;
  }

  OpeningSearchSelection? toOpeningSelection() {
    if (kind != RecentSearchKind.opening) return null;
    final code = targetId.toUpperCase();
    final filter =
        EcoOpenings.getFamily(code) == null
            ? GameEcoFilter.forCode(code)
            : GameEcoFilter.forFamily(code);
    final fallback = OpeningSearchSelection.forFilter(filter);
    final rawMoves = data['movePath'];
    final rawAggregate = data['isAggregate'];
    final moves =
        rawMoves is List
            ? rawMoves
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false)
            : fallback.movePath;
    return OpeningSearchSelection(
      filter: filter,
      hierarchyLabel:
          data['hierarchyLabel']?.toString().trim().isNotEmpty == true
              ? data['hierarchyLabel'].toString().trim()
              : fallback.hierarchyLabel,
      movePath: moves,
      isAggregate: rawAggregate is bool ? rawAggregate : fallback.isAggregate,
    );
  }

  static int? _readInt(Object? value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  static DateTime? _readDateTime(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String? _readNullableString(Object? value) {
    return value?.toString();
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList(growable: false);
  }

  static bool _readBool(Object? value, {required bool fallback}) {
    if (value is bool) return value;
    switch (value?.toString().toLowerCase()) {
      case 'true':
        return true;
      case 'false':
        return false;
      default:
        return fallback;
    }
  }
}

/// Restores the immutable Memorial identity before a recent-search result is
/// opened. Entries written before Memorial metadata was persisted still carry
/// the reviewed `memorial:<routeId>` profile key in `data.id`, which is enough
/// to hydrate the exact bundled player instead of falling back to a name query.
Future<SearchPlayer?> resolveRecentSearchPlayer(RecentSearchEntry entry) async {
  final restored = entry.toPlayer();
  if (restored == null ||
      restored.memorialSourceIdentity?.trim().isNotEmpty == true) {
    return restored;
  }

  final routeId = _storedMemorialRouteId(entry.data);
  if (routeId == null) return restored;
  final memorial = await findBundledMemorialPlayerByRouteId(routeId);
  if (memorial == null) {
    // Keep the entry on the Memorial data plane even if optional bundled
    // catalog enrichment is unavailable. Public numeric routes use that
    // number as their source identity; reviewed non-numeric routes use the
    // namespaced source identity consumed by the Memorial endpoints.
    final inferredSourceIdentity =
        int.tryParse(routeId) != null ? routeId : 'memorial:$routeId';
    return restored.copyWith(
      memorialSourceIdentity: inferredSourceIdentity,
      memorialRouteId: routeId,
    );
  }

  return SearchPlayer(
    id: memorial.profileKey,
    name: memorial.name,
    title: memorial.title,
    rating:
        memorial.ratingClassical > 0
            ? memorial.ratingClassical
            : restored.rating,
    fideId: int.tryParse(memorial.fideId ?? ''),
    fed: memorial.fed.isNotEmpty ? memorial.fed : restored.fed,
    tournamentId: restored.tournamentId,
    tournamentName: restored.tournamentName,
    gameId: restored.gameId,
    roundId: restored.roundId,
    isWhitePlayer: restored.isWhitePlayer,
    gamebasePlayerId: memorial.gamebasePlayerId,
    memorialSourceIdentity: memorial.sourceIdentity,
    memorialRouteId: memorial.routeId,
  );
}

String? _storedMemorialRouteId(Map<String, dynamic> data) {
  final explicit = data['memorialRouteId']?.toString().trim();
  if (explicit?.isNotEmpty == true) return explicit;
  final profileKey = data['id']?.toString().trim();
  const prefix = 'memorial:';
  if (profileKey == null || !profileKey.startsWith(prefix)) return null;
  final routeId = profileKey.substring(prefix.length).trim();
  return routeId.isEmpty ? null : routeId;
}

abstract class RecentSearchStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SqliteRecentSearchStorage implements RecentSearchStorage {
  const SqliteRecentSearchStorage(this.database);

  final AppDatabase database;

  @override
  Future<String?> read() => database.getString(_recentSearchesStorageKey);

  @override
  Future<void> write(String value) =>
      database.setString(_recentSearchesStorageKey, value);
}

final recentSearchStorageProvider = Provider<RecentSearchStorage>((ref) {
  return SqliteRecentSearchStorage(ref.watch(appDatabaseProvider));
});

final recentSearchesProvider = StateNotifierProvider<
  RecentSearchesNotifier,
  AsyncValue<List<RecentSearchEntry>>
>((ref) {
  return RecentSearchesNotifier(ref.watch(recentSearchStorageProvider));
});

class RecentSearchesNotifier
    extends StateNotifier<AsyncValue<List<RecentSearchEntry>>> {
  RecentSearchesNotifier(this._storage) : super(const AsyncValue.loading()) {
    _loadFuture = _load();
  }

  final RecentSearchStorage _storage;
  late final Future<void> _loadFuture;

  Future<void> _load() async {
    try {
      final raw = await _storage.read();
      if (raw == null || raw.trim().isEmpty) {
        state = const AsyncValue.data([]);
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('Expected a list');
      final entries = <RecentSearchEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          entries.add(
            RecentSearchEntry.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        } on FormatException {
          // A damaged entry should not hide the remaining valid history.
        }
      }
      state = AsyncValue.data(
        entries.take(_recentSearchesLimit).toList(growable: false),
      );
    } catch (_) {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> record(RecentSearchEntry entry) async {
    await _loadFuture;
    final current = state.valueOrNull ?? const <RecentSearchEntry>[];
    final updated = [
      entry,
      ...current.where((item) => item.identity != entry.identity),
    ].take(_recentSearchesLimit).toList(growable: false);
    state = AsyncValue.data(updated);
    await _persist(updated);
  }

  Future<void> remove(RecentSearchEntry entry) async {
    await _loadFuture;
    final current = state.valueOrNull ?? const <RecentSearchEntry>[];
    final updated = current
        .where((item) => item.identity != entry.identity)
        .toList(growable: false);
    state = AsyncValue.data(updated);
    await _persist(updated);
  }

  Future<void> clear() async {
    await _loadFuture;
    state = const AsyncValue.data([]);
    await _persist(const []);
  }

  Future<void> _persist(List<RecentSearchEntry> entries) async {
    try {
      await _storage.write(
        jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {
      // Keep the in-memory history usable when durable storage is unavailable.
    }
  }
}

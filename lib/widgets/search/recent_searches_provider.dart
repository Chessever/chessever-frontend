import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
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
        'timeControl': tournament.timeControl,
        'eventSource': tournament.eventSource.name,
      },
    );
  }

  factory RecentSearchEntry.player(SearchPlayer player) {
    final fideId = player.fideId;
    return RecentSearchEntry(
      kind: RecentSearchKind.player,
      targetId:
          fideId != null && fideId > 0
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
      },
    );
  }

  factory RecentSearchEntry.opening(GameEcoFilter eco) {
    final code = eco.code!;
    final family = EcoOpenings.getFamily(code);
    return RecentSearchEntry(
      kind: RecentSearchKind.opening,
      targetId: code,
      title: eco.openingName ?? code,
      subtitle:
          family == null
              ? code
              : family.codePrefixes.length == 1
              ? '$code · ${family.rangeLabel}'
              : family.rangeLabel,
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

  String get identity => '${kind.name}:$targetId';

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
    return GroupEventCardModel(
      id: targetId,
      title: title,
      dates: subtitle,
      maxAvgElo: 0,
      timeUntilStart: '',
      tourEventCategory: TourEventCategory.completed,
      timeControl: data['timeControl']?.toString() ?? '',
      endDate: null,
      startDate: null,
      eventSource: source,
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
      fed: data['fed']?.toString(),
      tournamentId: '',
      tournamentName: '',
    );
  }

  GameEcoFilter? toOpening() {
    if (kind != RecentSearchKind.opening) return null;
    final code = targetId.toUpperCase();
    return EcoOpenings.getFamily(code) == null
        ? GameEcoFilter.forCode(code)
        : GameEcoFilter.forFamily(code);
  }

  static int? _readInt(Object? value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }
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

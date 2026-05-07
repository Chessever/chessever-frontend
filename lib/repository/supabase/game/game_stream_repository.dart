import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveGameUpdate {
  const LiveGameUpdate({
    required this.gameId,
    this.pgn,
    this.fen,
    this.lastMove,
    this.lastMoveTime,
    this.lastClockWhite,
    this.lastClockBlack,
    this.status,
    this.players,
  });

  factory LiveGameUpdate.fromRow(Map<String, dynamic> row) {
    return LiveGameUpdate(
      gameId: row['id'] as String,
      pgn: row['pgn'] as String?,
      fen: row['fen'] as String?,
      lastMove: row['last_move'] as String?,
      lastMoveTime: row['last_move_time'] as String?,
      lastClockWhite: row['last_clock_white'] as num?,
      lastClockBlack: row['last_clock_black'] as num?,
      status: row['status'] as String?,
      players: row['players'],
    );
  }

  factory LiveGameUpdate.fromLegacyMap(
    String gameId,
    Map<String, dynamic> row,
  ) {
    return LiveGameUpdate(
      gameId: gameId,
      pgn: row['pgn'] as String?,
      fen: row['fen'] as String?,
      lastMove: row['last_move'] as String?,
      lastMoveTime: row['last_move_time'] as String?,
      lastClockWhite: row['last_clock_white'] as num?,
      lastClockBlack: row['last_clock_black'] as num?,
      status: row['status'] as String?,
      players: row['players'],
    );
  }

  final String gameId;
  final String? pgn;
  final String? fen;
  final String? lastMove;
  final String? lastMoveTime;
  final num? lastClockWhite;
  final num? lastClockBlack;
  final String? status;
  final Object? players;

  Map<String, dynamic> toLegacyMap() {
    return {
      'pgn': pgn,
      'fen': fen,
      'last_move': lastMove,
      'last_move_time': lastMoveTime,
      'last_clock_white': lastClockWhite,
      'last_clock_black': lastClockBlack,
      'status': status,
      'players': players,
    };
  }

  bool get hasPositionChange {
    return pgn != null || fen != null || lastMove != null || status != null;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LiveGameUpdate &&
            other.gameId == gameId &&
            other.pgn == pgn &&
            other.fen == fen &&
            other.lastMove == lastMove &&
            other.lastMoveTime == lastMoveTime &&
            other.lastClockWhite == lastClockWhite &&
            other.lastClockBlack == lastClockBlack &&
            other.status == status &&
            other.players == players;
  }

  @override
  int get hashCode {
    return Object.hash(
      gameId,
      pgn,
      fen,
      lastMove,
      lastMoveTime,
      lastClockWhite,
      lastClockBlack,
      status,
      players,
    );
  }
}

/// Repository provider for game streaming.
/// Each subscription creates its own Realtime channel that auto-disposes when the widget
/// is scrolled out of view (via Riverpod's autoDispose).
final gameStreamRepositoryProvider = AutoDisposeProvider<GameStreamRepository>((
  ref,
) {
  return GameStreamRepository();
});

/// Repository for streaming individual game updates from Supabase Realtime.
/// Uses Supabase's .stream() which creates individual channels per game.
/// Riverpod's autoDispose handles cleanup when widgets are disposed.
class GameStreamRepository {
  /// Subscribe to PGN updates for a specific game
  Stream<String?> subscribeToPgn(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) => data.isEmpty ? null : data.first['pgn'] as String?);
  }

  /// Subscribe to last move updates for a specific game
  Stream<String?> subscribeToLastMove(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map(
          (data) => data.isEmpty ? null : data.first['last_move'] as String?,
        );
  }

  /// Subscribe to FEN updates for a specific game
  Stream<String?> subscribeToFen(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) => data.isEmpty ? null : data.first['fen'] as String?);
  }

  /// Subscribe to status updates for a specific game
  Stream<String?> subscribeToStatus(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) => data.isEmpty ? null : data.first['status'] as String?);
  }

  /// Comprehensive game streaming - includes ALL game data in one stream.
  /// This is the primary method used by game cards for live updates.
  /// Each call creates an individual Realtime channel for this game.
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) {
          if (data.isEmpty) return null;
          return LiveGameUpdate.fromRow(data.first).toLegacyMap();
        });
  }

  Stream<LiveGameUpdate?> subscribeToLiveGameUpdate(String gameId) {
    return subscribeToGameUpdates(gameId).map(
      (update) =>
          update == null ? null : LiveGameUpdate.fromLegacyMap(gameId, update),
    );
  }

  /// One Realtime stream for a small set of visible games.
  ///
  /// Supabase's stream API performs the initial select and then merges
  /// Realtime row changes by primary key. Batching the first four rendered
  /// games per For You event replaces N per-card channels with one scoped
  /// channel while preserving atomic PGN/FEN/clock/status updates from the
  /// same `games` row.
  Stream<Map<String, LiveGameUpdate>> subscribeToLiveGameUpdatesBatch(
    List<String> gameIds,
  ) {
    final uniqueIds = gameIds.toSet().toList(growable: false);
    if (uniqueIds.isEmpty) {
      return Stream.value(const <String, LiveGameUpdate>{});
    }

    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .inFilter('id', uniqueIds)
        .map((rows) {
          return {
            for (final row in rows)
              row['id'] as String: LiveGameUpdate.fromRow(row),
          };
        });
  }
}

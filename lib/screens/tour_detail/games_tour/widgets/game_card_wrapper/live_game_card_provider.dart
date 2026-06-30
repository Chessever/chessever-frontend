import 'dart:async';

import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/live_game_position_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Stores the base game model for each game, keyed by gameId.
/// Auto-disposes once no visible card/provider is observing the game.
final baseGameProvider = StateProvider.autoDispose
    .family<GamesTourModel?, String>((ref, gameId) => null);

/// Provider that combines the base game model with real-time updates from the stream.
/// This is used by game cards to show live updates without entering the game screen.
///
/// Keyed by gameId only (not baseGame) so that polling-triggered rebuilds of the
/// parent widget don't recreate the provider and disrupt the Supabase stream.
///
/// Multi-game surfaces should pass a shared game-id batch key for the
/// currently rendered context. Focused board views keep their single-game
/// stream; cards without an explicit/context key do not open hidden round-wide
/// subscriptions.
final liveGameCardProvider =
    AutoDisposeProvider.family<GamesTourModel?, String>((ref, gameId) {
      return _watchMergedLiveGame(
        ref: ref,
        params: LiveGameWatchParams(gameId: gameId),
        mode: _LiveGameMergeMode.full,
      );
    });

@immutable
class LiveGameWatchParams {
  const LiveGameWatchParams({
    required this.gameId,
    this.batchKey,
    this.streamEnabled = true,
  });

  final String gameId;
  final LiveGamesBatchKey? batchKey;
  final bool streamEnabled;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LiveGameWatchParams &&
            other.gameId == gameId &&
            other.batchKey == batchKey &&
            other.streamEnabled == streamEnabled;
  }

  @override
  int get hashCode => Object.hash(gameId, batchKey, streamEnabled);
}

final scopedLiveGameCardProvider =
    AutoDisposeProvider.family<GamesTourModel?, LiveGameWatchParams>((
      ref,
      params,
    ) {
      return _watchMergedLiveGame(
        ref: ref,
        params: params,
        mode: _LiveGameMergeMode.full,
      );
    });

final liveGamePositionProvider =
    AutoDisposeProvider.family<GamesTourModel?, LiveGameWatchParams>((
      ref,
      params,
    ) {
      return _watchMergedLiveGame(
        ref: ref,
        params: params,
        mode: _LiveGameMergeMode.position,
      );
    });

final liveGameClockProvider =
    AutoDisposeProvider.family<GamesTourModel?, LiveGameWatchParams>((
      ref,
      params,
    ) {
      return _watchMergedLiveGame(
        ref: ref,
        params: params,
        mode: _LiveGameMergeMode.clock,
      );
    });

enum _LiveGameMergeMode { full, position, clock }

const int kLiveContextBatchSize = 25;

LiveGamesBatchKey? liveContextBatchKeyForGame({
  required GamesTourModel game,
  required List<GamesTourModel> contextGames,
  required String scopePrefix,
  int batchSize = kLiveContextBatchSize,
}) {
  if (game.source != GameSource.supabase || game.gameId.isEmpty) return null;
  if (batchSize <= 0) return null;

  final scopedGames = contextGames
      .where(
        (candidate) =>
            candidate.source == GameSource.supabase &&
            candidate.gameId.isNotEmpty,
      )
      .toList(growable: false);
  final index = scopedGames.indexWhere(
    (candidate) => candidate.gameId == game.gameId,
  );
  if (index < 0) return null;

  final chunkIndex = index ~/ batchSize;
  final start = chunkIndex * batchSize;
  final rawEnd = start + batchSize;
  final end = rawEnd > scopedGames.length ? scopedGames.length : rawEnd;
  final chunkGames = scopedGames.sublist(start, end);
  if (chunkGames.isEmpty) return null;

  return LiveGamesBatchKey(
    scopeId:
        '$scopePrefix:$chunkIndex:${chunkGames.first.gameId}:${chunkGames.last.gameId}',
    gameIds: chunkGames.map((candidate) => candidate.gameId),
  );
}

GamesTourModel? _watchMergedLiveGame({
  required Ref ref,
  required LiveGameWatchParams params,
  required _LiveGameMergeMode mode,
}) {
  final baseGame = _watchBaseGame(ref, params.gameId, mode);
  if (baseGame == null) return null;
  final update = _watchLiveUpdate(
    ref,
    _resolveLiveWatchParams(baseGame, params),
    mode,
  );
  if (update == null) return baseGame;

  final mergedGame = _mergeLiveUpdate(
    baseGame: baseGame,
    update: update,
    mode: mode,
  );
  if (_hasLiveFieldChanges(baseGame, mergedGame)) {
    _storeLatestBaseGame(ref, params.gameId, mergedGame);
  }
  return mergedGame;
}

GamesTourModel? _watchBaseGame(
  Ref ref,
  String gameId,
  _LiveGameMergeMode mode,
) {
  return ref
      .watch(
        baseGameProvider(
          gameId,
        ).select((game) => _ProjectedBaseGame.forMode(game, mode)),
      )
      .game;
}

LiveGameUpdate? _watchLiveUpdate(
  Ref ref,
  LiveGameWatchParams params,
  _LiveGameMergeMode mode,
) {
  if (!params.streamEnabled || !ref.watch(shouldStreamProvider)) {
    return null;
  }

  final batchKey = params.batchKey;
  if (batchKey != null) {
    if (!batchKey.contains(params.gameId)) return null;
    final projectedUpdateAsync = ref.watch(
      gameUpdatesBatchStreamProvider(batchKey).select((async) {
        return async.whenData(
          (updates) =>
              _ProjectedLiveGameUpdate.forMode(updates[params.gameId], mode),
        );
      }),
    );
    return projectedUpdateAsync.valueOrNull?.update;
  }
  return null;
}

@immutable
class _ProjectedBaseGame {
  const _ProjectedBaseGame._({required this.game, required this.fields});

  factory _ProjectedBaseGame.forMode(
    GamesTourModel? game,
    _LiveGameMergeMode mode,
  ) {
    if (game == null) {
      return const _ProjectedBaseGame._(game: null, fields: <Object?>[null]);
    }

    return _ProjectedBaseGame._(
      game: game,
      fields: switch (mode) {
        _LiveGameMergeMode.position => <Object?>[
          game.gameId,
          game.pgn,
          game.fen,
          game.lastMove,
          game.lastMoveTime,
          game.gameStatus,
        ],
        _LiveGameMergeMode.clock => <Object?>[
          game.gameId,
          // Clock countdown depends on the side-to-move and move timestamp.
          game.pgn,
          game.fen,
          game.lastMove,
          game.lastMoveTime,
          game.whiteClockCentiseconds,
          game.blackClockCentiseconds,
          game.whiteClockSeconds,
          game.blackClockSeconds,
          game.gameStatus,
        ],
        _LiveGameMergeMode.full => <Object?>[game],
      },
    );
  }

  final GamesTourModel? game;
  final List<Object?> fields;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _ProjectedBaseGame) return false;
    return _fieldsEqual(fields, other.fields);
  }

  @override
  int get hashCode => Object.hashAll(fields);
}

@immutable
class _ProjectedLiveGameUpdate {
  const _ProjectedLiveGameUpdate._({
    required this.update,
    required this.fields,
  });

  factory _ProjectedLiveGameUpdate.forMode(
    LiveGameUpdate? update,
    _LiveGameMergeMode mode,
  ) {
    if (update == null) {
      return const _ProjectedLiveGameUpdate._(
        update: null,
        fields: <Object?>[null],
      );
    }

    return _ProjectedLiveGameUpdate._(
      update: update,
      fields: switch (mode) {
        _LiveGameMergeMode.position => <Object?>[
          update.gameId,
          update.pgn,
          update.fen,
          update.lastMove,
          update.lastMoveTime,
          update.status,
        ],
        _LiveGameMergeMode.clock => <Object?>[
          update.gameId,
          update.pgn,
          update.fen,
          update.lastMove,
          update.lastMoveTime,
          update.lastClockWhite,
          update.lastClockBlack,
          update.status,
        ],
        _LiveGameMergeMode.full => <Object?>[update],
      },
    );
  }

  final LiveGameUpdate? update;
  final List<Object?> fields;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _ProjectedLiveGameUpdate) return false;
    return _fieldsEqual(fields, other.fields);
  }

  @override
  int get hashCode => Object.hashAll(fields);
}

bool _fieldsEqual(List<Object?> a, List<Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

GamesTourModel _mergeLiveUpdate({
  required GamesTourModel baseGame,
  required LiveGameUpdate update,
  required _LiveGameMergeMode mode,
}) {
  final includePosition =
      mode == _LiveGameMergeMode.full ||
      mode == _LiveGameMergeMode.position ||
      mode == _LiveGameMergeMode.clock;
  final includeClock =
      mode == _LiveGameMergeMode.full || mode == _LiveGameMergeMode.clock;

  final mergedPgn = includePosition ? update.pgn ?? baseGame.pgn : baseGame.pgn;
  final mergedLastMove =
      includePosition
          ? update.lastMove ?? baseGame.lastMove
          : baseGame.lastMove;
  final mergedStatus =
      includePosition || mode == _LiveGameMergeMode.clock
          ? _parseGameStatus(update.status, baseGame.gameStatus)
          : baseGame.gameStatus;
  final mergedFen =
      includePosition
          ? resolveFreshestGameFen(
            fen: update.fen ?? baseGame.fen,
            pgn: mergedPgn,
            lastMove: mergedLastMove,
          )
          : baseGame.fen;

  final normalizedWhiteClock =
      includeClock
          ? GamesTourModel.normalizeClockSeconds(
            clockSeconds: update.lastClockWhite?.round(),
            clockCentiseconds: baseGame.whiteClockCentiseconds,
          )
          : baseGame.whiteClockSeconds;
  final normalizedBlackClock =
      includeClock
          ? GamesTourModel.normalizeClockSeconds(
            clockSeconds: update.lastClockBlack?.round(),
            clockCentiseconds: baseGame.blackClockCentiseconds,
          )
          : baseGame.blackClockSeconds;

  return baseGame.copyWith(
    pgn: mergedPgn,
    fen: mergedFen ?? baseGame.fen,
    lastMove: mergedLastMove,
    lastMoveTime:
        includePosition && update.lastMoveTime != null
            ? DateTime.tryParse(update.lastMoveTime!)
            : baseGame.lastMoveTime,
    whiteClockSeconds: normalizedWhiteClock ?? baseGame.whiteClockSeconds,
    blackClockSeconds: normalizedBlackClock ?? baseGame.blackClockSeconds,
    gameStatus: mergedStatus,
  );
}

GameStatus _parseGameStatus(String? status, GameStatus fallback) {
  switch (status) {
    case '1-0':
      return GameStatus.whiteWins;
    case '0-1':
      return GameStatus.blackWins;
    case '1/2-1/2':
    case '½-½':
      return GameStatus.draw;
    case '*':
      return GameStatus.ongoing;
    default:
      return fallback;
  }
}

/// Helper that sets the base game and watches the live provider in one call.
/// Returns the live game data, falling back to the base game if not yet available.
GamesTourModel watchLiveGame(
  WidgetRef ref,
  GamesTourModel game, {
  LiveGamesBatchKey? batchKey,
  bool streamEnabled = true,
}) {
  final current = ref.read(baseGameProvider(game.gameId));
  if (_shouldUseIncomingGame(current, game, allowEqualFreshnessUpdate: false)) {
    Future.microtask(() {
      if (!ref.context.mounted) return;
      try {
        ref.read(baseGameProvider(game.gameId).notifier).state = game;
      } on StateError {
        // The card can be disposed while navigation is in flight.
      }
    });
  }
  final params = _liveWatchParamsForGame(
    game: game,
    batchKey: batchKey,
    streamEnabled: streamEnabled,
  );
  return ref.watch(scopedLiveGameCardProvider(params)) ?? game;
}

GamesTourModel watchLiveGamePosition(
  WidgetRef ref,
  GamesTourModel game, {
  LiveGamesBatchKey? batchKey,
  bool streamEnabled = true,
}) {
  _ensureBaseGame(ref, game);
  final params = _liveWatchParamsForGame(
    game: game,
    batchKey: batchKey,
    streamEnabled: streamEnabled,
  );
  return ref.watch(liveGamePositionProvider(params)) ?? game;
}

GamesTourModel watchLiveGameClock(
  WidgetRef ref,
  GamesTourModel game, {
  LiveGamesBatchKey? batchKey,
  bool streamEnabled = true,
}) {
  _ensureBaseGame(ref, game);
  final params = _liveWatchParamsForGame(
    game: game,
    batchKey: batchKey,
    streamEnabled: streamEnabled,
  );
  return ref.watch(liveGameClockProvider(params)) ?? game;
}

LiveGameWatchParams _liveWatchParamsForGame({
  required GamesTourModel game,
  required LiveGamesBatchKey? batchKey,
  required bool streamEnabled,
}) {
  final resolvedBatchKey = _resolveLiveBatchKey(game, batchKey);
  return LiveGameWatchParams(
    gameId: game.gameId,
    batchKey: resolvedBatchKey,
    streamEnabled: streamEnabled && resolvedBatchKey != null,
  );
}

LiveGamesBatchKey? _resolveLiveBatchKey(
  GamesTourModel game,
  LiveGamesBatchKey? batchKey,
) {
  if (batchKey != null) return batchKey;
  return null;
}

LiveGameWatchParams _resolveLiveWatchParams(
  GamesTourModel baseGame,
  LiveGameWatchParams params,
) {
  if (params.batchKey != null) return params;
  final resolvedBatchKey = _resolveLiveBatchKey(baseGame, null);
  return LiveGameWatchParams(
    gameId: params.gameId,
    batchKey: resolvedBatchKey,
    streamEnabled: params.streamEnabled && resolvedBatchKey != null,
  );
}

void _ensureBaseGame(WidgetRef ref, GamesTourModel game) {
  final current = ref.read(baseGameProvider(game.gameId));
  if (!_shouldUseIncomingGame(
    current,
    game,
    allowEqualFreshnessUpdate: false,
  )) {
    return;
  }
  Future.microtask(() {
    if (!ref.context.mounted) return;
    try {
      ref.read(baseGameProvider(game.gameId).notifier).state = game;
    } on StateError {
      // The card can be disposed while navigation is in flight.
    }
  });
}

void _storeLatestBaseGame(Ref ref, String gameId, GamesTourModel game) {
  Future.microtask(() {
    try {
      final current = ref.read(baseGameProvider(gameId));
      if (_shouldUseIncomingGame(
        current,
        game,
        allowEqualFreshnessUpdate: true,
      )) {
        ref.read(baseGameProvider(gameId).notifier).state = game;
      }
    } on StateError {
      // Provider/card was disposed while a stream event was being delivered.
    }
  });
}

bool _shouldUseIncomingGame(
  GamesTourModel? current,
  GamesTourModel incoming, {
  required bool allowEqualFreshnessUpdate,
}) {
  if (current == null) return true;
  if (current == incoming) return false;

  final currentTime = current.lastMoveTime;
  final incomingTime = incoming.lastMoveTime;
  if (currentTime != null && incomingTime != null) {
    if (incomingTime.isBefore(currentTime)) return false;
    if (incomingTime.isAfter(currentTime)) return true;
  } else if (currentTime != null && incomingTime == null) {
    return false;
  } else if (currentTime == null && incomingTime != null) {
    return true;
  }

  if (current.gameStatus == GameStatus.ongoing &&
      incoming.gameStatus != GameStatus.ongoing) {
    return true;
  }
  if (current.gameStatus != GameStatus.ongoing &&
      incoming.gameStatus == GameStatus.ongoing) {
    return false;
  }

  if ((current.lastMove?.isNotEmpty ?? false) &&
      (incoming.lastMove == null || incoming.lastMove!.isEmpty)) {
    return false;
  }

  if (!_hasPositionFieldChanges(current, incoming)) {
    return _hasLiveFieldChanges(current, incoming) || allowEqualFreshnessUpdate;
  }

  final currentPly = _knownPly(current);
  final incomingPly = _knownPly(incoming);
  if (currentPly != null && incomingPly != null) {
    if (incomingPly < currentPly) return false;
    if (incomingPly > currentPly) return true;
  } else if (currentPly != null && incomingPly == null) {
    return false;
  } else if (currentPly == null && incomingPly != null) {
    return true;
  }

  return allowEqualFreshnessUpdate;
}

bool _hasPositionFieldChanges(GamesTourModel current, GamesTourModel incoming) {
  return current.pgn != incoming.pgn ||
      current.fen != incoming.fen ||
      current.lastMove != incoming.lastMove ||
      current.lastMoveTime != incoming.lastMoveTime;
}

bool _hasLiveFieldChanges(GamesTourModel current, GamesTourModel incoming) {
  return current.pgn != incoming.pgn ||
      current.fen != incoming.fen ||
      current.lastMove != incoming.lastMove ||
      current.lastMoveTime != incoming.lastMoveTime ||
      current.whiteClockSeconds != incoming.whiteClockSeconds ||
      current.blackClockSeconds != incoming.blackClockSeconds ||
      current.gameStatus != incoming.gameStatus;
}

int? _knownPly(GamesTourModel game) {
  final pgnPly = resolveFinalPositionFromPgn(game.pgn)?.moveCount;
  final fenPly = plyFromFen(game.fen);
  if (pgnPly == null) return fenPly;
  if (fenPly == null) return pgnPly;
  return pgnPly > fenPly ? pgnPly : fenPly;
}

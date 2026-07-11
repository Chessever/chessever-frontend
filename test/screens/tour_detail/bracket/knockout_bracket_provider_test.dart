import 'dart:async';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/tour_detail/bracket/providers/knockout_bracket_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test(
    'coordinator retries stale successful metadata then accepts published round',
    () async {
      var gamesByTourId = <String, List<Games>>{
        'tour': [_game('game-1', 'round-1', status: '1-0')],
      };
      var loadCount = 0;
      final coordinator = KnockoutRoundMetadataCoordinator(
        tourIds: const ['tour'],
        loadRounds: (_) async {
          loadCount += 1;
          // Initial load and the immediate unseen-round refresh are stale.
          if (loadCount < 3) {
            return {
              'tour': [_round('round-1')],
            };
          }
          return {
            'tour': [_round('round-1'), _round('round-2')],
          };
        },
        readGames: () => gamesByTourId,
        retryDelay: (_) => Duration.zero,
      );
      addTearDown(coordinator.dispose);

      coordinator.start();
      await _waitUntil(
        () => loadCount == 1 && coordinator.state.hasValue,
        describe: () => 'loadCount=$loadCount state=${coordinator.state}',
      );

      gamesByTourId = {
        'tour': [
          _game('game-1', 'round-1', status: '1-0'),
          _game('game-2', 'round-2', status: '*'),
        ],
      };
      coordinator.gamesChanged();

      await _waitUntil(
        () =>
            loadCount == 3 &&
            (coordinator.state.valueOrNull?['tour'] ?? const <Round>[]).any(
              (round) => round.id == 'round-2',
            ),
        describe: () => 'loadCount=$loadCount state=${coordinator.state}',
      );

      expect(loadCount, 3);
      expect(
        knockoutBracketUnknownRoundIds(
          roundsByTourId: coordinator.state.requireValue,
          gamesByTourId: gamesByTourId,
        ),
        isEmpty,
      );
    },
  );

  test('coordinator disposal cancels a pending publication retry', () async {
    var gamesByTourId = <String, List<Games>>{
      'tour': [_game('game-1', 'round-1', status: '1-0')],
    };
    var loadCount = 0;
    Timer? pendingRetry;
    final coordinator = KnockoutRoundMetadataCoordinator(
      tourIds: const ['tour'],
      loadRounds: (_) async {
        loadCount += 1;
        return {
          'tour': [_round('round-1')],
        };
      },
      readGames: () => gamesByTourId,
      retryDelay: (_) => const Duration(hours: 1),
      createTimer: (delay, callback) {
        pendingRetry = Timer(delay, callback);
        return pendingRetry!;
      },
    );

    coordinator.start();
    await _waitUntil(
      () => loadCount == 1 && coordinator.state.hasValue,
      describe: () => 'loadCount=$loadCount state=${coordinator.state}',
    );
    gamesByTourId = {
      'tour': [
        _game('game-1', 'round-1', status: '1-0'),
        _game('game-2', 'round-2', status: '*'),
      ],
    };
    coordinator.gamesChanged();
    await _waitUntil(
      () => loadCount == 2 && pendingRetry != null,
      describe:
          () =>
              'loadCount=$loadCount pending=${pendingRetry != null} state=${coordinator.state}',
    );

    expect(pendingRetry!.isActive, isTrue);
    coordinator.dispose();
    expect(pendingRetry!.isActive, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(loadCount, 2);
  });

  test('unknown round publication retries use bounded backoff', () {
    expect(knockoutBracketRoundRetryDelay(0), const Duration(seconds: 2));
    expect(knockoutBracketRoundRetryDelay(1), const Duration(seconds: 5));
    expect(knockoutBracketRoundRetryDelay(2), const Duration(seconds: 12));
    expect(knockoutBracketRoundRetryDelay(3), isNull);
    expect(knockoutBracketRoundRetryDelay(100), isNull);
  });

  test('round refresh evidence only reports previously unseen round ids', () {
    final knownRound = _round('round-1');
    final sameMembershipAfterStatusChange = knockoutBracketUnknownRoundIds(
      roundsByTourId: {
        'tour': [knownRound],
      },
      gamesByTourId: {
        'tour': [
          _game('game-1', 'round-1', status: '1-0'),
          _game('game-2', 'round-1', status: '*'),
        ],
      },
    );

    expect(sameMembershipAfterStatusChange, isEmpty);

    final afterNewRoundMembership = knockoutBracketUnknownRoundIds(
      roundsByTourId: {
        'tour': [knownRound],
      },
      gamesByTourId: {
        'tour': [
          _game('game-1', 'round-1', status: '1-0'),
          _game('game-3', 'round-2', status: '*'),
          _game('game-4', 'round-2', status: '*'),
        ],
      },
    );

    expect(afterNewRoundMembership, {'round-2'});
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  String Function()? describe,
}) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail(
    'Timed out waiting for asynchronous coordinator state'
    '${describe == null ? '' : ': ${describe()}'}',
  );
}

Round _round(String id) => Round(
  id: id,
  slug: id,
  tourId: 'tour',
  tourSlug: 'tour',
  name: id,
  createdAt: DateTime.utc(2026),
  url: 'https://lichess.org/broadcast/tour/$id',
);

Games _game(String id, String roundId, {required String status}) => Games(
  id: id,
  roundId: roundId,
  roundSlug: roundId,
  tourId: 'tour',
  tourSlug: 'tour',
  status: status,
);

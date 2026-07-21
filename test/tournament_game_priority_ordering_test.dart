import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_priority_matching.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_stable_order_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tournament Games tab priority order', () {
    test('uses favorite, countryman, then board-number tiers', () {
      final sorted = sortTournamentRoundGamesByPriority(
        games: <GamesTourModel>[
          _game('regular-board-1', boardNr: 1),
          _game('country-board-2', boardNr: 2),
          _game('favorite-board-4', boardNr: 4),
          _game('favorite-board-3', boardNr: 3),
          _game('country-board-5', boardNr: 5),
        ],
        favoriteGameIds: const <String>{'favorite-board-4', 'favorite-board-3'},
        countrymanGameIds: const <String>{'country-board-2', 'country-board-5'},
      );

      expect(sorted.map((game) => game.gameId), <String>[
        'favorite-board-3',
        'favorite-board-4',
        'country-board-2',
        'country-board-5',
        'regular-board-1',
      ]);
    });

    test('favorite wins when a game also contains a countryman', () {
      final sorted = sortTournamentRoundGamesByPriority(
        games: <GamesTourModel>[
          _game('country-only', boardNr: 1),
          _game('favorite-and-country', boardNr: 8),
          _game('favorite-only', boardNr: 9),
        ],
        favoriteGameIds: const <String>{
          'favorite-and-country',
          'favorite-only',
        },
        countrymanGameIds: const <String>{
          'country-only',
          'favorite-and-country',
        },
      );

      expect(sorted.map((game) => game.gameId), <String>[
        'favorite-and-country',
        'favorite-only',
        'country-only',
      ]);
    });

    test(
      'search mode preserves board order instead of promoting priorities',
      () {
        final sorted = resolveTournamentRoundPresentationOrder(
          stableOrder: GamesTourStableOrder(),
          roundId: 'round-1',
          games: <GamesTourModel>[
            _game('favorite-board-10', boardNr: 10),
            _game('regular-board-1', boardNr: 1),
          ],
          isSearchMode: true,
          hasResolvedAutoPins: true,
          isRefreshingAutoPins: false,
          favoriteGameIds: const <String>{'favorite-board-10'},
          countrymanGameIds: const <String>{},
        );

        expect(sorted.map((game) => game.gameId), <String>[
          'regular-board-1',
          'favorite-board-10',
        ]);
      },
    );

    test('reuses decided positions for equivalent live model updates', () {
      final order = GamesTourStableOrder();
      final first = order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[
          _game('regular', boardNr: 1),
          _game('favorite', boardNr: 10),
        ],
        favoriteGameIds: const <String>{'favorite'},
        countrymanGameIds: const <String>{'arrives-later'},
      );
      final initialSortPasses = order.sortPassCount;

      final updated = order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[
          _game('favorite', boardNr: 99, status: GameStatus.whiteWins),
          _game('regular', boardNr: 0, status: GameStatus.draw),
        ],
        favoriteGameIds: const <String>{'favorite'},
        countrymanGameIds: const <String>{'arrives-later'},
      );

      expect(first.map((game) => game.gameId), <String>['favorite', 'regular']);
      expect(updated.map((game) => game.gameId), <String>[
        'favorite',
        'regular',
      ]);
      expect(updated.first.gameStatus, GameStatus.whiteWins);
      expect(order.sortPassCount, initialSortPasses);
    });

    test('sorts once when a new board arrives, not on later refreshes', () {
      final order = GamesTourStableOrder();
      order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[
          _game('regular', boardNr: 1),
          _game('favorite', boardNr: 2),
        ],
        favoriteGameIds: const <String>{'favorite'},
        countrymanGameIds: const <String>{'country-new'},
      );
      final beforeArrival = order.sortPassCount;

      final withArrival = order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[
          _game('regular', boardNr: 1),
          _game('favorite', boardNr: 2),
          _game('country-new', boardNr: 3),
        ],
        favoriteGameIds: const <String>{'favorite'},
        countrymanGameIds: const <String>{'country-new'},
      );
      final afterArrival = order.sortPassCount;

      order.resolveRound(
        roundId: 'round-1',
        games: withArrival.reversed,
        favoriteGameIds: const <String>{'favorite'},
        countrymanGameIds: const <String>{'country-new'},
      );

      expect(withArrival.map((game) => game.gameId), <String>[
        'favorite',
        'country-new',
        'regular',
      ]);
      expect(afterArrival, beforeArrival + 1);
      expect(order.sortPassCount, afterArrival);
    });

    test('re-sorts once for an explicit priority change', () {
      final order = GamesTourStableOrder();
      final games = <GamesTourModel>[
        _game('board-1', boardNr: 1),
        _game('new-favorite', boardNr: 10),
      ];
      final initial = order.resolveRound(
        roundId: 'round-1',
        games: games,
        favoriteGameIds: const <String>{},
        countrymanGameIds: const <String>{},
      );
      final beforeFavorite = order.sortPassCount;

      final prioritized = order.resolveRound(
        roundId: 'round-1',
        games: games.reversed,
        favoriteGameIds: const <String>{'new-favorite'},
        countrymanGameIds: const <String>{},
      );
      final afterFavorite = order.sortPassCount;
      order.resolveRound(
        roundId: 'round-1',
        games: games,
        favoriteGameIds: const <String>{'new-favorite'},
        countrymanGameIds: const <String>{},
      );

      expect(initial.map((game) => game.gameId), <String>[
        'board-1',
        'new-favorite',
      ]);
      expect(prioritized.map((game) => game.gameId), <String>[
        'new-favorite',
        'board-1',
      ]);
      expect(afterFavorite, beforeFavorite + 1);
      expect(order.sortPassCount, afterFavorite);
    });

    test('priority changes sort only rounds containing affected boards', () {
      final order = GamesTourStableOrder();
      order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[
          _game('round-1-board-1', boardNr: 1),
          _game('round-1-favorite', boardNr: 2),
        ],
        favoriteGameIds: const <String>{},
        countrymanGameIds: const <String>{},
      );
      order.resolveRound(
        roundId: 'round-2',
        games: <GamesTourModel>[
          _game('round-2-board-1', boardNr: 1),
          _game('round-2-board-2', boardNr: 2),
        ],
        favoriteGameIds: const <String>{},
        countrymanGameIds: const <String>{},
      );
      final beforePriorityChange = order.sortPassCount;

      order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[
          _game('round-1-board-1', boardNr: 1),
          _game('round-1-favorite', boardNr: 2),
        ],
        favoriteGameIds: const <String>{'round-1-favorite'},
        countrymanGameIds: const <String>{},
      );

      expect(order.sortPassCount, beforePriorityChange + 1);
    });

    test('a filtered board returns to its cached slot without sorting', () {
      final order = GamesTourStableOrder();
      order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[
          _game('favorite', boardNr: 9),
          _game('regular', boardNr: 1),
        ],
        favoriteGameIds: const <String>{'favorite'},
        countrymanGameIds: const <String>{},
      );
      final initialSortPasses = order.sortPassCount;

      final filtered = order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[_game('regular', boardNr: 1)],
        favoriteGameIds: const <String>{'favorite'},
        countrymanGameIds: const <String>{},
      );
      final restored = order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[
          _game('regular', boardNr: 1),
          _game('favorite', boardNr: 9),
        ],
        favoriteGameIds: const <String>{'favorite'},
        countrymanGameIds: const <String>{},
      );

      expect(filtered.map((game) => game.gameId), <String>['regular']);
      expect(restored.map((game) => game.gameId), <String>[
        'favorite',
        'regular',
      ]);
      expect(order.sortPassCount, initialSortPasses);
    });

    test('holds a new board until its priority snapshot is ready', () {
      final order = GamesTourStableOrder();
      order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[_game('existing', boardNr: 1)],
        favoriteGameIds: const <String>{},
        countrymanGameIds: const <String>{},
      );
      final beforeArrival = order.sortPassCount;

      final whileResolving = order.remapExistingRound(
        roundId: 'round-1',
        games: <GamesTourModel>[
          _game('existing', boardNr: 1),
          _game('favorite-new', boardNr: 20),
        ],
      );
      final resolved = order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[
          _game('existing', boardNr: 1),
          _game('favorite-new', boardNr: 20),
        ],
        favoriteGameIds: const <String>{'favorite-new'},
        countrymanGameIds: const <String>{},
      );

      expect(whileResolving.map((game) => game.gameId), <String>['existing']);
      expect(resolved.map((game) => game.gameId), <String>[
        'favorite-new',
        'existing',
      ]);
      expect(order.sortPassCount, beforeArrival + 1);
    });

    test('freezes the first placement even if board number hydrates later', () {
      final order = GamesTourStableOrder();
      final provisional = order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[
          _game('a', boardNr: null),
          _game('b', boardNr: 2),
        ],
        favoriteGameIds: const <String>{},
        countrymanGameIds: const <String>{},
      );
      final beforeHydration = order.sortPassCount;
      final hydrated = order.resolveRound(
        roundId: 'round-1',
        games: <GamesTourModel>[_game('a', boardNr: 1), _game('b', boardNr: 2)],
        favoriteGameIds: const <String>{},
        countrymanGameIds: const <String>{},
      );

      expect(provisional.map((game) => game.gameId), <String>['b', 'a']);
      expect(hydrated.map((game) => game.gameId), <String>['b', 'a']);
      expect(order.sortPassCount, beforeHydration);
    });
  });

  group('priority inputs', () {
    test('defaults favorites on and countrymen off', () {
      expect(AutoPinPreferences.defaults.favoritePlayersAutoPinEnabled, isTrue);
      expect(AutoPinPreferences.defaults.countrymenAutoPinEnabled, isFalse);
    });

    test('unpin overrides remove only effective auto priorities', () {
      const pins = GamesPinState(
        manualPins: <String>['manual'],
        favoriteAutoPins: <String>['favorite'],
        countrymanAutoPins: <String>['country'],
        unpinnedOverrides: <String>['favorite'],
        hasResolvedAutoPins: true,
      );

      expect(pins.effectiveFavoritePriorityIds, isEmpty);
      expect(pins.effectiveCountrymanPriorityIds, <String>{'country'});
      expect(pins.allPins, <String>['manual', 'country']);
    });

    test('per-tournament auto-pin disable suppresses both priority tiers', () {
      const pins = GamesPinState(
        favoriteAutoPins: <String>['favorite'],
        countrymanAutoPins: <String>['country'],
        autoPinDisabled: true,
        hasResolvedAutoPins: true,
      );

      expect(pins.effectiveFavoritePriorityIds, isEmpty);
      expect(pins.effectiveCountrymanPriorityIds, isEmpty);
      expect(pins.allPins, isEmpty);
    });

    test('matches favorite FIDE ids before normalized legacy names', () {
      final games = <GamesTourModel>[
        _game(
          'fide-match',
          boardNr: 1,
          white: _player('Different Display Name', fideId: 42),
        ),
        _game(
          'legacy-name-match',
          boardNr: 2,
          white: _player('Nakamura, Hikaru'),
        ),
        _game(
          'conflicting-id',
          boardNr: 3,
          white: _player('Different Display Name', fideId: 999),
        ),
      ];
      final matches = favoritePlayerGameIdsForGames(
        games: games,
        favorites: <FavoritePlayer>[
          _favorite('Shown Elsewhere', fideId: '42'),
          _favorite('GM Nakamura, Hikaru'),
        ],
      );

      expect(matches, <String>{'fide-match', 'legacy-name-match'});
    });

    test('legacy name fallback respects a saved country when present', () {
      final matches = favoritePlayerGameIdsForGames(
        games: <GamesTourModel>[
          _game(
            'same-country',
            boardNr: 1,
            white: _player('Shared Name', countryCode: 'USA'),
          ),
          _game(
            'different-country',
            boardNr: 2,
            white: _player('Shared Name', countryCode: 'GER'),
          ),
        ],
        favorites: <FavoritePlayer>[
          _favorite('Shared Name', countryCode: 'US'),
        ],
      );

      expect(matches, <String>{'same-country'});
    });

    test('matches ISO-2 selection against FIDE federation codes', () {
      final games = <GamesTourModel>[
        _game(
          'germany',
          boardNr: 1,
          white: _player('German Player', countryCode: 'GER'),
        ),
        _game(
          'turkiye',
          boardNr: 2,
          white: _player('Turkish Player', countryCode: 'TUR'),
        ),
        _game(
          'usa',
          boardNr: 3,
          white: _player('US Player', countryCode: 'USA'),
        ),
      ];

      expect(
        countrymanGameIdsForGames(games: games, selectedCountryCode: 'DE'),
        <String>{'germany'},
      );
      expect(
        countrymanGameIdsForGames(games: games, selectedCountryCode: 'TR'),
        <String>{'turkiye'},
      );
    });

    test(
      'detects player identity hydration but ignores clock-only updates',
      () {
        final original = _rawGame(
          'game-1',
          white: _rawPlayer('White', fideId: 0, federation: ''),
        );
        final clockOnly = _rawGame(
          'game-1',
          white: _rawPlayer('White', fideId: 0, federation: '', clock: 9000),
        );
        final hydrated = _rawGame(
          'game-1',
          white: _rawPlayer('White', fideId: 42, federation: 'GER'),
        );

        expect(
          didRawGamePriorityInputsChange(<Games>[original], <Games>[clockOnly]),
          isFalse,
        );
        expect(
          didRawGamePriorityInputsChange(<Games>[original], <Games>[hydrated]),
          isTrue,
        );
      },
    );

    test('supplemental rows use snapshots and preserve all-country skip', () {
      final games = <GamesTourModel>[
        _game(
          'favorite-fallback',
          boardNr: 1,
          white: _player('Favorite', fideId: 42, countryCode: 'GER'),
        ),
        _game(
          'other-fallback',
          boardNr: 2,
          white: _player('Other', countryCode: 'USA'),
        ),
      ];
      final state = GamesPinState(
        favoritePriorityEnabled: true,
        countrymanPriorityEnabled: true,
        favoritePlayersSnapshot: <FavoritePlayer>[
          _favorite('Favorite', fideId: '42'),
        ],
        selectedCountryCode: 'DE',
        hasResolvedAutoPins: true,
      );

      expect(state.effectiveFavoritePriorityIdsForGames(games), <String>{
        'favorite-fallback',
      });
      expect(state.effectiveCountrymanPriorityIdsForGames(games), <String>{
        'favorite-fallback',
      });
      expect(
        state.effectiveCountrymanPriorityIdsForGames(<GamesTourModel>[
          games.first,
        ]),
        isEmpty,
      );
    });

    test('team matchup order follows the prioritized game sequence', () {
      final grouped = groupTeamGamesByMatchup(
        selectedRoundId: 'round-1',
        games: <GamesTourModel>[
          _game(
            'favorite-team-board',
            boardNr: 8,
            white: _player('A1', countryCode: 'USA', team: 'Alpha'),
            black: _player('B1', countryCode: 'GER', team: 'Beta'),
          ),
          _game(
            'regular-team-board',
            boardNr: 1,
            white: _player('C1', countryCode: 'FRA', team: 'Gamma'),
            black: _player('D1', countryCode: 'ESP', team: 'Delta'),
          ),
        ],
      );

      expect(grouped.keys, <String>['Alpha vs Beta', 'Gamma vs Delta']);
    });
  });

  group('focus on live games order', () {
    test('keeps finished boards and bubbles live ids first', () {
      // Priority order first (board number): 1,2,3,4 — then focus partition.
      final priorityOrdered = sortTournamentRoundGamesByPriority(
        games: <GamesTourModel>[
          _game('finished-early', boardNr: 1, status: GameStatus.whiteWins),
          _game('live-a', boardNr: 2),
          _game('finished-late', boardNr: 3, status: GameStatus.draw),
          _game('live-b', boardNr: 4),
        ],
      );
      final snapshot = liveGameIdsForFocusSnapshot(priorityOrdered);
      final focused = applyLiveFocusOrder(
        games: priorityOrdered,
        liveGameIdsAtSnapshot: snapshot,
      );

      expect(focused.map((g) => g.gameId), <String>[
        'live-a',
        'live-b',
        'finished-early',
        'finished-late',
      ]);
      expect(focused.length, 4);
      expect(snapshot, <String>{'live-a', 'live-b'});
    });

    test('freezes order when a live board finishes after activation', () {
      final activationGames = <GamesTourModel>[
        _game('board-1', boardNr: 1, status: GameStatus.whiteWins),
        _game('board-2', boardNr: 2), // live at snapshot
        _game('board-3', boardNr: 3), // live at snapshot
        _game('board-4', boardNr: 4, status: GameStatus.draw),
      ];
      final priorityOrdered = sortTournamentRoundGamesByPriority(
        games: activationGames,
      );
      final snapshot = liveGameIdsForFocusSnapshot(priorityOrdered);
      final atActivation = applyLiveFocusOrder(
        games: priorityOrdered,
        liveGameIdsAtSnapshot: snapshot,
      );

      // Board 2 finishes while focus stays on — same frozen snapshot.
      final afterStatusChange = applyLiveFocusOrder(
        games: sortTournamentRoundGamesByPriority(
          games: <GamesTourModel>[
            _game('board-1', boardNr: 1, status: GameStatus.whiteWins),
            _game('board-2', boardNr: 2, status: GameStatus.blackWins),
            _game('board-3', boardNr: 3),
            _game('board-4', boardNr: 4, status: GameStatus.draw),
          ],
        ),
        liveGameIdsAtSnapshot: snapshot,
      );

      expect(atActivation.map((g) => g.gameId), <String>[
        'board-2',
        'board-3',
        'board-1',
        'board-4',
      ]);
      expect(afterStatusChange.map((g) => g.gameId), <String>[
        'board-2',
        'board-3',
        'board-1',
        'board-4',
      ]);
      // Content updates still flow through the frozen id order.
      expect(afterStatusChange[0].gameStatus, GameStatus.blackWins);
    });

    test('re-activation takes a fresh live snapshot', () {
      final firstSnapshot = liveGameIdsForFocusSnapshot(<GamesTourModel>[
        _game('a', boardNr: 1),
        _game('b', boardNr: 2),
        _game('c', boardNr: 3, status: GameStatus.draw),
      ]);
      final afterFirst = applyLiveFocusOrder(
        games: sortTournamentRoundGamesByPriority(
          games: <GamesTourModel>[
            _game('a', boardNr: 1),
            _game('b', boardNr: 2),
            _game('c', boardNr: 3, status: GameStatus.draw),
          ],
        ),
        liveGameIdsAtSnapshot: firstSnapshot,
      );

      // User deactivates then reactivates when only b is still live.
      final secondSnapshot = liveGameIdsForFocusSnapshot(<GamesTourModel>[
        _game('a', boardNr: 1, status: GameStatus.whiteWins),
        _game('b', boardNr: 2),
        _game('c', boardNr: 3, status: GameStatus.draw),
      ]);
      final afterSecond = applyLiveFocusOrder(
        games: sortTournamentRoundGamesByPriority(
          games: <GamesTourModel>[
            _game('a', boardNr: 1, status: GameStatus.whiteWins),
            _game('b', boardNr: 2),
            _game('c', boardNr: 3, status: GameStatus.draw),
          ],
        ),
        liveGameIdsAtSnapshot: secondSnapshot,
      );

      expect(afterFirst.map((g) => g.gameId), <String>['a', 'b', 'c']);
      expect(firstSnapshot, <String>{'a', 'b'});
      expect(afterSecond.map((g) => g.gameId), <String>['b', 'a', 'c']);
      expect(secondSnapshot, <String>{'b'});
    });

    test('all-finished round keeps membership and stable relative order', () {
      final games = <GamesTourModel>[
        _game('r1-b1', boardNr: 1, status: GameStatus.whiteWins),
        _game('r1-b2', boardNr: 2, status: GameStatus.draw),
        _game('r1-b3', boardNr: 3, status: GameStatus.blackWins),
      ];
      final priorityOrdered = sortTournamentRoundGamesByPriority(games: games);
      final snapshot = liveGameIdsForFocusSnapshot(priorityOrdered);
      final focused = applyLiveFocusOrder(
        games: priorityOrdered,
        liveGameIdsAtSnapshot: snapshot,
      );

      expect(snapshot, isEmpty);
      expect(focused.map((g) => g.gameId), priorityOrdered.map((g) => g.gameId));
      expect(focused.length, 3);
    });

    test('composes under favorite priority within live and non-live groups', () {
      final priorityOrdered = sortTournamentRoundGamesByPriority(
        games: <GamesTourModel>[
          _game('reg-live', boardNr: 1),
          _game('fav-finished', boardNr: 2, status: GameStatus.draw),
          _game('fav-live', boardNr: 5),
          _game('reg-finished', boardNr: 3, status: GameStatus.whiteWins),
        ],
        favoriteGameIds: const <String>{'fav-finished', 'fav-live'},
      );
      // Priority alone: fav-finished, fav-live, reg-live, reg-finished
      expect(priorityOrdered.map((g) => g.gameId), <String>[
        'fav-finished',
        'fav-live',
        'reg-live',
        'reg-finished',
      ]);

      final snapshot = liveGameIdsForFocusSnapshot(priorityOrdered);
      final focused = applyLiveFocusOrder(
        games: priorityOrdered,
        liveGameIdsAtSnapshot: snapshot,
      );

      // Live group keeps priority (fav before regular); finished group same.
      expect(focused.map((g) => g.gameId), <String>[
        'fav-live',
        'reg-live',
        'fav-finished',
        'reg-finished',
      ]);
    });
  });
}

GamesTourModel _game(
  String id, {
  required int? boardNr,
  GameStatus status = GameStatus.ongoing,
  PlayerCard? white,
  PlayerCard? black,
}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: white ?? _player('White $id'),
    blackPlayer: black ?? _player('Black $id'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: status,
    boardNr: boardNr,
    roundId: 'round-1',
    roundSlug: 'round-1',
    tourId: 'tour-1',
  );
}

PlayerCard _player(
  String name, {
  int? fideId,
  String countryCode = 'USA',
  String? team,
}) {
  return PlayerCard(
    name: name,
    federation: countryCode,
    title: 'GM',
    rating: 2700,
    countryCode: countryCode,
    fideId: fideId,
    team: team,
  );
}

Games _rawGame(String id, {Player? white, Player? black}) {
  return Games(
    id: id,
    roundId: 'round-1',
    roundSlug: 'round-1',
    tourId: 'tour-1',
    tourSlug: 'tour-1',
    players: <Player>[
      white ?? _rawPlayer('White'),
      black ?? _rawPlayer('Black'),
    ],
    boardNr: 1,
  );
}

Player _rawPlayer(
  String name, {
  int fideId = 0,
  String federation = 'USA',
  int clock = 0,
}) {
  return Player(
    name: name,
    title: 'GM',
    rating: 2700,
    fideId: fideId,
    fed: federation,
    clock: clock,
    team: '',
  );
}

FavoritePlayer _favorite(String name, {String? fideId, String? countryCode}) {
  final timestamp = DateTime.utc(2026, 7, 15);
  return FavoritePlayer(
    id: 'favorite-$name',
    userId: 'user-1',
    fideId: fideId,
    playerName: name,
    metadata: <String, dynamic>{
      if (countryCode != null) 'countryCode': countryCode,
    },
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

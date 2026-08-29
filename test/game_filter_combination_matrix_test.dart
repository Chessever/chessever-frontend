import 'dart:io';

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_combined_games_provider.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameFilter contradiction invariants', () {
    test(
      'live can never coexist with a final result or historical max year',
      () {
        final currentYear = DateTime.now().year;

        for (final result in GameResultFilter.values) {
          final filter = GameFilter(
            live: GameLiveFilter.live,
            result: result,
            maxYear: currentYear - 1,
          );

          expect(filter.result, GameResultFilter.all);
          expect(filter.maxYear, currentYear);
        }
      },
    );

    test('all non-live status/result combinations stay representable', () {
      for (final live in [GameLiveFilter.all, GameLiveFilter.completed]) {
        for (final result in GameResultFilter.values) {
          final filter = GameFilter(live: live, result: result);
          expect(filter.live, live);
          expect(filter.result, result);
        }
      }
    });
  });

  group('Favorites badge accounting', () {
    test('every visible filter dimension contributes to the badge', () {
      final currentYear = DateTime.now().year;
      final singleDimensionFilters = <GameFilter>[
        GameFilter(result: GameResultFilter.whiteWins),
        GameFilter(color: GameColorFilter.white),
        GameFilter(timeControl: GameTimeControlFilter.rapid),
        GameFilter(live: GameLiveFilter.completed),
        GameFilter(minRating: 2200),
        GameFilter(minYear: currentYear),
      ];

      for (final filter in singleDimensionFilters) {
        expect(filter.hasActiveFilters, isTrue);
        expect(filter.activeFilterCount, 1);
      }
    });

    test('combined visible dimensions produce the complete badge count', () {
      final filter = GameFilter(
        result: GameResultFilter.whiteWins,
        color: GameColorFilter.white,
        timeControl: GameTimeControlFilter.rapid,
        live: GameLiveFilter.completed,
        minRating: 2200,
        minYear: DateTime.now().year,
      );

      expect(filter.hasActiveFilters, isTrue);
      expect(filter.activeFilterCount, 6);
    });
  });

  group('server-filtered state is not filtered a second time locally', () {
    final serverMatch = _game(
      id: 'server-match',
      white: 'Favorite Player',
      black: 'Opponent',
    );
    final filter = GameFilter(color: GameColorFilter.white);

    test('Favorites trusts the repository result during text search', () {
      final state = FavoritesCombinedGamesState(
        games: [serverMatch],
        searchQuery: 'Sicilian',
        filter: filter,
      );

      expect(state.filteredGames, same(state.games));
    });

    test('Countrymen trusts the repository result during text search', () {
      final state = CountrymenCombinedGamesState(
        games: [serverMatch],
        searchQuery: 'Sicilian',
        filter: filter,
      );

      expect(state.filteredGames, same(state.games));
    });
  });

  group('PostgREST search encoding', () {
    test('quotes parser punctuation in every searched column', () {
      const query = 'Carlsen, "Magnus" \\ test (rapid)';

      final filter = buildGameSearchOrFilter(query);

      expect(
        filter,
        'name.ilike."%Carlsen, \\"Magnus\\" \\\\ test (rapid)%",'
        'eco.ilike."%Carlsen, \\"Magnus\\" \\\\ test (rapid)%",'
        'opening_name.ilike."%Carlsen, \\"Magnus\\" \\\\ test (rapid)%"',
      );
    });

    test('treats ILIKE wildcard characters as literal search text', () {
      final filter = buildGameSearchOrFilter('100%_sure');

      expect(
        filter,
        'name.ilike."%100\\%\\_sure%",'
        'eco.ilike."%100\\%\\_sure%",'
        'opening_name.ilike."%100\\%\\_sure%"',
      );
    });
  });

  test(
    'date RPC migration joins time control through authoritative tour IDs',
    () {
      final migration =
          File(
            'supabase/migrations/20260826195515_fix_favorite_country_time_control_dates.sql',
          ).readAsStringSync();

      expect(RegExp(r'g\.tour_id IN').allMatches(migration).length, 2);
      expect(migration, isNot(contains('g.tour_slug IN')));
    },
  );

  group('server query combination matrix', () {
    final currentYear = DateTime.now().year;
    final yearRanges = <(int, int)>[
      (GameFilter.defaultMinYear, currentYear),
      (currentYear, currentYear),
      (currentYear - 1, currentYear),
      (GameFilter.absoluteMinYear, currentYear - 1),
    ];
    const ratings = [0, 2200, 2300, 2400, 2500];
    const favoriteIdSets = [
      [1503014, 2016192, 2011420],
      [1503014],
      [1503014, 2016192],
    ];
    const searches = ['', 'Carlsen', 'Carlsen, "Magnus"'];

    test('Favorites represents every visible filter/search/selection tuple', () {
      var combinations = 0;

      for (final live in GameLiveFilter.values) {
        for (final result in GameResultFilter.values) {
          for (final timeControl in GameTimeControlFilter.values) {
            for (final color in GameColorFilter.values) {
              for (final rating in ratings) {
                for (final years in yearRanges) {
                  for (final search in searches) {
                    for (final fideIds in favoriteIdSets) {
                      combinations++;
                      final filter = GameFilter(
                        live: live,
                        result: result,
                        timeControl: timeControl,
                        color: color,
                        minRating: rating,
                        minYear: years.$1,
                        maxYear: years.$2,
                      );
                      final query = _QueryRecorder();

                      applyFavoritesFilterToSupabaseQuery(
                        query: query,
                        filter: filter,
                        fideIds: fideIds,
                        timeControlDbValue: _timeControlDbValue(timeControl),
                      );
                      if (search.isNotEmpty) {
                        query.or(buildGameSearchOrFilter(search));
                      }
                      _expectCommonPredicates(query, filter, search: search);
                      if (filter.color != GameColorFilter.all) {
                        expect(
                          query.calls,
                          contains(
                            _QueryCall(
                              'filter',
                              'players->${filter.color == GameColorFilter.white ? 0 : 1}->>fideId',
                              'in:(${fideIds.join(',')})',
                            ),
                          ),
                        );
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      expect(combinations, 25920);
    });

    test('Countrymen represents every visible filter/search tuple', () {
      var combinations = 0;

      for (final live in GameLiveFilter.values) {
        for (final result in GameResultFilter.values) {
          for (final timeControl in GameTimeControlFilter.values) {
            for (final color in GameColorFilter.values) {
              for (final rating in ratings) {
                for (final years in yearRanges) {
                  for (final search in searches) {
                    combinations++;
                    final filter = GameFilter(
                      live: live,
                      result: result,
                      timeControl: timeControl,
                      color: color,
                      minRating: rating,
                      minYear: years.$1,
                      maxYear: years.$2,
                    );
                    final query = _QueryRecorder();

                    applyCountryFilterToSupabaseQuery(
                      query: query,
                      filter: filter,
                      countryCode: 'NOR',
                      timeControlDbValue: _timeControlDbValue(timeControl),
                    );
                    if (search.isNotEmpty) {
                      query.or(buildGameSearchOrFilter(search));
                    }
                    _expectCommonPredicates(query, filter, search: search);
                    if (filter.color != GameColorFilter.all) {
                      expect(
                        query.calls,
                        contains(
                          _QueryCall(
                            'eq',
                            'players->${filter.color == GameColorFilter.white ? 0 : 1}->>fed',
                            'NOR',
                          ),
                        ),
                      );
                    }
                  }
                }
              }
            }
          }
        }
      }

      expect(combinations, 8640);
    });
  });
}

void _expectCommonPredicates(
  _QueryRecorder query,
  GameFilter filter, {
  required String search,
}) {
  switch (filter.live) {
    case GameLiveFilter.live:
      expect(
        query.calls,
        contains(const _QueryCall('or', 'status.is.null,status.eq.*', null)),
      );
      expect(
        query.calls
            .where((call) => call.name == 'or')
            .map((call) => call.column),
        contains(contains('game_day.eq.')),
      );
      break;
    case GameLiveFilter.completed:
      expect(query.calls, contains(const _QueryCall('not', 'status', 'is')));
      expect(query.calls, contains(const _QueryCall('neq', 'status', '*')));
      break;
    case GameLiveFilter.all:
      break;
  }

  switch (filter.result) {
    case GameResultFilter.whiteWins:
      expect(query.calls, contains(const _QueryCall('eq', 'status', '1-0')));
      break;
    case GameResultFilter.blackWins:
      expect(query.calls, contains(const _QueryCall('eq', 'status', '0-1')));
      break;
    case GameResultFilter.draw:
      expect(
        query.calls.where((call) => call.name == 'inFilter'),
        contains(
          isA<_QueryCall>().having((call) => call.column, 'column', 'status'),
        ),
      );
      break;
    case GameResultFilter.all:
      break;
  }

  if (filter.minRating > GameFilter.defaultMinRating) {
    expect(
      query.calls,
      contains(_QueryCall('gte', 'player_max_rating', filter.minRating)),
    );
  }
  if (filter.minYear != GameFilter.defaultMinYear) {
    expect(
      query.calls.where((call) => call.name == 'or').map((call) => call.column),
      contains(contains('${filter.minYear}-01-01')),
    );
  }
  if (filter.maxYear < DateTime.now().year) {
    expect(
      query.calls.where((call) => call.name == 'or').map((call) => call.column),
      contains(contains('${filter.maxYear + 1}-01-01')),
    );
  }
  if (filter.timeControl != GameTimeControlFilter.all) {
    expect(
      query.calls,
      contains(
        _QueryCall(
          'eq',
          'tours.group_broadcasts.time_control',
          _timeControlDbValue(filter.timeControl),
        ),
      ),
    );
  }
  if (search.isNotEmpty) {
    expect(
      query.calls,
      contains(_QueryCall('or', buildGameSearchOrFilter(search), null)),
    );
  }
}

String? _timeControlDbValue(GameTimeControlFilter value) => switch (value) {
  GameTimeControlFilter.all => null,
  GameTimeControlFilter.classical => 'standard',
  GameTimeControlFilter.rapid => 'rapid',
  GameTimeControlFilter.blitz => 'blitz',
};

class _QueryCall {
  const _QueryCall(this.name, this.column, this.value);

  final String name;
  final String column;
  final Object? value;

  @override
  bool operator ==(Object other) =>
      other is _QueryCall &&
      name == other.name &&
      column == other.column &&
      value == other.value;

  @override
  int get hashCode => Object.hash(name, column, value);

  @override
  String toString() => '$name($column, $value)';
}

class _QueryRecorder {
  final List<_QueryCall> calls = [];

  _QueryRecorder or(String filters) => _record('or', filters, null);
  _QueryRecorder not(String column, String operator, Object? value) =>
      _record('not', column, operator);
  _QueryRecorder neq(String column, Object value) =>
      _record('neq', column, value);
  _QueryRecorder eq(String column, Object value) =>
      _record('eq', column, value);
  _QueryRecorder gte(String column, Object value) =>
      _record('gte', column, value);
  _QueryRecorder lte(String column, Object value) =>
      _record('lte', column, value);
  _QueryRecorder inFilter(String column, List<Object> values) =>
      _record('inFilter', column, values);
  _QueryRecorder filter(String column, String operator, Object? value) =>
      _record('filter', column, '$operator:$value');

  _QueryRecorder _record(String name, String column, Object? value) {
    calls.add(_QueryCall(name, column, value));
    return this;
  }
}

GamesTourModel _game({
  required String id,
  required String white,
  required String black,
}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player(white, 1),
    blackPlayer: _player(black, 2),
    whiteTimeDisplay: '10:00',
    blackTimeDisplay: '10:00',
    whiteClockCentiseconds: 60000,
    blackClockCentiseconds: 60000,
    whiteClockSeconds: 600,
    blackClockSeconds: 600,
    gameStatus: GameStatus.whiteWins,
    roundId: 'round-1',
    tourId: 'tour-1',
    lastMoveTime: DateTime.utc(2020, 1, 1),
  );
}

PlayerCard _player(String name, int fideId) {
  return PlayerCard(
    name: name,
    federation: 'NOR',
    title: 'GM',
    rating: 2500,
    fideId: fideId,
    countryCode: 'NOR',
    team: null,
  );
}

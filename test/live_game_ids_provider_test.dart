import 'dart:async';

import 'package:chessever2/providers/app_resume_signal_provider.dart';
import 'package:chessever2/providers/live_game_ids_provider.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// "See N live" counts the games the server says are in play
/// (`get_live_game_ids`), per scope, and never guesses.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('liveGameIdsRpcParams', () {
    test('an event scope sends its tours, sorted and distinct', () {
      expect(liveGameIdsRpcParams(tourIds: const ['b', 'a', ' b ', '']), {
        'p_tour_ids': ['a', 'b'],
      });
    });

    test('an empty scope has nothing in play', () {
      expect(liveGameIdsRpcParams(tourIds: const []), isNull);
      expect(liveGameIdsRpcParams(fideIds: const ['x', '']), isNull);
      expect(liveGameIdsRpcParams(countryCode: '  '), isNull);
    });

    test('favorites send their FIDE ids and the list filter', () {
      final filter = GameFilter(
        live: GameLiveFilter.live,
        timeControl: GameTimeControlFilter.classical,
        color: GameColorFilter.white,
        minRating: 2500,
        eco: GameEcoFilter.forCode('B90'),
      );
      expect(
        liveGameIdsRpcParams(
          fideIds: const ['1503014', 'nope', '2016192'],
          filter: filter,
        ),
        {
          'p_fide_ids': [1503014, 2016192],
          'p_status': 'live',
          'p_time_control': 'standard',
          'p_min_rating': 2500,
          'p_color': 'white',
          'p_eco_codes': ['B90'],
        },
      );
    });

    test('a country always sends its rating floor, raised by the filter', () {
      expect(liveGameIdsRpcParams(countryCode: 'tur', minElo: 2000), {
        'p_country_code': 'TUR',
        'p_min_rating': 2000,
      });
      expect(
        liveGameIdsRpcParams(
          countryCode: 'IND',
          minElo: 2000,
          filter: GameFilter(minRating: 2400),
        ),
        {'p_country_code': 'IND', 'p_min_rating': 2400},
      );
      expect(liveGameIdsRpcParams(countryCode: 'IND', filter: GameFilter()), {
        'p_country_code': 'IND',
        'p_min_rating': 0,
      });
    });
  });

  group('scopes', () {
    test('an event is the same scope in any order', () {
      expect(
        EventLiveGamesScope(const ['b', 'a']),
        EventLiveGamesScope(const ['a', 'b', 'a']),
      );
      expect(
        EventLiveGamesScope(const ['a']).poll,
        EventLiveGamesScope.eventPoll,
      );
      expect(
        EventLiveGamesScope(const ['a', 'b']).poll,
        EventLiveGamesScope.combinedPoll,
      );
    });

    test('a list scope ignores the filter\'s sort order', () {
      final plain = GameFilter(minRating: 2400);
      final sorted = plain.copyWith(
        sorts: const [GameSortCriterion(field: GamebaseSortField.avgElo)],
      );
      expect(
        FavoritesLiveGamesScope(fideIds: const ['2', '1'], filter: sorted),
        FavoritesLiveGamesScope(fideIds: const ['1', '2'], filter: plain),
      );
      expect(
        CountrymenLiveGamesScope(countryCode: 'ind', filter: sorted),
        CountrymenLiveGamesScope(countryCode: 'IND', filter: plain),
      );
    });
  });

  group('LiveGameIdsNotifier', () {
    late _Live server;
    late StreamController<List<String>> rounds;
    late ProviderContainer container;

    setUp(() {
      server = _Live();
      rounds = StreamController<List<String>>.broadcast();
      container = ProviderContainer(
        overrides: [
          gameRepositoryProvider.overrideWithValue(server),
          liveRoundsIdProvider.overrideWith((ref) => rounds.stream),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await rounds.close();
    });

    final scope = EventLiveGamesScope(const [
      't1',
    ], poll: const Duration(milliseconds: 40));

    ProviderSubscription<Set<String>?> watch() {
      final sub = container.listen(eventLiveGameIdsProvider(scope), (_, __) {});
      addTearDown(sub.close);
      return sub;
    }

    test('is unknown until the server answers, then its ids', () async {
      final answer = Completer<Set<String>?>();
      server.next = () => answer.future;
      final sub = watch();
      expect(sub.read(), isNull);

      answer.complete({'g1', 'g2'});
      await _settle(() => sub.read() != null);
      expect(sub.read(), {'g1', 'g2'});
      expect(server.asked.single, const ['t1']);
    });

    test('stays unknown on a backend without the function', () async {
      server.next = () async => null;
      final sub = watch();
      await _settle(() => server.asked.isNotEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), isNull);
    });

    test('keeps its last answer through a failed refetch', () async {
      server.next = () async => {'g1'};
      final sub = watch();
      await _settle(() => sub.read() != null);

      server.next = () async => throw StateError('offline');
      final notifier = container.read(eventLiveGameIdsProvider(scope).notifier);
      await notifier.refresh();
      expect(sub.read(), {'g1'});
    });

    test('asks again when the live rounds change, and on resume', () async {
      server.next = () async => {'g1'};
      final sub = watch();
      await _settle(() => sub.read() != null);
      final notifier = container.read(eventLiveGameIdsProvider(scope).notifier);
      // Hold the timer off: only the triggers ask.
      notifier.visible = false;
      final before = server.asked.length;

      rounds.add(const ['r1']);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // The first rounds value is no change.
      expect(server.asked.length, before);

      server.next = () async => {'g1', 'g2'};
      notifier.visible = true;
      rounds.add(const ['r1', 'r2']);
      await _settle(() => sub.read()!.length == 2);

      server.next = () async => {'g3'};
      container.read(appResumedSignalProvider.notifier).state++;
      await _settle(() => sub.read()!.contains('g3'));
    });

    test(
      'polls while in view, waits out of view, and catches up on return',
      () async {
        server.next = () async => {'g1'};
        final sub = watch();
        await _settle(() => sub.read() != null);
        final notifier = container.read(
          eventLiveGameIdsProvider(scope).notifier,
        );

        server.next = () async => {'g2'};
        await _settle(() => sub.read()!.contains('g2'));

        notifier.visible = false;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final asked = server.asked.length;
        server.next = () async => {'g3'};
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(server.asked.length, asked);

        // A live-round change while away is asked for on return.
        rounds.add(const ['r1']);
        rounds.add(const ['r2']);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(server.asked.length, asked);
        notifier.visible = true;
        await _settle(() => sub.read()!.contains('g3'));
      },
    );

    test('counts what a list shows', () {
      expect(liveCountAmong(null, const ['a']), isNull);
      expect(liveCountAmong(const {}, const ['a']), 0);
      expect(liveCountAmong(const {'a', 'z'}, const ['a', 'b']), 1);
      expect(liveIdsAmong(const {'a', 'z'}, const ['a', 'b']), {'a'});
    });
  });
}

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(done(), isTrue, reason: 'never settled');
}

/// The server's `get_live_game_ids`, answered by [next].
class _Live implements GameRepository {
  Future<Set<String>?> Function() next = () async => <String>{};
  final List<List<String>?> asked = [];

  @override
  Future<Set<String>?> getLiveGameIds({
    List<String>? tourIds,
    List<String>? fideIds,
    String? countryCode,
    int minElo = 0,
    GameFilter? filter,
  }) {
    asked.add(tourIds);
    return next();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected game call: ${invocation.memberName}');
}

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_mode_provider.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One recorded call into the ranking fetcher.
class _Request {
  const _Request({
    required this.countryCode,
    required this.filters,
    required this.searchQuery,
    required this.offset,
  });

  final String countryCode;
  final RankingFilters filters;
  final String searchQuery;
  final int offset;
}

/// Stands in for [effectiveCountryProvider] so the test can switch federations
/// without the SQLite-backed persisted-country notifier.
final _testCountry = StateProvider<Country>(
  (ref) => CountryService().findByCode('US')!,
);

ChessPlayer _player({
  required int fideid,
  String name = 'Example, Player',
  String country = 'USA',
  String? flag,
}) {
  return ChessPlayer(
    fideid: fideid,
    name: name,
    title: 'GM',
    rating: 2500,
    rapidRating: 2400,
    blitzRating: 2300,
    country: country,
    flag: flag,
  );
}

void main() {
  late List<_Request> requests;

  /// Container wired to a fake fetcher, with the notifier kept alive (the real
  /// provider is autoDispose).
  ProviderContainer buildContainer({
    Future<List<ChessPlayer>> Function(_Request request)? results,
  }) {
    final container = ProviderContainer(
      overrides: [
        effectiveCountryProvider.overrideWith(
          (ref) => AsyncValue.data(ref.watch(_testCountry)),
        ),
        countryRankingsFetcherProvider.overrideWithValue(({
          required countryCode,
          required filters,
          required searchQuery,
          required limit,
          required offset,
        }) async {
          final request = _Request(
            countryCode: countryCode,
            filters: filters,
            searchQuery: searchQuery,
            offset: offset,
          );
          requests.add(request);
          if (results == null) return [_player(fideid: 1, flag: 'i')];
          return results(request);
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(countrymenPlayersProvider, (_, __) {});
    return container;
  }

  Future<void> waitFor(bool Function() predicate) async {
    for (var attempt = 0; attempt < 50; attempt++) {
      if (predicate()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for provider state');
  }

  setUp(() => requests = <_Request>[]);

  test('the country tab is labelled Rankings', () {
    expect(countrymenModeNames[CountrymenScreenMode.players], 'Rankings');
  });

  test('first load is country-scoped and uses the Rankings defaults', () async {
    final container = buildContainer();
    await waitFor(
      () =>
          requests.isNotEmpty &&
          !container.read(countrymenPlayersProvider).isLoading,
    );

    expect(requests.single.countryCode, 'USA');
    expect(requests.single.filters, RankingFilters.defaults);
    expect(requests.single.searchQuery, '');

    final state = container.read(countrymenPlayersProvider);
    expect(state.players.single.score, 2500);
    expect(state.inactivePlayerIds, {1});
  });

  test('changing a filter refetches within the same federation', () async {
    final container = buildContainer();
    await waitFor(() => requests.length == 1);

    await container
        .read(countrymenPlayersProvider.notifier)
        .updateFilters(
          RankingFilters.defaults.copyWith(timeControl: RankingTimeControl.rapid),
        );

    expect(requests, hasLength(2));
    expect(requests.last.countryCode, 'USA');
    expect(requests.last.filters.timeControl, RankingTimeControl.rapid);
    // The row's score must follow the selected time control, not stay on the
    // classical rating.
    expect(container.read(countrymenPlayersProvider).players.single.score, 2400);
  });

  test('search stays scoped to the selected federation', () async {
    final container = buildContainer();
    await waitFor(() => requests.length == 1);

    await container.read(countrymenPlayersProvider.notifier).search('  carl  ');

    expect(requests.last.countryCode, 'USA');
    expect(requests.last.searchQuery, 'carl');
    expect(requests.last.offset, 0);
    expect(container.read(countrymenPlayersProvider).isSearching, isTrue);
  });

  test('switching country reloads but keeps the selected filters', () async {
    final container = buildContainer();
    await waitFor(() => requests.length == 1);

    await container
        .read(countrymenPlayersProvider.notifier)
        .updateFilters(
          RankingFilters.defaults.copyWith(
            timeControl: RankingTimeControl.blitz,
            category: RankingCategory.juniors,
            activity: RankingActivity.all,
          ),
        );
    expect(requests, hasLength(2));

    container.read(_testCountry.notifier).state =
        CountryService().findByCode('TR')!;
    await waitFor(() => requests.length == 3);

    expect(requests.last.countryCode, 'TUR');
    expect(requests.last.filters.timeControl, RankingTimeControl.blitz);
    expect(requests.last.filters.category, RankingCategory.juniors);
    expect(requests.last.filters.activity, RankingActivity.all);
    expect(requests.last.offset, 0);
  });

  test('a late reply from a superseded filter never lands', () async {
    final container = buildContainer(
      results: (request) async {
        // The superseded Rapid page answers *after* the Blitz one the user is
        // actually looking at, and with a different player, so a missing
        // generation latch would be visible as row 1 coming back.
        if (request.filters.timeControl == RankingTimeControl.rapid) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return [_player(fideid: 1, name: 'Rapid, Player')];
        }
        return [_player(fideid: 2, name: 'Blitz, Player')];
      },
    );
    await waitFor(() => requests.length == 1);

    final notifier = container.read(countrymenPlayersProvider.notifier);
    final rapid = notifier.updateFilters(
      RankingFilters.defaults.copyWith(timeControl: RankingTimeControl.rapid),
    );
    final blitz = notifier.updateFilters(
      RankingFilters.defaults.copyWith(timeControl: RankingTimeControl.blitz),
    );
    await Future.wait([rapid, blitz]);

    final state = container.read(countrymenPlayersProvider);
    expect(state.filters.timeControl, RankingTimeControl.blitz);
    expect(state.players.single.fideId, 2);
  });

  test('paging appends instead of replacing', () async {
    final container = buildContainer(
      results:
          (request) async => List.generate(
            30,
            (i) => _player(fideid: request.offset + i + 1),
          ),
    );
    await waitFor(
      () =>
          requests.isNotEmpty &&
          !container.read(countrymenPlayersProvider).isLoading,
    );
    expect(container.read(countrymenPlayersProvider).players, hasLength(30));

    await container.read(countrymenPlayersProvider.notifier).loadMore();

    expect(requests.last.offset, 30);
    expect(requests.last.countryCode, 'USA');
    expect(container.read(countrymenPlayersProvider).players, hasLength(60));
  });
}

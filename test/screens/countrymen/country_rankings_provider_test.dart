import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_mode_provider.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Request {
  const _Request({required this.countryCode, required this.filters});

  final String countryCode;
  final RankingFilters filters;
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for provider state');
}

void main() {
  test('country rankings keep the selected federation across filter changes', () async {
    final requests = <_Request>[];
    final provider = Provider<CountrymenPlayersNotifier>((ref) {
      return CountrymenPlayersNotifier(
        ref,
        countryCodeOverride: () => 'USA',
        fetchRankings: ({
          required countryCode,
          required filters,
          required searchQuery,
          required limit,
          required offset,
        }) async {
          requests.add(_Request(countryCode: countryCode, filters: filters));
          return [
            const ChessPlayer(
              fideid: 1,
              name: 'Example, Player',
              title: 'GM',
              rating: 2500,
              rapidRating: 2400,
              blitzRating: 2300,
              country: 'USA',
              flag: 'i',
            ),
          ];
        },
      );
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(provider);
    await _waitFor(() => requests.length == 1 && !notifier.state.isLoading);

    expect(requests.single.countryCode, 'USA');
    expect(requests.single.filters, RankingFilters.defaults);
    expect(notifier.state.players.single.score, 2500);
    expect(notifier.state.inactivePlayerIds, {1});

    await notifier.updateFilters(
      RankingFilters.defaults.copyWith(timeControl: RankingTimeControl.rapid),
    );

    expect(requests, hasLength(2));
    expect(requests.last.countryCode, 'USA');
    expect(requests.last.filters.timeControl, RankingTimeControl.rapid);
    expect(notifier.state.players.single.score, 2400);
  });

  test('country player tab is labeled Rankings', () {
    expect(countrymenModeNames[CountrymenScreenMode.players], 'Rankings');
  });
}

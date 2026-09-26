import 'dart:async';

import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Tours extends TourRepository {
  List<Tour> tours = [_tour(latest: true), _tour(id: 'women', latest: true)];
  Future<List<Tour>>? pending;
  Object? failure;
  int calls = 0;

  @override
  Future<List<Tour>> getTourByGroupId(String groupId) async {
    expectSync(groupId, 'olympiad');
    calls++;
    if (failure != null) throw failure!;
    return pending ?? tours;
  }
}

class _Selections implements TourSelectionStore {
  @override
  Future<String?> getString(String key) async => null;
  @override
  Future<void> remove(String key) async {}
  @override
  Future<void> setString(String key, String value) async {}
}

Tour _tour({String id = 'open', bool latest = false}) => Tour.fromJson({
  'id': id,
  'name': id,
  'slug': id,
  'created_at': '2026-09-16T00:00:00Z',
  'url': 'https://example.test/$id',
  'tier': 1,
  'dates': [],
  'group_broadcast_id': 'olympiad',
  'info': {
    'standings': 'https://chess-results.com/tnr1469895.aspx',
    'officialTeamStandings': {
      'source': 'chess-results',
      'sourceUrl': 'https://chess-results.com/tnr1469895.aspx',
      'round': latest ? 10 : 9,
      'fetchedAt': '2026-09-26T17:42:28Z',
      'teams': [
        for (var i = 0; i < 2; i++)
          {
            'name': i == 0 ? 'Belarus' : 'Other',
            'rank': i + 1,
            'matchPoints': latest ? 14 : 12,
            'gamePoints': latest ? 24 : 21,
            'matchesPlayed': latest ? 10 : 9,
            'wins': latest ? 7 : 6,
            'draws': 0,
            'losses': 3,
          },
      ],
    },
  },
  'players': [
    {
      'name': 'Lazavik, Denis',
      'title': 'GM',
      'fideId': 13515110,
      'team': 'Belarus',
      'rating': 2621,
      'rank': 56,
      'played': latest ? 9 : 8,
      'score': latest ? 6.5 : 5.5,
      'ratingDiffs': {'standard': latest ? 13 : 7},
    },
  ],
});

ProviderContainer _container(_Tours repository, {bool active = true}) {
  final tour = _tour();
  return ProviderContainer(
    overrides: [
      tourRepositoryProvider.overrideWithValue(repository),
      tourSelectionStoreProvider.overrideWithValue(_Selections()),
      tournamentDetailVisibleProvider.overrideWith((ref) => active),
      selectedBroadcastModelProvider.overrideWith(
        (ref) => GroupBroadcast(
          id: 'olympiad',
          name: 'Olympiad',
          createdAt: DateTime.utc(2026, 9, 16),
          search: [],
        ),
      ),
      completeGamesTourFutureProvider('open').overrideWith((ref) async => []),
      tourDetailScreenProviderOverride(
        TourDetailViewModel(
          aboutTourModel: AboutTourModel.fromTour(tour),
          liveTourIds: [],
          tours: [
            TourModel(tour: tour, roundStatus: RoundStatus.completed),
            TourModel(
              tour: _tour(id: 'women'),
              roundStatus: RoundStatus.completed,
            ),
          ],
        ),
        refreshMetadata: true,
      ),
    ],
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'test',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });

  testWidgets(
    'result bursts refresh metadata then retry a delayed source aggregate',
    (tester) async {
      final repository = _Tours()..tours = [_tour(), _tour(id: 'women')];
      final container = _container(repository);
      container.listen(playerTourScreenProvider, (_, __) {});
      container.listen(teamStandingsProvider, (_, __) {});
      await tester.pump();
      final notifier = container.read(tourDetailScreenProvider.notifier);
      for (var i = 0; i < 300; i++) {
        notifier.scheduleStandingsRefresh();
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.calls, 1);
      expect(
        container
            .read(playerTourScreenProvider)
            .requireValue
            .single
            .scoreChange,
        7,
      );
      repository.tours = [
        _tour(latest: true),
        _tour(id: 'women', latest: true),
      ];
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(repository.calls, 2);
      expect(
        container
            .read(playerTourScreenProvider)
            .requireValue
            .single
            .scoreChange,
        13,
      );
      expect(
        container.read(teamStandingsProvider).requireValue.first.officialRound,
        10,
      );
      container.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'open standings advance roster and official table without re-entry',
    (tester) async {
      final repository = _Tours();
      final container = _container(repository);
      addTearDown(container.dispose);
      container.listen(playerTourScreenProvider, (_, __) {});
      container.listen(teamStandingsProvider, (_, __) {});
      await tester.pump();
      expect(
        container
            .read(playerTourScreenProvider)
            .requireValue
            .single
            .scoreChange,
        7,
      );
      expect(
        container.read(teamStandingsProvider).requireValue.first.officialRound,
        9,
      );

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      final player = container
          .read(playerTourScreenProvider)
          .requireValue
          .single;
      expect(player.scoreChange, 13);
      expect(player.matchScore, '6.5 / 9');
      expect(
        container.read(teamStandingsProvider).requireValue.first.officialRound,
        10,
      );
      expect(repository.calls, 1);
      container.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'stops when hidden or paused and refreshes immediately on return',
    (tester) async {
      final repository = _Tours();
      final container = _container(repository, active: false);
      addTearDown(container.dispose);
      container.listen(tourDetailScreenProvider, (_, __) {});
      await tester.pump(const Duration(minutes: 1));
      expect(repository.calls, 0);
      container.read(tournamentDetailVisibleProvider.notifier).state = true;
      await tester.pump(Duration.zero);
      expect(repository.calls, 1);
      container.read(shouldStreamProvider.notifier).state = false;
      await tester.pump(const Duration(minutes: 1));
      expect(repository.calls, 1);
      container.read(shouldStreamProvider.notifier).state = true;
      await tester.pump(Duration.zero);
      expect(repository.calls, 2);
      container.read(tournamentDetailVisibleProvider.notifier).state = false;
      await tester.pump(const Duration(minutes: 1));
      expect(repository.calls, 2);
      container.dispose();
      await tester.pump();
    },
  );

  testWidgets('failed or empty refresh retains standings and retries', (
    tester,
  ) async {
    final repository = _Tours()..failure = StateError('offline');
    final container = _container(repository);
    addTearDown(container.dispose);
    final initial = container.read(tourDetailScreenProvider).requireValue;
    await tester.pump(const Duration(seconds: 30));
    expect(
      container.read(tourDetailScreenProvider).requireValue,
      same(initial),
    );
    repository.failure = null;
    repository.tours = [];
    await tester.pump(const Duration(seconds: 30));
    expect(
      container.read(tourDetailScreenProvider).requireValue,
      same(initial),
    );
    repository.tours = [_tour(latest: true)];
    await tester.pump(const Duration(seconds: 30));
    expect(
      container
          .read(tourDetailScreenProvider)
          .requireValue
          .aboutTourModel
          .players
          .single
          .ratingDiff,
      13,
    );
    expect(repository.calls, 3);
    container.dispose();
    await tester.pump();
  });

  testWidgets(
    'one request at a time and a late response preserves category selection',
    (tester) async {
      final pending = Completer<List<Tour>>();
      final repository = _Tours()..pending = pending.future;
      final container = _container(repository);
      addTearDown(container.dispose);
      container.read(tourDetailScreenProvider);
      await tester.pump(const Duration(seconds: 30));
      unawaited(
        container.read(tourDetailScreenProvider.notifier).refreshTourDetails(),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(repository.calls, 1);
      await container
          .read(tourDetailScreenProvider.notifier)
          .updateSelection('women');
      pending.complete(repository.tours);
      await tester.pump();
      final detail = container.read(tourDetailScreenProvider).requireValue;
      expect(detail.aboutTourModel.id, 'women');
      expect(detail.aboutTourModel.players.single.ratingDiff, 13);
      container.dispose();
      await tester.pump();
    },
  );

  testWidgets('disposing while refresh is pending ignores the late response', (
    tester,
  ) async {
    final pending = Completer<List<Tour>>();
    final repository = _Tours()..pending = pending.future;
    final container = _container(repository);
    container.read(tourDetailScreenProvider);
    await tester.pump(const Duration(seconds: 30));
    expect(repository.calls, 1);
    container.dispose();
    pending.complete(repository.tours);
    await tester.pump(const Duration(minutes: 1));
    expect(repository.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged metadata does not rebuild the standings', (
    tester,
  ) async {
    final repository = _Tours()..tours = [_tour(id: 'women'), _tour()];
    final container = _container(repository);
    final initial = container.read(tourDetailScreenProvider).requireValue;
    await tester.pump(const Duration(seconds: 30));
    expect(repository.calls, 1);
    // The repository's rating order may differ from the category order.
    expect(
      container.read(tourDetailScreenProvider).requireValue,
      same(initial),
    );
    container.dispose();
    await tester.pump();
  });

  testWidgets('retained provider stops polling when its last listener leaves', (
    tester,
  ) async {
    final repository = _Tours();
    final container = _container(repository);
    final subscription = container.listen(tourDetailScreenProvider, (_, __) {});
    subscription.close();
    await tester.pump(const Duration(minutes: 1));
    expect(repository.calls, 0);
    container.listen(tourDetailScreenProvider, (_, __) {});
    await tester.pump(Duration.zero);
    expect(repository.calls, 1);
    container.dispose();
    await tester.pump();
  });

  testWidgets(
    'a timed-out response cannot overwrite the next successful refresh',
    (tester) async {
      final stalled = Completer<List<Tour>>();
      final repository = _Tours()..pending = stalled.future;
      final container = _container(repository);
      final initial = container.read(tourDetailScreenProvider).requireValue;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 12));
      expect(
        container.read(tourDetailScreenProvider).requireValue,
        same(initial),
      );
      repository.pending = null;
      await tester.pump(const Duration(seconds: 18));
      final fresh = container.read(tourDetailScreenProvider).requireValue;
      expect(fresh.aboutTourModel.players.single.ratingDiff, 13);
      expect(repository.calls, 2);
      stalled.complete([_tour()]);
      await tester.pump();
      expect(
        container.read(tourDetailScreenProvider).requireValue,
        same(fresh),
      );
      container.dispose();
      await tester.pump();
    },
  );
}

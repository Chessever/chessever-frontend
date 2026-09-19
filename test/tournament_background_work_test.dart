import 'dart:async';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Storage extends GamesLocalStorage {
  _Storage(super.ref);
  Future<List<Games>>? cached;
  Future<List<Games>>? fresh;
  List<Games>? preview;

  @override
  Future<List<Games>> getCachedGames(String tourId) async =>
      cached == null ? <Games>[] : await cached!;
  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
    String? priorityRoundId,
    void Function(List<Games>)? onPriorityRound,
    Future<void> Function()? afterPriorityRound,
    bool rethrowErrors = false,
  }) async {
    if (preview != null) onPriorityRound?.call(preview!);
    return fresh == null
        ? [
          Games(
            id: 'g',
            roundId: 'r',
            roundSlug: 'r',
            tourId: tourId,
            tourSlug: tourId,
            status: '*',
          ),
        ]
        : await fresh!;
  }
}

class _Rounds extends RoundRepository {
  @override
  Future<List<Round>> getRoundsByTourId(String tourId) async => [];
  @override
  Future<Round?> getLatestRoundByLastMove(String tourId) async => null;
}

class _Repository extends GameRepository {
  int polls = 0;
  @override
  Future<List<TourGameSafetyNetSnapshot>> getTourGamesSafetyNet(
    String tourId,
  ) async {
    polls++;
    return [
      const TourGameSafetyNetSnapshot(
        id: 'g',
        roundId: 'r',
        roundSlug: 'r',
        status: '*',
      ),
    ];
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder',
    );
  });

  Games game(String id) => Games(
    id: id,
    roundId: 'r',
    roundSlug: 'r',
    tourId: 'tour',
    tourSlug: 'tour',
    status: '*',
  );

  for (final failBackground in [false, true]) {
    testWidgets(
      'round preview stays usable with complete catalog pending: failure=$failBackground',
      (tester) async {
        final fresh = Completer<List<Games>>();
        final container = ProviderContainer(
          overrides: [
            roundRepositoryProvider.overrideWithValue(_Rounds()),
            gamesLocalStorage.overrideWith(
              (ref) =>
                  _Storage(ref)
                    ..preview = [game('current')]
                    ..fresh = fresh.future,
            ),
          ],
        );
        final subscription = container.listen(
          completeGamesTourProvider('tour'),
          (_, __) {},
        );
        final futureSubscription = container.listen(
          completeGamesTourFutureProvider('tour'),
          (_, __) {},
        );
        await tester.pump();
        expect(
          container.read(gamesTourProvider('tour')).valueOrNull?.single.id,
          'current',
        );
        expect(
          container.read(completeGamesTourProvider('tour')).isLoading,
          isTrue,
        );
        expect(
          container.read(completeGamesTourFutureProvider('tour')).isLoading,
          isTrue,
        );
        if (failBackground) {
          fresh.completeError(StateError('offline'));
        } else {
          fresh.complete([game('current'), game('older')]);
        }
        await tester.pump();
        expect(
          container.read(gamesTourProvider('tour')).valueOrNull?.first.id,
          'current',
        );
        final complete = container.read(completeGamesTourProvider('tour'));
        expect(complete.hasError, failBackground);
        expect(
          container.read(completeGamesTourFutureProvider('tour')).hasError,
          failBackground,
        );
        if (!failBackground) expect(complete.valueOrNull?.length, 2);
        futureSubscription.close();
        subscription.close();
        container.dispose();
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }

  testWidgets('saved roster paints before a slow fresh load', (tester) async {
    final fresh = Completer<List<Games>>();
    final container = ProviderContainer(
      overrides: [
        roundRepositoryProvider.overrideWithValue(_Rounds()),
        gamesLocalStorage.overrideWith(
          (ref) =>
              _Storage(ref)
                ..cached = Future.value([game('cached')])
                ..fresh = fresh.future,
        ),
      ],
    );
    final subscription = container.listen(
      gamesTourProvider('tour'),
      (_, __) {},
    );
    await tester.pump();
    expect(
      container.read(gamesTourProvider('tour')).valueOrNull?.single.id,
      'cached',
    );
    fresh.complete([game('fresh')]);
    await tester.pump();
    expect(
      container.read(gamesTourProvider('tour')).valueOrNull?.single.id,
      'fresh',
    );
    expect(container.read(completeGamesTourProvider('tour')).hasValue, isTrue);
    subscription.close();
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('late disk cache cannot overwrite the fresh roster', (
    tester,
  ) async {
    final cached = Completer<List<Games>>();
    final container = ProviderContainer(
      overrides: [
        roundRepositoryProvider.overrideWithValue(_Rounds()),
        gamesLocalStorage.overrideWith(
          (ref) =>
              _Storage(ref)
                ..cached = cached.future
                ..fresh = Future.value([game('fresh')]),
        ),
      ],
    );
    final subscription = container.listen(
      gamesTourProvider('tour'),
      (_, __) {},
    );
    await tester.pump();
    cached.complete([game('stale')]);
    await tester.pump();
    expect(
      container.read(gamesTourProvider('tour')).valueOrNull?.single.id,
      'fresh',
    );
    subscription.close();
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('board switcher cannot restart covered tournament polling', (
    tester,
  ) async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [
        roundRepositoryProvider.overrideWithValue(_Rounds()),
        gameRepositoryProvider.overrideWithValue(repository),
        gamesLocalStorage.overrideWith(_Storage.new),
        tournamentDetailVisibleProvider.overrideWith((ref) => true),
        tourDetailScreenProviderOverride(
          TourDetailViewModel(
            aboutTourModel: const AboutTourModel(
              id: 'tour',
              slug: 'tour',
              name: 'Tour',
              description: '',
              imageUrl: '',
              players: [],
              timeControl: '',
              date: '',
              location: '',
              websiteUrl: '',
              standingsUrl: '',
              tourUrl: '',
              groupBroadcastId: 'event',
            ),
            liveTourIds: const [],
            tours: const [],
          ),
        ),
      ],
    );
    final subscription = container.listen(
      gamesTourProvider('tour'),
      (_, __) {},
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.polls, 1);
    container.read(tournamentDetailVisibleProvider.notifier).state = false;
    container.read(shouldStreamProvider.notifier).state = false;
    await tester.pump();
    // This is the existing switcher action in chess_board_screen_new.dart.
    container.read(shouldStreamProvider.notifier).state = true;
    await tester.pump(const Duration(seconds: 30));
    expect(repository.polls, 1);
    container.read(tournamentDetailVisibleProvider.notifier).state = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.polls, 2);
    subscription.close();
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });
}

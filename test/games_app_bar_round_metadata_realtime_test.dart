import 'dart:async';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: 'https://placeholder.supabase.co',
        anonKey: 'placeholder-anon-key',
      );
    }
  });

  test(
    'round datetime joins already-visible boards after a realtime metadata change',
    () async {
      final repository = _MutableRoundRepository();
      final metadataChanges = StreamController<String>.broadcast();
      final board = Games(
        id: 'game-7-1',
        roundId: 'round-7',
        roundSlug: 'round-7',
        tourId: 'tour-1',
        tourSlug: 'tour-1',
        status: '*',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      );
      final container = ProviderContainer(
        overrides: [
          roundRepositoryProvider.overrideWithValue(repository),
          gamesAppBarTourIdProvider.overrideWithValue('tour-1'),
          gamesAppBarGamesProvider.overrideWith(
            (ref, tourId) => AsyncValue.data(<Games>[board]),
          ),
          roundMetadataChangesProvider.overrideWith(
            (ref, tourId) => metadataChanges.stream,
          ),
          knockoutTournamentStateProvider.overrideWith(
            (ref, tourId) => const KnockoutTournamentState.empty(),
          ),
          liveRoundsIdProvider.overrideWith(
            (ref) => const Stream<List<String>>.empty(),
          ),
        ],
      );
      final subscription = container.listen<AsyncValue<GamesAppBarViewModel>>(
        gamesAppBarProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await metadataChanges.close();
      });

      await _waitFor(
        () => container.read(gamesAppBarProvider).valueOrNull != null,
        debugState:
            () =>
                'initial=${container.read(gamesAppBarProvider)}, '
                'fetches=${repository.fetchCount}',
      );
      final before = container.read(gamesAppBarProvider).requireValue;
      expect(before.gamesAppBarModels.single.id, 'round-7');
      expect(before.gamesAppBarModels.single.startsAt, isNull);
      expect(repository.fetchCount, 1);

      final canonicalStart = DateTime.utc(2026, 7, 16, 20, 47, 44);
      repository.round = _round(startsAt: canonicalStart);
      metadataChanges.add('round-7');

      await _waitFor(
        () =>
            container
                .read(gamesAppBarProvider)
                .valueOrNull
                ?.gamesAppBarModels
                .single
                .startsAt ==
            canonicalStart.toLocal(),
        debugState:
            () =>
                'after change=${container.read(gamesAppBarProvider)}, '
                'fetches=${repository.fetchCount}',
      );

      final after = container.read(gamesAppBarProvider).requireValue;
      expect(after.gamesAppBarModels.single.id, 'round-7');
      expect(after.gamesAppBarModels.single.startsAt, canonicalStart.toLocal());
      expect(repository.fetchCount, 2);

      repository.failNextFetch = true;
      metadataChanges.add('round-7');
      await _waitFor(() => repository.fetchCount == 3);

      final afterTransientFailure = container.read(gamesAppBarProvider);
      expect(afterTransientFailure.hasValue, isTrue);
      expect(
        afterTransientFailure.requireValue.gamesAppBarModels.single.startsAt,
        canonicalStart.toLocal(),
      );
    },
  );
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
  String Function()? debugState,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Timed out waiting for provider replay state'
        '${debugState == null ? '' : ': ${debugState()}'}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Round _round({DateTime? startsAt}) => Round(
  id: 'round-7',
  slug: 'round-7',
  tourId: 'tour-1',
  tourSlug: 'tour-1',
  name: 'Round 7',
  createdAt: DateTime.utc(2026, 7, 16, 19, 26),
  startsAt: startsAt,
  url: 'https://lichess.org/broadcast/tour/round-7',
);

class _MutableRoundRepository extends RoundRepository {
  Round round = _round();
  int fetchCount = 0;
  bool failNextFetch = false;

  @override
  Future<List<Round>> getRoundsByTourId(String tourId) async {
    fetchCount++;
    if (failNextFetch) {
      failNextFetch = false;
      throw StateError('transient metadata read failure');
    }
    return <Round>[round];
  }

  @override
  Future<Round?> getLatestRoundByLastMove(String tourId) async => null;
}

import 'dart:async';

import 'package:chessever2/providers/event_video_provider.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_round_demand_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _GamesRepository extends GameRepository {
  final requests = <String>[];
  Completer<void>? oldRoundGate;

  @override
  Future<List<Games>> getRoundGamePreviews(
    String tourId,
    String roundId, {
    bool hydrateFallbacks = false,
  }) async {
    requests.add('$tourId/$roundId');
    if (roundId == 'old') await oldRoundGate?.future;
    return [_game(roundId, tourId: tourId)];
  }
}

class _RoundsRepository extends RoundRepository {
  @override
  Future<List<Round>> getRoundsByTourId(String tourId) async => [
    for (final (id, daysAgo) in [('current', 1), ('old', 2), ('ancient', 3)])
      Round(
        id: id,
        slug: id,
        tourId: tourId,
        tourSlug: tourId,
        name: id,
        createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
        startsAt: DateTime.now().subtract(Duration(days: daysAgo)),
        url: '',
      ),
  ];
}

class _Storage extends GamesLocalStorage {
  _Storage(super.ref);
  int completeRequests = 0;

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
    String? priorityRoundId,
    void Function(List<Games>)? onPriorityRound,
    Future<void> Function()? afterPriorityRound,
    bool rethrowErrors = false,
  }) async {
    completeRequests++;
    return [
      for (final id in ['current', 'old', 'ancient']) _game(id),
    ];
  }
}

Games _game(String roundId, {String tourId = 'selected'}) => Games(
  id: '$tourId-$roundId',
  roundId: roundId,
  roundSlug: roundId,
  tourId: tourId,
  tourSlug: tourId,
  status: '1-0',
);

const _detail = TourDetailViewModel(
  aboutTourModel: AboutTourModel(
    id: 'selected',
    slug: '',
    name: '',
    description: '',
    imageUrl: '',
    players: [],
    timeControl: '',
    date: '',
    location: '',
    websiteUrl: '',
    standingsUrl: '',
    tourUrl: '',
  ),
  liveTourIds: [],
  tours: [],
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'placeholder',
    );
  });

  late ProviderContainer container;
  late _GamesRepository repository;
  late _Storage storage;
  setUp(() {
    repository = _GamesRepository();
    container = ProviderContainer(
      overrides: [
        tourDetailScreenProviderOverride(_detail),
        gameRepositoryProvider.overrideWithValue(repository),
        roundRepositoryProvider.overrideWithValue(_RoundsRepository()),
        eventVideoConfigurationProvider.overrideWithValue(null),
        gamesLocalStorage.overrideWith((ref) => storage = _Storage(ref)),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<GamesTourNotifier> openTour() async {
    container.listen(gamesTourProvider('selected'), (_, _) {});
    final loader = container.read(gamesTourProvider('selected').notifier);
    await loader.setActiveRounds({'current'});
    return loader;
  }

  test(
    'entry loads only current round; old rounds load on demand and reuse cache',
    () async {
      final loader = await openTour();
      expect(repository.requests, ['selected/current']);
      expect(loader.isCatalogComplete, isFalse);
      expect(container.exists(gamesLocalStorage), isFalse);
      await loader.setActiveRounds({'current', 'old'});
      expect(repository.requests, ['selected/current', 'selected/old']);
      await loader.setActiveRounds({});
      await loader.setActiveRounds({'old'});
      expect(repository.requests.length, 2);
      await loader.refreshGames();
      expect(repository.requests.last, 'selected/old');
      expect(repository.requests, isNot(contains('selected/ancient')));
    },
  );

  test(
    'sibling structural consumers never bootstrap another category',
    () async {
      container.listen(gamesTourProvider('other-category'), (_, _) {});
      final loader = container.read(
        gamesTourProvider('other-category').notifier,
      );
      await loader.setActiveRounds({});
      expect(repository.requests, isEmpty);
      await loader.setActiveRounds({'old'});
      expect(repository.requests, ['other-category/old']);
    },
  );

  test('collapse cancels queued older rounds during Expand all', () async {
    final loader = await openTour();
    repository.oldRoundGate = Completer<void>();
    final expanding = loader.setActiveRounds({'current', 'old', 'ancient'});
    await Future<void>.delayed(Duration.zero);
    loader.deactivateRounds();
    repository.oldRoundGate!.complete();
    await expanding;
    expect(repository.requests, ['selected/current', 'selected/old']);
  });

  test(
    'complete catalog is requested explicitly and stays complete for standings',
    () async {
      final loader = await openTour();
      final results = await loader.waitForCompleteCatalog();
      expect(results.length, 3);
      expect(loader.isCatalogComplete, isTrue);
      expect(storage.completeRequests, 1);
      await loader.waitForCompleteCatalog();
      expect(storage.completeRequests, 1);
    },
  );

  test('only expanded display sections contribute source round requests', () {
    final rounds = [
      const GamesAppBarModel(
        id: 'current',
        name: '',
        startsAt: null,
        roundStatus: RoundStatus.live,
      ),
      const GamesAppBarModel(
        id: 'old',
        name: '',
        startsAt: null,
        roundStatus: RoundStatus.completed,
      ),
      const GamesAppBarModel(
        id: 'knockout-stage-sibling',
        name: '',
        startsAt: null,
        roundStatus: RoundStatus.completed,
        sourceRoundIds: ['leg-1', 'leg-2'],
      ),
    ];
    expect(
      expandedTournamentRoundDemand(
        selectedTourId: 'selected',
        knownTourIds: ['selected', 'sibling'],
        rounds: rounds,
        expansion: {'current': true},
      ),
      {
        'selected': {'current'},
      },
    );
    expect(
      expandedTournamentRoundDemand(
        selectedTourId: 'selected',
        knownTourIds: ['selected', 'sibling'],
        rounds: rounds,
        expansion: {'current': true, 'old': false},
        visibleRoundIds: {'old'},
      ),
      {
        'selected': {'current', 'old'},
      },
    );
    expect(
      expandedTournamentRoundDemand(
        selectedTourId: 'selected',
        knownTourIds: ['selected', 'sibling'],
        rounds: rounds,
        expansion: {'knockout-stage-sibling': true},
      ),
      {
        'selected': <String>{},
        'sibling': {'leg-1', 'leg-2'},
      },
    );
  });

  test(
    'metadata refresh preserves manual collapse and bulk actions reach late team cards',
    () {
      final rounds = RoundExpansionNotifier();
      final matches = MatchExpansionNotifier();
      addTearDown(rounds.dispose);
      addTearDown(matches.dispose);
      rounds.initializeRound('current');
      expect(rounds.isExpanded('old'), isFalse);
      rounds.collapseAll(['current', 'old']);
      matches.collapseAll([]);
      rounds.initializeRound('current');
      expect(rounds.isExpanded('current'), isFalse);
      final lateKey = teamMatchExpansionKey('old', 'A vs B');
      expect(matches.isExpanded(lateKey), isFalse);
      rounds.expandAll(['current', 'old']);
      matches.expandAll();
      expect(rounds.isExpanded('old'), isTrue);
      expect(matches.isExpanded(lateKey), isTrue);
      matches.toggleMatch(lateKey);
      expect(
        matches.isExpanded(teamMatchExpansionKey('current', 'A vs B')),
        isTrue,
      );
    },
  );
}

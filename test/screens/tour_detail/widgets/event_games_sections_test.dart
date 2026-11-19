import 'dart:async';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_list_presentation_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_quick_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The sections Collapse all reads in one category's Games list, from the
/// real providers: it folds every round the list shows, and a search (which
/// shows every hit open under inert headers) leaves nothing to fold.

GamesAppBarModel _round(
  String id, {
  RoundStatus status = RoundStatus.ongoing,
}) => GamesAppBarModel(
  id: id,
  name: 'Round $id',
  startsAt: null,
  roundStatus: status,
);

/// The single-category screen model, swapped in place as a search starts
/// and ends.
class _Screen extends GamesTourScreenProvider {
  _Screen({required super.ref}) : super.loading() {
    show(isSearchMode: false);
  }

  void show({required bool isSearchMode}) {
    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels: const [],
        pinnedGamedIs: const [],
        isSearchMode: isSearchMode,
        searchQuery: isSearchMode ? 'Carlsen' : null,
      ),
    );
  }
}

TourDetailViewModel _event({String? format}) => TourDetailViewModel(
  aboutTourModel: const AboutTourModel(
    id: 'tour-1',
    slug: 'test-open',
    name: 'Test Open',
    description: '',
    imageUrl: '',
    players: [],
    timeControl: '90+30',
    date: '1 Jan 2026',
    location: '',
    websiteUrl: '',
    standingsUrl: '',
    tourUrl: '',
  ),
  liveTourIds: const [],
  tours: [
    TourModel(
      tour: Tour.virtual(
        id: 'tour-1',
        name: 'Test Open',
        slug: 'test-open',
        dates: [DateTime.utc(2026, 1, 1), DateTime.utc(2026, 1, 9)],
        players: const [],
        format: format,
      ),
      roundStatus: RoundStatus.ongoing,
    ),
  ],
);

/// One category whose list shows [shownRoundIds]. With no [rounds] the app
/// bar knows no round yet, so only the rounds on screen are foldable.
List<Override> _singleCategory({
  required List<String> shownRoundIds,
  String? format,
  List<Round>? rounds,
  List<Games> games = const [],
}) => [
  combinedCategorySelectedProvider.overrideWithValue(false),
  gamesTourScreenProvider.overrideWith((ref) => _Screen(ref: ref)),
  gamesTourDisplayRoundsProvider.overrideWithValue([
    for (final id in shownRoundIds) _round(id),
  ]),
  tourDetailScreenProviderOverride(_event(format: format)),
  knockoutTournamentStateProvider.overrideWith(
    (ref, tourId) => const KnockoutTournamentState.empty(),
  ),
  liveRoundsIdProvider.overrideWith(
    (ref) => const Stream<List<String>>.empty(),
  ),
  if (rounds == null)
    gamesAppBarTourIdProvider.overrideWith((ref) => null)
  else ...[
    gamesAppBarTourIdProvider.overrideWith((ref) => 'tour-1'),
    roundRepositoryProvider.overrideWithValue(_Rounds(rounds)),
    gamesAppBarGamesProvider.overrideWith(
      (ref, tourId) => AsyncValue.data(games),
    ),
    roundMetadataChangesProvider.overrideWith(
      (ref, tourId) => const Stream<String>.empty(),
    ),
  ],
];

/// A container kept alive on [eventGamesSectionsProvider], as the button
/// keeps it on screen.
ProviderContainer _container(List<Override> overrides) {
  final container = ProviderContainer(overrides: overrides);
  final sub = container.listen(eventGamesSectionsProvider, (_, _) {});
  addTearDown(() {
    sub.close();
    container.dispose();
  });
  return container;
}

void main() {
  test(
    'folds a Lichess pairings card with the rounds that have games',
    () async {
      // Rounds 1 and 2 have games in the database; round 3's boards are on
      // screen from Lichess while the backend sync lags, so the app bar counts
      // no games for it. Round 1 is off screen.
      final container = _container(
        _singleCategory(
          shownRoundIds: ['round-2', 'round-3'],
          rounds: [
            _dbRound('round-1', day: 1),
            _dbRound('round-2', day: 2),
            _dbRound('round-3', day: 3),
          ],
          games: [_dbGame('round-1'), _dbGame('round-2')],
        ),
      );
      await _waitFor(
        () =>
            container
                .read(gamesAppBarProvider)
                .valueOrNull
                ?.gamesAppBarModels
                .length ==
            3,
        debugState: () => '${container.read(gamesAppBarProvider)}',
      );
      expect(
        container.read(gamesAppBarProvider.notifier).getAllRoundIdsWithGames(),
        unorderedEquals(['round-1', 'round-2']),
      );
      final sections = container.read(eventGamesSectionsProvider);
      expect(sections.roundIds, ['round-2', 'round-3']);
      expect(
        sections.foldRoundIds,
        unorderedEquals(['round-1', 'round-2', 'round-3']),
      );

      toggleEventGamesSections(container.read);
      expect(container.read(roundExpansionProvider), {
        'round-1': false,
        'round-2': false,
        'round-3': false,
      });
      expect(eventGamesSectionsCollapsed(container.read, sections), isTrue);

      // Everything is folded, so the next press opens it all again.
      toggleEventGamesSections(container.read);
      expect(container.read(roundExpansionProvider), {
        'round-1': true,
        'round-2': true,
        'round-3': true,
      });
      expect(eventGamesSectionsCollapsed(container.read, sections), isFalse);
    },
  );

  test('a search leaves nothing to fold, and the folds outlast it', () {
    final container = _container(
      _singleCategory(shownRoundIds: ['round-1', 'round-2']),
    );
    final screen = container.read(gamesTourScreenProvider.notifier) as _Screen;
    toggleEventGamesSections(container.read);
    const folded = {'round-1': false, 'round-2': false};
    expect(container.read(roundExpansionProvider), folded);

    screen.show(isSearchMode: true);
    expect(container.read(eventGamesSectionsProvider), EventGamesSections.none);
    expect(container.read(eventGamesSectionsProvider).isEmpty, isTrue);
    // A press during the search changes nothing behind the hits.
    toggleEventGamesSections(container.read);
    expect(container.read(roundExpansionProvider), folded);

    screen.show(isSearchMode: false);
    final sections = container.read(eventGamesSectionsProvider);
    expect(sections.roundIds, ['round-1', 'round-2']);
    expect(eventGamesSectionsCollapsed(container.read, sections), isTrue);
  });

  test('team matchups open every round through a search too', () {
    // The team list shows every hit open under inert headers, as the board
    // list does: a search leaves nothing to fold, and the folds outlast it.
    final container = _container(
      _singleCategory(
        shownRoundIds: ['round-1', 'round-2'],
        format: 'Team Swiss',
      ),
    );
    final screen = container.read(gamesTourScreenProvider.notifier) as _Screen;
    toggleEventGamesSections(container.read);
    const folded = {'round-1': false, 'round-2': false};
    expect(container.read(roundExpansionProvider), folded);

    screen.show(isSearchMode: true);
    expect(container.read(eventGamesSectionsProvider), EventGamesSections.none);
    toggleEventGamesSections(container.read);
    expect(container.read(roundExpansionProvider), folded);

    screen.show(isSearchMode: false);
    final sections = container.read(eventGamesSectionsProvider);
    expect(sections.roundIds, ['round-1', 'round-2']);
    expect(eventGamesSectionsCollapsed(container.read, sections), isTrue);
  });
}

Round _dbRound(String id, {required int day}) => Round(
  id: id,
  slug: id,
  tourId: 'tour-1',
  tourSlug: 'tour-1',
  name: 'Round ${id.split('-').last}',
  createdAt: DateTime.utc(2026, 1, 1),
  startsAt: DateTime.utc(2026, 1, day, 14),
  url: 'https://lichess.org/broadcast/tour/$id',
);

Games _dbGame(String roundId) => Games(
  id: 'game-$roundId',
  roundId: roundId,
  roundSlug: roundId,
  tourId: 'tour-1',
  tourSlug: 'tour-1',
  status: '1-0',
  fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
);

/// The event's rounds, with no database behind them.
class _Rounds implements RoundRepository {
  _Rounds(this.rounds);

  final List<Round> rounds;

  @override
  Future<List<Round>> getRoundsByTourId(String tourId) async => rounds;

  @override
  Future<Round?> getLatestRoundByLastMove(String tourId) async => null;

  @override
  Future<List<Round>> getRoundsByIds(List<String> ids) async => [
    for (final round in rounds)
      if (ids.contains(round.id)) round,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
  String Function()? debugState,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out${debugState == null ? '' : ': ${debugState()}'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

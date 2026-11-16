import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_standings.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
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

/// The providers behind the Combined Standings tab, run for real: a category
/// other than the selected one must get its own table, a team opened from it
/// must stay scoped to it, and nothing may fall back to "loading" or to a
/// table of zeros once a table has been shown.

class _MemoryStore implements TourSelectionStore {
  final Map<String, String> values = {};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}

class _FixedGroups extends CombinedStandingsGroupsNotifier {
  _FixedGroups(this.groups);

  final CombinedStandingsGroups groups;

  @override
  CombinedStandingsGroups build() => groups;
}

const _eventId = 'olympiad';

/// A published table: every player ranked, so no rating lookup is needed.
Tour _tour(String id, List<String> players, {bool teams = false}) =>
    Tour.fromJson({
      'id': id,
      'name': 'Olympiad | $id',
      'slug': id,
      'created_at': '2026-09-16T00:00:00Z',
      'url': 'https://example.test/$id',
      'tier': 1,
      'dates': ['2026-09-16T00:00:00Z'],
      'group_broadcast_id': _eventId,
      'info': <String, dynamic>{},
      'players': [
        for (var i = 0; i < players.length; i++)
          {
            'name': players[i],
            'title': 'GM',
            'fed': 'NOR',
            'rating': 2700 - i,
            'rank': i + 1,
            'played': 3,
            'score': 3.0 - i,
            if (teams) 'team': i.isEven ? 'Norway' : 'India',
          },
      ],
    });

final _open = _tour('open', ['Open One', 'Open Two']);
final _women = _tour('women', ['Women One', 'Women Two', 'Women Three']);
final _juniors = _tour('juniors', const []);

const _groups = CombinedStandingsGroups([
  CombinedStandingsGroup(tourIds: ['open'], label: 'Open', isTeam: false),
  CombinedStandingsGroup(tourIds: ['women'], label: 'Women', isTeam: false),
  CombinedStandingsGroup(tourIds: ['juniors'], label: 'Juniors', isTeam: false),
]);

/// What the women's boards are doing: loaded, or being refetched.
final _womenCatalog = StateProvider<AsyncValue<List<Games>>>(
  (ref) => const AsyncData(<Games>[]),
);

ProviderContainer _container({List<Override> overrides = const []}) {
  final container = ProviderContainer(
    overrides: [
      selectedBroadcastModelProvider.overrideWith(
        (ref) => GroupBroadcast(
          id: _eventId,
          name: 'Olympiad',
          createdAt: DateTime.utc(2026, 9, 16),
          search: const [],
        ),
      ),
      tourSelectionStoreProvider.overrideWithValue(_MemoryStore()),
      tourDetailScreenProviderOverride(
        TourDetailViewModel(
          aboutTourModel: AboutTourModel.fromTour(_open),
          liveTourIds: const [],
          tours: [
            for (final tour in [_open, _women, _juniors])
              TourModel(tour: tour, roundStatus: RoundStatus.ongoing),
          ],
        ),
      ),
      completeGamesTourFutureProvider(
        'open',
      ).overrideWith((ref) async => const <Games>[]),
      completeGamesTourProvider(
        'open',
      ).overrideWith((ref) => const AsyncData(<Games>[])),
      completeGamesTourProvider(
        'women',
      ).overrideWith((ref) => ref.watch(_womenCatalog)),
      completeGamesTourProvider(
        'juniors',
      ).overrideWith((ref) => const AsyncData(<Games>[])),
      combinedStandingsGroupsProvider.overrideWith(() => _FixedGroups(_groups)),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

List<String> _names(List<PlayerStandingModel> players) => [
  for (final player in players) player.name,
];

TeamStandingModel _team(String name) => TeamStandingModel(
  teamName: name,
  rank: 1,
  matchPoints: 2,
  gamePoints: 3,
  matchesWon: 1,
  matchesDrawn: 0,
  matchesLost: 0,
  boardsPlayed: 4,
  players: const [],
);

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

  test('a category other than the selected one gets its own table', () async {
    final container = _container();
    container.listen(categoryStandingsProvider('women'), (_, __) {});

    final women = await container.read(
      categoryStandingsProvider('women').future,
    );

    expect(_names(women), ['Women One', 'Women Two', 'Women Three']);
    expect([for (final player in women) player.overallRank], [1, 2, 3]);
  });

  test('the selected category is computed once and shared', () async {
    final container = _container();
    container.listen(playerTourScreenProvider, (_, __) {});
    container.listen(categoryStandingsProvider('open'), (_, __) {});

    final selected = await container.read(playerTourScreenProvider.future);
    final category = await container.read(
      categoryStandingsProvider('open').future,
    );

    expect(_names(selected), ['Open One', 'Open Two']);
    expect(identical(category, selected), isTrue);
  });

  test('one section per category that has a table, in the given order, '
      'each ranked on its own', () async {
    final container = _container();
    const view = CombinedStandingsView.standings;
    container.listen(combinedStandingsProvider(view), (_, __) {});
    // First paint waits for every table.
    expect(container.read(combinedStandingsProvider(view)).isLoading, isTrue);

    await container.read(categoryStandingsProvider('open').future);
    await container.read(categoryStandingsProvider('women').future);
    await container.read(categoryStandingsProvider('juniors').future);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(combinedStandingsProvider(view));
    expect(state.isLoading, isFalse);
    // Juniors has nobody to rank yet, so it has no section.
    expect([for (final s in state.sections) s.group.label], ['Open', 'Women']);
    expect(state.tableCount, 2);
    expect(state.sections.first.isSelectedCategory, isTrue);
    expect(state.sections.last.isSelectedCategory, isFalse);
    expect(_names(state.sections.last.players).first, 'Women One');
    expect(state.sections.last.players.first.overallRank, 1);
  });

  test('a search filters every table and keeps counting the tables', () async {
    final container = _container();
    const view = CombinedStandingsView.standings;
    container.listen(combinedStandingsProvider(view), (_, __) {});
    await container.read(categoryStandingsProvider('open').future);
    await container.read(categoryStandingsProvider('women').future);
    await container.read(categoryStandingsProvider('juniors').future);
    await Future<void>.delayed(Duration.zero);

    container.read(standingsSearchQueryProvider.notifier).state = 'women t';

    final state = container.read(combinedStandingsProvider(view));
    expect([for (final s in state.sections) s.group.label], ['Women']);
    expect(_names(state.sections.single.players), ['Women Two', 'Women Three']);
    expect(state.sections.single.total, 3);
    // Still two tables in the event: the one section keeps its header.
    expect(state.tableCount, 2);
  });

  test('a team table from the boards is kept while the boards are '
      'refetched, never rebuilt on zero games', () async {
    final teamed = _tour('women', ['Women One', 'Women Two'], teams: true);
    final players = [
      for (final player in teamed.players)
        PlayerStandingModel.fromPlayer(player),
    ];
    final container = _container(
      overrides: [
        categoryStandingsProvider('women').overrideWith((ref) async => players),
      ],
    );
    container.read(_womenCatalog.notifier).state = const AsyncLoading();
    container.listen(categoryTeamStandingsProvider('women'), (_, __) {});
    await container.read(categoryStandingsProvider('women').future);
    await Future<void>.delayed(Duration.zero);

    // No complete catalog yet: loading, not a table computed from nothing.
    expect(
      container.read(categoryTeamStandingsProvider('women')).hasValue,
      isFalse,
    );

    container.read(_womenCatalog.notifier).state = const AsyncData(<Games>[]);
    final table = container
        .read(categoryTeamStandingsProvider('women'))
        .requireValue;

    // A refetch (resume, pull to refresh) drops the catalog to loading.
    container.read(_womenCatalog.notifier).state = const AsyncLoading();
    expect(
      identical(
        container.read(categoryTeamStandingsProvider('women')).requireValue,
        table,
      ),
      isTrue,
    );
  });

  group('a team opened from another category', () {
    Future<ProviderContainer> combined() async {
      final container = _container();
      await container
          .read(combinedCategoryPrefsProvider.notifier)
          .setSelected(_eventId, true);
      expect(container.read(combinedCategorySelectedProvider), isTrue);
      return container;
    }

    test('is scoped to that category', () async {
      final container = await combined();
      final india = _team('India');
      container.read(selectedTeamProvider.notifier).state = india;
      container.read(selectedTeamCategoryProvider.notifier).state = (
        team: india,
        tourId: 'women',
      );

      expect(container.read(selectedTeamTourIdProvider), 'women');
    });

    test('a team of the same name opened another way is not', () async {
      final container = await combined();
      container.read(selectedTeamCategoryProvider.notifier).state = (
        team: _team('India'),
        tourId: 'women',
      );
      // The Games tab or a link selects its own "India": the Open one.
      container.read(selectedTeamProvider.notifier).state = _team('India');

      expect(container.read(selectedTeamTourIdProvider), isNull);
    });

    test('the scope ends when the event leaves Combined', () async {
      final container = await combined();
      final india = _team('India');
      container.read(selectedTeamProvider.notifier).state = india;
      container.read(selectedTeamCategoryProvider.notifier).state = (
        team: india,
        tourId: 'women',
      );
      expect(container.read(selectedTeamTourIdProvider), 'women');

      await container
          .read(combinedCategoryPrefsProvider.notifier)
          .setSelected(_eventId, false);

      expect(container.read(selectedTeamTourIdProvider), isNull);
    });

    test('the selected category itself needs no scope', () async {
      final container = await combined();
      final india = _team('India');
      container.read(selectedTeamProvider.notifier).state = india;
      container.read(selectedTeamCategoryProvider.notifier).state = (
        team: india,
        tourId: 'open',
      );

      expect(container.read(selectedTeamTourIdProvider), isNull);
    });
  });
}

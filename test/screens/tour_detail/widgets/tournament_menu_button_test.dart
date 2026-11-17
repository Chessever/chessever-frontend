import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/event_mute_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  // The Games-tab menu reads the event's pin store, which opens the local
  // database. Answer its platform calls with a failure at once, so the stores
  // fall back to empty inside the test clock instead of waiting on a plugin
  // that is not there.
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in _storageChannels) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'unavailable'),
      );
    }
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in _storageChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  group('standingsShareActionsFor', () {
    test('games tab never includes standings share actions', () {
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.games,
          isTeamEvent: false,
        ),
        isEmpty,
      );
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.games,
          isTeamEvent: true,
        ),
        isEmpty,
      );
    });

    test('about and bracket tabs never include standings share actions', () {
      for (final mode in [
        TournamentDetailScreenMode.about,
        TournamentDetailScreenMode.bracket,
      ]) {
        expect(
          standingsShareActionsFor(mode: mode, isTeamEvent: false),
          isEmpty,
        );
        expect(
          standingsShareActionsFor(mode: mode, isTeamEvent: true),
          isEmpty,
        );
      }
    });

    test('non-team standings tab shows Share standings only', () {
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.standings,
          isTeamEvent: false,
        ),
        [TournamentMenuAction.shareStandings],
      );
    });

    test('team standings tab shows Share team standings only', () {
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.standings,
          isTeamEvent: true,
        ),
        [TournamentMenuAction.shareTeamStandings],
      );
    });

    test('team players tab (individual table) shows Share standings only', () {
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.players,
          isTeamEvent: true,
        ),
        [TournamentMenuAction.shareStandings],
      );
    });

    test('players mode on non-team events shows nothing (tab not used)', () {
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.players,
          isTeamEvent: false,
        ),
        isEmpty,
      );
    });
  });

  group('Games tab menu', () {
    for (final combined in [false, true]) {
      final path = combined ? 'Combined' : 'one category';
      testWidgets('keeps its rows but no Live first or Collapse all ($path)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            overrides: _gamesTab(combined: combined),
            child: const TournamentMenuButton(tourData: _tourData),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(TournamentMenuButton));
        await tester.pumpAndSettle();

        // What stays in the ⋮ menu on the Games tab.
        expect(find.text('No Spoilers'), findsOneWidget);
        expect(find.text('Pin all'), findsOneWidget);
        expect(find.text('Share event'), findsOneWidget);
        // Moved beside the search field (event_games_quick_actions.dart).
        for (final gone in [
          'Live games first',
          'Board order',
          'Collapse all',
          'Expand all',
        ]) {
          expect(find.text(gone), findsNothing, reason: gone);
        }
        await _settleMenuDependencies(tester);
      });
    }
  });

  group('header glyph', () {
    testWidgets('boxed by default, bare on a 44pt target when asked', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          overrides: _gamesTab(combined: false),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TournamentMenuButton(key: ValueKey('boxed'), tourData: _tourData),
              TournamentMenuButton(
                key: ValueKey('bare'),
                tourData: _tourData,
                boxed: false,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      Iterable<BoxDecoration> tiles(String key) => tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Container),
            ),
          )
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.color != null);

      expect(tiles('boxed'), isNotEmpty);
      expect(tiles('bare'), isEmpty);
      final bare = tester.getSize(find.byKey(const ValueKey('bare')));
      expect(bare.width, greaterThanOrEqualTo(44));
      expect(bare.height, greaterThanOrEqualTo(44));

      await tester.tap(find.byKey(const ValueKey('bare')));
      await tester.pumpAndSettle();
      expect(find.text('Share event'), findsOneWidget);
      await _settleMenuDependencies(tester);
    });
  });
}

/// Opening the Games-tab menu reads the event's real pin store, which starts
/// loading games and arms its auto-pin timeout. Tear the tree down and let
/// those timers run out so nothing outlives the test.
Future<void> _settleMenuDependencies(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

const _about = AboutTourModel(
  id: 'tour-1',
  slug: 'sinquefield-cup-2026',
  name: 'Sinquefield Cup 2026',
  description: '',
  imageUrl: '',
  players: [],
  timeControl: '90+30',
  date: 'Aug 1 - 9, 2026',
  location: 'Saint Louis',
  websiteUrl: '',
  standingsUrl: '',
  tourUrl: '',
  groupBroadcastId: 'group-1',
);

const _tourData = TourDetailViewModel(
  aboutTourModel: _about,
  liveTourIds: [],
  tours: [],
);

List<Override> _gamesTab({required bool combined}) => [
  tourDetailScreenProviderOverride(_tourData),
  selectedBroadcastModelProvider.overrideWith(
    (ref) => GroupBroadcast(
      id: 'group-1',
      createdAt: DateTime(2026, 8, 1),
      name: 'Sinquefield Cup 2026',
      search: const [],
    ),
  ),
  selectedTourModeProvider.overrideWith(
    (ref) => TournamentDetailScreenMode.games,
  ),
  eventMuteProvider.overrideWith(_NotMuted.new),
  isTeamEventProvider.overrideWith((ref, id) => false),
  knockoutTournamentStateProvider.overrideWith(
    (ref, id) => const KnockoutTournamentState.empty(),
  ),
  gamesAppBarTourIdProvider.overrideWith((ref) => null),
  combinedCategorySelectedProvider.overrideWithValue(combined),
  if (combined)
    combinedCategoriesProvider.overrideWithValue(
      const CombinedCategories([
        CombinedCategory(tourId: 'open', label: 'Open', avgElo: 2700, order: 0),
        CombinedCategory(
          tourId: 'women',
          label: 'Women',
          avgElo: 2500,
          order: 1,
        ),
      ]),
    ),
];

Widget _host({required List<Override> overrides, required Widget child}) {
  return ProviderScope(
    overrides: [
      spaceShortcutsProvider.overrideWith(_MemorySpaceShortcuts.new),
      gamesLocalStorage.overrideWith((ref) => _NoGamesLocalStorage(ref)),
      appDatabaseProvider.overrideWithValue(_NoAppDatabase()),
      autoPinPreferencesProvider.overrideWith(_DefaultAutoPin.new),
      favoritePlayersProviderNew.overrideWith(_NoFavoritePlayers.new),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _MemoryNoSpoilers(ref, tourId),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(alignment: Alignment.topCenter, child: child),
            ),
          );
        },
      ),
    ),
  );
}

/// The Games-tab menu reads the event's pin store, which loads the event's
/// games: none here, and no database or network behind them.
class _NoGamesLocalStorage extends GamesLocalStorage {
  _NoGamesLocalStorage(super.ref);

  @override
  Future<List<Games>> getCachedGames(String tourId) async => const [];

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
    String? priorityRoundId,
    void Function(List<Games>)? onPriorityRound,
    Future<void> Function()? afterPriorityRound,
    bool rethrowErrors = false,
  }) async => const [];
}

const _storageChannels = [
  MethodChannel('com.tekartik.sqflite'),
  MethodChannel('plugins.flutter.io/path_provider'),
];

/// Local pins and preferences read as empty: every query fails the way an
/// unavailable database does, and the stores fall back to nothing.
class _NoAppDatabase implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('No database in this test'));
}

class _DefaultAutoPin extends AutoPinPreferencesNotifier {
  @override
  Future<AutoPinPreferences> build() async => AutoPinPreferences.defaults;
}

class _NoFavoritePlayers extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

class _MemorySpaceShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

class _MemoryNoSpoilers extends EventNoSpoilersController {
  _MemoryNoSpoilers(Ref ref, String tourId) : super(ref: ref, tourId: tourId);

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _NotMuted extends EventMuteNotifier {
  @override
  Future<bool> build(String arg) async => false;
}

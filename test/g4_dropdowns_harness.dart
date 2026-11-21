// Shared scenes for the G4 dropdown / anchored-panel tests: every popover the
// group owns, opened over a busy page (live boards), in either theme.
//
// Not a test file on its own: g4_dropdowns_open_perf_test.dart,
// g4_dropdowns_glass_test.dart and g4_dropdowns_preview_test.dart drive it.
// Every scene is opened the way a reader opens it (a tap on its trigger), so
// the same scenes measure the code before and after the glass conversion.
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/library/providers/book_games_search_provider.dart';
import 'package:chessever2/screens/library/widgets/book_games_filter_dialog.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filter_popup.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/category_dropdown.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/widget/text_dropdown_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessground/chessground.dart';
import 'package:country_picker/country_picker.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const g4Capture = ValueKey('g4_capture');
const g4Screen = Size(393, 852);

const _fens = [
  'r1bqkb1r/pp3ppp/2nppn2/8/3NP3/2N5/PPP1BPPP/R1BQK2R w KQkq - 0 7',
  'rnbqk2r/ppp1bppp/4pn2/3p4/2PP4/2N2N2/PP2PPPP/R1BQKB1R w KQkq - 2 5',
  'r2q1rk1/pp1nbppp/2p1pn2/3p4/2PP4/1PN1PN2/PB3PPP/R2QKB1R w KQ - 1 9',
];

const _pairings = [
  ('GM Firouzja, Alireza', 2759, 'GM Caruana, Fabiano', 2795),
  ('GM Nakamura, Hikaru', 2802, 'GM Gukesh, D', 2777),
  ('GM Abdusattorov, Nodirbek', 2766, 'GM Erigaisi, Arjun', 2778),
];

/// A column of live boards: the busiest thing a dropdown opens over.
class G4BusyBoards extends StatelessWidget {
  const G4BusyBoards({super.key, this.top = 0});

  final double top;

  @override
  Widget build(BuildContext context) {
    const settings = BoardSettingsNew();
    final colors = context.colors;
    Widget player(String name, int rating, String clock) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$name  $rating',
              style: AppTypography.textSmMedium.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            clock,
            style: AppTypography.textSmMedium.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, top, 16, 120),
      children: [
        for (var i = 0; i < _fens.length; i++) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                player(_pairings[i].$1, _pairings[i].$2, '1:42:10'),
                StaticChessboard(
                  size: 341,
                  orientation: Side.white,
                  fen: _fens[i],
                  settings: StaticChessboardSettings(
                    colorScheme: settings.colorScheme,
                    pieceAssets: settings.pieceAssets,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                player(_pairings[i].$3, _pairings[i].$4, '1:38:55'),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _MemoryStore implements TourSelectionStore {
  final Map<String, String> values = {};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}

Tour _tour(String id, String name) => Tour.virtual(
  id: id,
  name: name,
  slug: id,
  dates: [DateTime.utc(2026, 11, 7), DateTime.utc(2026, 11, 14)],
  players: const [],
);

/// A smart event already read, so the page under the tier menu is the real
/// page, its games listed, never its error state. It reads nothing: the real
/// notifier starts its first read in its constructor, which a test (with no
/// backend) answers with an error that would replace any state set here.
class _LoadedAggregateNotifier
    extends StateNotifier<AsyncValue<SmartAggregateEvent>>
    implements SmartAggregateEventNotifier {
  _LoadedAggregateNotifier() : super(AsyncValue.data(_smartEvent));

  @override
  Future<void> loadMore() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final SmartAggregateEvent _smartEvent = () {
  PlayerCard player(String name, String fed, int rating) => PlayerCard(
    name: name,
    federation: fed,
    title: 'GM',
    rating: rating,
    countryCode: fed,
    team: null,
  );
  final day = DateTime.utc(2026, 11, 20, 15);
  final games = [
    for (final (i, white, black, status, fen) in [
      (
        1,
        player('Carlsen, Magnus', 'NOR', 2833),
        player('Caruana, Fabiano', 'USA', 2795),
        GameStatus.whiteWins,
        'r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P4/2PBPN2/PP1N1PPP/R1BQ1RK1 w - - 0 8',
      ),
      (
        2,
        player('Nakamura, Hikaru', 'USA', 2802),
        player('Gukesh, D', 'IND', 2767),
        GameStatus.draw,
        'rnbqkb1r/pp3ppp/4pn2/2pp4/3P4/2P1PN2/PP3PPP/RNBQKB1R w KQkq - 0 5',
      ),
      (
        3,
        player('Firouzja, Alireza', 'FRA', 2759),
        player('Abdusattorov, Nodirbek', 'UZB', 2766),
        GameStatus.blackWins,
        'r2q1rk1/1b2bppp/p2ppn2/1p6/3NP3/1BN1B3/PPP2PPP/R2Q1RK1 w - - 0 11',
      ),
      (
        4,
        player('Nepomniachtchi, Ian', 'RUS', 2754),
        player('Ding, Liren', 'CHN', 2734),
        GameStatus.draw,
        'r1bqk2r/ppp1bppp/2np1n2/4p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - 2 6',
      ),
    ])
      GamesTourModel(
        gameId: 'smart-$i',
        whitePlayer: white,
        blackPlayer: black,
        whiteTimeDisplay: '--:--',
        blackTimeDisplay: '--:--',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: status,
        roundId: 'round-1',
        tourId: 'tour-1',
        fen: fen,
        boardNr: i,
        lastMoveTime: day,
      ),
  ];
  return SmartAggregateEvent(
    games: games,
    tournamentCount: 1,
    avgElo: 2776,
    minElo: 2734,
    tournamentNames: const ['Grand Chess Tour Finals 2026'],
    dateStart: day,
    dateEnd: day,
    timeControls: const ['Classical'],
    pinnedGameIds: const [],
    events: const [],
    gameEventNames: {
      for (final g in games) g.gameId: 'Grand Chess Tour Finals 2026',
    },
    gameEventIds: {for (final g in games) g.gameId: 'tour-1'},
  );
}();

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

class _Country extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _Country() : super(AsyncData(CountryService().findByCode('NO')!));

  @override
  String getCountryName(String code) => CountryService().findByCode(code)!.name;

  @override
  void selectCountry(String code) {
    state = AsyncData(CountryService().findByCode(code)!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One popover of the group: how to put its page on screen, the trigger a
/// reader taps, and text that only the open popover draws.
class G4Scene {
  const G4Scene({
    required this.name,
    required this.pump,
    required this.trigger,
    required this.marker,
  });

  final String name;
  final Future<void> Function(WidgetTester tester, {required bool light}) pump;
  final Finder Function() trigger;
  final Finder Function() marker;
}

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = g4Screen * 3;
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Widget _app({
  required bool light,
  required Widget home,
  NavigatorObserver? observer,
}) => RepaintBoundary(
  key: g4Capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
    navigatorObservers: [?observer],
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return home;
      },
    ),
  ),
);

/// A trigger pinned over the top of the busy page.
Widget _overBoards(Widget trigger, {double top = 70}) => Scaffold(
  body: Stack(
    children: [
      const Positioned.fill(child: G4BusyBoards(top: 130)),
      Positioned(left: 16, right: 16, top: top, child: trigger),
    ],
  ),
);

const _groupId = 'g4_open';

final g4Scenes = <G4Scene>[
  G4Scene(
    name: 'category_dropdown',
    trigger: () => find.byType(CategoryDropdown),
    marker: () => find.text('Women'),
    pump: (tester, {required light}) async {
      _phone(tester);
      final tours = [
        for (final name in ['Open', 'Women', 'U18', 'U16', 'U14', 'Seniors'])
          _tour('tour-$name', name),
      ];
      final broadcast = GroupBroadcast.fromJson({
        'id': _groupId,
        'created_at': '2026-11-05T19:50:50.000Z',
        'name': 'Isle of Man Masters',
        'search': const <String>[],
      });
      final container = ProviderContainer(
        overrides: [
          selectedBroadcastModelProvider.overrideWith((ref) => broadcast),
          selectedTourModeProvider.overrideWith(
            (ref) => TournamentDetailScreenMode.games,
          ),
          tourSelectionStoreProvider.overrideWithValue(_MemoryStore()),
          gamesAppBarTourIdProvider.overrideWith((ref) => null),
          combinedCategoryEntitledProvider.overrideWithValue(true),
          tourDetailScreenProviderOverride(
            TourDetailViewModel(
              aboutTourModel: AboutTourModel.fromTour(tours.first),
              liveTourIds: const [],
              tours: [
                for (final tour in tours)
                  TourModel(tour: tour, roundStatus: RoundStatus.ongoing),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _app(
            light: light,
            home: Scaffold(
              body: Stack(
                children: const [
                  Positioned.fill(child: G4BusyBoards(top: 130)),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 59,
                    child: GamesAppBarWidget(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    },
  ),
  G4Scene(
    name: 'smart_event_tier',
    trigger: () => find.text('GM+'),
    marker: () => find.text('International Master · 2400+'),
    pump: (tester, {required light}) async {
      _phone(tester);
      final container = ProviderContainer(
        overrides: [
          boardSettingsProviderNew.overrideWith(_BoardSettings.new),
          favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
          spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
          smartAggregateEventRepositoryProvider.overrideWith(
            (ref, query) => _LoadedAggregateNotifier(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _app(
            light: light,
            observer: routeObserver,
            home: SmartEventScreen(
              request: SmartEventRequest(
                source: SmartEventSource.forYou,
                tierLabel: 'GM',
                titleSuffix: 'Games',
                minElo: 2500,
                maxElo: 3200,
                caption: 'From your filters',
                countSingular: 'event',
                countPlural: 'events',
                events: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    },
  ),
  G4Scene(
    name: 'collections_round_select',
    trigger: () => find.byType(TextDropDownWidget),
    marker: () => find.text('Round 3'),
    pump: (tester, {required light}) async {
      _phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: _app(
            light: light,
            home: _overBoards(
              SizedBox(
                height: 56,
                child: Builder(
                  builder: (context) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextDropDownWidget(
                      multiline: true,
                      selectedId: 'all',
                      items: [
                        {
                          'key': 'all',
                          'value': 'All games',
                          'status': 'completed',
                        },
                        for (var round = 1; round <= 24; round++)
                          {
                            'key': 'r$round',
                            'value': 'Round $round',
                            'status': 'completed',
                          },
                      ],
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    },
  ),
  G4Scene(
    name: 'country_picker',
    trigger: () => find.byType(CountryDropdown),
    marker: () => find.text('Oman'),
    pump: (tester, {required light}) async {
      _phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            countryDropdownProvider.overrideWith((ref) => _Country()),
          ],
          child: _app(
            light: light,
            home: _overBoards(
              CountryDropdown(
                selectedCountryCode: 'NO',
                requireAuthToChange: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    },
  ),
  G4Scene(
    name: 'prep_filter_select',
    trigger: () => find.byType(PrepFilterSelect<String>),
    marker: () => find.text('Last 3 months'),
    pump: (tester, {required light}) async {
      _phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: _app(
            light: light,
            home: _overBoards(
              Material(
                type: MaterialType.transparency,
                child: PrepFilterSelect<String>(
                  label: 'Period',
                  value: 'all',
                  items: [
                    for (final (value, label) in const [
                      ('all', 'All time'),
                      ('w', 'Last week'),
                      ('m', 'Last month'),
                      ('q', 'Last 3 months'),
                      ('h', 'Last 6 months'),
                      ('y', 'Last year'),
                    ])
                      DropdownMenuItem(value: value, child: Text(label)),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    },
  ),
  // A dropdown inside a popup that is glass already: the menu's scrim and
  // glass sit over the dialog's.
  G4Scene(
    name: 'book_filter_in_dialog',
    trigger: () => find.text('All Results'),
    marker: () => find.text('½-½'),
    pump: (tester, {required light}) async {
      _phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: _app(
            light: light,
            home: _overBoards(
              Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('g4_open_dialog'),
                  onPressed: () => showBookGamesFilterDialog(
                    context: context,
                    currentFilter: const BookGamesFilter(),
                  ),
                  child: const Text('filters'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      tester
          .widget<TextButton>(find.byKey(const ValueKey('g4_open_dialog')))
          .onPressed!();
      await tester.pump();
      await g4Settle(tester, cap: 90);
    },
  ),
];

/// Taps [scene]'s trigger and pumps frames until its popover is on screen.
/// Returns how many frames that took (1 = the popover is in the frame the
/// tap scheduled).
Future<int> g4Open(WidgetTester tester, G4Scene scene) async {
  final before = scene.marker().evaluate().length;
  await tester.tap(scene.trigger().first, warnIfMissed: false);
  var frames = 0;
  while (frames < 12) {
    await tester.pump();
    frames++;
    if (scene.marker().evaluate().length > before) break;
  }
  return frames;
}

/// Pumps 16 ms frames while any are scheduled, up to [cap].
Future<int> g4Settle(WidgetTester tester, {int cap = 120}) async {
  var frames = 0;
  while (tester.binding.hasScheduledFrame && frames < cap) {
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
  return frames;
}

/// Closes whatever popover is open by tapping the page well clear of it.
Future<void> g4Dismiss(WidgetTester tester) async {
  await tester.tapAt(const Offset(12, 820));
  await tester.pump();
  await g4Settle(tester, cap: 60);
}

/// Whether any render object between [finder]'s and the root fades it.
bool g4UnderOpacity(WidgetTester tester, Finder finder) {
  RenderObject? node = tester.renderObject(finder).parent;
  while (node != null) {
    if (node is RenderOpacity && node.opacity < 1) return true;
    if (node is RenderAnimatedOpacity && node.opacity.value < 1) return true;
    node = node.parent;
  }
  return false;
}

/// Frames until the open popover itself comes to rest: its row ([marker])
/// stops moving and nothing fades it. The trigger's own ripple and any page
/// animation are not counted.
Future<int> g4PanelMotionFrames(
  WidgetTester tester,
  Finder Function() marker, {
  int cap = 120,
}) async {
  Rect? last;
  var still = 0;
  var frames = 0;
  while (frames < cap) {
    final row = marker().last;
    final rect = tester.getRect(row);
    final faded = g4UnderOpacity(tester, row);
    if (rect == last && !faded) {
      if (++still >= 2) return frames - still;
    } else {
      still = 0;
    }
    last = rect;
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
  return frames;
}

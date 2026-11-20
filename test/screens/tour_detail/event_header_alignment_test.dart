import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/category_dropdown.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/tournament_detail_screen.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The event screen's header: the category chip on the screen's centre line
/// (the middle tab's centre), the chevron and the ⋮ equally far in from the
/// tab strip's two edges, the board view and the ⋮ a tight pair on whole
/// 44pt targets, and none of it moving between tabs or states.

const _about = AboutTourModel(
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
  groupBroadcastId: 'gb-1',
);

TourDetailViewModel _viewModel() => TourDetailViewModel(
  aboutTourModel: _about,
  liveTourIds: const [],
  tours: [
    TourModel(
      tour: Tour.virtual(
        id: 'tour-1',
        name: 'Test Open',
        slug: 'test-open',
        dates: [DateTime.utc(2026, 1, 1), DateTime.utc(2026, 1, 9)],
        players: const [],
      ),
      roundStatus: RoundStatus.ongoing,
    ),
  ],
);

List<Override> _overrides({bool loading = false, bool team = false}) => [
  selectedBroadcastModelProvider.overrideWith(
    (ref) => loading
        ? null
        : GroupBroadcast(
            id: 'gb-1',
            createdAt: DateTime(2026),
            name: 'Test Open',
            search: const [],
          ),
  ),
  if (!loading) tourDetailScreenProviderOverride(_viewModel()),
  selectedTourModeProvider.overrideWith(
    (ref) => TournamentDetailScreenMode.games,
  ),
  liveTourIdProvider.overrideWith(
    (ref) => Stream<List<String>>.value(const <String>[]),
  ),
  shouldStreamProvider.overrideWith((ref) => false),
  gamesAppBarTourIdProvider.overrideWith((ref) => null),
  botvinnikEnabledProvider.overrideWith(_DisabledChat.new),
  gamesListViewModeProvider.overrideWithValue(GamesListViewMode.gamesCard),
  engineSettingsProviderNew.overrideWith(_TestEngineSettings.new),
  eventNoSpoilersProvider.overrideWith(
    (ref, tourId) => _TestSpoilers(ref: ref, tourId: tourId),
  ),
  knockoutTournamentStateProvider.overrideWith(
    (ref, tourId) => team
        ? const KnockoutTournamentState(
            isKnockout: false,
            isTeamEvent: true,
            stageName: null,
            allGames: [],
          )
        : const KnockoutTournamentState.empty(),
  ),
  gamesTourScreenProvider.overrideWith(
    (ref) => GamesTourScreenProvider.loading(ref: ref),
  ),
];

Future<void> _pumpScreen(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  bool loading = false,
  bool team = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(loading: loading, team: team),
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const TournamentDetailScreen();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _frames(WidgetTester tester, [int count = 40]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

const _storageChannels = [
  MethodChannel('com.tekartik.sqflite'),
  MethodChannel('plugins.flutter.io/path_provider'),
];

/// The same place and size, to a hundredth of a point.
void _expectSameRect(Rect actual, Rect expected, String reason) {
  expect(actual.left, closeTo(expected.left, 0.01), reason: '$reason left');
  expect(actual.top, closeTo(expected.top, 0.01), reason: '$reason top');
  expect(actual.right, closeTo(expected.right, 0.01), reason: '$reason right');
  expect(
    actual.bottom,
    closeTo(expected.bottom, 0.01),
    reason: '$reason bottom',
  );
}

/// What the header shows, measured on screen.
class _Header {
  _Header(this.tester);

  final WidgetTester tester;

  Rect get chevron => tester.getRect(
    find.byIcon(Icons.arrow_back_ios_new_outlined).hitTestable(),
  );

  /// Material's `arrow_back_ios_new` is inked from 6 of its 24 units.
  double get chevronInkStart => chevron.left + chevron.width * 6 / 24;

  Rect get menuGlyph => tester.getRect(
    find.descendant(
      of: find.byType(TournamentMenuButton),
      matching: find.byType(SvgPicture),
    ),
  );

  /// The ⋮ asset is fitted into its box and its dots are 3 of 24 units
  /// wide, about the centre.
  double get dotsHalfWidth =>
      (menuGlyph.width < menuGlyph.height
          ? menuGlyph.width
          : menuGlyph.height) *
      1.5 /
      24;
  double get dotsStart => menuGlyph.center.dx - dotsHalfWidth;
  double get dotsEnd => menuGlyph.center.dx + dotsHalfWidth;

  Rect get menuTarget => tester.getRect(
    find.descendant(
      of: find.byType(TournamentMenuButton),
      matching: find.byType(AppBarIconSurface),
    ),
  );

  /// The board view's glyph as inked (the asset fills its box).
  Rect get toggleInk => tester.getRect(
    find.descendant(
      of: find.byType(BoardViewGlyph),
      matching: find.byType(SvgPicture),
    ),
  );

  /// The board view's slot: the square its button is moved inside.
  Rect get toggleSlot => tester.getRect(
    find
        .ancestor(
          of: find.byType(BoardViewToggleButton),
          matching: find.byType(Transform),
        )
        .first,
  );

  Rect get chip => tester.getRect(find.byType(CategoryDropdown));

  Rect get strip => tester.getRect(find.byType(SegmentedSwitcher));

  Offset tab(String label) => tester.getCenter(
    find.descendant(
      of: find.byType(SegmentedSwitcher),
      matching: find.text(label),
    ),
  );
}

void main() {
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

  for (final size in const [
    Size(393, 852),
    Size(320, 568),
    Size(430, 932),
    // A tablet window: the header's own scale, the tab strip's wider gutter.
    Size(1024, 1366),
  ]) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('$label: the chip sits on the screen\'s centre line, over the '
        'middle tab, and nothing moves between tabs', (tester) async {
      await _pumpScreen(tester, size: size);
      final header = _Header(tester);
      final centre = size.width / 2;

      ({Rect chevron, Rect menu, Rect chip, Rect strip}) measure() => (
        chevron: header.chevron,
        menu: header.menuGlyph,
        chip: header.chip,
        strip: header.strip,
      );

      expect(header.chip.center.dx, closeTo(centre, 0.5));
      // The middle of a three-tab strip is the screen's centre too.
      expect(header.tab('Games').dx, closeTo(centre, 0.5));
      expect(header.strip.center.dx, closeTo(centre, 0.5));
      final games = measure();

      for (final tabLabel in ['About', 'Standings', 'Games']) {
        await tester.tap(
          find.descendant(
            of: find.byType(SegmentedSwitcher),
            matching: find.text(tabLabel),
          ),
        );
        await tester.pump();
        await _frames(tester);
        expect(tester.takeException(), isNull);
        final now = measure();
        _expectSameRect(now.chevron, games.chevron, '$tabLabel chevron');
        _expectSameRect(now.menu, games.menu, '$tabLabel ⋮');
        _expectSameRect(now.chip, games.chip, '$tabLabel chip');
        _expectSameRect(now.strip, games.strip, '$tabLabel strip');
        expect(now.chip.center.dx, closeTo(centre, 0.5), reason: tabLabel);
      }
      // The board view belongs to Games only, and comes back with it.
      expect(find.byType(BoardViewToggleButton), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('$label: the chevron and the ⋮ stand on the tab strip\'s '
        'edges, one column', (tester) async {
      await _pumpScreen(tester, size: size);
      final header = _Header(tester);
      final strip = header.strip;

      // The chevron's point and the dots' outer edge mirror each other...
      expect(header.chevronInkStart, closeTo(size.width - header.dotsEnd, 0.5));
      // ...and the strip's edges are on them.
      expect(strip.left, closeTo(header.chevronInkStart, 0.5));
      expect(strip.right, closeTo(header.dotsEnd, 0.5));
      // The metrics say what the screen shows.
      expect(header.chevronInkStart, closeTo(EventHeaderMetrics.backInk, 0.5));
      expect(
        size.width - header.menuGlyph.center.dx,
        closeTo(EventHeaderMetrics.menuGlyph, 0.5),
      );
      // The back is the search header's, at its inset.
      expect(
        header.chevron.center.dx,
        closeTo(SearchHeaderMetrics.backGlyphCenter, 0.5),
      );
      await _unmount(tester);
    });

    testWidgets('$label: the board view and the ⋮ are a tight pair on whole '
        '44pt targets', (tester) async {
      await _pumpScreen(tester, size: size);
      final header = _Header(tester);

      // The clear space between the two glyphs' ink.
      final gap = header.dotsStart - header.toggleInk.right;
      expect(gap, closeTo(EventHeaderMetrics.pairGap, 0.5));
      expect(gap, greaterThan(0));
      // Half the old 40pt split (393pt phone), scaled with the glyphs.
      expect(gap, lessThanOrEqualTo(20 * size.width / 393 + 0.5));
      // A pair: closer to each other than the board view is to the chip.
      expect(header.toggleInk.left - header.chip.right, greaterThan(gap));

      // Two whole targets, side by side: no overlap and no hole.
      final slot = header.toggleSlot;
      final menu = header.menuTarget;
      expect(slot.width, closeTo(44, 0.01));
      expect(slot.height, closeTo(44, 0.01));
      expect(menu.width, greaterThanOrEqualTo(44));
      expect(menu.height, greaterThanOrEqualTo(44));
      expect(slot.right, closeTo(menu.left, 0.5));
      // They meet halfway between the glyphs.
      expect(
        slot.right,
        closeTo(
          (header.toggleInk.center.dx + header.menuGlyph.center.dx) / 2,
          0.5,
        ),
      );
      // The pair stays on the screen.
      expect(menu.right, lessThanOrEqualTo(size.width));
      await _unmount(tester);
    });
  }

  testWidgets('every point of the board view\'s slot toggles it, and the '
      '⋮ takes its own target from the midpoint on', (tester) async {
    await _pumpScreen(tester);
    final header = _Header(tester);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add('${call.arguments}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final slot = header.toggleSlot;
    // The strip the moved button leaves, and the side by the ⋮.
    for (final x in [slot.left + 1, slot.right - 1]) {
      haptics.clear();
      await tester.tapAt(Offset(x, slot.center.dy));
      await tester.pump();
      expect(haptics, ['HapticFeedbackType.lightImpact'], reason: 'x=$x');
      expect(find.text('Share event'), findsNothing);
    }

    // Just past the midpoint the ⋮ answers, opening the event's menu.
    final menu = header.menuTarget;
    await tester.tapAt(Offset(menu.left + 1, menu.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Share event'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a team event\'s four tabs keep the same header', (tester) async {
    await _pumpScreen(tester, team: true);
    final header = _Header(tester);
    final chevron = header.chevron;
    final menu = header.menuGlyph;
    final chip = header.chip;
    expect(chip.center.dx, closeTo(393 / 2, 0.5));

    for (final tabLabel in ['Standings', 'Players', 'About', 'Games']) {
      final tab = find.descendant(
        of: find.byType(SegmentedSwitcher),
        matching: find.text(tabLabel),
      );
      await tester.ensureVisible(tab);
      await tester.pump();
      await tester.tap(tab);
      await tester.pump();
      await _frames(tester);
      expect(tester.takeException(), isNull);
      _expectSameRect(header.chevron, chevron, '$tabLabel chevron');
      _expectSameRect(header.menuGlyph, menu, '$tabLabel ⋮');
      _expectSameRect(header.chip, chip, '$tabLabel chip');
    }
    await _unmount(tester);
  });

  testWidgets('loading: the back where the loaded header has it, the title '
      'on the screen\'s centre line', (tester) async {
    await _pumpScreen(tester);
    final loaded = _Header(tester).chevron;
    await _unmount(tester);

    await _pumpScreen(tester, loading: true);
    expect(find.byType(CategoryDropdown), findsNothing);
    _expectSameRect(_Header(tester).chevron, loaded, 'loading chevron');
    final title = find.text('ChessEver');
    expect(title, findsOneWidget);
    expect(tester.getCenter(title).dx, closeTo(393 / 2, 0.5));
    await _unmount(tester);
  });

  group('EventHeaderRow', () {
    Future<void> pumpRow(
      WidgetTester tester,
      Widget row, {
      TextDirection direction = TextDirection.ltr,
    }) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: Align(alignment: Alignment.topCenter, child: row),
                ),
              );
            },
          ),
        ),
      );
    }

    testWidgets('a middle wider than its room stays centred, clear of both '
        'sides', (tester) async {
      await pumpRow(
        tester,
        const EventHeaderRow(
          middle: SizedBox(key: ValueKey('middle'), width: 900, height: 20),
        ),
      );
      final middle = tester.getRect(find.byKey(const ValueKey('middle')));
      final inset = EventHeaderMetrics.middleInset();
      expect(middle.center.dx, closeTo(393 / 2, 0.5));
      expect(middle.left, closeTo(inset, 0.5));
      expect(middle.right, closeTo(393 - inset, 0.5));
      // The room keeps clear of the Games pair's far edge.
      expect(393 - middle.right, greaterThan(EventHeaderMetrics.pairExtent));
      expect(tester.getSize(find.byType(EventHeaderRow)).height, 48);
    });

    testWidgets('right to left, the back is at the right and the middle '
        'still centred', (tester) async {
      await pumpRow(
        tester,
        const EventHeaderRow(
          middle: SizedBox(key: ValueKey('middle'), width: 80, height: 20),
        ),
        direction: TextDirection.rtl,
      );
      final chevron = tester.getRect(
        find.byIcon(Icons.arrow_back_ios_new_outlined),
      );
      expect(
        393 - chevron.center.dx,
        closeTo(SearchHeaderMetrics.backGlyphCenter, 0.5),
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('middle'))).dx,
        closeTo(393 / 2, 0.5),
      );
    });
  });
}

class _DisabledChat extends BotvinnikEnabledNotifier {
  @override
  Future<bool> build() async => false;
}

class _TestEngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false, showEngineGauge: false);
}

class _TestSpoilers extends EventNoSpoilersController {
  _TestSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(isLoading: false);
  }
}

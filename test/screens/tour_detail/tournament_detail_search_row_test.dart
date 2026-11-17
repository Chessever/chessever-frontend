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
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/tournament_detail_screen.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_quick_actions.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The event screen's pinned search row (Trello #1420): on Games it carries
/// Live first and Collapse all beside a slimmer field, under bare header
/// glyphs; the other tabs keep the plain field.

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

List<Override> _overrides(TournamentDetailScreenMode mode) => [
  selectedBroadcastModelProvider.overrideWith(
    (ref) => GroupBroadcast(
      id: 'gb-1',
      createdAt: DateTime(2026),
      name: 'Test Open',
      search: const [],
    ),
  ),
  tourDetailScreenProviderOverride(_viewModel()),
  selectedTourModeProvider.overrideWith((ref) => mode),
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
    (ref, tourId) => const KnockoutTournamentState.empty(),
  ),
  gamesTourScreenProvider.overrideWith(
    (ref) => GamesTourScreenProvider.loading(ref: ref),
  ),
];

Future<void> _pumpScreen(
  WidgetTester tester, {
  required TournamentDetailScreenMode mode,
  Size size = const Size(393, 852),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(mode),
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // A long category name scrolls as a marquee whose pause timer outlives the
  // tree; let it run out.
  await tester.pump(const Duration(seconds: 3));
}

const _storageChannels = [
  MethodChannel('com.tekartik.sqflite'),
  MethodChannel('plugins.flutter.io/path_provider'),
];

void main() {
  // The tabs open the local database on their way in. Answer its platform
  // calls with a failure at once, so stores fall back to empty inside the
  // test clock instead of waiting on a plugin that is not there.
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

  testWidgets('Games: slim field, Live first and Collapse all beside it', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);

    expect(find.byType(EventSearchBar), findsOneWidget);
    expect(find.byType(EventGamesQuickActions), findsOneWidget);
    expect(find.bySemanticsLabel('Show live games first'), findsOneWidget);
    expect(find.bySemanticsLabel(kCollapseAllRoundsLabel), findsOneWidget);

    // The field itself is slimmer than the 40pt it used to be.
    final field = tester.getSize(
      find
          .descendant(
            of: find.byType(EventSearchBarFrame),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(field.height, lessThan(40));

    // The field, Live first and Collapse all share one centre line.
    final fieldCentre = tester.getCenter(find.byType(EventSearchBarFrame)).dy;
    for (final label in ['Show live games first', kCollapseAllRoundsLabel]) {
      expect(
        tester.getCenter(find.bySemanticsLabel(label)).dy,
        moreOrLessEquals(fieldCentre, epsilon: 0.5),
      );
    }
    await _unmount(tester);
  });

  testWidgets('Games header: bare glyphs, list controls in their columns', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);

    final icons = tester.widgetList<AppBarIcons>(find.byType(AppBarIcons));
    expect(icons, hasLength(2));
    expect(icons.every((icon) => !icon.boxed), isTrue);
    final tiles = find.descendant(
      of: find.byType(AppBarIconSurface),
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.decoration != null,
      ),
    );
    expect(tiles, findsNothing);

    // Each tap target is at least 44pt.
    for (final surface in tester.widgetList<AppBarIconSurface>(
      find.byType(AppBarIconSurface),
    )) {
      final size = tester.getSize(find.byWidget(surface));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }

    // Live first sits under the view toggle and Collapse all under the ⋮.
    final toggle = tester.getCenter(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppBarIcons && widget.image == SvgAsset.chase_grid,
      ),
    );
    final menu = tester.getCenter(find.byType(TournamentMenuButton));
    final live = tester.getCenter(
      find.bySemanticsLabel('Show live games first'),
    );
    final fold = tester.getCenter(
      find.bySemanticsLabel(kCollapseAllRoundsLabel),
    );
    expect(live.dx, moreOrLessEquals(toggle.dx, epsilon: 0.5));
    expect(fold.dx, moreOrLessEquals(menu.dx, epsilon: 0.5));
    await _unmount(tester);
  });

  testWidgets('Standings keeps the plain field, no list controls', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);
    final gamesRowHeight = tester
        .getSize(find.byType(EventSearchBarFrame))
        .height;

    await tester.tap(find.text('Standings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(EventSearchBar), findsOneWidget);
    expect(find.byType(EventGamesQuickActions), findsNothing);
    expect(find.bySemanticsLabel('Show live games first'), findsNothing);
    // The field keeps its height between the tabs.
    expect(
      tester.getSize(find.byType(EventSearchBarFrame)).height,
      gamesRowHeight,
    );
    await _unmount(tester);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('nothing overflows on a 320pt phone at ${textScale}x text', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        size: const Size(320, 568),
        textScale: textScale,
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Show live games first'), findsOneWidget);
      final row = tester.getRect(find.byType(EventGamesQuickActions));
      expect(row.right, lessThanOrEqualTo(320));
      await _unmount(tester);
    });
  }
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

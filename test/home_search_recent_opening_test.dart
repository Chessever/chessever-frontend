import 'dart:convert';

import 'package:chessever2/repository/gamebase/memorial_player_local_search.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _MemoryStorage implements RecentSearchStorage {
  _MemoryStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class _SearchHarness extends StatefulWidget {
  const _SearchHarness({
    required this.onOpeningSelected,
    this.onPlayerSelected,
    this.onTournamentSelected,
  });

  final ValueChanged<OpeningSearchSelection> onOpeningSelected;
  final ValueChanged<SearchPlayer>? onPlayerSelected;
  final ValueChanged<GroupEventCardModel>? onTournamentSelected;

  @override
  State<_SearchHarness> createState() => _SearchHarnessState();
}

class _SearchHarnessState extends State<_SearchHarness> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: EnhancedRoundedSearchBar(
          controller: controller,
          showProfile: false,
          showFilter: false,
          onOpeningSelected: widget.onOpeningSelected,
          onPlayerSelected: widget.onPlayerSelected,
          onTournamentSelected: widget.onTournamentSelected,
        ),
      ),
    );
  }
}

void main() {
  testWidgets('empty focus shows recent surface and ECO family opens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    OpeningSearchSelection? selectedOpening;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentSearchStorageProvider.overrideWithValue(_MemoryStorage()),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: _SearchHarness(
            onOpeningSelected: (opening) => selectedOpening = opening,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.text('Search players, tournaments, openings, or ECO codes'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Najdorf');
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('B20-B99'), findsNothing);
    final horizontalResults = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalResults, findsOneWidget);
    final family = find.textContaining('B90-B99', findRichText: true);
    expect(family, findsOneWidget);
    expect(find.textContaining('Najdorf · 10 ECO codes'), findsOneWidget);
    expect(find.text('B9'), findsNothing);
    final familyTapTarget = find.ancestor(
      of: family,
      matching: find.byType(InkWell),
    );
    expect(
      tester.getSize(familyTapTarget.first).height,
      greaterThanOrEqualTo(44),
    );
    tester
        .widget<InkWell>(find.byKey(const ValueKey('opening-result-B9')))
        .onTap
        ?.call();
    await tester.pump();

    expect(selectedOpening?.filter.code, 'B9');
    expect(selectedOpening?.filter.isFamily, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('named subvariant search renders useful grey child text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    OpeningSearchSelection? selectedOpening;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentSearchStorageProvider.overrideWithValue(_MemoryStorage()),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: _SearchHarness(
            onOpeningSelected: (opening) => selectedOpening = opening,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Gurgen');
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('B20-B99'), findsNothing);
    final title = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.textSpan?.toPlainText().contains('Robatsch defence') ??
              false),
    );
    expect(title, findsOneWidget);
    final subvariant = find.text('Gurgenidze variation');
    expect(subvariant, findsOneWidget);

    final tile = find.ancestor(of: subvariant, matching: find.byType(InkWell));
    final tileSize = tester.getSize(tile);
    expect(tileSize.width, 230);
    expect(tileSize.height, inInclusiveRange(92, 108));
    final titleWidget = tester.widget<Text>(title);
    final subvariantWidget = tester.widget<Text>(subvariant);
    expect(titleWidget.style?.fontSize, 12);
    expect(titleWidget.maxLines, 2);
    expect(subvariantWidget.style?.fontSize, 12);
    expect(subvariantWidget.maxLines, 3);
    expect(subvariantWidget.style?.color, isNot(titleWidget.style?.color));

    tester.widget<InkWell>(tile).onTap?.call();
    await tester.pump();
    expect(selectedOpening?.filter.code, 'B06');
    expect(selectedOpening?.filter.isFamily, isFalse);
    expect(selectedOpening?.hierarchyLabel, contains('Gurgenidze variation'));
    expect(selectedOpening?.isAggregate, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a deep hierarchy fits inside the readable opening card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentSearchStorageProvider.overrideWithValue(_MemoryStorage()),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: _SearchHarness(onOpeningSelected: (_) {}),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Sicilian Wing');
    await tester.pump(const Duration(milliseconds: 450));

    final parentTile = find.ancestor(
      of: find.text('Wing gambit'),
      matching: find.byType(InkWell),
    );
    final parentMainText = find.descendant(
      of: parentTile,
      matching: find.byKey(const ValueKey('opening-all-star')),
    );
    expect(
      find.descendant(
        of: parentTile,
        matching: find.byKey(const ValueKey('opening-all-star')),
      ),
      findsOneWidget,
    );
    final parentTextWidget = tester.widget<Text>(parentMainText);
    final parentSpan = parentTextWidget.textSpan! as TextSpan;
    final allSpan = parentSpan.children!.whereType<TextSpan>().singleWhere(
      (span) => span.text?.contains('★ All') ?? false,
    );
    expect(parentTextWidget.style?.fontSize, 12);
    expect(allSpan.style?.fontSize, isNull);
    expect(allSpan.style?.color, kPrimaryColor);

    final hierarchy = find.text(
      'Wing gambit › Marshall variation › Carlsbad variation',
    );
    final horizontalList = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    );
    await tester.scrollUntilVisible(
      hierarchy,
      180,
      scrollable: find.descendant(
        of: horizontalList,
        matching: find.byType(Scrollable),
      ),
    );

    final leafTile = find.ancestor(
      of: hierarchy,
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(leafTile).width, 230);
    expect(tester.getSize(leafTile).height, inInclusiveRange(92, 108));
    final parentSubtitleOffset =
        tester.getTopLeft(find.text('Wing gambit')).dy -
        tester.getTopLeft(parentTile).dy;
    final leafSubtitleOffset =
        tester.getTopLeft(hierarchy).dy - tester.getTopLeft(leafTile).dy;
    expect(leafSubtitleOffset, closeTo(parentSubtitleOffset, 0.1));
    expect(
      find.descendant(
        of: leafTile,
        matching: find.byKey(const ValueKey('opening-all-star')),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stored opening can be revisited from recent searches', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    OpeningSearchSelection? selectedOpening;
    final storage = _MemoryStorage(
      '[{"kind":"opening","targetId":"B9",'
      '"title":"Sicilian: Najdorf","subtitle":"B9 · B90–B99"}]',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [recentSearchStorageProvider.overrideWithValue(storage)],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: _SearchHarness(
            onOpeningSelected: (opening) => selectedOpening = opening,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('Sicilian: Najdorf'), findsOneWidget);
    final recentTapTarget = find.ancestor(
      of: find.text('Sicilian: Najdorf'),
      matching: find.byType(InkWell),
    );
    expect(
      tester.getSize(recentTapTarget.first).height,
      greaterThanOrEqualTo(48),
    );
    expect(recentTapTarget.hitTestable(), findsOneWidget);
    await tester.tap(find.text('Sicilian: Najdorf'));
    await tester.pump();

    expect(selectedOpening?.filter.code, 'B9');
    expect(selectedOpening?.filter.isFamily, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a recent tournament tap emits the complete live result payload',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final live = GroupEventCardModel(
        id: 'cal_event_mikhail_tal_memorial',
        title: 'Mikhail Tal Memorial',
        dates: 'Nov 5–12',
        maxAvgElo: 2765,
        timeUntilStart: 'Starts in 2 days',
        tourEventCategory: TourEventCategory.upcoming,
        timeControl: 'Rapid',
        startDate: DateTime.utc(2026, 11, 5, 12, 30),
        endDate: DateTime.utc(2026, 11, 12, 18, 45),
        location: 'Riga, Latvia',
        searchTerms: const ['mikhail tal memorial', 'riga', 'rapid'],
        eventSource: EventSource.communityEvent,
        isMajorUpcoming: true,
      );
      GroupEventCardModel? selectedTournament;
      final storage = _MemoryStorage(
        jsonEncode([RecentSearchEntry.tournament(live).toJson()]),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [recentSearchStorageProvider.overrideWithValue(storage)],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: _SearchHarness(
              onOpeningSelected: (_) {},
              onTournamentSelected: (event) => selectedTournament = event,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text(live.title));
      await tester.pump();

      expect(selectedTournament?.id, live.id);
      expect(selectedTournament?.title, live.title);
      expect(selectedTournament?.dates, live.dates);
      expect(selectedTournament?.maxAvgElo, live.maxAvgElo);
      expect(selectedTournament?.timeUntilStart, live.timeUntilStart);
      expect(selectedTournament?.tourEventCategory, live.tourEventCategory);
      expect(selectedTournament?.timeControl, live.timeControl);
      expect(selectedTournament?.startDate, live.startDate);
      expect(selectedTournament?.endDate, live.endDate);
      expect(selectedTournament?.location, live.location);
      expect(selectedTournament?.searchTerms, live.searchTerms);
      expect(selectedTournament?.eventSource, live.eventSource);
      expect(selectedTournament?.isMajorUpcoming, live.isMajorUpcoming);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a recent player tap emits the complete live result payload', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const live = SearchPlayer(
      id: 'event-42_700070_game-8',
      name: 'Judit Polgar',
      title: 'GM',
      rating: 2735,
      fideId: 700070,
      fed: 'HUN',
      tournamentId: 'event-42',
      tournamentName: 'Legends Match',
      gameId: 'game-8',
      roundId: 'round-3',
      isWhitePlayer: false,
      gamebasePlayerId: 'gamebase-judit-polgar',
    );
    SearchPlayer? selectedPlayer;
    final storage = _MemoryStorage(
      jsonEncode([RecentSearchEntry.player(live).toJson()]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [recentSearchStorageProvider.overrideWithValue(storage)],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: _SearchHarness(
            onOpeningSelected: (_) {},
            onPlayerSelected: (player) => selectedPlayer = player,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final recentTapTarget = find.ancestor(
      of: find.text(live.name),
      matching: find.byType(InkWell),
    );
    final onTap = tester.widget<InkWell>(recentTapTarget.first).onTap;
    expect(onTap, isNotNull);
    await tester.runAsync(() async {
      onTap!.call();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    await tester.pump();

    expect(selectedPlayer?.id, live.id);
    expect(selectedPlayer?.name, live.name);
    expect(selectedPlayer?.title, live.title);
    expect(selectedPlayer?.rating, live.rating);
    expect(selectedPlayer?.fideId, live.fideId);
    expect(selectedPlayer?.fed, live.fed);
    expect(selectedPlayer?.tournamentId, live.tournamentId);
    expect(selectedPlayer?.tournamentName, live.tournamentName);
    expect(selectedPlayer?.gameId, live.gameId);
    expect(selectedPlayer?.roundId, live.roundId);
    expect(selectedPlayer?.isWhitePlayer, live.isWhitePlayer);
    expect(selectedPlayer?.gamebasePlayerId, live.gamebasePlayerId);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recent remove and clear controls update history without opening',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final event = GroupEventCardModel(
        id: 'event-to-remove',
        title: 'Event to remove',
        dates: 'Sep 10–12',
        maxAvgElo: 2500,
        timeUntilStart: '',
        tourEventCategory: TourEventCategory.upcoming,
        timeControl: 'Standard',
        endDate: DateTime.utc(2026, 9, 12),
        startDate: DateTime.utc(2026, 9, 10),
      );
      final opening = OpeningSearchSelection(
        filter: GameEcoFilter.forCode('B06'),
        hierarchyLabel: 'Modern Defense',
        movePath: const ['e4', 'g6'],
        isAggregate: false,
      );
      final storage = _MemoryStorage(
        jsonEncode([
          RecentSearchEntry.tournament(event).toJson(),
          RecentSearchEntry.openingSelection(opening).toJson(),
        ]),
      );
      var opened = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [recentSearchStorageProvider.overrideWithValue(storage)],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: _SearchHarness(
              onOpeningSelected: (_) => opened = true,
              onPlayerSelected: (_) => opened = true,
              onTournamentSelected: (_) => opened = true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final removeButtons = find.byTooltip('Remove from recent searches');
      expect(removeButtons, findsNWidgets(2));
      expect(
        tester.getSize(removeButtons.first).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(removeButtons.first);
      await tester.pump();
      await tester.pump();

      expect(opened, isFalse);
      expect(find.text(event.title), findsNothing);
      expect(find.text('Modern Defense'), findsOneWidget);
      expect(storage.value, isNot(contains('event-to-remove')));

      final clearButton = find.widgetWithText(TextButton, 'Clear');
      expect(clearButton, findsOneWidget);
      expect(tester.getSize(clearButton).height, greaterThanOrEqualTo(44));
      await tester.tap(clearButton);
      await tester.pump();
      await tester.pump();

      expect(opened, isFalse);
      expect(find.text('Recent searches'), findsNothing);
      expect(
        find.text('Search players, tournaments, openings, or ECO codes'),
        findsOneWidget,
      );
      expect(storage.value, '[]');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a legacy Memorial recent result restores its exact player before opening',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SearchPlayer? selectedPlayer;
      await tester.runAsync(warmBundledMemorialPlayerCatalog);
      final storage = _MemoryStorage(
        '[{"kind":"player","targetId":"name:tal, mikhail",'
        '"title":"Tal, Mikhail","subtitle":"GM · 2705 · LAT",'
        '"data":{"id":"memorial:memorial-e03cdf6af47b368c",'
        '"title":"GM","rating":2705,"fed":"LAT"}}]',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [recentSearchStorageProvider.overrideWithValue(storage)],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: _SearchHarness(
              onOpeningSelected: (_) {},
              onPlayerSelected: (player) {
                selectedPlayer = player;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Tal, Mikhail').hitTestable(), findsOneWidget);
      final recentTapTarget = find.ancestor(
        of: find.text('Tal, Mikhail'),
        matching: find.byType(InkWell),
      );
      final onTap = tester.widget<InkWell>(recentTapTarget.first).onTap;
      expect(onTap, isNotNull);
      await tester.runAsync(() async {
        onTap!.call();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      await tester.pump();

      expect(
        selectedPlayer?.memorialSourceIdentity,
        'memorial:memorial-e03cdf6af47b368c',
      );
      expect(selectedPlayer?.memorialRouteId, 'memorial-e03cdf6af47b368c');
      expect(selectedPlayer?.fideId, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}

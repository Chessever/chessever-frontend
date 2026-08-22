import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
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
  const _SearchHarness({required this.onOpeningSelected});

  final ValueChanged<OpeningSearchSelection> onOpeningSelected;

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
}

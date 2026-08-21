import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
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

  final ValueChanged<GameEcoFilter> onOpeningSelected;

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
    GameEcoFilter? selectedOpening;

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
    await tester.pump();

    expect(find.text('Find a chess destination'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Najdorf');
    await tester.pump();

    final family = find.text('B9');
    expect(family, findsOneWidget);
    await tester.tap(family);
    await tester.pump();

    expect(selectedOpening?.code, 'B9');
    expect(selectedOpening?.isFamily, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stored opening can be revisited from recent searches', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    GameEcoFilter? selectedOpening;
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

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump();

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Sicilian: Najdorf'), findsOneWidget);
    await tester.tap(find.text('Sicilian: Najdorf'));
    await tester.pump();

    expect(selectedOpening?.code, 'B9');
    expect(selectedOpening?.isFamily, isTrue);
    expect(tester.takeException(), isNull);
  });
}

import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_share.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _IdlePlayers extends StateNotifier<MiniaturePlayersState>
    implements MiniaturePlayersNotifier {
  _IdlePlayers() : super(const MiniaturePlayersState(hasMore: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final shares = <String>[];
  setUp(() {
    shares.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          shares.add((call.arguments as Map)['text'] as String);
          return 'success';
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.darkTheme,
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return child;
      },
    ),
  );

  testWidgets(
    'holding each Miniatures tab offers its share link without switching tabs',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          selectedMiniaturesModeProvider.overrideWith(
            (ref) => MiniaturesScreenMode.about,
          ),
          miniaturePlayersPaginatedProvider.overrideWith(
            (ref) => _IdlePlayers(),
          ),
          spaceShortcutExistsProvider.overrideWith((ref, key) => false),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: host(const MiniaturesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      for (final tab in MiniaturesScreenMode.values) {
        await tester.longPress(find.text(miniaturesModeNames[tab]!).first);
        await tester.pumpAndSettle();
        expect(find.text('Share'), findsOneWidget);
        expect(
          container.read(selectedMiniaturesModeProvider),
          MiniaturesScreenMode.about,
        );
        await tester.tap(find.text('Share'));
        await tester.pumpAndSettle();
        expect(shares.last, miniaturesShareUri(tab).toString());
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  testWidgets(
    'a date heading keeps collapse on tap and shares its calendar day on hold',
    (tester) async {
      var toggles = 0;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: MiniaturesDateShareHeader(
              date: '2026-10-28',
              dateLabel: 'Oct 28',
              isExpanded: true,
              onToggle: () => toggles++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Oct 28'));
      expect(toggles, 1);
      await tester.longPress(find.text('Oct 28'));
      await tester.pumpAndSettle();
      expect(toggles, 1);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(shares, [
        'https://chessever.com/app/miniatures/games?date=2026-10-28',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an unknown-date heading has no misleading date share', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Scaffold(
          body: MiniaturesDateShareHeader(
            date: null,
            dateLabel: 'Unknown date',
            isExpanded: true,
          ),
        ),
      ),
    );
    await tester.longPress(find.text('Unknown date'));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsNothing);
    expect(shares, isEmpty);
  });
}

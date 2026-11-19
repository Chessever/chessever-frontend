import 'package:chessever2/screens/for_you/discovery/discovery_share.dart';
import 'package:chessever2/screens/my_space/actions/space_component_share.dart';
import 'package:chessever2/services/app_destination.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// One card on a page, as the app sets it up.
Future<void> _pumpCard(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Center(child: SizedBox(width: 200, child: card)),
          );
        },
      ),
    ),
  );
}

/// Lets the focus menu's springs run out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// The original card's own visibility while its copy may be lifted.
bool _originalShown(WidgetTester tester, Finder card) => tester
    .widget<Visibility>(
      find.ancestor(of: card, matching: find.byType(Visibility)).first,
    )
    .visible;

void main() {
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  late List<String> shares;
  late List<String> haptics;

  setUp(() {
    shares = [];
    haptics = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      shares.add((call.arguments as Map)['text'] as String);
      return 'success';
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add('${call.arguments}');
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('each permanent card holds into the focus menu every card uses: '
      'Open and Share, never a Material popup', (tester) async {
    for (final component in SpaceComponent.values) {
      var taps = 0;
      var opens = 0;
      await _pumpCard(
        tester,
        SpaceComponentShare(
          component: component,
          onOpen: () => opens++,
          child: GestureDetector(
            onTap: () => taps++,
            child: const SizedBox(height: 100, child: Text('Component')),
          ),
        ),
      );
      final card = find.text('Component');
      haptics.clear();
      await tester.longPress(card);
      await _settle(tester);
      expect(find.byType(PopupMenuItem<bool>), findsNothing);
      expect(find.text('Open ${component.title}'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      // The menu's own confirmation, as on every card.
      expect(haptics, contains('null'));
      // The copy lifts in the original's place: the original is hidden.
      expect(_originalShown(tester, card.first), isFalse);
      expect(taps, 0);

      await tester.tap(find.text('Share'));
      await _settle(tester);
      expect(shares.last, spaceComponentShareUri(component).toString());
      expect(opens, 0);
      expect(_originalShown(tester, card), isTrue);

      await tester.longPress(card);
      await _settle(tester);
      await tester.tap(find.text('Open ${component.title}'));
      await _settle(tester);
      expect(opens, 1);

      await tester.tap(card);
      expect(taps, 1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Discovery tile offers its own tap as Open, and Share', (
    tester,
  ) async {
    var opens = 0;
    await _pumpCard(
      tester,
      DiscoveryTileShare(
        component: DiscoveryShareDestination.news,
        child: HubTile(
          title: 'News',
          mark: const SizedBox.square(dimension: 20),
          onTap: () => opens++,
        ),
      ),
    );
    await tester.longPress(find.text('News'));
    await _settle(tester);
    expect(find.text('Open News'), findsOneWidget);
    await tester.tap(find.text('Share'));
    await _settle(tester);
    expect(shares.last, 'https://chessever.com/app/news');
    expect(opens, 0);

    await tester.longPress(find.text('News'));
    await _settle(tester);
    await tester.tap(find.text('Open News'));
    await _settle(tester);
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });

  test('My Space components accept links, schemes and notification routes', () {
    final kinds = [
      AppDestinationKind.myPrep,
      AppDestinationKind.library,
      AppDestinationKind.myLikes,
    ];
    for (final component in SpaceComponent.values) {
      final uri = spaceComponentShareUri(component);
      for (final raw in [
        uri.toString(),
        uri.path,
        'com.chessever.app://app/my-space/${component.name}',
      ]) {
        final target = parseAppDestination(raw)!;
        expect(target.kind, kinds[component.index]);
        if (component == SpaceComponent.library) {
          expect(target.section, 'databases');
        }
      }
    }
    expect(parseAppDestination('/app/my-space')!.section, 'my-space');
    for (final raw in [
      '/app/my-space/unknown',
      '/app/my-space/prep/extra',
      '/app/my-space/library?user=someone',
    ]) {
      expect(parseAppDestination(raw), isNull);
    }
  });
}

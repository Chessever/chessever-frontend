import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:chessever2/watch/core/watch_account.dart';
import 'package:chessever2/watch/core/watch_repository.dart';
import 'package:chessever2/watch/ui/watch_board.dart';
import 'package:chessever2/watch/ui/watch_home_page.dart';
import 'package:chessever2/watch/watch_app.dart';
import 'package:chessever2/watch/watch_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_link/flutter_watch_link.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'watch_controller_test.dart' show FakeWatchLink;
import 'watch_core_test.dart' show fixtureGame;

void main() {
  const capture = bool.fromEnvironment('WATCH_REVIEW_CAPTURE');
  late WatchController controller;
  late FakeWatchLink link;
  double publishedScore = 4.5;
  const previewKey = Key('watch-render');

  setUpAll(() async {
    if (capture && Platform.isMacOS) {
      final font = File('/System/Library/Fonts/SFCompact.ttf');
      if (font.existsSync()) {
        for (final family in [
          'CupertinoSystemText',
          'CupertinoSystemDisplay',
        ]) {
          final loader = FontLoader(family)
            ..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            );
          await loader.load();
        }
        final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
          ..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          );
        await icons.load();
      }
    }
  });

  setUp(() {
    publishedScore = 4.5;
    SharedPreferences.setMockInitialValues({});
    link = FakeWatchLink();
    link.context = const WatchAccount(
      revision: 1,
      userId: 'account',
      name: 'ChessEver account',
      eventIds: ['open'],
      playerNames: ['Player One'],
      preferences: {'favorite_event_alerts': true},
    ).toJson();
    WatchLink.backendOverride = link;
    final repository = WatchRepository(
      apiKey: 'key',
      client: MockClient((request) async {
        final path = request.url.path;
        final data = path.endsWith('/group_broadcasts_current')
            ? [
                {
                  'id': 'open',
                  'name': 'European Club Championship',
                  'time_control': 'standard',
                },
              ]
            : path.endsWith('/tours')
            ? [
                {
                  'id': 'tour1',
                  'group_broadcast_id': 'open',
                  'name': 'Open section',
                  'players': [
                    {
                      'name': 'Player One',
                      'fideId': 123,
                      'score': publishedScore,
                      'played': 6,
                      'rank': 1,
                    },
                    {
                      'name': 'Player Two',
                      'fideId': 456,
                      'score': 4,
                      'played': 6,
                      'rank': 2,
                    },
                  ],
                },
              ]
            : path.endsWith('/rounds')
            ? [
                {
                  'id': 'round1',
                  'name': 'Round 1',
                  'starts_at': '2026-10-14T16:00:00Z',
                },
              ]
            : [fixtureGame('game1')];
        return http.Response(jsonEncode(data), 200);
      }),
    );
    controller = WatchController(repository: repository);
  });
  tearDown(() async {
    controller.dispose();
    await link.dispose();
    WatchLink.backendOverride = null;
  });

  Future<void> size(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    final corner = size.width > 200
        ? 17.0
        : size.width > 180
        ? 12.0
        : 9.0;
    final band = size.width > 200
        ? 56.5
        : size.width > 180
        ? 45.0
        : 40.0;
    tester.view.padding = FakeViewPadding(
      top: band,
      left: corner,
      right: corner,
      bottom: corner,
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
  }

  Future<void> show(WidgetTester tester, Finder target) async {
    final scrollable = find.byType(Scrollable).last;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      target,
      60,
      scrollable: scrollable,
      maxScrolls: 150,
    );
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(previewKey),
    );
    if (find.byType(WatchBoard).evaluate().isNotEmpty) {
      final context = tester.element(find.byType(WatchBoard));
      await tester.runAsync(
        () => Future.wait([
          for (final color in ['w', 'b'])
            for (final role in ['P', 'N', 'B', 'R', 'Q', 'K'])
              precacheImage(
                AssetImage(
                  'packages/chessground/assets/piece_sets/cburnett/$color$role.webp',
                ),
                context,
              ),
        ]),
      );
      await tester.pump();
    }
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/watch-review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final screen in [
    const Size(162, 197),
    const Size(184, 224),
    const Size(211, 257),
  ]) {
    testWidgets(
      'Current, account and event navigation fit ${screen.width.toInt()}pt',
      (tester) async {
        await size(tester, screen);
        await controller.initialize();
        await tester.pumpWidget(
          RepaintBoundary(
            key: previewKey,
            child: ChessEverWatchApp(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await screenshot(tester, 'home-${screen.width.toInt()}');
        final phone = find.text('My iPhone');
        await show(tester, phone);
        await tester.tap(phone);
        await tester.pumpAndSettle();
        expect(find.text('Account connected'), findsNothing);
        await show(tester, find.text('Event alerts'));
        expect(find.text('Event alerts'), findsOneWidget);
        await screenshot(tester, 'account-${screen.width.toInt()}');
        await show(tester, find.text('Sync with iPhone'));
        await tester.tap(find.text('Sync with iPhone'));
        await tester.pumpAndSettle();
        expect(link.sent.any((p) => p['kind'] == 'chessever.sync.v1'), isTrue);
        await show(tester, find.text('Back'));
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        await show(tester, find.text('Show followed events'));
        await tester.tap(find.text('Show followed events'));
        await tester.pumpAndSettle();
        expect(controller.favoritesOnly, isTrue);
        await show(tester, find.text('Show all current events'));
        await tester.tap(find.text('Show all current events'));
        await tester.pumpAndSettle();
        final event = find.text('European Club Championship');
        await show(tester, event);
        await tester.tap(event);
        await tester.pumpAndSettle();
        await show(tester, find.text('Open section'));
        await tester.tap(find.text('Open section'));
        await tester.pumpAndSettle();
        await screenshot(tester, 'rounds-${screen.width.toInt()}');
        await show(tester, find.text('Players & scores'));
        await tester.tap(find.text('Players & scores'));
        await tester.pumpAndSettle();
        await show(tester, find.text('Show followed players'));
        await tester.tap(find.text('Show followed players'));
        await tester.pumpAndSettle();
        expect(find.text('Player Two'), findsNothing);
        await show(tester, find.text('Show all players'));
        await tester.tap(find.text('Show all players'));
        await tester.pumpAndSettle();
        await show(tester, find.text('Back'));
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        await show(tester, find.text('Round 1'));
        await tester.tap(find.text('Round 1'));
        await tester.pumpAndSettle();
        final game = find.text('Player One\nPlayer Two');
        await show(tester, game);
        await tester.tap(game);
        await tester.pumpAndSettle();
        expect(find.byType(WatchBoard), findsOneWidget);
        final boardBounds = tester.getRect(find.byType(WatchBoard));
        expect(boardBounds.top, greaterThanOrEqualTo(40));
        expect(boardBounds.bottom, lessThanOrEqualTo(screen.height - 9));
        await screenshot(tester, 'game-${screen.width.toInt()}');
        await show(tester, find.text('White · 2750 · 0:00'));
        expect(find.text('White · 2750 · 0:00'), findsOneWidget);
        await show(tester, find.text('Black at bottom'));
        await tester.tap(find.text('Black at bottom'));
        await tester.pumpAndSettle();
        await show(tester, find.byType(WatchBoard));
        expect(
          tester.widget<WatchBoard>(find.byType(WatchBoard)).flipped,
          isTrue,
        );
        await show(tester, find.text('Open on iPhone'));
        await tester.tap(find.text('Open on iPhone'));
        await tester.pumpAndSettle();
        expect(find.text('Sent to iPhone.'), findsOneWidget);
        await show(tester, find.text('Player One'));
        await tester.tap(find.text('Player One'));
        await tester.pumpAndSettle();
        expect(find.text('4½ / 6'), findsOneWidget);
        await screenshot(tester, 'scorecard-${screen.width.toInt()}');
        publishedScore = 5;
        await show(tester, find.text('Refresh'));
        await tester.tap(find.text('Refresh'));
        await tester.pumpAndSettle();
        await show(tester, find.text('5 / 6'));
        expect(find.text('5 / 6'), findsOneWidget);
        await show(tester, find.text('Back'));
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        await show(tester, find.text('Back to games'));
        await tester.tap(find.text('Back to games'));
        await tester.pumpAndSettle();
        expect(find.byType(WatchBoard), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('large text preserves controls and readable event names', (
    tester,
  ) async {
    await size(tester, const Size(162, 197));
    await controller.initialize();
    await tester.pumpWidget(
      CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: WatchHomePage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await show(tester, find.text('European Club Championship'));
    expect(tester.takeException(), isNull);
    final target = find
        .ancestor(
          of: find.text('European Club Championship'),
          matching: find.byType(CupertinoButton),
        )
        .first;
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
  });

  testWidgets('More current events loads another page through a real row tap', (
    tester,
  ) async {
    await size(tester, const Size(162, 197));
    controller.dispose();
    controller = WatchController(
      repository: WatchRepository(
        apiKey: 'key',
        client: MockClient((request) async {
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          return http.Response(
            jsonEncode(
              List.generate(
                offset == 0 ? 30 : 1,
                (index) => {
                  'id': 'event${offset + index}',
                  'name': 'Event ${offset + index}',
                },
              ),
            ),
            200,
          );
        }),
      ),
    );
    await controller.initialize();
    await tester.pumpWidget(
      CupertinoApp(home: WatchHomePage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await show(tester, find.text('More current events'));
    await tester.tap(find.text('More current events'));
    await tester.pumpAndSettle();
    expect(controller.events.length, 31);
    expect(controller.hasMore, isFalse);
    await show(tester, find.text('Event 30'));
    expect(find.text('Event 30'), findsOneWidget);
  });

  testWidgets(
    'missing connection exposes an actionable state with no fictional content',
    (tester) async {
      await size(tester, const Size(162, 197));
      controller.error = 'Open ChessEver on iPhone to connect.';
      controller.hasMore = false;
      await tester.pumpWidget(
        CupertinoApp(home: WatchHomePage(controller: controller)),
      );
      await show(tester, find.text('Open ChessEver on iPhone to connect.'));
      expect(find.text('Open ChessEver on iPhone to connect.'), findsOneWidget);
      await show(tester, find.text('Refresh'));
      expect(find.text('Refresh'), findsOneWidget);
      await show(tester, find.text('My iPhone'));
      expect(find.text('My iPhone'), findsOneWidget);
    },
  );
}

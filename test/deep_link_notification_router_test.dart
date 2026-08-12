import 'package:chessever2/services/deep_link_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A notification tap can reach Dart before the widget tree that owns a
/// [WidgetRef] exists. On a cold start the native SDK replays the tapped
/// notification as soon as a click listener is registered — which now happens in
/// `main()`, long before `MyApp` paints — so the payload has to survive that gap
/// instead of being dropped on the floor. Dropping it is what left a
/// terminated-app tap sitting on Home while the same tap worked fine when the
/// app was merely backgrounded.
///
/// These tests drive the boundary with a payload that carries no routing hints,
/// so routing resolves synchronously to the Home fallback and no repository,
/// auth or network work is involved.
void main() {
  const noHintsPayload = <String, dynamic>{'type': 'call_to_action'};

  late GlobalKey<NavigatorState> navigatorKey;
  late List<String> pushedRoutes;

  setUp(() {
    // dispose() clears the router binding's sibling state (nav guards, the
    // app-ready gate) so each test starts from a cold-boot shape.
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
    navigatorKey = GlobalKey<NavigatorState>();
    pushedRoutes = <String>[];
  });

  tearDown(() {
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
  });

  Future<WidgetRef> pumpHost(WidgetTester tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          onGenerateRoute: (settings) {
            pushedRoutes.add(settings.name ?? '');
            return MaterialPageRoute<void>(
              settings: settings,
              builder:
                  (_) => Consumer(
                    builder: (_, ref, __) {
                      captured = ref;
                      return const SizedBox.shrink();
                    },
                  ),
            );
          },
          initialRoute: '/',
        ),
      ),
    );
    return captured;
  }

  testWidgets('a tap that lands before the router is attached is not lost', (
    tester,
  ) async {
    final ref = await pumpHost(tester);
    pushedRoutes.clear();

    // Cold start: the click listener fires while nothing can navigate yet.
    DeepLinkService.instance.ingestNotificationData(noHintsPayload);
    await tester.pump();

    expect(
      pushedRoutes,
      isEmpty,
      reason: 'nothing should navigate before the router is attached',
    );

    // The tree comes up and claims the tap.
    DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);
    await tester.pump();

    expect(pushedRoutes, contains('/home_screen'));
  });

  testWidgets('a tap that lands after attach routes straight away', (
    tester,
  ) async {
    final ref = await pumpHost(tester);
    DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);
    pushedRoutes.clear();

    // Warm start: the app is already up when the tap arrives.
    DeepLinkService.instance.ingestNotificationData(noHintsPayload);
    await tester.pump();

    expect(pushedRoutes, contains('/home_screen'));
  });

  testWidgets('only the most recent buffered tap is routed', (tester) async {
    final ref = await pumpHost(tester);
    pushedRoutes.clear();

    DeepLinkService.instance.ingestNotificationData(noHintsPayload);
    DeepLinkService.instance.ingestNotificationData(noHintsPayload);
    DeepLinkService.instance.ingestNotificationData(noHintsPayload);
    await tester.pump();

    DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);
    await tester.pump();

    // Three buffered taps must not become three competing navigations — the
    // user tapped one notification.
    expect(
      pushedRoutes.where((r) => r == '/home_screen'),
      hasLength(1),
      reason: 'buffered taps collapse to the newest one',
    );
  });

  testWidgets('attaching with an empty buffer navigates nothing', (
    tester,
  ) async {
    final ref = await pumpHost(tester);
    pushedRoutes.clear();

    DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);
    await tester.pump();

    expect(pushedRoutes, isEmpty);
  });
}

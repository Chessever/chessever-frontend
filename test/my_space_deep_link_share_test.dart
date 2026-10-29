import 'package:chessever2/screens/my_space/actions/space_component_share.dart';
import 'package:chessever2/services/app_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  testWidgets('each permanent component shares on hold and keeps its tap', (
    tester,
  ) async {
    final shares = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          shares.add((call.arguments as Map)['text'] as String);
          return 'success';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    for (final component in SpaceComponent.values) {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SpaceComponentShare(
                component: component,
                child: GestureDetector(
                  onTap: () => taps++,
                  child: const SizedBox(
                    width: 200,
                    height: 100,
                    child: Text('Component'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Component'));
      await tester.pumpAndSettle();
      expect(taps, 0);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(shares.last, spaceComponentShareUri(component).toString());
      await tester.tap(find.text('Component'));
      expect(taps, 1);
    }
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

import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the regression that pinned "Removed from …" over unrelated screens:
/// Flutter >=3.38 defaults `SnackBar.persist` to `action != null`, so an Undo
/// snack shown through the raw API never times out.
void main() {
  Widget host(void Function(BuildContext context) onTap) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Builder(
              builder:
                  (inner) => TextButton(
                    onPressed: () => onTap(inner),
                    child: const Text('go'),
                  ),
            ),
          );
        },
      ),
    );
  }

  testWidgets('a snack carrying an action still auto-dismisses', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        (context) => showAppSnack(
          context,
          'Removed from "My Subdatabase"',
          actionLabel: 'Undo',
          onAction: () {},
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Removed from "My Subdatabase"'), findsOneWidget);

    // 5s action lifetime, then the exit animation.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Removed from "My Subdatabase"'), findsNothing);
  });

  testWidgets('a plain snack clears on its own', (tester) async {
    await tester.pumpWidget(host((context) => showAppSnack(context, 'Link copied')));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Link copied'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Link copied'), findsNothing);
  });

  testWidgets('tapping the action runs it and closes the snack', (
    tester,
  ) async {
    var undone = false;
    await tester.pumpWidget(
      host(
        (context) => showAppSnack(
          context,
          'Removed from "My Subdatabase"',
          actionLabel: 'Undo',
          onAction: () => undone = true,
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(undone, isTrue);
    expect(find.text('Removed from "My Subdatabase"'), findsNothing);
  });

  testWidgets('the action clears a 44dp tap target', (tester) async {
    await tester.pumpWidget(
      host(
        (context) => showAppSnack(
          context,
          'Removed from "My Subdatabase"',
          actionLabel: 'Undo',
          onAction: () {},
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final target = tester.getSize(
      find.ancestor(of: find.text('Undo'), matching: find.byType(InkWell)),
    );
    expect(target.height, greaterThanOrEqualTo(44));
    expect(target.width, greaterThanOrEqualTo(44));
  });

  testWidgets('the drain rule sits clear of the message', (tester) async {
    await tester.pumpWidget(host((context) => showAppSnack(context, 'Link copied')));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final text = tester.getRect(find.text('Link copied'));
    final drain = tester.getRect(find.byType(FractionallySizedBox));
    // The rule lives below the type, never behind it.
    expect(drain.top, greaterThanOrEqualTo(text.bottom));
    // And it starts full-width, so it can only ever drain away.
    expect(drain.width, greaterThan(0));
  });

  testWidgets('a new snack replaces the current one instead of queueing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host((context) {
        showAppSnack(context, 'first');
        showAppSnack(context, 'second');
      }),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
  });
}

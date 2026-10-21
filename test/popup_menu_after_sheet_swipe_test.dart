import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// CHESSEVER-12R: on Android, swiping a modal sheet shut and then opening
/// an app-bar 3-dots menu grey-screened with "RenderBox was not laid out:
/// RenderFractionalTranslation".
void main() {
  testWidgets('3-dots menu opens after a modal sheet is swiped shut', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.android),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'share', child: Text('Share Game')),
                  ],
                ),
              ],
            ),
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  ChessSheetRoutes.commentEditor(
                    builder: (_) => const Sheet(
                      child: SizedBox(
                        key: ValueKey('sheet'),
                        height: 400,
                        width: double.infinity,
                        child: ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),
                ),
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sheet')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('sheet')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sheet')), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('Share Game'), findsOneWidget);
  });
}

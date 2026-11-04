import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'sheet centers, clears keyboard and retains edits across resizing',
    (tester) async {
      addTearDown(tester.view.reset);
      void resize(Size size, {double keyboard = 0}) {
        tester.view
          ..devicePixelRatio = 3
          ..physicalSize = size * 3
          ..viewInsets = FakeViewPadding(bottom: keyboard * 3);
      }

      resize(const Size(951, 669));
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => AdaptiveWindowScope(child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSmoothBottomSheet<void>(
                  context: context,
                  builder: (_) => const _SheetForm(),
                  maxHeight: 600,
                ),
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();
      final state = tester.state<_SheetFormState>(find.byType(_SheetForm));
      await tester.enterText(find.byType(TextField), 'Najdorf');
      var bounds = tester.getRect(find.byType(_SheetForm));
      expect(bounds.width, 500);
      expect(bounds.center.dx, closeTo(951 / 2, 0.01));

      for (final size in [const Size(466, 678), const Size(904, 810)]) {
        resize(size, keyboard: 300);
        await tester.pumpAndSettle();
        bounds = tester.getRect(find.byType(_SheetForm));
        expect(bounds.bottom, lessThanOrEqualTo(size.height - 300));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.center.dx, closeTo(size.width / 2, 0.01));
        expect(bounds.width, lessThanOrEqualTo(size.width));
        expect(
          tester.state<_SheetFormState>(find.byType(_SheetForm)),
          same(state),
        );
        expect(find.text('Najdorf'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(_SheetForm), findsNothing);
    },
  );
}

class _SheetForm extends StatefulWidget {
  const _SheetForm();
  @override
  State<_SheetForm> createState() => _SheetFormState();
}

class _SheetFormState extends State<_SheetForm> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 500,
    width: double.infinity,
    child: ListView(
      children: [
        TextField(controller: controller),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/destination_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 390.0, 768.0]) {
    for (final scale in [1.0, 1.4]) {
      testWidgets(
        'destination title centers icon and text at $width, scale $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: EventViewShell(
                      title: 'Reports',
                      titleIcon: const Icon(Icons.assessment_rounded),
                      tabs: const ['Reports'],
                      pageBuilder: (_, _) => const SizedBox.shrink(),
                    ),
                  );
                },
              ),
            ),
          );
          final title = tester.getRect(find.byType(DestinationTitle));
          final icon = tester.getRect(find.byIcon(Icons.assessment_rounded));
          final text = tester.getRect(
            find.descendant(
              of: find.byType(DestinationTitle),
              matching: find.text('Reports'),
            ),
          );
          expect(title.center.dx, closeTo(width / 2, 0.5));
          expect(icon.right, lessThan(text.left));
          expect(icon.center.dy, closeTo(text.center.dy, 0.5));
          expect(title.contains(text.topLeft), isTrue);
          expect(
            title.contains(text.bottomRight - const Offset(0.01, 0.01)),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

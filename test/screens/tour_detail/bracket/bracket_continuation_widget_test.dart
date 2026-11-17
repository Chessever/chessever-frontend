import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_connector_painter.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_graph_layout.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/knockout_bracket_canvas.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/knockout_match_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'match_play_advancement_test.dart' as f;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('InterDisplay');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Inter-$weight.otf').readAsBytesSync(),
          ),
        ),
      );
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final light in [false, true]) {
    testWidgets(
      'complete future bracket is readable and static in ${light ? 'light' : 'dark'}',
      (tester) async {
        final bracket = f.build(metadata: f.metadata());
        final layout = buildBracketGraphLayout(bracket);
        await tester.binding.setSurfaceSize(layout.size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final boundary = GlobalKey();
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: light
                      ? AppColors.light.background
                      : AppColors.dark.background,
                  child: KnockoutBracketCanvas(
                    bracket: bracket,
                    layout: layout,
                    onMatchTap: (_) => taps++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(KnockoutMatchCard), findsNWidgets(16));
        final projected = bracket.stages
            .expand((s) => s.matches)
            .where((m) => m.isProjected);
        expect(projected, hasLength(8));
        for (final match in projected) {
          final card = find.byKey(ValueKey('bracket-match-${match.key}'));
          await tester.tap(card, warnIfMissed: false);
          expect(
            find.descendant(of: card, matching: find.text('0')),
            findsNothing,
          );
        }
        expect(taps, 0);
        final painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<BracketConnectorPainter>()
            .single;
        expect(painter.connections, hasLength(16));
        expect(painter.futureColor.a, lessThan(painter.confirmedColor.a));
        final colors = light ? AppColors.light : AppColors.dark;
        expect(
          wcagContrast(painter.futureColor, colors.background),
          greaterThanOrEqualTo(3),
        );
        final futureGround = Color.alphaBlend(
          colors.popup.withValues(alpha: 0.55),
          colors.background,
        );
        expect(
          wcagContrast(colors.textSecondary, futureGround),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
        final output = Platform.environment['BRACKET_SNAPSHOT_DIR'];
        if (output != null) {
          final images = tester.widgetList<Image>(find.byType(Image)).toList();
          await tester.runAsync(
            () => Future.wait(
              images.map(
                (image) => precacheImage(image.image, boundary.currentContext!),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await Directory(output).create(recursive: true);
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$output/bracket-complete-${light ? 'light' : 'dark'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
}

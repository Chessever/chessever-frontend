import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/widgets/youtube_video_fields.dart';

void main() {
  testWidgets(
    'pasting a parameter URL fills fields and editing time updates the saved link',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        for (final family in ['Roboto', 'Inter', 'Geist']) {
          await (FontLoader(
            family,
          )..addFont(rootBundle.load('assets/fonts/Inter-Regular.otf'))).load();
        }
      });
      final form = GlobalKey<FormState>();
      final paint = GlobalKey();
      var saved = '';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: RepaintBoundary(
              key: paint,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Form(
                    key: form,
                    child: YoutubeVideoFields(
                      value: '',
                      onChanged: (value) => saved = value,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byType(EditableText).first,
        'https://youtu.be/abcdefghijk?t=12m30s&end=1200&loop=1&cc_load_policy=1&cc_lang_pref=en',
      );
      await tester.pump();
      expect(find.text('12:30'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget);
      await tester.enterText(find.byType(EditableText).at(1), '13:00');
      await tester.pump();
      expect(saved, contains('start=780'));
      expect(saved, contains('loop=1'));
      expect(form.currentState!.validate(), isTrue);
      await tester.tap(find.text('More playback options'));
      await tester.pumpAndSettle();
      expect(find.text('Show captions'), findsOneWidget);
      if (const bool.fromEnvironment('VIDEO_SCREENSHOTS')) {
        await tester.runAsync(() async {
          final boundary =
              paint.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '/tmp/chessever-video-mobile-form.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
      await tester.enterText(find.byType(EditableText).at(2), '01:00');
      await tester.pump();
      expect(form.currentState!.validate(), isFalse);
      await tester.enterText(find.byType(EditableText).first, '');
      await tester.pump();
      expect(saved, '');
      expect(form.currentState!.validate(), isTrue);
    },
  );
}

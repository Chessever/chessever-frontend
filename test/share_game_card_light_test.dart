import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:screenshot/screenshot.dart';

double _contrast(Color ink, Color ground) {
  final fg = Color.alphaBlend(ink, ground).computeLuminance();
  final bg = ground.computeLuminance();
  return (math.max(fg, bg) + 0.05) / (math.min(fg, bg) + 0.05);
}

Future<void> _loadInter() async {
  final loader = FontLoader('InterDisplay');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.otf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Pumps the share overlay for a finished draw, in [theme].
Future<void> _pumpOverlay(
  WidgetTester tester,
  ThemeData theme, {
  Size size = const Size(430, 932),
  double textScale = 1,
  String whitePlayerName = 'Carlsen, Magnus',
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        key: UniqueKey(),
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return ShareGameCardOverlay(
              boardSettings: const ChessboardSettings(),
              positionFen: '8/8/4k3/8/8/4K3/8/8 w - - 0 60',
              lastMove: null,
              pgn: '1. e4 e5 *',
              moveSans: const ['e4', 'e5'],
              whitePlayerName: whitePlayerName,
              blackPlayerName: 'Nakamura, Hikaru',
              whitePlayerElo: '2831',
              blackPlayerElo: '2802',
              whitePlayerTitle: 'GM',
              blackPlayerTitle: 'GM',
              whitePlayerClock: '1:57:00',
              blackPlayerClock: '1:55:00',
              tournamentName: 'Norway Chess 2026',
              roundInfo: 'Round 4',
              currentMoveIndex: 1,
              evaluation: 0.0,
              mate: 0,
              isFlipped: false,
              gameStatus: GameStatus.draw,
              isAtGameEnd: true,
              onClose: () {},
              shareUrl: 'https://chessever.com/g/abc123',
              gameId: 'test',
            );
          },
        ),
      ),
    ),
  );
  // Entrance fades and the draw markers' delayed springs.
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The captured card's own frame: the one decoration in the off-screen
/// capture that carries both an edge and a cast shadow.
BoxDecoration _cardFrame(WidgetTester tester) {
  final frames = [
    for (final box in tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(Screenshot),
        matching: find.byType(DecoratedBox),
      ),
    ))
      if (box.decoration case final BoxDecoration d
          when d.border != null && (d.boxShadow?.isNotEmpty ?? false))
        d,
  ];
  expect(frames, isNotEmpty);
  return frames.first;
}

void main() {
  setUpAll(_loadInter);

  testWidgets('the draw marker is a drawn one-half, centred on its disc', (
    tester,
  ) async {
    const side = 64.0;
    final pixels = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      const ShareDrawGlyphPainter().paint(
        Canvas(recorder),
        const Size.square(side),
      );
      final image = await recorder.endRecording().toImage(
        side.toInt(),
        side.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    });

    var minX = side, minY = side, maxX = -1.0, maxY = -1.0;
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final alpha = pixels!.getUint8((y * side.toInt() + x) * 4 + 3);
        if (alpha < 128) continue;
        minX = math.min(minX, x.toDouble());
        maxX = math.max(maxX, x.toDouble());
        minY = math.min(minY, y.toDouble());
        maxY = math.max(maxY, y.toDouble());
      }
    }
    expect(maxX, greaterThan(minX), reason: 'the glyph painted no ink');
    // Mathematically centred on the ink, within a pixel on each axis.
    expect((minX + maxX) / 2, closeTo((side - 1) / 2, 1));
    expect((minY + maxY) / 2, closeTo((side - 1) / 2, 1));
    // And sized to read: most of the disc, clear of its edge.
    expect(maxY - minY, inInclusiveRange(side * 0.35, side * 0.7));
  });

  testWidgets('light: the card sits on paper with an edge and a tight shadow', (
    tester,
  ) async {
    await _pumpOverlay(tester, AppTheme.lightTheme);
    final colors = AppColors.light;
    final frame = _cardFrame(tester);
    expect(frame.color, colors.surface);
    expect((frame.border! as Border).top.width, 1);
    final shadow = frame.boxShadow!.single;
    expect(shadow.color, colors.shadow);
    expect(shadow.blurRadius, lessThanOrEqualTo(6));
    // The card lifts off the capture margin behind it.
    expect(
      _contrast(colors.divider, colors.background),
      greaterThan(1.2),
      reason: 'card edge vs capture margin',
    );
    // The draw mark stays the board's shipped dove in both themes.
    expect(find.textContaining('\u{1F54A}'), findsWidgets);
  });

  testWidgets('dark: the card keeps its historical frame', (tester) async {
    await _pumpOverlay(tester, AppTheme.darkTheme);
    final frame = _cardFrame(tester);
    expect(frame.color, AppColors.dark.background);
    expect((frame.border! as Border).top.width, 3);
    expect(frame.boxShadow!.single.blurRadius, 12);
  });

  testWidgets('light: nothing overflows at 360dp and 1.3x text', (
    tester,
  ) async {
    await _pumpOverlay(
      tester,
      AppTheme.lightTheme,
      size: const Size(360, 780),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Share Image'), findsOneWidget);
    expect(find.text('Copy FEN'), findsOneWidget);
  });

  testWidgets('light: every text run on the card and chrome clears AA', (
    tester,
  ) async {
    await _pumpOverlay(tester, AppTheme.lightTheme);
    final failures = <String>[];
    final checked = <String>{};
    for (final element in find.byType(RichText).evaluate()) {
      final paragraph = element.widget as RichText;
      final ground = _nearestGround(element);
      if (ground == null) continue;
      _visitInks(paragraph.text, null, (text, ink) {
        checked.add(text);
        final ratio = _contrast(ink, ground);
        if (ratio < 4.5) {
          failures.add('"$text" ${ratio.toStringAsFixed(2)}');
        }
      });
    }
    // The card's names and clocks and the chrome's labels were all read.
    expect(
      checked,
      containsAll(<String>['Nakamura', '1:57:00', '0.0', 'Share GIF']),
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  testWidgets(
    'a shared board keeps the name size: a long surname fades, never shrinks',
    (tester) async {
      const surname = 'García de la Cruz Fernández de la Fuente';
      await _pumpOverlay(
        tester,
        AppTheme.darkTheme,
        size: const Size(360, 780),
        whitePlayerName: '$surname, María',
      );

      // Visible preview and export capture.
      final labels = find.textContaining(surname, findRichText: true);
      final shortLabels = find.text(
        'GM Nakamura, Hikaru 2802',
        findRichText: true,
      );
      expect(labels, findsNWidgets(2));
      expect(shortLabels, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final label = labels.at(i);
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.overflow, TextOverflow.fade);
        expect(
          find.ancestor(of: label, matching: find.byType(FittedBox)),
          findsNothing,
        );
        // Exactly the size of the short name on the same card.
        expect(
          _fontSizes(tester.widget<RichText>(label).text).toSet(),
          everyElement(
            isIn(_fontSizes(tester.widget<RichText>(shortLabels.at(i)).text)),
          ),
        );
        expect(
          tester.getSize(label).height,
          tester.getSize(shortLabels.at(i)).height,
        );
      }

      // At 360dp the surname is too wide even alone: it fades at its end and
      // the rating stays whole beside it, clear of the clock.
      final faded = find.text('GM $surname', findRichText: true);
      expect(faded, findsOneWidget);
      final fadedParagraph = tester.renderObject<RenderParagraph>(faded);
      expect(
        fadedParagraph.size.width,
        lessThan(fadedParagraph.textSize.width),
      );
      final rating = find.text(' 2831', findRichText: true);
      expect(rating, findsOneWidget);
      final ratingParagraph = tester.renderObject<RenderParagraph>(rating);
      expect(
        ratingParagraph.size.width,
        greaterThanOrEqualTo(ratingParagraph.textSize.width),
      );
      expect(
        _fontSizes(tester.widget<RichText>(rating).text).single,
        isIn(_fontSizes(tester.widget<RichText>(shortLabels.first).text)),
      );
      final ratingRect = tester.getRect(rating);
      expect(find.text('1:57:00'), findsNWidgets(2));
      final clockRects =
          [
            for (var i = 0; i < 2; i++)
              tester.getRect(find.text('1:57:00').at(i)),
          ]..sort(
            (a, b) => (a.center.dy - ratingRect.center.dy).abs().compareTo(
              (b.center.dy - ratingRect.center.dy).abs(),
            ),
          );
      expect(tester.getRect(faded).right, lessThanOrEqualTo(ratingRect.left));
      expect(ratingRect.right, lessThan(clockRects.first.left));

      for (final paragraph in tester.widgetList<RichText>(
        find.byType(RichText),
      )) {
        if (paragraph.text.toPlainText().contains(surname)) {
          expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
        }
      }
    },
  );
}

/// Font size of every piece of text in [root], inherited styles applied.
List<double> _fontSizes(InlineSpan root) {
  final sizes = <double>[];
  void visit(InlineSpan span, double? inherited) {
    final size = span.style?.fontSize ?? inherited;
    if (span is! TextSpan) return;
    if ((span.text ?? '').isNotEmpty) sizes.add(size!);
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, size);
    }
  }

  visit(root, null);
  return sizes;
}

/// The first opaque fill behind [element], translucent layers above it
/// composited on.
Color? _nearestGround(Element element) {
  final layers = <Color>[];
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    Color? fill;
    if (widget is ColoredBox) {
      fill = widget.color;
    } else if (widget is DecoratedBox &&
        widget.position == DecorationPosition.background &&
        widget.decoration is BoxDecoration) {
      fill = (widget.decoration as BoxDecoration).color;
    } else if (widget is Material &&
        widget.type != MaterialType.transparency &&
        widget.color != null) {
      fill = widget.color;
    }
    if (fill == null || fill.a == 0) return true;
    layers.add(fill);
    return fill.a < 1;
  });
  if (layers.isEmpty || layers.last.a < 1) return null;
  var ground = layers.last;
  for (final layer in layers.reversed.skip(1)) {
    ground = Color.alphaBlend(layer, ground);
  }
  return ground;
}

void _visitInks(
  InlineSpan span,
  TextStyle? inherited,
  void Function(String text, Color ink) visit,
) {
  if (span is! TextSpan) return;
  final style = inherited?.merge(span.style) ?? span.style;
  final text = span.text?.trim() ?? '';
  if (text.isNotEmpty && style?.color != null) visit(text, style!.color!);
  for (final child in span.children ?? const <InlineSpan>[]) {
    _visitInks(child, style, visit);
  }
}

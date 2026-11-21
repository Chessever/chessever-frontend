// Renders every popup that opens over the board, over the live board page
// (board, players, a 60-ply notation), in light and dark, at a 393x852
// phone view at 3x (the tablet menu at 1024x1366, 2x).
//
//   flutter test --no-pub test/chessboard_surfaces_preview_test.dart \
//     --dart-define=POPUP_SWEEP_DIR=/tmp/popup_sweep/g2/after
//
// Without POPUP_SWEEP_DIR the scenes still run as a smoke test and write
// nothing.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessground/chessground.dart'
    show Chessboard, ChessgroundImages;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show AsyncValue;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/chessboard_surfaces_harness.dart';

const _outDir = String.fromEnvironment('POPUP_SWEEP_DIR');
const _capture = ValueKey('chessboard_surfaces_capture');

Future<SurfacesBoard> _pumpBoard(
  WidgetTester tester, {
  required bool light,
  bool tablet = false,
}) async {
  final board = await pumpSurfacesBoard(
    tester,
    light: light,
    size: tablet ? const Size(1024, 1366) : const Size(393, 852),
    dpr: tablet ? 2 : 3,
    safeArea: tablet
        ? const EdgeInsets.only(top: 24, bottom: 20)
        : const EdgeInsets.only(top: 59, bottom: 34),
    wrap: (app) => RepaintBoundary(key: _capture, child: app),
  );
  await _precache(tester);
  return board;
}

/// Decodes every picture on screen for real, so the page is the busy one.
Future<void> _precache(WidgetTester tester) async {
  await tester.runAsync(() async {
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
    final context = tester.element(find.byType(Scaffold).first);
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      try {
        await precacheImage(widget.image, context);
      } catch (_) {}
    }
  });
  await tester.pump();
  await tester.pump();
}

Future<void> _shot(WidgetTester tester, String name, bool light) async {
  expect(tester.takeException(), isNull);
  if (_outDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_outDir).create(recursive: true);
    await File(
      '$_outDir/${name}_${light ? 'light' : 'dark'}.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// A scene with real shadows: flutter_test draws every shadow as an
/// unblurred block ([debugDisableShadows]), which is not what a phone shows.
void _scene(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

/// The worst WCAG contrast of the theme's text inks over [panel]'s pixels
/// (an empty plate, so every pixel is glass): the 0.5th and 99.5th
/// percentiles decide, a lone grain speck is not what a glyph sits on.
Future<Map<String, double>> _plateContrast(
  WidgetTester tester,
  Rect panel,
) async {
  final pixels = <Color>[];
  final ratio = tester.view.devicePixelRatio;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final inside = panel.deflate(4);
    for (var y = (inside.top * ratio).ceil(); y < inside.bottom * ratio; y++) {
      for (
        var x = (inside.left * ratio).ceil();
        x < inside.right * ratio;
        x++
      ) {
        final i = (y * image.width + x) * 4;
        pixels.add(
          Color.fromARGB(
            255,
            data.getUint8(i),
            data.getUint8(i + 1),
            data.getUint8(i + 2),
          ),
        );
      }
    }
    image.dispose();
  });
  pixels.sort((a, b) => a.computeLuminance().compareTo(b.computeLuminance()));
  final darkest = pixels[pixels.length ~/ 200];
  final lightest = pixels[pixels.length - 1 - pixels.length ~/ 200];
  final colors = tester.element(find.byType(Scaffold).first).colors;
  return {
    for (final MapEntry(key: name, value: ink) in {
      'textPrimary': colors.textPrimary,
      'textSecondary': colors.textSecondary,
      'body (textPrimary 70%)': colors.textPrimary.withValues(alpha: 0.7),
    }.entries)
      name: [
        wcagContrast(ink, darkest),
        wcagContrast(ink, lightest),
      ].reduce((a, b) => a < b ? a : b),
  };
}

/// The contrast of the ink in [box] (a line of text) against the fill
/// behind it, as drawn: the pixel furthest from the box's median, past the
/// 0.5th percentile, against that median.
Future<double> _inkOnFill(WidgetTester tester, Rect box) async {
  final lums = <double>[];
  final ratio = tester.view.devicePixelRatio;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    for (var y = (box.top * ratio).ceil(); y < box.bottom * ratio; y++) {
      for (var x = (box.left * ratio).ceil(); x < box.right * ratio; x++) {
        final i = (y * image.width + x) * 4;
        lums.add(
          Color.fromARGB(
            255,
            data.getUint8(i),
            data.getUint8(i + 1),
            data.getUint8(i + 2),
          ).computeLuminance(),
        );
      }
    }
    image.dispose();
  });
  lums.sort();
  final fill = lums[lums.length ~/ 2];
  final low = lums[lums.length ~/ 200];
  final high = lums[lums.length - 1 - lums.length ~/ 200];
  final ink = (high - fill).abs() > (fill - low).abs() ? high : low;
  final lighter = ink > fill ? ink : fill;
  final darker = ink > fill ? fill : ink;
  return (lighter + 0.05) / (darker + 0.05);
}

void _expectLegible(String scene, Map<String, double> contrasts) {
  // ignore: avoid_print
  print(
    'CONTRAST $scene: ${contrasts.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}:1').join(' | ')}',
  );
  for (final MapEntry(key: ink, value: ratio) in contrasts.entries) {
    expect(ratio, greaterThanOrEqualTo(4.5), reason: '$scene: $ink');
  }
}

Finder get _move => find.textContaining(RegExp(r'^[NBRQK]?[a-h]?x?[a-h][1-8]'));

/// Whether [finder]'s widget is drawn at full strength: nothing above it
/// fades it, and nothing scales it away.
bool _drawnInFull(WidgetTester tester, Finder finder) {
  var full = true;
  tester.element(finder).visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Opacity && widget.opacity < 1) full = false;
    if (widget is FadeTransition && widget.opacity.value < 1) full = false;
    if (widget is Transform && widget.transform.getMaxScaleOnAxis() < 0.5) {
      full = false;
    }
    return widget is! Scaffold;
  });
  return full;
}

/// Puts the first board into a PV preview, as previewing an engine line
/// does: the notation lays its "Preview mode" veil over the moves.
void _enterPvPreview(SurfacesBoard board) {
  final notifier = board.container.read(
    chessBoardScreenProviderNew(
      ChessBoardProviderParams(game: board.games.first, index: 0),
    ).notifier,
  );
  // ignore: invalid_use_of_protected_member
  final state = notifier.state.value!;
  // ignore: invalid_use_of_protected_member
  notifier.state = AsyncValue.data(state.copyWith(isPvPreviewActive: true));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'swipable_walkthrough_dont_show': true,
      'explorer_panel_walkthrough_dont_show': true,
      'like_walkthrough_dont_show': true,
      'board_pinch_coachmark_dont_show': true,
    });
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-anon-key',
    );
    GameAnalysisReportStore.debugSetInstance(GameAnalysisReportStore.memory());

    Future<void> family(String name, List<String> files) async {
      final loader = FontLoader(name);
      for (final file in files) {
        loader.addFont(
          Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
        );
      }
      await loader.load();
    }

    final inter = [
      for (final weight in ['Regular', 'Medium', 'Bold'])
        'assets/fonts/Inter-$weight.otf',
    ];
    await family('InterDisplay', inter);
    await family('Inter', inter);
    await family('Roboto', inter);
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
  });

  tearDownAll(GameAnalysisReportStore.debugResetInstance);

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';

    _scene('the board page, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light);
      await _shot(tester, 'page', light);
      await board.dispose();
    });

    _scene('game switcher, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light);
      board.tapGameSwitcher();
      await tester.pump();
      await board.settle();
      await _shot(tester, 'game_switcher', light);
      // The chip the panel hangs from stays out of the dim: its label reads
      // as it does with nothing open (it fell to 1.83:1 under the dim).
      final label = find.descendant(
        of: find.byKey(e2eKey(E2eIds.boardGameSelector)).first,
        matching: find.byType(Text),
      );
      final contrast = await _inkOnFill(tester, tester.getRect(label.first));
      // ignore: avoid_print
      print('CONTRAST switcher chip $theme: ${contrast.toStringAsFixed(2)}:1');
      expect(contrast, greaterThanOrEqualTo(4.5));
      await board.dispose();
    });

    _scene('app-bar menu, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light);
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pump();
      await board.settle();
      expect(find.text('Share Game'), findsWidgets);
      await _shot(tester, 'overflow_menu', light);
      await board.dispose();
    });

    _scene('board hold menu, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light);
      final hold = await tester.startGesture(
        tester.getCenter(find.byType(Chessboard).first),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      await hold.up();
      await tester.pump();
      await board.settle();
      expect(find.text('Flip Board'), findsWidgets);
      await _shot(tester, 'board_menu', light);
      await board.dispose();
    });

    _scene('event info sheet, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light);
      await tester.tap(find.byTooltip('Event info').first);
      await tester.pump();
      // Fixed frames: a loading spinner never settles.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _shot(tester, 'event_info', light);
      await board.dispose();
    });

    _scene('move actions sheet, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light);
      await tester.longPress(_move.first);
      await tester.pump();
      await board.settle();
      expect(find.text('Comment'), findsWidgets);
      await _shot(tester, 'move_actions', light);
      await board.dispose();
    });

    _scene('comment editor, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light);
      await tester.longPress(_move.first);
      await board.settle();
      await tester.tap(find.text('Comment').first);
      await tester.pump();
      await board.settle();
      FocusManager.instance.primaryFocus?.unfocus();
      await board.settle();
      await _shot(tester, 'comment_editor', light);
      await board.dispose();
    });

    _scene('NAG picker, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light);
      await tester.longPress(_move.first);
      await board.settle();
      await tester.tap(find.text('Annotate (!? ± ∞ =)'));
      await tester.pump();
      await board.settle();
      expect(find.text('QUALITY'), findsOneWidget);
      await _shot(tester, 'nag_picker', light);
      await board.dispose();
    });

    // The notation's "Preview mode" veil, laid over the moves while a PV
    // line is previewed on the board. Its copy is on screen from the veil's
    // first frame, and every ink on it reads over the busiest notation.
    _scene('notation preview veil, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light);
      _enterPvPreview(board);
      await tester.pump();
      final title = find.text('Preview mode');
      expect(title, findsOneWidget);
      final fullOnFirstFrame = _drawnInFull(tester, title);
      await _shot(tester, 'pv_preview_first_frame', light);
      await board.settle();
      await _shot(tester, 'pv_preview', light);
      // The glass between the notation's top and the copy: blurred moves
      // under the veil, what the copy has to read over.
      final notation = tester.getRect(
        find.byKey(e2eKey(E2eIds.boardNotationRoot)),
      );
      final copyTop = tester
          .getRect(find.byIcon(Icons.visibility_outlined))
          .top;
      _expectLegible(
        'preview veil $theme',
        await _plateContrast(
          tester,
          Rect.fromLTRB(
            notation.left + 8,
            notation.top + 4,
            notation.right - 8,
            copyTop - 4,
          ),
        ),
      );
      expect(fullOnFirstFrame, isTrue, reason: 'copy hidden on frame one');
      await board.dispose();
    });

    // The plates, empty, over the busiest part of the page: every pixel of
    // them is glass, and the worst one decides whether text on it reads.
    _scene('sheet plate contrast over the board, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light);
      final context = tester.element(find.byType(Scaffold).first);
      unawaited(
        Navigator.of(context).push(
          ChessSheetRoutes.commentEditor(
            context: context,
            builder: (context) => Sheet(
              decoration: ChessSheetDecoration.dark(context),
              // Up over the board: the sheet's top reaches the busy squares.
              child: const SizedBox(height: 640, width: double.infinity),
            ),
          ),
        ),
      );
      await tester.pump();
      await board.settle();
      final panel = tester.getRect(find.byType(ChessSheetGlass));
      _expectLegible('sheet $theme', await _plateContrast(tester, panel));
      await _shot(tester, 'plate_sheet', light);
      board.navigator.pop();
      await board.settle();
      await board.dispose();
    });

    _scene('popdown plate contrast over the board, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light);
      final context = tester.element(find.byType(Scaffold).first);
      // The game switcher's panel, at its place and size, over its dim,
      // cut as the switcher cuts it: solved over the page the anchored dim
      // leaves, at the anchored menus' coverage.
      unawaited(
        showGeneralDialog<void>(
          context: context,
          barrierColor: AnchoredGlassDim.colorOf(context),
          transitionDuration: Duration.zero,
          pageBuilder: (context, _, _) => Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 112),
              child: PopupGlass(
                width: 361,
                height: 420,
                borderRadius: BorderRadius.circular(12),
                tone: context.colors.surface,
                page: AnchoredGlassDim.pageOf(context),
                cover: AnchoredGlassDim.cover,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await board.settle();
      final panel = tester.getRect(find.byType(PopupGlass));
      _expectLegible('popdown $theme', await _plateContrast(tester, panel));
      board.navigator.pop();
      await board.settle();
      await board.dispose();
    });

    _scene('tablet app-bar menu, $theme', (tester) async {
      final board = await _pumpBoard(tester, light: light, tablet: true);
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pump();
      await board.settle();
      expect(find.text('Share Game'), findsWidgets);
      await _shot(tester, 'tablet_overflow_menu', light);
      // The tablet menu holds off dismissal for a moment after opening.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tapAt(const Offset(20, 1300));
      await board.settle();
      await board.dispose();
    });
  }
}

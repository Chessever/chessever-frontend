// Renders the centred popups over a busy Today page to PNGs for review:
// Today's filter popup (opened by its glass button), a confirm dialog and
// the games filter, in light and dark, at a 393x852 phone view, 3x.
//
//   flutter test --no-pub test/popup_glass_preview_test.dart \
//     --dart-define=POPUP_DIR=/tmp/popup/out
//
// Without POPUP_DIR the scenes still run as a smoke test and write nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _outDir = String.fromEnvironment('POPUP_DIR');

const _capture = ValueKey('popup_capture');
const _confirm = ValueKey('popup_confirm');
const _games = ValueKey('popup_games');

const _fens = [
  'r1bqkb1r/pp3ppp/2nppn2/8/3NP3/2N5/PPP1BPPP/R1BQK2R w KQkq - 0 7',
  'rnbqk2r/ppp1bppp/4pn2/3p4/2PP4/2N2N2/PP2PPPP/R1BQKB1R w KQkq - 2 5',
  'r2q1rk1/pp1nbppp/2p1pn2/3p4/2PP4/1PN1PN2/PB3PPP/R2QKB1R w KQ - 1 9',
  'rn1qkb1r/pp2pppp/2p2n2/5b2/P1pP4/2N2N2/1P2PPPP/R1BQKB1R w KQkq - 1 6',
];

const _pairings = [
  ('GM Firouzja, Alireza', 2759, 'GM Caruana, Fabiano', 2795),
  ('GM Nakamura, Hikaru', 2802, 'GM Gukesh, D', 2777),
  ('GM Abdusattorov, Nodirbek', 2766, 'GM Erigaisi, Arjun', 2778),
  ('GM So, Wesley', 2741, 'GM Praggnanandhaa, R', 2758),
];

/// A Today-like column of live boards: the busiest thing a popup opens over.
class _TodayBoards extends StatelessWidget {
  const _TodayBoards();

  @override
  Widget build(BuildContext context) {
    const settings = BoardSettingsNew();
    final colors = context.colors;
    Widget player(String name, int rating, String clock) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$name  $rating',
              style: AppTypography.textSmMedium.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            clock,
            style: AppTypography.textSmMedium.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 12,
        16,
        120,
      ),
      children: [
        Text(
          'Today',
          style: AppTypography.textXlBold.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _fens.length; i++) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                player(_pairings[i].$1, _pairings[i].$2, '1:42:10'),
                StaticChessboard(
                  size: 341,
                  orientation: Side.white,
                  fen: _fens[i],
                  settings: StaticChessboardSettings(
                    colorScheme: settings.colorScheme,
                    pieceAssets: settings.pieceAssets,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                player(_pairings[i].$3, _pairings[i].$4, '1:38:55'),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

Future<void> _pumpToday(WidgetTester tester, {required bool light}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: const _TodayBoards(),
                floatingActionButton: Consumer(
                  builder: (context, ref, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Off-screen openers for the other popups.
                      Offstage(
                        child: Column(
                          children: [
                            TextButton(
                              key: _confirm,
                              onPressed: () => showSmoothConfirmDialog(
                                context: context,
                                title: 'Remove Smart Event?',
                                message:
                                    'Remove Najdorf Sicilian 2700+ from My '
                                    'Space? You can restore it with Undo. '
                                    'Starred events will still send '
                                    'notifications.',
                                confirmText: 'Remove',
                                isDangerous: true,
                              ),
                              child: const Text('confirm'),
                            ),
                            TextButton(
                              key: _games,
                              onPressed: () => showGameFilterDialog(
                                context: context,
                                currentFilter: GameFilter(),
                                showLiveFilter: false,
                              ),
                              child: const Text('games'),
                            ),
                          ],
                        ),
                      ),
                      const ForYouTodayFabs(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await _precache(tester);
}

/// Decodes every picture on screen (the board backgrounds, the pieces) for
/// real, so the page drawn is the finished, busiest one.
Future<void> _precache(WidgetTester tester) async {
  await tester.runAsync(() async {
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
    final context = tester.element(find.byType(Scaffold).first);
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(widget.image, context);
    }
    for (final box in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    )) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration && decoration.image != null) {
        await precacheImage(decoration.image!.image, context);
      }
    }
  });
  await tester.pump();
  await tester.pump();
}

/// Pumps until the open spring has come to rest.
Future<void> _settle(WidgetTester tester) async {
  var frames = 0;
  while (tester.binding.hasScheduledFrame && frames < 240) {
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
}

Future<void> _press(WidgetTester tester, Finder opener) async {
  final button = tester.widget<TextButton>(opener);
  button.onPressed!();
  await tester.pump();
  await _settle(tester);
}

Future<void> _shot(WidgetTester tester, String name, bool light) async {
  expect(tester.takeException(), isNull);
  if (_outDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = await boundary.toImage(pixelRatio: 3);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
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
    // Popups whose styles name no family take the theme's default (Roboto
    // on the test platform): give it Inter so they render as type.
    await family('Roboto', inter);
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
    // Pieces decoded before the first board is built, so every scene's
    // page is equally busy.
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';

    _scene('Today filter popup over live boards, $theme', (tester) async {
      await _pumpToday(tester, light: light);
      await tester.tap(find.byKey(const ValueKey(kForYouFilterButtonKey)));
      await tester.pump();
      await _settle(tester);
      expect(find.text('Apply Filters'), findsOneWidget);
      await _shot(tester, 'today_filter', light);
    });

    _scene('confirm popup, $theme', (tester) async {
      await _pumpToday(tester, light: light);
      await _press(tester, find.byKey(_confirm, skipOffstage: false));
      expect(find.text('Remove Smart Event?'), findsOneWidget);
      await _shot(tester, 'confirm', light);
    });

    _scene('games filter popup, $theme', (tester) async {
      await _pumpToday(tester, light: light);
      await _press(tester, find.byKey(_games, skipOffstage: false));
      expect(find.byType(GameFilterDialog), findsOneWidget);
      await _shot(tester, 'games_filter', light);
    });

    // Every tone a popup's glass is cut from: the surface (most popups),
    // the page background (the review prompts) and the raised popup tone
    // (About, Delete account, the update prompt).
    for (final tone in ['surface', 'background', 'surfaceElevated', 'popup']) {
      _scene('plate contrast over the busiest page, $tone, $theme', (
        tester,
      ) async {
        await _pumpToday(tester, light: light);
        // An empty panel the size of Today's filter popup over the boards, so
        // every pixel inside it is plate: the worst one decides legibility.
        final context = tester.element(find.byType(Scaffold).first);
        final palette = context.colors;
        showAlertModal<void>(
          context: context,
          horizontalPadding: 0,
          child: PopupGlass(
            width: 280.w,
            height: 470.h,
            borderRadius: BorderRadius.circular(16.br),
            tone: switch (tone) {
              'background' => palette.background,
              'surfaceElevated' => palette.surfaceElevated,
              'popup' => palette.popup,
              _ => palette.surface,
            },
            child: const SizedBox.expand(),
          ),
        );
        await tester.pump();
        await _settle(tester);
        final panel = tester.getRect(find.byType(PopupGlass));
        final pixels = <Color>[];
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(_capture),
          );
          final image = await boundary.toImage(pixelRatio: 3);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final inside = panel.deflate(4);
          for (var y = (inside.top * 3).ceil(); y < inside.bottom * 3; y++) {
            for (var x = (inside.left * 3).ceil(); x < inside.right * 3; x++) {
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
        pixels.sort(
          (a, b) => a.computeLuminance().compareTo(b.computeLuminance()),
        );
        // The 0.5th and 99.5th percentiles: single grain specks are not what
        // a glyph sits on.
        final darkest = pixels[pixels.length ~/ 200];
        final lightest = pixels[pixels.length - 1 - pixels.length ~/ 200];
        final colors = context.colors;
        final inks = {
          'textPrimary': colors.textPrimary,
          'textSecondary': colors.textSecondary,
          'body (textPrimary 70%)': colors.textPrimary.withValues(alpha: 0.7),
        };
        final report = <String>[];
        final contrasts = <String, double>{};
        for (final MapEntry(key: name, value: ink) in inks.entries) {
          final worst = [
            wcagContrast(ink, darkest),
            wcagContrast(ink, lightest),
          ].reduce((a, b) => a < b ? a : b);
          report.add('$name ${worst.toStringAsFixed(2)}:1');
          contrasts[name] = worst;
        }
        String hex(Color c) =>
            '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
        // ignore: avoid_print
        print(
          'CONTRAST $theme $tone: plate ${hex(darkest)}..${hex(lightest)} '
          '(${pixels.length} px) | ${report.join(' | ')}',
        );
        for (final MapEntry(key: name, value: worst) in contrasts.entries) {
          expect(
            worst,
            greaterThanOrEqualTo(4.5),
            reason: '$name on the plate',
          );
        }
        if (tone == 'surface') await _shot(tester, 'plate_empty', light);
      });
    }

    _scene('the page under the popups, $theme', (tester) async {
      await _pumpToday(tester, light: light);
      expect(find.byType(InkFab), findsWidgets);
      await _shot(tester, 'page', light);
    });
  }
}

// The bottom sheets' test bench: a busy Today-like page of live boards on a
// 393x852 phone at 3x, and an opener that calls a real sheet opener over it.
// Shared by the sheets glass, preview and open-perf tests.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const sheetsCapture = ValueKey('sheets_capture');
const sheetsOpen = ValueKey('sheets_open');
const sheetsScreen = Size(393, 852);

/// Opens a sheet from the page: [context] is under the page's Scaffold.
/// What it returns (the opener's future) is kept in [sheetsLastOpen].
typedef SheetOpener = Object? Function(BuildContext context, WidgetRef ref);

/// What the last opener returned: its future, for the sheets that have one.
Object? sheetsLastOpen;

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

/// A Today-like column of live boards: the busiest page a sheet opens over.
class SheetsBusyPage extends StatelessWidget {
  const SheetsBusyPage({super.key});

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

/// A phone: 393x852 logical at 3x, with a notch and a home indicator.
void sheetsPhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = sheetsScreen * 3;
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

/// The busy page with an opener button wired to [opener].
Widget sheetsHost({
  required SheetOpener opener,
  bool light = false,
  List<Override> overrides = const [],
}) => RepaintBoundary(
  key: sheetsCapture,
  child: ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(child: SheetsBusyPage()),
                Positioned(
                  right: 16,
                  bottom: 120,
                  child: Consumer(
                    builder: (context, ref, _) => Opacity(
                      opacity: 0,
                      child: TextButton(
                        key: sheetsOpen,
                        onPressed: () => sheetsLastOpen = opener(context, ref),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  ),
);

/// Calls the opener as a tap would.
void sheetsTapOpen(WidgetTester tester) =>
    tester.widget<TextButton>(find.byKey(sheetsOpen)).onPressed!();

/// Decodes every picture on screen for real, so the page is the finished,
/// busiest one.
Future<void> sheetsPrecache(WidgetTester tester) async {
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

/// Pumps 16 ms frames until nothing is scheduled; the frames it took.
Future<int> sheetsSettle(WidgetTester tester, {int limit = 600}) async {
  var frames = 0;
  while (tester.binding.hasScheduledFrame && frames < limit) {
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
  return frames;
}

/// Writes the capture boundary to `$dir/$name.png`.
Future<void> sheetsShot(WidgetTester tester, String dir, String name) async {
  if (dir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(sheetsCapture),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// A share card PNG, as the share flow renders one: [width] x [height]
/// physical pixels of a board-like checker with a title band.
Future<Uint8List> sheetsSharePng(
  WidgetTester tester, {
  int width = 1080,
  int height = 1350,
}) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFF1C2B2D),
    );
    final square = width / 8;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * square, 180 + y * square, square, square),
          Paint()
            ..color = (x + y).isEven
                ? const Color(0xFFE8D7B5)
                : const Color(0xFF9A7650),
        );
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    bytes = data!.buffer.asUint8List();
  });
  return bytes;
}

/// Loads Inter (and Material icons) so renders show type, not boxes.
Future<void> sheetsLoadFonts() async {
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
}

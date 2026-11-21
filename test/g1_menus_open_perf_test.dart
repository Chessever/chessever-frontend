// G1 (focus menu + popup menus): what opening each menu costs, on the UI
// thread and for the rasterizer, before and after the glass pass.
//
//   flutter test --no-pub test/g1_menus_open_perf_test.dart
//
// Uses only openers that exist before and after the change, so the same
// file runs against the previous build (copied into a scratch export of it)
// for the "before" numbers. Every number is a median of several runs and is
// printed as a `PERF` line. Host timings (debug JIT, software raster) are a
// proxy for the device: good for before/after ratios, not for milliseconds.
import 'dart:ui' as ui;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_chip.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_offer.dart';
import 'package:chessever2/screens/for_you/discovery/reports_share.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/popover_add_fab.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _runs = 7;
const _capture = ValueKey('g1_capture');
const _card = ValueKey('g1_card');
const _share = ValueKey('g1_share');
const _screen = Size(393, 852);

const _fens = [
  'r1bqkb1r/pp3ppp/2nppn2/8/3NP3/2N5/PPP1BPPP/R1BQK2R w KQkq - 0 7',
  'rnbqk2r/ppp1bppp/4pn2/3p4/2PP4/2N2N2/PP2PPPP/R1BQKB1R w KQkq - 2 5',
  'r2q1rk1/pp1nbppp/2p1pn2/3p4/2PP4/1PN1PN2/PB3PPP/R2QKB1R w KQ - 1 9',
  'rn1qkb1r/pp2pppp/2p2n2/5b2/P1pP4/2N2N2/1P2PPPP/R1BQKB1R w KQkq - 1 6',
];

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

String _ms(double value) => '${value.toStringAsFixed(2)} ms';

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _screen * 3;
  addTearDown(tester.view.reset);
}

/// A live board card: what a focus menu lifts on Today or the Feed.
class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.fen});

  final String fen;

  @override
  Widget build(BuildContext context) {
    const settings = BoardSettingsNew();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Expanded(child: Text('GM Firouzja, Alireza  2759')),
                Text('1:42:10'),
              ],
            ),
            const SizedBox(height: 6),
            StaticChessboard(
              size: 341,
              orientation: Side.white,
              fen: fen,
              settings: StaticChessboardSettings(
                colorScheme: settings.colorScheme,
                pieceAssets: settings.pieceAssets,
              ),
            ),
            const SizedBox(height: 6),
            const Row(
              children: [
                Expanded(child: Text('GM Caruana, Fabiano  2795')),
                Text('1:38:55'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A Today-like page of live boards, the second card long-pressable, and the
/// page's floating add button.
class _BusyPage extends StatelessWidget {
  const _BusyPage();

  static List<LibraryMenuAction> actions() => [
    for (final (icon, label) in [
      (Icons.ios_share_rounded, 'Share'),
      (Icons.link_rounded, 'Copy link'),
    ])
      LibraryMenuAction(
        icon: icon,
        label: label,
        prominent: true,
        onSelected: () {},
      ),
    for (final label in ['Open game', 'Copy PGN', 'Add to My Space'])
      LibraryMenuAction(
        icon: Icons.open_in_new_rounded,
        label: label,
        onSelected: () {},
      ),
    LibraryMenuAction(
      icon: Icons.delete_outline_rounded,
      label: 'Remove',
      destructive: true,
      onSelected: () {},
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 60, 16, 120),
        children: [
          // A Reports date heading's share menu opens here, over the boards.
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (context) => TextButton(
                key: _share,
                onPressed: () => showReportsShareMenu(context, null),
                child: const Text('Share reports'),
              ),
            ),
          ),
          for (var i = 0; i < _fens.length; i++) ...[
            if (i == 1)
              Builder(
                builder: (cardContext) => KeyedSubtree(
                  key: _card,
                  child: _BoardCard(fen: _fens[i]),
                ),
              )
            else
              _BoardCard(fen: _fens[i]),
            const SizedBox(height: 14),
          ],
        ],
      ),
      floatingActionButton: PopoverAddFab<int>(
        label: 'Add to My Space',
        choices: const [
          PopoverAddChoice(
            leading: Icon(Icons.storage_rounded),
            label: 'Database',
            value: 1,
          ),
          PopoverAddChoice(
            leading: Icon(Icons.auto_awesome_rounded),
            label: 'Smart event',
            value: 2,
          ),
          PopoverAddChoice(
            leading: Icon(Icons.edit_rounded),
            label: 'Edit',
            value: 3,
          ),
        ],
        onPicked: (_) {},
      ),
    );
  }
}

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    RepaintBoundary(
      key: _capture,
      child: ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return home;
            },
          ),
        ),
      ),
    );

/// Every backdrop filter on screen, with its size.
List<Size> _backdrops(WidgetTester tester) => [
  for (final element in find.byType(BackdropFilter).evaluate())
    (element.renderObject! as RenderBox).size,
];

String _describe(List<Size> sizes) => sizes.isEmpty
    ? 'none'
    : sizes
          .map(
            (size) =>
                '${size.width.toStringAsFixed(0)}x'
                '${size.height.toStringAsFixed(0)}'
                '${size == _screen ? ' (FULL SCREEN)' : ''}',
          )
          .join(', ');

/// Decodes every picture on the page for real, so it is the busiest one.
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

/// Rasterizes the frame on screen (page, dim, blurs, menu) as the GPU would
/// on every frame of an open; the median of a few passes.
Future<double> _raster(WidgetTester tester) async {
  final runs = <double>[];
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    for (var i = 0; i < 5; i++) {
      final watch = Stopwatch()..start();
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      watch.stop();
      expect(bytes, isNotNull);
      image.dispose();
      runs.add(watch.elapsedMicroseconds / 1000);
    }
  });
  return _median(runs);
}

/// One surface's open, measured [_runs] times.
///
/// [open] starts it synchronously (the opener's own work is timed with the
/// frame it schedules); [close] dismisses it. [gone] tells when it has left,
/// for a page that keeps animating on its own (else: when frames stop).
Future<void> _measure(
  WidgetTester tester, {
  required String name,
  required void Function() open,
  required Future<void> Function() close,
  bool Function()? gone,
}) async {
  final firstFrames = <double>[];
  final openFrames = <int>[];
  final closeFrames = <int>[];
  var fullScreenBlurFrames = 0;
  var rasterMs = 0.0;
  var inFlight = <Size>[];
  var atRest = <Size>[];
  for (var run = 0; run < _runs; run++) {
    final watch = Stopwatch()..start();
    open();
    await tester.pump();
    watch.stop();
    firstFrames.add(watch.elapsedMicroseconds / 1000);
    if (run == 0) {
      // Three frames in: the spring in flight.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      inFlight = _backdrops(tester);
      rasterMs = await _raster(tester);
    }
    var frames = 0;
    while (tester.binding.hasScheduledFrame && frames < 600) {
      if (_backdrops(tester).contains(_screen)) fullScreenBlurFrames++;
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
    }
    openFrames.add(frames);
    if (run == 0) atRest = _backdrops(tester);
    await close();
    var closing = 0;
    while (tester.binding.hasScheduledFrame &&
        closing < 600 &&
        !(gone?.call() ?? false)) {
      if (_backdrops(tester).contains(_screen)) fullScreenBlurFrames++;
      await tester.pump(const Duration(milliseconds: 16));
      closing++;
    }
    closeFrames.add(closing);
  }
  expect(tester.takeException(), isNull);
  // ignore: avoid_print
  print(
    'PERF $name: open (opener + first frame) median '
    '${_ms(_median(firstFrames))} (runs ${firstFrames.map(_ms).join(', ')})'
    ' | frames to settle open ${openFrames.join(',')}, close '
    '${closeFrames.join(',')} | raster of an in-flight frame '
    '${_ms(rasterMs)} | backdrops in flight ${inFlight.length}: '
    '${_describe(inFlight)} | at rest ${atRest.length}: ${_describe(atRest)}'
    ' | frames with a full-screen blur (all runs) $fullScreenBlurFrames',
  );
}

Future<void> _tapOutside(WidgetTester tester) async {
  await tester.tapAt(const Offset(200, 30));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
  });

  testWidgets('baseline: the page alone', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(const _BusyPage()));
    await _precache(tester);
    final raster = await _raster(tester);
    // ignore: avoid_print
    print('PERF page alone: raster ${_ms(raster)}');
  });

  testWidgets('focus menu (card lifted, 6 actions)', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(const _BusyPage()));
    await _precache(tester);
    await _measure(
      tester,
      name: 'focus menu',
      open: () {
        final cardContext = tester.element(find.byKey(_card));
        showLibraryContextMenu(
          context: cardContext,
          actions: _BusyPage.actions(),
          previewBuilder: (_) => _BoardCard(fen: _fens[1]),
        );
      },
      close: () => _tapOutside(tester),
    );
  });

  testWidgets('popup menu (Reports Share, the shared menu helper)', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_app(const _BusyPage()));
    await _precache(tester);
    await _measure(
      tester,
      name: 'popup menu',
      open: () => tester.widget<TextButton>(find.byKey(_share)).onPressed!(),
      close: () => _tapOutside(tester),
    );
  });

  testWidgets('popover (My Space add button)', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(const _BusyPage()));
    await _precache(tester);
    final fab = find.byType(PopoverAddFab<int>);
    await _measure(
      tester,
      name: 'popover',
      open: () {
        final gesture = tester.widget<GestureDetector>(
          find
              .descendant(of: fab, matching: find.byType(GestureDetector))
              .first,
        );
        gesture.onTap!();
      },
      close: () => _tapOutside(tester),
    );
  });

  testWidgets('like tag picker (board toolbar chip)', (tester) async {
    _phone(tester);
    final offers = TagChipOfferController()..open('game', const []);
    addTearDown(offers.dispose);
    await tester.pumpWidget(
      _app(
        Scaffold(
          appBar: AppBar(
            actions: [
              ValueListenableBuilder<TagOffer?>(
                valueListenable: offers.current,
                builder: (context, offer, _) => offer == null
                    ? const SizedBox.shrink()
                    : LikeTagChip(key: ValueKey(offer.token), offer: offer),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [for (final fen in _fens) _BoardCard(fen: fen)],
          ),
        ),
        overrides: [tagChipOfferProvider.overrideWithValue(offers)],
      ),
    );
    await _precache(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final chip = find.byType(LikeTagChip);
    await _measure(
      tester,
      name: 'like tag picker',
      open: () {
        final gesture = tester.widget<GestureDetector>(
          find
              .descendant(of: chip, matching: find.byType(GestureDetector))
              .first,
        );
        gesture.onTap!();
      },
      close: () => _tapOutside(tester),
      // The chip's own countdown keeps frames coming once the menu is shut.
      gone: () => find.byType(GridView).evaluate().isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

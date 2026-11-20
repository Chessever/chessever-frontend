// Times what opening Today's filter popup costs, on the UI thread and for
// the rasterizer, and pins the shape of the cure.
//
//   flutter test --no-pub test/popup_open_perf_test.dart
//
// Every number is a median of several runs and printed as a `PERF` line.
// These are host timings (debug JIT, software raster): a proxy for the
// device, good for before/after ratios, not for absolute milliseconds.
import 'dart:ui' as ui;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _runs = 7;
const _capture = ValueKey('perf_capture');
const _open = ValueKey('perf_open');

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

String _ms(double value) => '${value.toStringAsFixed(2)} ms';

double _time(void Function() body) {
  final watch = Stopwatch()..start();
  body();
  return watch.elapsedMicroseconds / 1000;
}

Future<double> _timeAsync(Future<void> Function() body) async {
  final watch = Stopwatch()..start();
  await body();
  return watch.elapsedMicroseconds / 1000;
}

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  addTearDown(tester.view.reset);
}

/// A Today-like page: a column of live boards with their players, busy
/// enough that a full-screen blur has real work to do.
class _BusyPage extends StatelessWidget {
  const _BusyPage();

  static const _fens = [
    'r1bqkb1r/pp3ppp/2nppn2/8/3NP3/2N5/PPP1BPPP/R1BQK2R w KQkq - 0 7',
    'rnbqk2r/ppp1bppp/4pn2/3p4/2PP4/2N2N2/PP2PPPP/R1BQKB1R w KQkq - 2 5',
    'r2q1rk1/pp1nbppp/2p1pn2/3p4/2PP4/1PN1PN2/PB3PPP/R2QKB1R w KQ - 1 9',
    'rn1qkb1r/pp2pppp/2p2n2/5b2/P1pP4/2N2N2/1P2PPPP/R1BQKB1R w KQkq - 1 6',
  ];

  @override
  Widget build(BuildContext context) {
    const settings = BoardSettingsNew();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      children: [
        for (final fen in _fens) ...[
          Row(
            children: const [
              Expanded(child: Text('GM Firouzja, Alireza  2759')),
              Text('1:42:10'),
            ],
          ),
          const SizedBox(height: 6),
          StaticChessboard(
            size: 361,
            orientation: Side.white,
            fen: fen,
            settings: StaticChessboardSettings(
              colorScheme: settings.colorScheme,
              pieceAssets: settings.pieceAssets,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: const [
              Expanded(child: Text('GM Caruana, Fabiano  2795')),
              Text('1:38:55'),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

Widget _app({required Widget home}) => RepaintBoundary(
  key: _capture,
  child: ProviderScope(
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

/// The Today page with its filter button calling the real opener.
Widget _today() => _app(
  home: Scaffold(
    body: Stack(
      children: [
        const Positioned.fill(child: _BusyPage()),
        Positioned(
          right: 16,
          bottom: 40,
          child: Consumer(
            builder: (context, ref, _) => TextButton(
              key: _open,
              onPressed: () => showEventFilters(context, ref),
              child: const Text('Filters'),
            ),
          ),
        ),
      ],
    ),
  ),
);

/// Pumps frames 16 ms apart until none is scheduled; the count of frames.
Future<int> _framesUntilIdle(WidgetTester tester) async {
  var frames = 0;
  while (tester.binding.hasScheduledFrame && frames < 600) {
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
  return frames;
}

/// Every BackdropFilter on screen, with how much of the screen it covers.
List<(BackdropFilter, Size)> _backdrops(WidgetTester tester) => [
  for (final element in find.byType(BackdropFilter).evaluate())
    (
      element.widget as BackdropFilter,
      (element.renderObject! as RenderBox).size,
    ),
];

void main() {
  // First, while nothing in this isolate has touched the opening catalog:
  // the first time a session opens the filter. Must stay the first test.
  testWidgets('Today filter: the first open of a session (cold)', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_today());
    await tester.pump();
    await tester.tap(find.byKey(_open));
    final coldMs = await _timeAsync(() => tester.pump());
    expect(find.byType(FilterPopup), findsOneWidget);
    await _framesUntilIdle(tester);
    Navigator.of(tester.element(find.byType(FilterPopup))).pop();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(_open));
    final secondMs = await _timeAsync(() => tester.pump());
    await _framesUntilIdle(tester);
    // ignore: avoid_print
    print(
      'PERF cold: first open tap frame ${_ms(coldMs)}, second open '
      '${_ms(secondMs)}',
    );
  });

  test('ECO browse tree: what the Opening dropdown built on every open', () {
    // EcoOpenings' static tables and the browse list are built once per
    // process; take that cost apart from the tree's own.
    final firstMs = _time(browseOpeningSuggestions);
    final suggestionsMs = _median([
      for (var i = 0; i < _runs; i++) _time(browseOpeningSuggestions),
    ]);
    final suggestions = browseOpeningSuggestions();
    expect(identical(suggestions, browseOpeningSuggestions()), isTrue);
    late Map<String, List<EcoBrowseNode>> tree;
    final treeMs = _median([
      for (var i = 0; i < _runs; i++)
        _time(() => tree = buildEcoBrowseTree(suggestions)),
    ]);
    expect(tree.keys, containsAll(['A', 'B', 'C', 'D', 'E']));
    // The dropdown's session copy: built once, then handed out as is.
    final sessionFirstMs = _time(ecoFilterBrowseTree);
    final sessionMs = _median([
      for (var i = 0; i < _runs; i++) _time(ecoFilterBrowseTree),
    ]);
    expect(identical(ecoFilterBrowseTree(), ecoFilterBrowseTree()), isTrue);
    // ignore: avoid_print
    print(
      'PERF eco: browseOpeningSuggestions first call (with statics) '
      '${_ms(firstMs)}, then ${_ms(suggestionsMs)} | buildEcoBrowseTree '
      '${_ms(treeMs)} (${suggestions.length} suggestions) | '
      'ecoFilterBrowseTree first ${_ms(sessionFirstMs)}, then '
      '${_ms(sessionMs)}',
    );
  });

  testWidgets('FilterPopup: opening the Opening list', (tester) async {
    _phone(tester);
    ecoFilterBrowseTree(); // As the warm-up leaves it.
    final runs = <double>[];
    for (var i = 0; i < _runs; i++) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(
          home: Scaffold(
            body: Center(
              child: FilterPopup(onApplyFilters: (_) {}, onResetFilters: () {}),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('eco-dropdown-header')));
      runs.add(await _timeAsync(() => tester.pump()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('eco-category-A')), findsOneWidget);
    }
    // ignore: avoid_print
    print(
      'PERF Opening expand frame: median ${_ms(_median(runs))} '
      '(runs ${runs.map(_ms).join(', ')})',
    );
  });

  testWidgets('FilterPopup: first build and layout', (tester) async {
    _phone(tester);
    final runs = <double>[];
    for (var i = 0; i < _runs; i++) {
      await tester.pumpWidget(const SizedBox());
      runs.add(
        await _timeAsync(
          () => tester.pumpWidget(
            _app(
              home: Scaffold(
                body: Center(
                  child: FilterPopup(
                    onApplyFilters: (_) {},
                    onResetFilters: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    expect(find.byType(FilterPopup), findsOneWidget);
    // ignore: avoid_print
    print(
      'PERF FilterPopup pumpWidget: median ${_ms(_median(runs))} '
      '(first ${_ms(runs.first)}; runs ${runs.map(_ms).join(', ')})',
    );
  });

  testWidgets('Today filter: open path, frames and backdrop', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_today());
    await tester.pump();
    final firstFrames = <double>[];
    final settleFrames = <int>[];
    for (var i = 0; i < _runs; i++) {
      await tester.tap(find.byKey(_open));
      // The tap's frame: route push, the popup's build, layout and paint.
      firstFrames.add(await _timeAsync(() => tester.pump()));
      settleFrames.add(await _framesUntilIdle(tester));
      expect(find.byType(FilterPopup), findsOneWidget);
      Navigator.of(tester.element(find.byType(FilterPopup))).pop();
      await tester.pump();
      await tester.pump();
    }

    // Open once more and look at the frame the spring is in flight on.
    await tester.tap(find.byKey(_open));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final backdrops = _backdrops(tester);
    final described = [
      for (final (filter, size) in backdrops)
        '${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}'
            '${size == screen ? ' (full screen)' : ''} ${filter.filter}',
    ];

    // Raster proxy: rasterize this in-flight frame (the page, the blur, the
    // popup) the way the GPU would every frame of the open.
    final rasterRuns = <double>[];
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_capture),
      );
      for (var i = 0; i < 5; i++) {
        final watch = Stopwatch()..start();
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        watch.stop();
        expect(bytes, isNotNull);
        image.dispose();
        rasterRuns.add(watch.elapsedMicroseconds / 1000);
      }
    });
    await _framesUntilIdle(tester);

    // ignore: avoid_print
    print(
      'PERF open: tap frame median ${_ms(_median(firstFrames))} '
      '(runs ${firstFrames.map(_ms).join(', ')}) | frames until idle '
      '${settleFrames.join(', ')} | raster of an in-flight frame median '
      '${_ms(_median(rasterRuns))} | backdrops ${backdrops.length}: '
      '${described.join('; ')}',
    );
  });
}

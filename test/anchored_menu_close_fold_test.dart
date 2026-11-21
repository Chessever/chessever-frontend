// How every anchored glass surface leaves the screen: the shared glass menu
// (showTabletSafeMenu), a dropdown (GlassDropdown), the panels that drop from
// a chip (an event's categories, a smart event's tiers), the focus menu, the
// add button's popover, the tag picker, and the game switcher they all fold
// like.
//
// A close must fold the whole glass (plate, rim, shadow, blur) away to
// nothing: the last frame with the panel still mounted may hold no visible
// glass, so taking the route (or the overlay entry) away changes no pixel a
// reader can see. A panel that shrinks to a size and is then removed pops.
//
//   flutter test --no-pub test/anchored_menu_close_fold_test.dart \
//     --dart-define=POPUP_SWEEP_DIR=/tmp/fixmenus/after
//
// Prints a `FOLD` line per surface and theme: the frames the close takes,
// how much of the glass was still on screen in its last mounted frame
// (painted area, as a share of the open panel's), and the pop: the pixels
// that change when the panel finally goes (channel delta over 12/255; the
// whole screen, where a button's own glyph may still be settling, and the
// panel's own area), and the largest change. Every surface but the board's
// game switcher (the reference, measured only) must fold to nothing. With
// POPUP_SWEEP_DIR it also writes a filmstrip of each close (every frame,
// cropped to the panel).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_chip.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_offer.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart';
import 'package:chessever2/widgets/popover_add_fab.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'g4_dropdowns_harness.dart';
import 'support/chessboard_surfaces_harness.dart';

const _outDir = String.fromEnvironment('POPUP_SWEEP_DIR');
const _capture = ValueKey('fold_capture');
const _card = ValueKey('fold_card');
const _menuButton = ValueKey('fold_menu_button');
const _screen = Size(393, 852);

/// A channel delta a reader can see.
const _visible = 12;

const _fens = [
  'r1bqkb1r/pp3ppp/2nppn2/8/3NP3/2N5/PPP1BPPP/R1BQK2R w KQkq - 0 7',
  'rnbqk2r/ppp1bppp/4pn2/3p4/2PP4/2N2N2/PP2PPPP/R1BQKB1R w KQkq - 2 5',
  'r2q1rk1/pp1nbppp/2p1pn2/3p4/2PP4/1PN1PN2/PB3PPP/R2QKB1R w KQ - 1 9',
];

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.fen});

  final String fen;

  @override
  Widget build(BuildContext context) {
    const settings = BoardSettingsNew();
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GM Firouzja, Alireza  2759',
              style: TextStyle(color: colors.textPrimary),
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
          ],
        ),
      ),
    );
  }
}

List<LibraryMenuAction> _focusActions() => [
  for (final (icon, label) in [
    (Icons.ios_share_rounded, 'Share'),
    (Icons.link_rounded, 'Copy link'),
    (Icons.favorite_border_rounded, 'Like'),
  ])
    LibraryMenuAction(
      icon: icon,
      label: label,
      prominent: true,
      onSelected: () {},
    ),
  for (final (icon, label) in [
    (Icons.open_in_new_rounded, 'Open game'),
    (Icons.content_copy_rounded, 'Copy PGN'),
  ])
    LibraryMenuAction(icon: icon, label: label, onSelected: () {}),
  LibraryMenuAction(
    icon: Icons.delete_outline_rounded,
    label: 'Remove',
    destructive: true,
    onSelected: () {},
  ),
];

class _BusyPage extends StatelessWidget {
  const _BusyPage({this.fab = false});

  final bool fab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 70, 16, 120),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              key: _menuButton,
              icon: const Icon(Icons.more_horiz_rounded),
              onPressed: () {},
            ),
          ),
          for (var i = 0; i < _fens.length; i++) ...[
            if (i == 1)
              KeyedSubtree(
                key: _card,
                child: _BoardCard(fen: _fens[i]),
              )
            else
              _BoardCard(fen: _fens[i]),
            const SizedBox(height: 14),
          ],
        ],
      ),
      floatingActionButton: fab
          ? PopoverAddFab<int>(
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
              ],
              onPicked: (_) {},
            )
          : null,
    );
  }
}

Widget _app(
  Widget home, {
  required bool light,
  List<Override> overrides = const [],
}) => RepaintBoundary(
  key: _capture,
  child: ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return home;
        },
      ),
    ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _screen * 3;
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _precache(WidgetTester tester) async {
  await tester.runAsync(() async {
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
  });
  await tester.pump();
  await tester.pump();
}

Future<void> _settle(WidgetTester tester, {int cap = 90}) async {
  var frames = 0;
  while (tester.binding.hasScheduledFrame && frames < cap) {
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
}

class _Frame {
  _Frame(this.image, this.bytes);

  final ui.Image image;
  final ByteData bytes;
}

Future<_Frame> _grab(WidgetTester tester, Key key) async {
  late _Frame frame;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame = _Frame(image, bytes!);
  });
  return frame;
}

/// Every glass panel on screen, painted, in logical pixels: its box through
/// every transform above it (a fold included).
List<Rect> _glass(WidgetTester tester) => [
  for (final element in find.byType(PopupGlass).evaluate())
    if (element.renderObject case final RenderBox box when box.attached)
      MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      ),
];

double _area(List<Rect> rects) =>
    rects.fold(0.0, (sum, r) => sum + r.width.abs() * r.height.abs());

/// Pixels that differ visibly between [a] and [b], the largest delta, and
/// where they are (logical pixels; null when none do). With [within] only
/// the pixels inside it (logical) count.
(int, int, Rect?) _diff(_Frame a, _Frame b, {Rect? within}) {
  var count = 0;
  var worst = 0;
  final x = a.bytes.buffer.asUint8List();
  final y = b.bytes.buffer.asUint8List();
  final n = math.min(x.length, y.length);
  final width = a.image.width;
  var left = 1 << 30, top = 1 << 30, right = -1, bottom = -1;
  for (var i = 0; i < n; i += 4) {
    var d = 0;
    for (var c = 0; c < 3; c++) {
      d = math.max(d, (x[i + c] - y[i + c]).abs());
    }
    final p = i ~/ 4;
    final px = p % width, py = p ~/ width;
    if (within != null && !within.contains(Offset(px / 3, py / 3))) continue;
    if (d > worst) worst = d;
    if (d > _visible) {
      count++;
      left = math.min(left, px);
      top = math.min(top, py);
      right = math.max(right, px);
      bottom = math.max(bottom, py);
    }
  }
  final where = right < 0
      ? null
      : Rect.fromLTRB(left / 3, top / 3, (right + 1) / 3, (bottom + 1) / 3);
  return (count, worst, where);
}

/// Writes the close's frames side by side, cropped to [crop].
Future<void> _filmstrip(
  WidgetTester tester,
  String name,
  List<_Frame> frames,
  Rect crop,
) async {
  if (_outDir.isEmpty || frames.isEmpty) return;
  const ratio = 3.0;
  final src = Rect.fromLTRB(
    (crop.left * ratio).floorToDouble(),
    (crop.top * ratio).floorToDouble(),
    (crop.right * ratio).ceilToDouble(),
    (crop.bottom * ratio).ceilToDouble(),
  );
  const scale = 0.5;
  const gap = 6.0;
  final cell = Size(src.width * scale, src.height * scale);
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final width = frames.length * (cell.width + gap) - gap;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, cell.height),
      Paint()..color = const Color(0xFF808080),
    );
    for (var i = 0; i < frames.length; i++) {
      canvas.drawImageRect(
        frames[i].image,
        src,
        Offset(i * (cell.width + gap), 0) & cell,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.ceil(), cell.height.ceil());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_outDir).create(recursive: true);
    await File(
      '$_outDir/close_$name.png',
    ).writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  });
}

/// Closes the open surface with [close] and follows it frame by frame until
/// its glass is gone ([gone], or no [PopupGlass] beyond [baseline] is left).
///
/// With [strict] it must fold to nothing: under 1% of the glass left in its
/// last mounted frame, and no pixel of the panel's own area changing by
/// more than [_maxPop] when it is finally taken away.
Future<void> _followClose(
  WidgetTester tester,
  String name, {
  required Future<void> Function() close,
  Key key = _capture,
  int baseline = 0,
  bool Function()? gone,
  bool strict = true,
}) async {
  expect(tester.takeException(), isNull);
  final open = _glass(tester);
  expect(open.length, greaterThan(baseline), reason: '$name is not open');
  final openArea = _area(open.skip(baseline).toList());
  final panel = open.skip(baseline).reduce((a, b) => a.expandToInclude(b));
  final crop = panel.inflate(28).intersect(Offset.zero & _screen);

  bool isGone() =>
      gone?.call() ?? find.byType(PopupGlass).evaluate().length <= baseline;

  final frames = <_Frame>[await _grab(tester, key)];
  await close();
  var lastArea = openArea;
  var count = 0;
  while (!isGone() && count < 60) {
    lastArea = _area(_glass(tester).skip(baseline).toList());
    frames.add(await _grab(tester, key));
    await tester.pump(const Duration(milliseconds: 16));
    count++;
  }
  // The first frame without the panel.
  final after = await _grab(tester, key);
  final (popPixels, popWorst, popWhere) = _diff(frames.last, after);
  final (_, panelPop, _) = _diff(frames.last, after, within: panel);
  frames.add(after);
  // ignore: avoid_print
  print(
    'FOLD $name: close frames $count | glass left in the last mounted frame '
    '${(100 * lastArea / math.max(openArea, 1)).toStringAsFixed(2)}% of the '
    'open panel | pop on removal: $popPixels px over $_visible/255, '
    'max delta $popWorst/255${popWhere == null ? '' : ' at $popWhere'} | '
    'inside the panel max delta $panelPop/255',
  );
  await _filmstrip(tester, name, frames, crop);
  for (final frame in frames) {
    frame.image.dispose();
  }
  expect(tester.takeException(), isNull);
  if (!strict) return;
  expect(count, greaterThan(1), reason: '$name closed without folding');
  expect(
    lastArea / openArea,
    lessThan(0.01),
    reason: '$name left glass on screen in its last frame',
  );
  expect(
    panelPop,
    lessThanOrEqualTo(_maxPop),
    reason: '$name popped when it was taken away',
  );
}

/// The most a pixel of the panel's area may change when a folded panel is
/// finally taken away: under what reads as a change.
const _maxPop = 32;

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

    _scene('shared glass menu folds away, $theme', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(const _BusyPage(), light: light));
      await _precache(tester);
      final context = tester.element(find.byKey(_menuButton));
      final button = context.findRenderObject()! as RenderBox;
      final overlay =
          Navigator.of(context).overlay!.context.findRenderObject()!
              as RenderBox;
      showTabletSafeMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          button.localToGlobal(Offset.zero, ancestor: overlay) & button.size,
          Offset.zero & overlay.size,
        ),
        items: const [
          PopupMenuItem(value: 'share', child: Text('Share game')),
          PopupMenuItem(value: 'copy', child: Text('Copy PGN')),
          PopupMenuItem(value: 'space', child: Text('Add to My Space')),
          PopupMenuItem(value: 'flip', child: Text('Flip board')),
        ],
      );
      await tester.pump();
      await _settle(tester);
      await _followClose(
        tester,
        'tablet_safe_menu_$theme',
        close: () async {
          await tester.tapAt(const Offset(30, 800));
          await tester.pump();
        },
      );
    });

    _scene('focus menu folds away, $theme', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(const _BusyPage(), light: light));
      await _precache(tester);
      showLibraryContextMenu(
        context: tester.element(find.byKey(_card)),
        actions: _focusActions(),
        previewBuilder: (_) => _BoardCard(fen: _fens[1]),
      );
      await tester.pump();
      await _settle(tester);
      await _followClose(
        tester,
        'focus_menu_$theme',
        close: () async {
          await tester.tapAt(const Offset(200, 20));
          await tester.pump();
        },
      );
    });

    _scene('add button popover folds away, $theme', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(const _BusyPage(fab: true), light: light));
      await _precache(tester);
      await tester.tap(find.byType(PopoverAddFab<int>));
      await tester.pump();
      await _settle(tester);
      await _followClose(
        tester,
        'add_fab_popover_$theme',
        close: () async {
          await tester.tapAt(const Offset(30, 200));
          await tester.pump();
        },
      );
    });

    _scene('tag picker folds away, $theme', (tester) async {
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
          light: light,
          overrides: [tagChipOfferProvider.overrideWithValue(offers)],
        ),
      );
      await _precache(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byType(LikeTagChip));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _followClose(
        tester,
        'tag_picker_$theme',
        close: () async {
          await tester.tapAt(const Offset(30, 800));
          await tester.pump();
        },
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    _scene('game switcher folds away (the reference), $theme', (tester) async {
      final board = await pumpSurfacesBoard(
        tester,
        light: light,
        wrap: (app) => RepaintBoundary(key: _capture, child: app),
      );
      await _precache(tester);
      final baseline = find.byType(PopupGlass).evaluate().length;
      board.tapGameSwitcher();
      await tester.pump();
      await board.settle();
      await _followClose(
        tester,
        'game_switcher_$theme',
        baseline: baseline,
        // The board's own surface: measured here as the reference.
        strict: false,
        close: () async {
          await tester.tapAt(const Offset(200, 800));
          await tester.pump();
        },
      );
      await board.dispose();
    });

    for (final (sceneName, file) in [
      ('category_dropdown', 'category_chip_menu'),
      ('smart_event_tier', 'smart_event_tier'),
      ('collections_round_select', 'dropdown'),
    ]) {
      final scene = g4Scenes.firstWhere((s) => s.name == sceneName);
      _scene('$file folds away, $theme', (tester) async {
        await scene.pump(tester, light: light);
        await _precache(tester);
        final baseline = find.byType(PopupGlass).evaluate().length;
        await g4Open(tester, scene);
        await g4Settle(tester, cap: 90);
        // Let the page's own async work (a populated page's cards reading
        // their evaluations) land before the close is followed, so a card
        // that changes under the panel is never counted as the panel's pop.
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g4Settle(tester, cap: 90);
        await _followClose(
          tester,
          '${file}_$theme',
          key: g4Capture,
          baseline: baseline,
          close: () async {
            await tester.tapAt(const Offset(12, 820));
            await tester.pump();
          },
        );
        await tester.pumpWidget(const SizedBox.shrink());
        // Past the realtime client's 50 s disconnect timer.
        await tester.pump(const Duration(seconds: 60));
      });
    }
  }
}

// Renders every anchored popup (the focus menu, the shared glass menu, a
// dropdown, the category chip menu, the game switcher, the smart event tier
// popover, the add button's popover and the tag picker) open over a busy
// page, in light and dark, at a 393x852 phone at 3x, and prints how the
// control that opened each one reads while it is open.
//
//   flutter test --no-pub test/popup_consolidation_preview_test.dart \
//     --dart-define=POPUP_SWEEP_DIR=/tmp/popup_consolidation/a/after
//
// Uses only openers that exist before and after the consolidation, so the
// same file renders both. Without POPUP_SWEEP_DIR the scenes still run as a
// smoke test and write nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/e2e/e2e_ids.dart';
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
const _capture = ValueKey('consolidation_capture');
const _card = ValueKey('consolidation_card');
const _menuButton = ValueKey('consolidation_menu_button');
const _screen = Size(393, 852);

const _fens = [
  'r1bqkb1r/pp3ppp/2nppn2/8/3NP3/2N5/PPP1BPPP/R1BQK2R w KQkq - 0 7',
  'rnbqk2r/ppp1bppp/4pn2/3p4/2PP4/2N2N2/PP2PPPP/R1BQKB1R w KQkq - 2 5',
  'r2q1rk1/pp1nbppp/2p1pn2/3p4/2PP4/1PN1PN2/PB3PPP/R2QKB1R w KQ - 1 9',
];

/// A live board card: what a focus menu lifts on Today or the Feed.
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'GM Firouzja, Alireza  2759',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                ),
                Text('1:42:10', style: TextStyle(color: colors.textSecondary)),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'GM Caruana, Fabiano  2795',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                ),
                Text('1:38:55', style: TextStyle(color: colors.textSecondary)),
              ],
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
    (Icons.dashboard_customize_outlined, 'Add to My Space'),
  ])
    LibraryMenuAction(icon: icon, label: label, onSelected: () {}),
  LibraryMenuAction(
    icon: Icons.delete_outline_rounded,
    label: 'Remove',
    destructive: true,
    onSelected: () {},
  ),
];

/// A Today-like page of live boards, the second card long-pressable, a menu
/// button over the first board, and the page's floating add button.
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
              KeyedSubtree(key: _card, child: _BoardCard(fen: _fens[i]))
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
                PopoverAddChoice(
                  leading: Icon(Icons.person_search_rounded),
                  label: 'Player',
                  value: 3,
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

/// Decodes every picture on the page for real, so it is the busy one.
Future<void> _precache(WidgetTester tester) async {
  await tester.runAsync(() async {
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
    final scaffolds = find.byType(Scaffold);
    if (scaffolds.evaluate().isEmpty) return;
    final context = tester.element(scaffolds.first);
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      try {
        await precacheImage(widget.image, context);
      } catch (_) {}
    }
  });
  await tester.pump();
  await tester.pump();
}

Future<int> _settle(WidgetTester tester, {int cap = 120}) async {
  var frames = 0;
  while (tester.binding.hasScheduledFrame && frames < cap) {
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
  return frames;
}

Future<ui.Image> _grab(WidgetTester tester, Key key) async {
  late ui.Image image;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
  });
  return image;
}

Future<void> _shot(
  WidgetTester tester,
  String name, {
  required bool light,
  Key key = _capture,
}) async {
  expect(tester.takeException(), isNull);
  if (_outDir.isEmpty) return;
  final image = await _grab(tester, key);
  await tester.runAsync(() async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_outDir).create(recursive: true);
    await File(
      '$_outDir/${name}_${light ? 'light' : 'dark'}.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
  image.dispose();
}

/// How the control in [rect] reads as it is drawn now: its most frequent
/// pixel is its ground, its pixel furthest from that is its ink (a glyph's
/// fully covered stem), and the WCAG ratio between the two.
Future<double> _renderedContrast(
  WidgetTester tester,
  Rect rect, {
  Key key = _capture,
}) async {
  final image = await _grab(tester, key);
  final ratio = tester.view.devicePixelRatio;
  final counts = <int, int>{};
  final pixels = <Color>[];
  await tester.runAsync(() async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    for (var y = (rect.top * ratio).ceil(); y < rect.bottom * ratio; y++) {
      for (var x = (rect.left * ratio).ceil(); x < rect.right * ratio; x++) {
        final i = (y * image.width + x) * 4;
        final c = Color.fromARGB(
          255,
          data.getUint8(i),
          data.getUint8(i + 1),
          data.getUint8(i + 2),
        );
        pixels.add(c);
        counts.update(c.toARGB32(), (n) => n + 1, ifAbsent: () => 1);
      }
    }
  });
  image.dispose();
  final ground = Color(
    counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key,
  );
  var best = 1.0;
  for (final pixel in pixels) {
    final contrast = wcagContrast(pixel, ground);
    if (contrast > best) best = contrast;
  }
  return best;
}

void _report(String name, String theme, double contrast) {
  // ignore: avoid_print
  print(
    'CHIPCONTRAST $name $theme: ${contrast.toStringAsFixed(2)}:1 '
    '(the opener, read while its popup is open)',
  );
}

/// A scene with real shadows: flutter_test otherwise draws every shadow as
/// an unblurred block.
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

    _scene('focus menu, $theme', (tester) async {
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
      await _shot(tester, 'focus_menu', light: light);
    });

    _scene('shared glass menu (tablet-safe), $theme', (tester) async {
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
      await _shot(tester, 'tablet_safe_menu', light: light);
    });

    _scene('add button popover, $theme', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(const _BusyPage(fab: true), light: light));
      await _precache(tester);
      await tester.tap(find.byType(PopoverAddFab<int>));
      await tester.pump();
      await _settle(tester);
      await _shot(tester, 'add_fab_popover', light: light);
    });

    _scene('tag picker, $theme', (tester) async {
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
      // The chip keeps its own countdown going: fixed frames, not settle.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      _report(
        'tag_chip',
        theme,
        await _renderedContrast(tester, tester.getRect(find.byType(LikeTagChip))),
      );
      await _shot(tester, 'tag_picker', light: light);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    // The same picker opened from mid-screen (where Feed's action row
    // sits), with too little room for its grid: the rows scroll, and once
    // scrolled a little both edges fade into the glass.
    _scene('tag picker, scrolled, $theme', (tester) async {
      _phone(tester);
      final offers = TagChipOfferController()..open('game', const []);
      addTearDown(offers.dispose);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 70, 16, 16),
                  children: [for (final fen in _fens) _BoardCard(fen: fen)],
                ),
                Positioned(
                  right: 16,
                  top: 420,
                  child: ValueListenableBuilder<TagOffer?>(
                    valueListenable: offers.current,
                    builder: (context, offer, _) => offer == null
                        ? const SizedBox.shrink()
                        : LikeTagChip(key: ValueKey(offer.token), offer: offer),
                  ),
                ),
              ],
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
      final grid = find.byType(GridView);
      expect(grid, findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(of: grid, matching: find.byType(Scrollable)),
            )
            .position
            .maxScrollExtent,
        greaterThan(0),
        reason: 'the grid must overflow for its edges to fade',
      );
      await tester.drag(grid, const Offset(0, -48));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _shot(tester, 'tag_picker_scrolled', light: light);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    _scene('game switcher, $theme', (tester) async {
      final board = await pumpSurfacesBoard(
        tester,
        light: light,
        wrap: (app) => RepaintBoundary(key: _capture, child: app),
      );
      await _precache(tester);
      board.tapGameSwitcher();
      await tester.pump();
      await board.settle();
      final chip = find.byKey(e2eKey(E2eIds.boardGameSelector)).first;
      _report(
        'game_switcher_chip',
        theme,
        await _renderedContrast(tester, tester.getRect(chip)),
      );
      await _shot(tester, 'game_switcher', light: light);
      await board.dispose();
    });

    for (final (sceneName, file, chipFinder) in [
      ('category_dropdown', 'category_chip_menu', null),
      ('smart_event_tier', 'smart_event_tier', 'GM+'),
      ('collections_round_select', 'dropdown', null),
    ]) {
      final scene = g4Scenes.firstWhere((s) => s.name == sceneName);
      _scene('$file, $theme', (tester) async {
        await scene.pump(tester, light: light);
        await _precache(tester);
        final opener = chipFinder == null
            ? scene.trigger().first
            : find.ancestor(
                of: find.text(chipFinder),
                matching: find.byType(AnimatedContainer),
              ).first;
        final rect = tester.getRect(opener);
        await g4Open(tester, scene);
        await g4Settle(tester, cap: 90);
        await _precache(tester);
        _report(
          '${file}_opener',
          theme,
          await _renderedContrast(tester, rect, key: g4Capture),
        );
        await _shot(tester, file, light: light, key: g4Capture);
        await tester.pumpWidget(const SizedBox.shrink());
        // The category scene's realtime channel leaves a 50 s timer.
        await tester.pump(const Duration(minutes: 1));
      });
    }
  }
}

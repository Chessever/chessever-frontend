// G1 (focus menu + popup menus): renders every menu surface of the group
// over a busy Today-like page of live boards, light and dark, at a 393x852
// phone view, 3x, for review.
//
//   flutter test --no-pub test/g1_menus_popup_sweep_test.dart \
//     --dart-define=POPUP_SWEEP_DIR=/tmp/popup_sweep/G1/after
//
// Uses only openers that exist before and after the glass pass, so the same
// file renders the previous build from a scratch export of it. Without
// POPUP_SWEEP_DIR the scenes still run as a smoke test and write nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_stream.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_chip.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_offer.dart';
import 'package:chessever2/screens/for_you/discovery/reports_share.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
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

const _outDir = String.fromEnvironment('POPUP_SWEEP_DIR');

const _capture = ValueKey('g1_sweep_capture');
const _card = ValueKey('g1_sweep_card');
const _share = ValueKey('g1_sweep_share');
const _rich = ValueKey('g1_sweep_rich');
const _prep = ValueKey('g1_sweep_prep');

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

/// One live board card, as Today lists them.
class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.index});

  final int index;

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
    final pairing = _pairings[index];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          player(pairing.$1, pairing.$2, '1:42:10'),
          StaticChessboard(
            size: 341,
            orientation: Side.white,
            fen: _fens[index],
            settings: StaticChessboardSettings(
              colorScheme: settings.colorScheme,
              pieceAssets: settings.pieceAssets,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          player(pairing.$3, pairing.$4, '1:38:55'),
        ],
      ),
    );
  }
}

List<LibraryMenuAction> _gameActions() => [
  LibraryMenuAction(
    icon: Icons.ios_share_rounded,
    label: 'Share',
    prominent: true,
    onSelected: () {},
  ),
  LibraryMenuAction(
    icon: Icons.link_rounded,
    label: 'Copy link',
    prominent: true,
    onSelected: () {},
  ),
  LibraryMenuAction(
    icon: Icons.bookmark_add_outlined,
    label: 'My Space',
    prominent: true,
    onSelected: () {},
  ),
  LibraryMenuAction(
    icon: Icons.open_in_new_rounded,
    label: 'Open game',
    onSelected: () {},
  ),
  LibraryMenuAction(
    icon: Icons.copy_rounded,
    label: 'Copy PGN',
    onSelected: () {},
  ),
  LibraryMenuAction(
    icon: Icons.sell_outlined,
    label: 'Tag this game',
    onSelected: () {},
  ),
  LibraryMenuAction(
    icon: Icons.delete_outline_rounded,
    label: 'Remove from Likes',
    destructive: true,
    onSelected: () {},
  ),
];

/// The favourites menu's rows (the one [showTabletSafeMenu] caller).
List<PopupMenuEntry<String>> _favoriteItems(BuildContext context) => [
  PopupMenuItem(
    value: 'space_player',
    child: Row(
      children: [
        Icon(Icons.dashboard_customize, size: 20.ic),
        SizedBox(width: 12.w),
        Text('Remove from My Space', style: AppTypography.textSmRegular),
      ],
    ),
  ),
  PopupMenuItem(
    value: 'delete',
    child: Row(
      children: [
        Icon(Icons.delete_outline, color: kRedColor, size: 20.ic),
        SizedBox(width: 12.w),
        Text(
          'Remove from favorites',
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.danger,
          ),
        ),
      ],
    ),
  ),
];

/// The Prep "Add source" menu's rows, the attached database one disabled.
List<PopupMenuEntry<PrepSource>> _prepItems() => [
  for (final source in PrepSource.playerSources)
    PopupMenuItem(
      key: ValueKey('prep_attach_${source.name}'),
      value: source,
      enabled: source != PrepSource.chessever,
      child: Row(
        children: [
          PrepSourceMark(source: source, size: 22.sp),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(source.label, style: AppTypography.textSmRegular),
          ),
        ],
      ),
    ),
];

RelativeRect _rectOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  return RelativeRect.fromRect(
    box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
    Offset.zero & overlay.size,
  );
}

/// The busy page: Today's boards, the add button, and the openers.
class _Today extends StatelessWidget {
  const _Today();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          Builder(
            builder: (context) => IconButton(
              key: _prep,
              tooltip: 'Add source',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => showTabletSafeMenu<PrepSource>(
                context: context,
                position: _rectOf(context),
                color: colors.surfaceElevated,
                items: _prepItems(),
              ),
            ),
          ),
          Builder(
            builder: (context) => IconButton(
              key: _rich,
              icon: const Icon(Icons.more_vert),
              onPressed: () => showTabletSafeMenu<String>(
                context: context,
                position: _rectOf(context),
                color: colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.br),
                ),
                items: _favoriteItems(context),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (context) => TextButton(
                key: _share,
                onPressed: () => showReportsShareMenu(context, null),
                child: const Text('Thursday, 20 November'),
              ),
            ),
          ),
          for (var i = 0; i < _fens.length; i++) ...[
            if (i == 1)
              KeyedSubtree(
                key: _card,
                child: _BoardCard(index: i),
              )
            else
              _BoardCard(index: i),
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

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required bool light,
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
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
    ),
  );
  await tester.pump();
  await _precache(tester);
}

/// Decodes every picture on screen for real, so the page is the busiest.
Future<void> _precache(WidgetTester tester) async {
  await tester.runAsync(() async {
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

/// Pumps until the open has come to rest (or the page keeps going).
Future<void> _settle(WidgetTester tester, {int max = 90}) async {
  var frames = 0;
  while (tester.binding.hasScheduledFrame && frames < max) {
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
}

Future<void> _shot(WidgetTester tester, String name, bool light) async {
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

void _press(WidgetTester tester, Key key) {
  final finder = find.byKey(key);
  final widget = tester.widget(finder);
  switch (widget) {
    case TextButton(:final onPressed?) || IconButton(:final onPressed?):
      onPressed();
    default:
      fail('$key is not a button');
  }
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

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';

    _scene('the page under the menus, $theme', (tester) async {
      await _pump(tester, const _Today(), light: light);
      await _shot(tester, 'page', light);
    });

    _scene('focus menu over live boards, $theme', (tester) async {
      await _pump(tester, const _Today(), light: light);
      showLibraryContextMenu(
        context: tester.element(find.byKey(_card)),
        actions: _gameActions(),
        previewBuilder: (_) => const _BoardCard(index: 1),
        origin: tester.getCenter(find.byKey(_card)),
      );
      await tester.pump();
      await _settle(tester);
      expect(find.text('Copy PGN'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shot(tester, 'focus_menu', light);
    });

    _scene('focus menu, mid-open (frame 3), $theme', (tester) async {
      await _pump(tester, const _Today(), light: light);
      showLibraryContextMenu(
        context: tester.element(find.byKey(_card)),
        actions: _gameActions(),
        previewBuilder: (_) => const _BoardCard(index: 1),
      );
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _shot(tester, 'focus_menu_opening', light);
    });

    _scene('Reports share menu, $theme', (tester) async {
      await _pump(tester, const _Today(), light: light);
      _press(tester, _share);
      await tester.pump();
      await _settle(tester);
      expect(find.text('Share'), findsOneWidget);
      await _shot(tester, 'share_menu', light);
    });

    _scene('favourites menu (showTabletSafeMenu), $theme', (tester) async {
      await _pump(tester, const _Today(), light: light);
      _press(tester, _rich);
      await tester.pump();
      await _settle(tester);
      expect(find.text('Remove from favorites'), findsOneWidget);
      await _shot(tester, 'favorites_menu', light);
    });

    _scene('Prep add-source menu, $theme', (tester) async {
      await _pump(tester, const _Today(), light: light);
      _press(tester, _prep);
      await tester.pump();
      await _settle(tester);
      expect(find.byKey(const ValueKey('prep_attach_lichess')), findsOneWidget);
      await _shot(tester, 'prep_add_source', light);
    });

    _scene('popover from the add button, $theme', (tester) async {
      await _pump(tester, const _Today(), light: light);
      await tester.tap(find.byType(PopoverAddFab<int>));
      await tester.pump();
      await _settle(tester);
      expect(find.text('Smart event'), findsOneWidget);
      await _shot(tester, 'popover', light);
    });

    _scene('tag picker from the board toolbar, $theme', (tester) async {
      final offers = TagChipOfferController()..open('game', ['Sacrifice']);
      addTearDown(offers.dispose);
      await _pump(
        tester,
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
            children: [
              for (var i = 0; i < _fens.length; i++) ...[
                _BoardCard(index: i),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
        light: light,
        overrides: [tagChipOfferProvider.overrideWithValue(offers)],
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byType(LikeTagChip));
      await tester.pump();
      await _settle(tester, max: 60);
      expect(find.text('Save'), findsOneWidget);
      await _shot(tester, 'tag_picker', light);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    _scene('stream chip follow menu, $theme', (tester) async {
      final session = EventVideoSession(repository: null);
      addTearDown(session.dispose);
      session.streams = EventVideoStream.readList([
        for (final (id, label) in [
          ('analysis-1', 'Analysis · English'),
          ('analysis-2', 'Analysis · Español'),
        ])
          {
            'id': id,
            'label': label,
            'kind': 'analysis',
            'authorId': 'author-$id',
            'authorName': 'Coach',
            'countryCode': 'GB',
            'url': 'https://www.youtube.com/watch?v=abcdefghijk',
            'provider': 'youtube',
            'sourceId': 'abcdefghijk',
            'publication': {'language': 'en', 'title': 'Analysis'},
          },
      ]);
      await _pump(
        tester,
        EventVideoScope(
          session: session,
          player: null,
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
              children: [
                const EventVideoFlags(),
                const SizedBox(height: 12),
                for (var i = 0; i < 3; i++) ...[
                  _BoardCard(index: i),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
        light: light,
      );
      await tester.longPress(
        find.byKey(const ValueKey('video_stream_analysis-1')),
      );
      await tester.pump();
      await _settle(tester);
      final error = tester.takeException();
      if (error != null) {
        // ignore: avoid_print
        print('SWEEP follow menu ($theme): the long-press threw $error');
      }
      await _shot(tester, 'follow_menu', light);
    });
  }
}

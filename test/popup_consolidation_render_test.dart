// Renders the surfaces the popup consolidation touches, over a busy page of
// live boards, in light and dark, at a 393x852 phone view, 3x: a short
// sheet, two tall sheets, the save-analysis sheet, the share preview, a
// dialog, the avatar lightbox, a coachmark, the share overlay, a tooltip
// and the paywall.
//
//   flutter test --no-pub test/popup_consolidation_render_test.dart \
//     --dart-define=POPUP_CONSOLIDATION_DIR=/tmp/popup_consolidation/b/after
//
// Only entry points that exist before and after the consolidation are used,
// so the same file renders the "before" set. Without POPUP_CONSOLIDATION_DIR
// the scenes still run as a smoke test and write nothing.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/widgets/board_pinch_coachmark.dart';
import 'package:chessever2/screens/chessboard/widgets/save_analysis_sheet.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_view.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dialogs_harness.dart';
import 'sheets_harness.dart';
import 'sheets_scenes.dart';

const _outDir = String.fromEnvironment('POPUP_CONSOLIDATION_DIR');

Future<void> _shot(WidgetTester tester, Key capture, String name) async {
  expect(tester.takeException(), isNull);
  if (_outDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(capture),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_outDir).create(recursive: true);
    await File('$_outDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// The mean colours of [cell]-point squares over [rect] of [capture], at 3x.
Future<List<Color>> _cells(
  WidgetTester tester,
  Key capture,
  Rect rect, {
  double cell = 4,
}) async {
  final cells = <Color>[];
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(capture),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final side = (cell * 3).round();
    for (
      var y = (rect.top * 3).ceil();
      y + side <= rect.bottom * 3;
      y += side
    ) {
      for (
        var x = (rect.left * 3).ceil();
        x + side <= rect.right * 3;
        x += side
      ) {
        var r = 0, g = 0, b = 0;
        for (var dy = 0; dy < side; dy++) {
          for (var dx = 0; dx < side; dx++) {
            final i = ((y + dy) * image.width + x + dx) * 4;
            r += data.getUint8(i);
            g += data.getUint8(i + 1);
            b += data.getUint8(i + 2);
          }
        }
        final n = side * side;
        cells.add(Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n));
      }
    }
    image.dispose();
  });
  return cells;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Real shadows: flutter_test draws every shadow as an unblurred block
/// otherwise, which is not what a phone shows.
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

PlayerCard _player(String name) => PlayerCard(
  name: name,
  federation: '',
  title: '',
  rating: 0,
  countryCode: '',
  team: null,
);

class _Board extends StateNotifier<AsyncValue<ChessBoardStateNew>>
    implements ChessBoardScreenNotifierNew {
  _Board(ChessBoardStateNew initial) : super(AsyncData(initial));

  @override
  SavedAnalysisData? get savedAnalysisData => null;

  @override
  void updateSavedAnalysisTagsSnapshot(List<String> tags) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => [];
}

class _Library implements LibraryRepository {
  @override
  Future<List<LibraryFolder>> getFolders() async => [
    for (var i = 0; i < 6; i++)
      LibraryFolder(
        id: 'db-$i',
        userId: 'render-user',
        name: const [
          'Najdorf repertoire',
          'Tata Steel 2026',
          'Endgame studies',
          'My blitz',
          'Candidates prep',
          'Classics',
        ][i],
        color: '#0FB4E5',
        icon: 'database',
        orderIndex: i,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ];

  @override
  Future<List<SavedAnalysis>> getSavedAnalysesBySourceGame({
    required String sourceGameId,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Package _package(PackageType type, double price, String label) => Package(
  type.name,
  type,
  StoreProduct(type.name, '', '', price, label, 'USD'),
  const PresentedOfferingContext('default', null, null),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List shareImage;
  var shareImageReady = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-publishable-key',
      // No deep-link listener (app_links has no test platform).
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
    await sheetsLoadFonts();
    // Styles with no family at all fall to the test font: Inter there too.
    final loader = FontLoader('FlutterTest');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Inter-$weight.otf').readAsBytesSync(),
          ),
        ),
      );
    }
    await loader.load();
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';

    // Sheets that open from the busy page through their real openers.
    for (final (shot, scene) in [
      ('short_sheet', 'add_to_library'),
      ('tall_sheet', 'position_games'),
      ('tall_sheet_my_space', 'my_space_add'),
      ('share_preview', 'share_preview'),
    ]) {
      _scene('$shot over live boards, $theme', (tester) async {
        sheetsPhone(tester);
        if (!shareImageReady) {
          shareImage = await sheetsSharePng(tester);
          shareImageReady = true;
        }
        final found = sheetScenes(
          shareImage: shareImage,
        ).firstWhere((s) => s.name == scene);
        await tester.pumpWidget(
          sheetsHost(
            opener: found.opener,
            light: light,
            overrides: found.overrides,
          ),
        );
        await tester.pump();
        await sheetsPrecache(tester);
        sheetsTapOpen(tester);
        await tester.pump();
        await sheetsSettle(tester);
        // The share preview's image decodes off the frame.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await sheetsSettle(tester);
        await _shot(tester, sheetsCapture, '${shot}_$theme');
      });
    }

    _scene('save analysis sheet over live boards, $theme', (tester) async {
      sheetsPhone(tester);
      final game = GamesTourModel(
        gameId: 'render-game',
        source: GameSource.localAnalysis,
        whitePlayer: _player('Firouzja, Alireza'),
        blackPlayer: _player('Caruana, Fabiano'),
        whiteTimeDisplay: '',
        blackTimeDisplay: '',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: GameStatus.unknown,
        roundId: '',
        tourId: '',
      );
      final state = ChessBoardStateNew(game: game);
      final params = ChessBoardProviderParams(game: game, index: 0);
      await tester.pumpWidget(
        sheetsHost(
          light: light,
          overrides: [
            chessBoardScreenProviderNew(
              params,
            ).overrideWith((ref) => _Board(state)),
            likedGamesProvider.overrideWith(_NoLikes.new),
            libraryRepositoryProvider.overrideWithValue(_Library()),
            folderAnalysisCountProvider.overrideWith(
              (ref, folderId) async => 3,
            ),
          ],
          opener: (context, ref) => unawaited(
            showSaveAnalysisSheet(
              context: context,
              state: state,
              params: params,
            ),
          ),
        ),
      );
      await tester.pump();
      await sheetsPrecache(tester);
      sheetsTapOpen(tester);
      await tester.pump();
      await sheetsSettle(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await sheetsSettle(tester);
      // The actions sit on the sheet's own glass: the sheet is solid (no
      // backdrop filter at all), and the bar is the same material, no band
      // across.
      expect(tester.widget<PopupGlass>(find.byType(PopupGlass)).solid, isTrue);
      expect(
        find.descendant(
          of: find.byType(PopupGlass),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      final bar = tester.getRect(find.byType(PopupGlassFill));
      // The strip left of the content, in the bar and just above it.
      final inBar = await _cells(
        tester,
        sheetsCapture,
        Rect.fromLTRB(3, bar.top + 4, 9, bar.bottom - 4),
        cell: 2,
      );
      final above = await _cells(
        tester,
        sheetsCapture,
        Rect.fromLTRB(3, bar.top - 60, 9, bar.top - 4),
        cell: 2,
      );
      Color mean(List<Color> cells) => Color.from(
        alpha: 1,
        red: cells.map((c) => c.r).reduce((a, b) => a + b) / cells.length,
        green: cells.map((c) => c.g).reduce((a, b) => a + b) / cells.length,
        blue: cells.map((c) => c.b).reduce((a, b) => a + b) / cells.length,
      );
      final a = mean(inBar), b = mean(above);
      for (final (x, y) in [(a.r, b.r), (a.g, b.g), (a.b, b.b)]) {
        expect((x - y).abs() * 255, lessThanOrEqualTo(2), reason: '$a vs $b');
      }
      await _shot(tester, sheetsCapture, 'save_analysis_$theme');
    });

    _scene('pinch coachmark over live boards, $theme', (tester) async {
      sheetsPhone(tester);
      await tester.pumpWidget(
        sheetsHost(
          light: light,
          opener: (context, ref) => Overlay.of(context).insert(
            OverlayEntry(
              builder: (_) => BoardPinchCoachmark(
                onDismiss: () {},
                onDontShowAgain: () {},
                currentStep: 2,
                totalSteps: 2,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await sheetsPrecache(tester);
      sheetsTapOpen(tester);
      await tester.pump();
      // The demo loops: a fixed time in, the card at rest.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // The card is the popups' glass, without a live blur over the
      // teaching stage.
      final card = find.descendant(
        of: find.byType(BoardPinchCoachmark),
        matching: find.byType(PopupGlass),
      );
      expect(card, findsOneWidget);
      expect(
        tester
            .renderObject<RenderBackdropFilter>(
              find.descendant(of: card, matching: find.byType(BackdropFilter)),
            )
            .enabled,
        isFalse,
      );
      await _shot(tester, sheetsCapture, 'coachmark_$theme');
      await tester.pumpWidget(const SizedBox());
    });

    _scene('share overlay over live boards, $theme', (tester) async {
      sheetsPhone(tester);
      await tester.pumpWidget(
        sheetsHost(
          light: light,
          opener: (context, ref) => Overlay.of(context).insert(
            OverlayEntry(
              builder: (_) => ShareGameCardOverlay(
                boardSettings: const ChessboardSettings(),
                positionFen:
                    'r1bqkb1r/pp3ppp/2nppn2/8/3NP3/2N5/PPP1BPPP/R1BQK2R '
                    'w KQkq - 0 7',
                lastMove: null,
                pgn: '1. e4 c5 *',
                moveSans: const ['e4', 'c5'],
                whitePlayerName: 'Carlsen, Magnus',
                blackPlayerName: 'Nakamura, Hikaru',
                currentMoveIndex: 1,
                evaluation: 0.3,
                mate: 0,
                isFlipped: false,
                gameStatus: GameStatus.ongoing,
                onClose: () {},
                shareUrl: 'https://chessever.com/g/abc123',
                gameId: 'render',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await sheetsPrecache(tester);
      sheetsTapOpen(tester);
      await tester.pump();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _shot(tester, sheetsCapture, 'share_overlay_$theme');
      await tester.pumpWidget(const SizedBox());
    });

    _scene('tooltip over live boards, $theme', (tester) async {
      sheetsPhone(tester);
      final tip = GlobalKey<TooltipState>();
      await tester.pumpWidget(
        sheetsHost(
          light: light,
          opener: (context, ref) => Overlay.of(context).insert(
            OverlayEntry(
              builder: (_) => Positioned(
                top: 360,
                left: 0,
                right: 0,
                child: Center(
                  child: Tooltip(
                    key: tip,
                    message: 'Copy the position as FEN',
                    child: const SizedBox(width: 44, height: 44),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await sheetsPrecache(tester);
      sheetsTapOpen(tester);
      await tester.pump();
      tip.currentState!.ensureTooltipVisible();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _shot(tester, sheetsCapture, 'tooltip_$theme');
      await tester.pumpWidget(const SizedBox());
    });

    _scene('paywall over live boards, $theme', (tester) async {
      sheetsPhone(tester);
      await tester.pumpWidget(
        sheetsHost(
          light: light,
          // As showPremiumPaywallSheet opens it.
          opener: (context, ref) => showGlassModalBottomSheet<bool>(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (context) => SizedBox(
              height: MediaQuery.sizeOf(context).height,
              child: PremiumPaywallView(
                trigger: PaywallTrigger.settings,
                plan: PlanType.annual,
                annual: _package(PackageType.annual, 119.99, r'$119.99'),
                monthly: _package(PackageType.monthly, 11.99, r'$11.99'),
                busy: false,
                loadingProducts: false,
                onSelect: (_) {},
                onPurchase: () {},
                onRestore: () {},
                onRedeem: () {},
                onClose: () {},
                onRetry: () {},
                onOpenUrl: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await sheetsPrecache(tester);
      sheetsTapOpen(tester);
      await tester.pump();
      await sheetsSettle(tester);
      await _shot(tester, sheetsCapture, 'paywall_$theme');
    });

    // A dialog and the avatar lightbox, from the dialogs' bench.
    for (final (shot, name) in [
      ('dialog', 'rewarded_choice'),
      ('avatar_lightbox', 'avatar_lightbox'),
    ]) {
      _scene('$shot over live boards, $theme', (tester) async {
        final scene = dialogScenes.firstWhere((s) => s.name == name);
        muteDialogsPlatform(tester);
        final opener = await scene.open(tester, light: light);
        opener();
        await tester.pump(scene.firstPump);
        var extra = 0;
        while (scene.shown().evaluate().isEmpty && extra < 20) {
          await tester.pump();
          extra++;
        }
        expect(scene.shown(), findsWidgets);
        await settleDialogs(tester, limit: 90);
        if (name == 'avatar_lightbox') {
          // The controls' type reads well over 7:1 on their glass.
          final panel = tester.getRect(find.byType(PopupGlass));
          final cells = await _cells(
            tester,
            dialogsCapture,
            Rect.fromLTRB(
              panel.left + 4,
              panel.top + PopupGlassStyle.sheenDepth,
              panel.right - 4,
              panel.top + PopupGlassStyle.sheenDepth + 8,
            ),
          );
          final worst = cells
              .map((c) => _contrast(Colors.white, c))
              .reduce((a, b) => a < b ? a : b);
          // And the page under the stage falls quiet: the brightest and
          // darkest parts of a board row differ by little.
          final stage = await _cells(
            tester,
            dialogsCapture,
            const Rect.fromLTRB(16, 150, 377, 200),
          );
          final lum = stage.map((c) => c.computeLuminance()).toList()..sort();
          // ignore: avoid_print
          print(
            'LIGHTBOX $theme: white on controls ${worst.toStringAsFixed(2)}:1, '
            'stage luminance ${lum.first.toStringAsFixed(3)}..'
            '${lum.last.toStringAsFixed(3)}',
          );
          expect(worst, greaterThanOrEqualTo(7));
        }
        await _shot(tester, dialogsCapture, '${shot}_$theme');
        await scene.close?.call(tester);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

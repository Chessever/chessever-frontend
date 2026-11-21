// The popups over the board, and the smooth_sheets sheets, are cut from the
// popups' frosted glass: each surface's one backdrop filter is clipped to it
// and on screen at full strength from the first frame (never under an
// opacity), nothing blurs the whole screen on any frame of an open, and the
// barrier under a glass sheet is the plain scrim its plate is solved over.
import 'dart:async';

import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessground/chessground.dart'
    show Chessboard, ChessboardSettings;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/chessboard_surfaces_harness.dart';

const _phone = Size(393, 852);

/// Every backdrop filter on screen, with its size.
List<Size> _backdropSizes(WidgetTester tester) => [
  for (final element in find.byType(BackdropFilter).evaluate())
    (element.renderObject! as RenderBox).size,
];

/// Whether anything between [finder]'s render object and the root fades it.
bool _underOpacity(WidgetTester tester, Finder finder) {
  RenderObject? node = tester.renderObject(finder).parent;
  while (node != null) {
    if (node is RenderOpacity && node.opacity < 1) return true;
    if (node is RenderAnimatedOpacity && node.opacity.value < 1) return true;
    node = node.parent;
  }
  return false;
}

/// Pumps [frames] 16 ms frames of an open; on each one, no backdrop filter
/// covers the screen, and once [glass] is on screen its frost is never
/// faded.
Future<void> _expectNoScreenBlur(
  WidgetTester tester,
  Finder glass, {
  Size screen = _phone,
  int frames = 30,
}) async {
  for (var frame = 0; frame < frames; frame++) {
    for (final size in _backdropSizes(tester)) {
      expect(
        size.width >= screen.width && size.height >= screen.height,
        isFalse,
        reason: 'a screen-sized blur on frame $frame',
      );
    }
    if (glass.evaluate().isNotEmpty) {
      expect(_underOpacity(tester, glass.first), isFalse, reason: '$frame');
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// [glass]'s one backdrop filter: inside it, clipped, no larger than it.
void _expectOwnFilter(WidgetTester tester, Finder glass) {
  final filters = find.descendant(
    of: glass,
    matching: find.byType(BackdropFilter),
  );
  expect(filters, findsOneWidget);
  expect(
    find.ancestor(of: filters, matching: find.byType(ClipRRect)),
    findsWidgets,
  );
  final panel = tester.getRect(
    find
            .descendant(of: glass, matching: find.byType(PopupGlass))
            .evaluate()
            .isEmpty
        ? glass
        : find.descendant(of: glass, matching: find.byType(PopupGlass)).first,
  );
  final filter = tester.getRect(filters);
  expect(filter.width, lessThanOrEqualTo(panel.width + 0.01));
  expect(filter.height, lessThanOrEqualTo(panel.height + 0.01));
  final blur = tester.widget<BackdropFilter>(filters).filter.toString();
  expect(
    blur,
    contains('blur(${PopupGlassStyle.blurSigma}, ${PopupGlassStyle.blurSigma}'),
  );
}

/// The topmost barrier's colour once it is at rest.
Color? _barrierColor(WidgetTester tester) {
  final barriers = tester
      .widgetList<ModalBarrier>(find.byType(ModalBarrier))
      .where((b) => b.color != null && b.color!.a > 0)
      .toList();
  return barriers.isEmpty ? null : barriers.last.color;
}

Finder get _move => find.textContaining(RegExp(r'^[NBRQK]?[a-h]?x?[a-h][1-8]'));

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
  });

  tearDownAll(GameAnalysisReportStore.debugResetInstance);

  group('the smooth_sheets sheet glass', () {
    for (final light in [false, true]) {
      testWidgets('ChessSheetDecoration is the glass over the glass scrim, '
          '${light ? 'light' : 'dark'}', (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = _phone * 3;
        addTearDown(tester.view.reset);
        late BuildContext host;
        await tester.pumpWidget(
          MaterialApp(
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                host = context;
                ResponsiveHelper.init(context);
                return const Scaffold(body: SizedBox.expand());
              },
            ),
          ),
        );
        unawaited(
          Navigator.of(host).push(
            ChessSheetRoutes.actionMenu(
              context: host,
              builder: (context) => Sheet(
                decoration: ChessSheetDecoration.dark(context),
                child: const SizedBox(
                  key: ValueKey('content'),
                  height: 360,
                  width: double.infinity,
                  child: ListTile(title: Text('Comment')),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final glass = find.byType(ChessSheetGlass);
        await _expectNoScreenBlur(tester, glass);
        await tester.pumpAndSettle();

        expect(glass, findsOneWidget);
        _expectOwnFilter(tester, glass);
        // Rounded at the top only.
        final panel = tester.widget<PopupGlass>(
          find.descendant(of: glass, matching: find.byType(PopupGlass)),
        );
        expect(panel.borderRadius.topLeft, const Radius.circular(28));
        expect(panel.borderRadius.bottomLeft, Radius.zero);
        // The content sits exactly where the sheet puts it; the panel hangs
        // past the sheet's sides and bottom so only the top rim reads.
        final content = tester.getRect(find.byKey(const ValueKey('content')));
        final slot = tester.getRect(glass);
        final rim = tester.getRect(
          find.descendant(of: glass, matching: find.byType(PopupGlass)),
        );
        expect(content.left, slot.left);
        expect(content.width, slot.width);
        expect(content.bottom, slot.bottom);
        expect(rim.left, lessThan(slot.left));
        expect(rim.right, greaterThan(slot.right));
        expect(rim.bottom, greaterThan(slot.bottom));
        expect(rim.top, slot.top);
        // The ink inside lands on a transparent Material.
        expect(
          find.descendant(of: glass, matching: find.byType(Material)),
          findsWidgets,
        );
        // The barrier: the theme's scrim at the popups' strength.
        final context = tester.element(glass);
        expect(
          _barrierColor(tester),
          context.colors.scrim.withValues(
            alpha: PopupGlassStyle.of(context).scrim,
          ),
        );
        expect(tester.takeException(), isNull);

        // A drag down still dismisses it.
        await tester.drag(
          find.byKey(const ValueKey('content')),
          const Offset(0, 500),
        );
        await tester.pumpAndSettle();
        expect(glass, findsNothing);
      });
    }

    testWidgets('the routes slide on a spring that comes to rest promptly', (
      tester,
    ) async {
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );
      final route = ChessSheetRoutes.commentEditor(
        context: host,
        builder: (context) => Sheet(
          decoration: ChessSheetDecoration.dark(context),
          child: const SizedBox(height: 300, width: double.infinity),
        ),
      );
      expect(route, isA<MotionSheetRoute<void>>());
      unawaited(Navigator.of(host).push(route));
      var frames = 0;
      await tester.pump();
      while (tester.binding.hasScheduledFrame && frames < 200) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      // A 400 ms spring at a sub-pixel rest: well under the ~48 frames the
      // default tolerance's creeping tail took.
      expect(frames, lessThan(42));
      expect(route.animation!.value, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('the board popups', () {
    Future<SurfacesBoard> board(WidgetTester tester, {bool light = false}) =>
        pumpSurfacesBoard(tester, light: light);

    for (final light in [false, true]) {
      final theme = light ? 'light' : 'dark';

      testWidgets('the game switcher is a glass popdown, $theme', (
        tester,
      ) async {
        final b = await board(tester, light: light);
        b.tapGameSwitcher();
        await tester.pump();
        final glass = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_GameDropdownOverlay',
          ),
          matching: find.byType(PopupGlass),
        );
        // Full strength from the first frame.
        expect(glass, findsOneWidget);
        await _expectNoScreenBlur(tester, glass);
        await b.settle();
        _expectOwnFilter(tester, glass);
        expect(_underOpacity(tester, glass), isFalse);
        // Closing folds it away; it leaves the tree once shut.
        await tester.tapAt(const Offset(8, 840));
        await _expectNoScreenBlur(tester, glass, frames: 10);
        await b.settle();
        expect(glass, findsNothing);
        expect(tester.takeException(), isNull);
        await b.dispose();
      });

      testWidgets('the app-bar menu is the glass menu, $theme', (tester) async {
        final b = await board(tester, light: light);
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pump();
        final glass = find.ancestor(
          of: find.text('Share Game'),
          matching: find.byType(PopupGlass),
        );
        await _expectNoScreenBlur(tester, glass);
        await b.settle();
        expect(glass, findsOneWidget);
        _expectOwnFilter(tester, glass);
        await tester.tap(find.text('Flip Board'));
        await b.settle();
        expect(glass, findsNothing);
        expect(tester.takeException(), isNull);
        await b.dispose();
      });

      testWidgets('a hold on the board opens the glass menu, $theme', (
        tester,
      ) async {
        final b = await board(tester, light: light);
        final hold = await tester.startGesture(
          tester.getCenter(find.byType(Chessboard).first),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
        await hold.up();
        await tester.pump();
        final glass = find.ancestor(
          of: find.text('Flip Board'),
          matching: find.byType(PopupGlass),
        );
        await _expectNoScreenBlur(tester, glass);
        await b.settle();
        expect(glass, findsOneWidget);
        _expectOwnFilter(tester, glass);
        b.navigator.pop();
        await b.settle();
        expect(tester.takeException(), isNull);
        await b.dispose();
      });

      testWidgets('event info is a glass sheet, $theme', (tester) async {
        final b = await board(tester, light: light);
        await tester.tap(find.byTooltip('Event info').first);
        await tester.pump();
        final glass = find.byType(ChessSheetGlass);
        await _expectNoScreenBlur(tester, glass, frames: 40);
        expect(glass, findsOneWidget);
        _expectOwnFilter(tester, glass);
        final context = tester.element(glass);
        expect(_barrierColor(tester), ChessSheetGlass.barrierColor(context));
        b.navigator.pop();
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        await b.dispose();
      });

      testWidgets('move actions, comment and NAG sheets are glass, $theme', (
        tester,
      ) async {
        final b = await board(tester, light: light);
        await tester.longPress(_move.first);
        await tester.pump();
        final glass = find.byType(ChessSheetGlass);
        await _expectNoScreenBlur(tester, glass);
        await b.settle();
        expect(find.text('Comment'), findsWidgets);
        expect(glass, findsOneWidget);
        _expectOwnFilter(tester, glass);

        // The comment editor is a page of the same sheet.
        await tester.tap(find.text('Comment').first);
        await tester.pump();
        await _expectNoScreenBlur(tester, glass);
        await b.settle();
        expect(glass, findsOneWidget);
        FocusManager.instance.primaryFocus?.unfocus();
        b.navigator.pop();
        await b.settle();

        // The NAG picker.
        await tester.longPress(_move.first);
        await b.settle();
        await tester.tap(find.text('Annotate (!? ± ∞ =)'));
        await tester.pump();
        await _expectNoScreenBlur(tester, glass);
        await b.settle();
        expect(find.text('QUALITY'), findsOneWidget);
        expect(glass, findsOneWidget);
        _expectOwnFilter(tester, glass);
        final context = tester.element(glass);
        expect(_barrierColor(tester), ChessSheetGlass.barrierColor(context));
        // Its glass reaches the bottom edge; the safe area is inside it.
        expect(tester.getRect(glass).bottom, _phone.height);
        expect(tester.takeException(), isNull);
        b.navigator.pop();
        await b.settle();
        await b.dispose();
      });
    }

    testWidgets('the open NAG picker rebuilds for its glyphs only', (
      tester,
    ) async {
      final b = await board(tester);
      await tester.longPress(_move.first);
      await b.settle();
      await tester.tap(find.text('Annotate (!? ± ∞ =)'));
      await tester.pump();
      await b.settle();
      expect(find.text('QUALITY'), findsOneWidget);

      final params = ChessBoardProviderParams(game: b.games.first, index: 0);
      final provider = chessBoardScreenProviderNew(params);
      var pickerBuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget.runtimeType.toString() == '_NagPickerSheet') {
          pickerBuilds++;
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      // An engine line: the board state changes, the move's glyphs do not.
      final notifier = b.container.read(provider.notifier);
      // ignore: invalid_use_of_protected_member
      notifier.state = AsyncValue.data(
        b.container
            .read(provider)
            .requireValue
            .copyWith(evaluation: 0.42, isEvaluating: true),
      );
      await tester.pump();
      expect(pickerBuilds, 0);

      // A glyph: the picker follows it.
      await tester.tap(find.text('!?').first);
      await tester.pump();
      expect(pickerBuilds, greaterThan(0));
      debugOnRebuildDirtyWidget = null;
      b.navigator.pop();
      await b.settle();
      expect(tester.takeException(), isNull);
      await b.dispose();
    });

    testWidgets('the tablet app-bar menu is the glass menu', (tester) async {
      final b = await pumpSurfacesBoard(
        tester,
        size: const Size(1024, 1366),
        dpr: 2,
        safeArea: const EdgeInsets.only(top: 24, bottom: 20),
      );
      expect(ResponsiveHelper.isTablet, isTrue);
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pump();
      final glass = find.ancestor(
        of: find.text('Share Game'),
        matching: find.byType(PopupGlass),
      );
      // The phantom tap that follows an open on a tablet (some 350 ms
      // later) does not close it: the menu is still up once everything has
      // settled (a close would have folded it away by then).
      await _expectNoScreenBlur(
        tester,
        glass,
        screen: const Size(1024, 1366),
        frames: 22,
      );
      await tester.tapAt(const Offset(20, 1300));
      await tester.pump();
      expect(glass, findsOneWidget);
      await _expectNoScreenBlur(tester, glass, screen: const Size(1024, 1366));
      await b.settle();
      expect(glass, findsOneWidget);
      _expectOwnFilter(tester, glass);
      // After the guard, a tap on the page closes it: it folds shut into
      // the button and is gone once folded.
      await tester.tapAt(const Offset(20, 1300));
      await tester.pump();
      await b.settle();
      expect(glass, findsNothing);
      expect(tester.takeException(), isNull);
      await b.dispose();
    });
  });

  group('the share overlay opens on the tap', () {
    testWidgets('a grid card waiting on the network opens at once', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(430, 932) * 3;
      addTearDown(tester.view.reset);
      final pgn = Completer<String?>();
      final repository = _PendingGameRepository(pgn.future);
      late WidgetRef cardRef;
      late BuildContext cardContext;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [gameRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Consumer(
              builder: (context, ref, _) {
                ResponsiveHelper.init(context);
                cardRef = ref;
                cardContext = context;
                return const Scaffold(body: SizedBox.expand());
              },
            ),
          ),
        ),
      );
      // A lean row: no PGN on the model, so the GIF's moves come from the
      // network, which has not answered.
      final game = GamesTourModel.fromGame(
        Games(
          id: 'lean-1',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'tour-1',
          tourSlug: 'tour-1',
          players: [
            Player(
              name: 'Carlsen, Magnus',
              title: 'GM',
              rating: 2831,
              fideId: 1503014,
              fed: 'NOR',
              clock: 0,
              team: '',
            ),
            Player(
              name: 'Nakamura, Hikaru',
              title: 'GM',
              rating: 2802,
              fideId: 2016192,
              fed: 'USA',
              clock: 0,
              team: '',
            ),
          ],
          status: '1-0',
          fen: '8/8/4k3/8/8/4K3/8/8 w - - 0 60',
        ),
      );
      unawaited(showGameShareOverlay(cardContext, cardRef, game));
      await tester.pump();
      await tester.pump();
      // On screen while the PGN is still on its way.
      expect(find.byType(ShareGameCardOverlay), findsOneWidget);
      expect(repository.asked, 1);
      // The export capture is built from the overlay's second frame.
      expect(find.byType(Screenshot), findsOneWidget);

      pgn.complete(null);
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ShareGameCardOverlay), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the export card waits for the overlay\'s first frame', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return ShareGameCardOverlay(
                  boardSettings: const ChessboardSettings(),
                  positionFen: '8/8/4k3/8/8/4K3/8/8 w - - 0 60',
                  lastMove: null,
                  pgn: '1. e4 e5 *',
                  moveSans: const ['e4', 'e5'],
                  whitePlayerName: 'Carlsen, Magnus',
                  blackPlayerName: 'Nakamura, Hikaru',
                  currentMoveIndex: 1,
                  evaluation: 0.0,
                  mate: 0,
                  isFlipped: false,
                  gameStatus: GameStatus.ongoing,
                  onClose: () {},
                  gameId: 'test',
                );
              },
            ),
          ),
        ),
      );
      // The first frame builds the card the reader sees, and only it.
      expect(find.byType(Screenshot), findsNothing);
      await tester.pump();
      expect(find.byType(Screenshot), findsOneWidget);
    });
  });
}

/// A repository whose PGN answer is [pgn], whenever it lands.
class _PendingGameRepository extends GameRepository {
  _PendingGameRepository(this.pgn);

  final Future<String?> pgn;
  int asked = 0;

  @override
  Future<String?> getGamePgn(String gameId) {
    asked++;
    return pgn;
  }
}

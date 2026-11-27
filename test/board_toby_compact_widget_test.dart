import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/widgets/toby_live_prediction.dart';
import 'package:chessever2/services/toby/toby_prediction.dart';
import 'package:chessground/chessground.dart'
    show Chessboard, ChessgroundImages;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/chessboard_surfaces_harness.dart';

const _captureKey = ValueKey('toby_compact_capture');
const _capturePath = String.fromEnvironment('TOBY_BOARD_CAPTURE');
const _badgeCapturePath = String.fromEnvironment('TOBY_BADGE_CAPTURE');

class _FixtureReading extends TobyReadingNotifier {
  _FixtureReading(this.reading);

  final TobyReading reading;

  @override
  TobyReadingState build(TobyQuery arg) => TobyReadingState.ready(reading);
}

class _BoardSubscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _BoardSubscription(bool paid)
    : super(SubscriptionState(isSubscribed: paid, isLoading: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoardReward extends RewardedAccessNotifier {
  int attempts = 0;
  bool confirm = false;

  @override
  Future<bool> unlock(BuildContext context) async {
    attempts++;
    if (confirm) {
      state = const RewardedAccessState(remaining: Duration(minutes: 10));
    }
    return confirm;
  }

  void expire() => state = const RewardedAccessState(expiry: 1);
}

Future<void> _captureBoard(WidgetTester tester, String path) async {
  if (path.isEmpty) return;
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pump();
  await tester.pump();
  await tester.runAsync(() async {
    final box = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await box.toImage(pixelRatio: tester.view.devicePixelRatio);
    final encoded = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    await File(path).writeAsBytes(encoded.buffer.asUint8List());
  });
}

void main() {
  late TobyReading reading;

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
    final fixture =
        jsonDecode(File('test/fixtures/toby/final-200.json').readAsStringSync())
            as Map<String, dynamic>;
    reading = TobyReading.fromJson(fixture['body'])!;

    if (_capturePath.isNotEmpty || _badgeCapturePath.isNotEmpty) {
      Future<void> family(String name, Iterable<String> paths) async {
        final loader = FontLoader(name);
        for (final path in paths) {
          loader.addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          );
        }
        await loader.load();
      }

      final inter = [
        for (final weight in ['Regular', 'Medium', 'Bold'])
          'assets/fonts/Inter-$weight.otf',
      ];
      for (final name in ['InterDisplay', 'Inter', 'Roboto']) {
        await family(name, inter);
      }
      final flutterRoot =
          Platform.environment['FLUTTER_ROOT'] ??
          File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
      final icons =
          '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
      if (File(icons).existsSync()) await family('MaterialIcons', [icons]);
      await ChessgroundImages.instance.loadAll(
        const BoardSettingsNew().pieceAssets,
        devicePixelRatio: 3,
      );
    }
  });

  tearDownAll(GameAnalysisReportStore.debugResetInstance);

  Future<SurfacesBoard> pumpBoard(
    WidgetTester tester,
    Size size, {
    bool premium = true,
  }) => pumpSurfacesBoard(
    tester,
    size: size,
    safeArea: const EdgeInsets.only(top: 30, bottom: 18),
    wrap: (app) => RepaintBoundary(key: _captureKey, child: app),
    extraOverrides: [
      tobyReaderHasPremiumProvider.overrideWithValue(premium),
      tobyReadingProvider.overrideWith(() => _FixtureReading(reading)),
    ],
  );

  final panel = find.byType(TobyPredictsLine);
  final engineStrip = find.byKey(e2eKey(E2eIds.boardPvList)).first;
  final notation = find.byKey(e2eKey(E2eIds.boardNotationRoot)).first;
  final notationScroll = find
      .descendant(of: notation, matching: find.byType(SingleChildScrollView))
      .first;

  testWidgets('Toby fits between the board and notation when there is room', (
    tester,
  ) async {
    final board = await pumpBoard(tester, const Size(393, 852));
    expect(panel, findsOneWidget);
    expect(
      tester.getTopLeft(panel).dy,
      greaterThan(tester.getBottomLeft(find.byType(Chessboard).first).dy),
    );
    expect(
      tester.getBottomLeft(panel).dy,
      lessThanOrEqualTo(tester.getTopLeft(notationScroll).dy),
    );
    expect(find.byTooltip('Engine settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await board.dispose();
  });

  Future<SurfacesBoard> pumpEngineBoard(
    WidgetTester tester,
    Size size, {
    bool? premium = true,
    bool tobyEnabled = true,
    EngineSource source = EngineSource.toby,
    List<Override> extraOverrides = const [],
  }) => pumpSurfacesBoard(
    tester,
    size: size,
    safeArea: const EdgeInsets.only(top: 30, bottom: 18),
    wrap: (app) => RepaintBoundary(key: _captureKey, child: app),
    engineSettings: EngineSettings(
      engineSource: source,
      tobyEnabled: tobyEnabled,
      showEngineGaugeOnBoard: true,
    ),
    extraOverrides: [
      if (premium != null)
        tobyReaderHasPremiumProvider.overrideWithValue(premium),
      tobyReadingProvider.overrideWith(() => _FixtureReading(reading)),
      ...extraOverrides,
    ],
  );

  testWidgets('saved Toby preference cannot show predictions without Premium', (
    tester,
  ) async {
    final board = await pumpEngineBoard(
      tester,
      const Size(393, 852),
      premium: false,
    );
    try {
      expect(find.byKey(const ValueKey('board-engine-toby')), findsOneWidget);
      expect(panel, findsNothing);
      expect(
        find.byKey(const ValueKey('toby-position-outcomes')),
        findsNothing,
      );
      final state = board.container
          .read(
            chessBoardScreenProviderNew(
              ChessBoardProviderParams(game: board.games.first, index: 0),
            ),
          )
          .value!;
      expect(state.tobyPosition, isNull);
      expect(
        state.principalVariations.every((line) => line.evalLabel == null),
        isTrue,
      );
    } finally {
      await board.dispose();
    }
  });

  testWidgets(
    'Toby keeps Stockfish until a reward is confirmed and falls back at expiry',
    (tester) async {
      final reward = _BoardReward();
      final board = await pumpEngineBoard(
        tester,
        const Size(393, 852),
        source: EngineSource.stockfish,
        premium: null,
        extraOverrides: [
          rewardedAdsAvailableProvider.overrideWithValue(true),
          subscriptionProvider.overrideWith((ref) => _BoardSubscription(false)),
          rewardedAccessProvider.overrideWith((ref) => reward),
        ],
      );
      final toby = find.byKey(const ValueKey('board-engine-toby'));
      final stockfish = find.byKey(const ValueKey('board-engine-stockfish'));
      final tabPanel = find.descendant(of: engineStrip, matching: panel);
      EngineSource? chosen() => board.container
          .read(engineSettingsProviderNew)
          .valueOrNull
          ?.engineSource;
      final boardProvider = chessBoardScreenProviderNew(
        ChessBoardProviderParams(game: board.games.first, index: 0),
      );
      final initial = board.container
          .read(boardProvider)
          .value!
          .analysisState
          .position
          .fen;
      Future<void> openChoice() async {
        await tester.tap(toby);
        await tester.pumpAndSettle();
        expect(find.text('Watch ad'), findsOneWidget);
        expect(find.text('Upgrade'), findsOneWidget);
        expect(chosen(), EngineSource.stockfish);
        expect(tabPanel, findsNothing);
      }

      try {
        expect(stockfish, findsOneWidget);
        await openChoice();
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(chosen(), EngineSource.stockfish);
        expect(reward.attempts, 0);
        await openChoice();
        await tester.tap(find.text('Watch ad'));
        await tester.pumpAndSettle();
        expect(reward.attempts, 1);
        expect(chosen(), EngineSource.stockfish);
        expect(tabPanel, findsNothing);
        // The chooser is still open after an unconfirmed ad.
        expect(find.text('Watch ad'), findsOneWidget);
        reward.confirm = true;
        await tester.tap(find.text('Watch ad'));
        for (var i = 0; i < 9; i++) {
          await tester.pump(const Duration(milliseconds: 170));
        }
        expect(reward.attempts, 2);
        expect(chosen(), EngineSource.toby);
        expect(tabPanel, findsOneWidget);
        expect(find.text('45%'), findsOneWidget);
        reward.expire();
        await tester.pump();
        expect(tabPanel, findsNothing);
        expect(
          find.byKey(const ValueKey('toby-position-outcomes')),
          findsNothing,
        );
        expect(board.container.read(boardProvider).value!.tobyPosition, isNull);
        expect(
          board.container.read(boardProvider).value!.analysisState.position.fen,
          initial,
        );
        expect(
          chosen(),
          EngineSource.toby,
          reason: 'expiry does not overwrite the preference',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await board.dispose();
      }
    },
  );

  testWidgets('subscribers can select Toby after an older opt-out', (
    tester,
  ) async {
    final board = await pumpEngineBoard(
      tester,
      const Size(393, 852),
      source: EngineSource.toby,
      tobyEnabled: false,
      premium: null,
      extraOverrides: [
        rewardedAdsAvailableProvider.overrideWithValue(true),
        subscriptionProvider.overrideWith((ref) => _BoardSubscription(true)),
      ],
    );
    try {
      expect(panel, findsNothing);
      expect(
        board.container.read(engineSettingsProviderNew).requireValue.tobyEnabled,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('board-engine-toby')));
      await tester.pump();
      expect(find.text('Watch ad'), findsNothing);
      expect(find.descendant(of: engineStrip, matching: panel), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await board.dispose();
    }
  });

  testWidgets('Toby grades outcomes, not rank, using notation badges', (
    tester,
  ) async {
    final graded = TobyReading(
      isFinal: true,
      sideToMove: reading.sideToMove,
      positionWdl: const TobyWdl(white: .50, draw: .20, black: .30),
      candidates: const [
        TobyCandidate(
          uci: 'e2e4',
          san: 'e4',
          probability: .45,
          wdl: TobyWdl(white: .10, draw: .20, black: .70),
        ),
        TobyCandidate(uci: 'd2d4', san: 'd4', probability: .38),
        TobyCandidate(
          uci: 'g1f3',
          san: 'Nf3',
          probability: .01,
          wdl: TobyWdl(white: .50, draw: .20, black: .30),
        ),
      ],
      otherProbability: .16,
      otherMoveCount: 1,
    );
    final board = await pumpEngineBoard(
      tester,
      const Size(393, 852),
      extraOverrides: [
        tobyReadingProvider.overrideWith(() => _FixtureReading(graded)),
      ],
    );
    try {
      final blunder = find.byKey(const ValueKey('toby-quality-e2e4'));
      final best = find.byKey(const ValueKey('toby-quality-g1f3'));
      expect(blunder, findsOneWidget);
      expect(best, findsOneWidget);
      expect(
        (tester.widget<SvgPicture>(blunder).bytesLoader as SvgAssetLoader)
            .assetName,
        'assets/svgs/blunder.svg',
      );
      expect(
        (tester.widget<SvgPicture>(best).bytesLoader as SvgAssetLoader)
            .assetName,
        'assets/svgs/best.svg',
      );
      expect(find.byKey(const ValueKey('toby-quality-d2d4')), findsNothing);
      expect(
        tester.getTopLeft(blunder).dy,
        lessThan(tester.getTopLeft(best).dy),
      );
      expect(tester.takeException(), isNull);
      await _captureBoard(tester, _badgeCapturePath);
    } finally {
      await board.dispose();
    }
  });

  testWidgets('Toby replaces the engine strip, not the notation panel', (
    tester,
  ) async {
    final board = await pumpEngineBoard(tester, const Size(393, 852));
    try {
      final state = board.container
          .read(
            chessBoardScreenProviderNew(
              ChessBoardProviderParams(game: board.games.first, index: 0),
            ),
          )
          .value!;
      // The real fixture publishes the percentage-labeled PVs shown in the
      // report; these, not the notation footer, must own the new rendering.
      expect(
        state.principalVariations.map((line) => line.evalLabel),
        containsAll(['45%', '38%', '<1%']),
      );
      expect(panel, findsOneWidget);
      expect(find.text('Chance'), findsOneWidget);
      final legend = find.byKey(const ValueKey('toby-outcome-legend'));
      expect(
        find.descendant(of: legend, matching: find.text('Draw')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: legend, matching: find.byType(Image)),
        findsNWidgets(2),
      );
      final chance = tester.getTopLeft(find.text('Chance'));
      final firstChance = tester.getTopLeft(find.text('45%'));
      expect(firstChance.dx, closeTo(chance.dx, 0.01));
      expect(
        chance.dx,
        greaterThan(
          tester
                  .getTopRight(find.byKey(const ValueKey('board-engine-toby')))
                  .dx +
              5,
        ),
      );
      expect(find.text('W / = / B'), findsNothing);
      expect(
        find.descendant(
          of: engineStrip,
          matching: find.byTooltip('Engine settings'),
        ),
        findsNothing,
      );
      expect(find.text('Played'), findsNothing);
      final tokens = tester.widget<TobyPredictsLine>(panel).tokens;
      expect(tokens, hasLength(3));
      for (final token in tokens) {
        final move = tester.widget<Text>(find.text(token.move));
        final chance = tester.widget<Text>(find.text(token.chance));
        expect(move.style?.color, chance.style?.color, reason: token.move);
      }
      for (final chance in ['45%', '38%', '<1%']) {
        final row = tester
            .element(find.text(chance))
            .findAncestorWidgetOfExactType<ColoredBox>();
        expect(row?.color, Colors.transparent, reason: '$chance Toby row');
      }
      final positionBar = find.byKey(const ValueKey('toby-position-outcomes'));
      expect(positionBar, findsOneWidget);
      expect(
        tester.widget<TobyOutcomeBar>(positionBar).outcome,
        reading.positionWdl,
      );
      final semantics = tester.ensureSemantics();
      try {
        expect(
          find.bySemanticsLabel(RegExp(r'^Toby position: White wins')),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
      expect(find.descendant(of: engineStrip, matching: panel), findsOneWidget);
      expect(find.descendant(of: notation, matching: panel), findsNothing);
      expect(
        tester.getTopLeft(panel).dy,
        greaterThan(tester.getBottomLeft(find.byType(Chessboard).first).dy),
      );
      expect(
        tester.getBottomLeft(panel).dy,
        lessThanOrEqualTo(tester.getTopLeft(notation).dy),
      );
      expect(
        find.byTooltip(
          'White wins 31% · Draw 46% · Black wins 23%\nWhite expected score 54%',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _captureBoard(tester, _capturePath);
    } finally {
      await board.dispose();
    }
  });

  testWidgets('one tap swaps the engine and gauge without moving the board', (
    tester,
  ) async {
    final board = await pumpEngineBoard(tester, const Size(393, 852));
    final params = ChessBoardProviderParams(game: board.games.first, index: 0);
    final provider = chessBoardScreenProviderNew(params);
    final positionBar = find.byKey(const ValueKey('toby-position-outcomes'));
    final stockfishBar = find.byKey(e2eKey(E2eIds.boardEvalBar));
    final stockfish = find.byKey(const ValueKey('board-engine-stockfish'));
    final toby = find.byKey(const ValueKey('board-engine-toby'));
    try {
      final initial = board.container
          .read(provider)
          .value!
          .analysisState
          .position
          .fen;
      expect(positionBar, findsOneWidget);
      expect(stockfishBar, findsNothing);
      final notationTop = tester.getTopLeft(notation).dy;
      final switchBounds = tester.getRect(stockfish);
      await tester.tap(stockfish);
      await tester.pump();
      expect(tester.getTopLeft(notation).dy, closeTo(notationTop, 0.01));
      expect(tester.getRect(stockfish), switchBounds);
      expect(
        find.descendant(
          of: engineStrip,
          matching: find.byTooltip('Engine settings'),
        ),
        findsNothing,
      );
      expect(tester.widget<InkWell>(stockfish).onLongPress, isNotNull);
      expect(positionBar, findsNothing);
      expect(stockfishBar, findsOneWidget);
      expect(find.descendant(of: engineStrip, matching: panel), findsNothing);
      expect(board.container.read(provider).value!.tobyPosition, isNull);
      expect(
        board.container.read(provider).value!.analysisState.position.fen,
        initial,
      );
      await tester.tap(toby);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(positionBar, findsOneWidget);
      expect(stockfishBar, findsNothing);
      expect(find.descendant(of: engineStrip, matching: panel), findsOneWidget);
      expect(
        board.container.read(provider).value!.analysisState.position.fen,
        initial,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await board.dispose();
    }
  });

  testWidgets('Toby column labels explain themselves on tap', (tester) async {
    final board = await pumpEngineBoard(tester, const Size(360, 655));
    try {
      final stripPanel = find.descendant(of: engineStrip, matching: panel);
      final bars = find.descendant(
        of: stripPanel,
        matching: find.byType(TobyOutcomeBar),
      );
      final legend = find.byKey(const ValueKey('toby-outcome-legend'));
      final white = find
          .descendant(of: legend, matching: find.byType(Image))
          .first;
      final black = find
          .descendant(of: legend, matching: find.byType(Image))
          .last;
      final groupCenter =
          (tester.getCenter(white).dx + tester.getCenter(black).dx) / 2;
      expect(groupCenter, closeTo(tester.getCenter(bars.first).dx, 4));
      final help = <(Finder, String)>[
        (find.text('Chance'), 'How likely the player is to make this move.'),
        (white, 'How likely White is to win after this move.'),
        (
          find.text('Draw'),
          'How likely the game is to end in a draw after this move.',
        ),
        (black, 'How likely Black is to win after this move.'),
      ];
      for (final (target, message) in help) {
        expect(find.text(message), findsNothing);
        await tester.tap(target);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        expect(find.text(message), findsOneWidget);
      }
      Tooltip.dismissAllToolTips();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await board.dispose();
    }
  });

  testWidgets('the engine strip fills short phones without a duplicate Toby', (
    tester,
  ) async {
    final board = await pumpEngineBoard(tester, const Size(360, 655));
    try {
      expect(panel, findsOneWidget);
      expect(find.descendant(of: engineStrip, matching: panel), findsOneWidget);
      expect(tester.getSize(notation).height, greaterThan(48));
      expect(tester.takeException(), isNull);
    } finally {
      await board.dispose();
    }
  });

  testWidgets('Toby scrolls with notation on a short viewport', (tester) async {
    final board = await pumpBoard(tester, const Size(393, 655));
    expect(panel, findsOneWidget);
    expect(find.ancestor(of: panel, matching: notationScroll), findsOneWidget);
    await tester.ensureVisible(panel);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await board.dispose();
  });

  testWidgets('Toby has no panel or reserved space without access', (
    tester,
  ) async {
    final board = await pumpBoard(tester, const Size(393, 852), premium: false);
    expect(panel, findsNothing);
    expect(
      tester.getTopLeft(notationScroll).dy,
      closeTo(tester.getTopLeft(notation).dy, 1),
    );
    await board.dispose();
  });
}

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

  final engineIcon = find.byKey(e2eKey(E2eIds.boardEngineToggle)).first;
  Future<void> openEngineSettings(WidgetTester tester) async {
    await tester.longPress(engineIcon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
  }

  Future<void> closeEngineSettings(WidgetTester tester) async {
    Navigator.of(tester.element(find.text('Engine Experience'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
  }

  final panel = find.byType(TobyPredictsLine);
  final engineStrip = find.byKey(e2eKey(E2eIds.boardPvList)).first;
  final notation = find.byKey(e2eKey(E2eIds.boardNotationRoot)).first;

  Future<SurfacesBoard> pumpEngineBoard(
    WidgetTester tester,
    Size size, {
    bool? premium = true,
    bool tobyEnabled = true,
    bool both = false,
    int lineIndex = 2,
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
      showBothEngines: both,
      principalVariationIndex: lineIndex,
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
      expect(find.byKey(const ValueKey('engine-source-toby')), findsNothing);
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
      final toby = find.byKey(const ValueKey('engine-source-toby'));
      final stockfish = find.byKey(const ValueKey('engine-source-stockfish'));
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
        await openEngineSettings(tester);
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
        await closeEngineSettings(tester);
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
        board.container
            .read(engineSettingsProviderNew)
            .requireValue
            .tobyEnabled,
        isFalse,
      );
      await openEngineSettings(tester);
      await tester.tap(find.byKey(const ValueKey('engine-source-toby')));
      await closeEngineSettings(tester);
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

  testWidgets('board engine icon opens a focused Engine Experience', (
    tester,
  ) async {
    final board = await pumpEngineBoard(tester, const Size(393, 852));
    try {
      await openEngineSettings(tester);
      expect(find.text('Engine Experience'), findsOneWidget);
      expect(find.text('Evaluation Bar'), findsOneWidget);
      expect(find.text('Grid View'), findsNothing);
      expect(find.text('Computer Analysis'), findsNothing);
      expect(find.byKey(const ValueKey('engine-source-toby')), findsOneWidget);
      expect(find.byKey(const ValueKey('board-engine-toby')), findsNothing);
      expect(find.byTooltip('About Toby'), findsNothing);
      expect(find.text('Thinking Time'), findsNothing);
      expect(find.text('Analysis Depth Indicator'), findsNothing);
      expect(find.text('Cards'), findsNothing);
      expect(find.text('List'), findsNothing);
      expect(find.text('Show Engine Lines'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Engine')).dy,
        lessThan(tester.getTopLeft(find.text('Show Engine Lines')).dy),
      );
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
      expect(find.text('W / = / B'), findsNothing);
      expect(find.text('Chance'), findsNothing);
      expect(find.text('Stockfish'), findsNothing);
      expect(find.text('Toby'), findsNothing);
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

  testWidgets(
    'Engine Experience swaps engine and gauge without moving the board',
    (tester) async {
      final board = await pumpEngineBoard(tester, const Size(393, 852));
      final params = ChessBoardProviderParams(
        game: board.games.first,
        index: 0,
      );
      final provider = chessBoardScreenProviderNew(params);
      final positionBar = find.byKey(const ValueKey('toby-position-outcomes'));
      final stockfishBar = find.byKey(e2eKey(E2eIds.boardEvalBar));
      final stockfish = find.byKey(const ValueKey('engine-source-stockfish'));
      final toby = find.byKey(const ValueKey('engine-source-toby'));
      try {
        final initial = board.container
            .read(provider)
            .value!
            .analysisState
            .position
            .fen;
        expect(positionBar, findsOneWidget);
        expect(stockfishBar, findsNothing);
        await openEngineSettings(tester);
        await tester.tap(stockfish);
        await closeEngineSettings(tester);
        expect(positionBar, findsNothing);
        expect(stockfishBar, findsOneWidget);
        expect(find.descendant(of: engineStrip, matching: panel), findsNothing);
        expect(board.container.read(provider).value!.tobyPosition, isNull);
        expect(
          board.container.read(provider).value!.analysisState.position.fen,
          initial,
        );
        await openEngineSettings(tester);
        await tester.tap(toby);
        await closeEngineSettings(tester);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(positionBar, findsOneWidget);
        expect(stockfishBar, findsNothing);
        expect(
          find.descendant(of: engineStrip, matching: panel),
          findsOneWidget,
        );
        expect(
          board.container.read(provider).value!.analysisState.position.fen,
          initial,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await board.dispose();
      }
    },
  );

  testWidgets('Toby percentages and bars give tap help without a header', (
    tester,
  ) async {
    final board = await pumpEngineBoard(tester, const Size(360, 655));
    try {
      final stripPanel = find.descendant(of: engineStrip, matching: panel);
      final bar = find
          .descendant(of: stripPanel, matching: find.byType(TobyOutcomeBar))
          .first;
      await tester.tap(find.text('45%'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        find.textContaining('How likely the player is to make this move'),
        findsOneWidget,
      );
      await tester.tap(bar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(find.textContaining('White expected score'), findsOneWidget);
      Tooltip.dismissAllToolTips();
      await tester.pump(const Duration(milliseconds: 180));
      expect(tester.takeException(), isNull);
    } finally {
      await board.dispose();
    }
  });

  testWidgets('Both puts Stockfish above Toby and keeps one board gauge', (
    tester,
  ) async {
    final board = await pumpEngineBoard(
      tester,
      const Size(393, 1100),
      both: true,
    );
    try {
      final stack = find.byKey(const ValueKey('board-engine-stack'));
      expect(stack, findsOneWidget);
      expect(
        find.descendant(of: stack, matching: find.text('Stockfish')),
        findsNothing,
      );
      expect(
        find.descendant(of: stack, matching: find.text('Toby')),
        findsNothing,
      );
      final stockfish = find.byKey(
        const ValueKey('board-stacked-stockfish-lines'),
      );
      final toby = find.byKey(const ValueKey('board-stacked-toby-lines'));
      expect(
        tester.getBottomLeft(stockfish).dy,
        lessThanOrEqualTo(tester.getTopLeft(toby).dy),
      );
      expect(
        find.byKey(const ValueKey('board-stacked-toby-lines')),
        findsOneWidget,
      );
      expect(find.text('45%'), findsOneWidget);
      expect(find.byKey(e2eKey(E2eIds.boardEvalBar)), findsOneWidget);
      expect(
        find.byKey(const ValueKey('toby-position-outcomes')),
        findsNothing,
      );
      expect(
        tester.getTopLeft(notation).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(stack).dy),
      );
      await tester.tap(engineIcon);
      await tester.pump(const Duration(milliseconds: 300));
      expect(stack, findsNothing);
      expect(find.byKey(e2eKey(E2eIds.boardEvalBar)), findsOneWidget);
      await tester.tap(engineIcon);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(stack, findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await board.dispose();
    }
  });

  testWidgets(
    'Both offers a right-side Toby gauge independently of engine lines',
    (tester) async {
      final board = await pumpEngineBoard(
        tester,
        const Size(411, 914),
        both: true,
      );
      final left = find.byKey(e2eKey(E2eIds.boardEvalBar));
      final right = find.byKey(const ValueKey('board-toby-secondary-gauge'));
      final toggle = find.byKey(
        const ValueKey('evaluation-bar-toby-both-switch'),
      );
      try {
        expect(right, findsNothing);
        await openEngineSettings(tester);
        expect(toggle, findsOneWidget);
        expect(tester.widget<Switch>(toggle).value, isFalse);
        await tester.tap(toggle);
        await closeEngineSettings(tester);
        final chessboard = tester.getRect(find.byType(Chessboard).first);
        expect(tester.getRect(left).right, lessThanOrEqualTo(chessboard.left));
        expect(
          tester.getRect(right).left,
          greaterThanOrEqualTo(chessboard.right),
        );
        final bar = find.descendant(
          of: right,
          matching: find.byType(TobyOutcomeBar),
        );
        expect(
          tester.widget<TobyOutcomeBar>(bar).outcome,
          same(reading.positionWdl),
        );
        await tester.tap(engineIcon);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('board-engine-stack')), findsNothing);
        expect(left, findsOneWidget);
        expect(tester.widget<TobyOutcomeBar>(bar).outcome, isNotNull);
        await openEngineSettings(tester);
        await tester.tap(
          find.byKey(const ValueKey('evaluation-bar-board-switch')),
        );
        await closeEngineSettings(tester);
        expect(left, findsNothing);
        expect(right, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await board.dispose();
      }
    },
  );

  testWidgets('Both stays enabled and scrolls five lines on a short phone', (
    tester,
  ) async {
    final board = await pumpEngineBoard(
      tester,
      const Size(411, 914),
      lineIndex: 4,
    );
    try {
      final boardBefore = tester.getRect(find.byType(Chessboard).first);
      await openEngineSettings(tester);
      await tester.tap(find.byKey(const ValueKey('engine-source-both')));
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      await closeEngineSettings(tester);
      final stack = find.byKey(const ValueKey('board-engine-stack'));
      expect(stack, findsOneWidget);
      expect(tester.getRect(find.byType(Chessboard).first), boardBefore);
      final scroll = find.byKey(const ValueKey('board-engine-scroll'));
      expect(scroll, findsOneWidget);
      final engineScrollable = find
          .descendant(of: scroll, matching: find.byType(Scrollable))
          .first;
      expect(
        tester
            .state<ScrollableState>(engineScrollable)
            .position
            .maxScrollExtent,
        greaterThan(0),
      );
      expect(
        tester
            .widget<TobyPredictsLine>(
              find.byKey(const ValueKey('board-stacked-toby-lines')),
            )
            .engineRowCount,
        5,
      );
      final stockfish = find.byKey(
        const ValueKey('board-stacked-stockfish-lines'),
      );
      final toby = find.byKey(const ValueKey('board-stacked-toby-lines'));
      expect(
        tester.getBottomLeft(stockfish).dy,
        lessThanOrEqualTo(tester.getTopLeft(toby).dy),
      );
      await tester.drag(scroll, const Offset(0, -320));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('45%').hitTestable(), findsOneWidget);
      expect(tester.getSize(notation).height, greaterThan(48));
      expect(tester.takeException(), isNull);
    } finally {
      await board.dispose();
    }
  });

  testWidgets('Both is Premium and returns to Stockfish on reward expiry', (
    tester,
  ) async {
    final reward = _BoardReward();
    final board = await pumpEngineBoard(
      tester,
      const Size(393, 1100),
      source: EngineSource.stockfish,
      premium: null,
      extraOverrides: [
        rewardedAdsAvailableProvider.overrideWithValue(true),
        subscriptionProvider.overrideWith((ref) => _BoardSubscription(false)),
        rewardedAccessProvider.overrideWith((ref) => reward),
      ],
    );
    try {
      final stack = find.byKey(const ValueKey('board-engine-stack'));
      await openEngineSettings(tester);
      await tester.tap(find.byKey(const ValueKey('engine-source-both')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Watch ad'), findsOneWidget);
      expect(
        board.container
            .read(engineSettingsProviderNew)
            .requireValue
            .showBothEngines,
        isFalse,
      );
      reward.confirm = true;
      await tester.tap(find.text('Watch ad'));
      for (var i = 0; i < 9; i++) {
        await tester.pump(const Duration(milliseconds: 170));
      }
      await closeEngineSettings(tester);
      expect(stack, findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      final rightBar = find.byKey(const ValueKey('board-toby-secondary-gauge'));
      await openEngineSettings(tester);
      await tester.tap(
        find.byKey(const ValueKey('evaluation-bar-toby-both-switch')),
      );
      await closeEngineSettings(tester);
      expect(rightBar, findsOneWidget);
      reward.expire();
      await tester.pump();
      expect(stack, findsNothing);
      expect(rightBar, findsNothing);
      expect(find.byKey(e2eKey(E2eIds.boardEvalBar)), findsOneWidget);
      expect(
        board.container
            .read(engineSettingsProviderNew)
            .requireValue
            .showBothEngines,
        isTrue,
      );
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

  testWidgets('Stockfish-only mode does not request a second Toby panel', (
    tester,
  ) async {
    final board = await pumpEngineBoard(
      tester,
      const Size(393, 852),
      source: EngineSource.stockfish,
    );
    try {
      expect(panel, findsNothing);
      expect(find.byKey(e2eKey(E2eIds.boardEvalBar)), findsOneWidget);
    } finally {
      await board.dispose();
    }
  });
}

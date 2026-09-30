import 'package:chessever2/screens/favorites/widgets/collection_inks.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/player_class_scoreboard.dart';
import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_graph_layout.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/knockout_bracket_canvas.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/knockout_match_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/match_header_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// WCAG 2.x contrast. A translucent foreground is composited over the
/// background first, which is how it renders.
double contrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background);
  final l1 = fg.computeLuminance();
  final l2 = background.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

const double kText = 4.5;
const double kUi = 3.0;

const AppColors light = AppColors.light;
const AppColors dark = AppColors.dark;

Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  required Brightness brightness,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        // Fresh app per pump: a theme switch would otherwise lerp.
        key: UniqueKey(),
        theme: brightness == Brightness.light
            ? AppTheme.lightTheme
            : AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(body: Center(child: child));
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

String drawnAsset(WidgetTester tester, Finder image) =>
    (tester.widget<Image>(image).image as AssetImage).assetName;

void main() {
  group('Time-control marks', () {
    const twins = {
      StreakTimeClass.standard: (
        PngAsset.classicalIcon,
        PngAsset.classicalIconLight,
      ),
      StreakTimeClass.rapid: (PngAsset.rapidIcon, PngAsset.rapidIconLight),
      StreakTimeClass.blitz: (PngAsset.blitzIcon, PngAsset.blitzIconLight),
    };

    for (final MapEntry(key: timeClass, value: (original, paper))
        in twins.entries) {
      testWidgets('${timeClass.name} draws the shipped art in dark', (
        tester,
      ) async {
        await pumpThemed(
          tester,
          StreakClassIcon(timeClass: timeClass, size: 16),
          brightness: Brightness.dark,
        );
        expect(drawnAsset(tester, find.byType(Image)), original);
        expect(find.byType(ColorFiltered), findsNothing);
      });

      testWidgets('${timeClass.name} swaps to its paper twin in light', (
        tester,
      ) async {
        await pumpThemed(
          tester,
          StreakClassIcon(timeClass: timeClass, size: 16),
          brightness: Brightness.light,
        );
        expect(drawnAsset(tester, find.byType(Image)), paper);
        // An asset swap, not a per-item filter layer.
        expect(find.byType(ColorFiltered), findsNothing);
      });
    }
  });

  test('calendar filter count sits on paper, clear of the AA line', () {
    // The selected filter button: a 0.15 cyan wash over the page.
    final button = Color.alphaBlend(
      kPrimaryColor.withValues(alpha: 0.15),
      light.background,
    );
    final oldBadge = Color.alphaBlend(
      kPrimaryColor.withValues(alpha: 0.25),
      button,
    );
    final newBadge = light.surface;
    // The cyan badge sat right on the AA line; the paper seat clears it well.
    expect(contrast(light.accentText, oldBadge), lessThan(4.6));
    expect(contrast(light.accentText, newBadge), greaterThanOrEqualTo(6.5));
    // The label beside it stays on the wash and still reads.
    expect(contrast(light.accentText, button), greaterThanOrEqualTo(kText));
  });

  group('Collection inks', () {
    Future<BuildContext> contextFor(
      WidgetTester tester,
      Brightness brightness,
    ) async {
      late BuildContext captured;
      await pumpThemed(
        tester,
        Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
        brightness: brightness,
      );
      return captured;
    }

    testWidgets('dark keeps the historic zinc and red literals', (
      tester,
    ) async {
      final context = await contextFor(tester, Brightness.dark);
      expect(context.collectionMutedInk, const Color(0xFFA1A1AA));
      expect(context.collectionSubtleInk, const Color(0xFF71717A));
      expect(context.collectionAlertInk, const Color(0xFFEF4444));
    });

    testWidgets('light inks all read as text on paper', (tester) async {
      final context = await contextFor(tester, Brightness.light);
      for (final surface in [light.background, light.surface]) {
        expect(
          contrast(context.collectionMutedInk, surface),
          greaterThanOrEqualTo(kText),
        );
        expect(
          contrast(context.collectionSubtleInk, surface),
          greaterThanOrEqualTo(kText),
        );
        expect(
          contrast(context.collectionAlertInk, surface),
          greaterThanOrEqualTo(kText),
        );
      }
      // The active-filter glyph sits on its own 15% tint.
      final tint = Color.alphaBlend(
        context.collectionAlertInk.withValues(alpha: 0.15),
        light.background,
      );
      expect(
        contrast(context.collectionAlertInk, tint),
        greaterThanOrEqualTo(kUi),
      );
      // The dark literals fail on paper, which is why these exist.
      expect(
        contrast(const Color(0xFFA1A1AA), light.background),
        lessThan(kUi),
      );
    });
  });

  group('Knockout bracket', () {
    const alpha = BracketParticipant(id: 'a', name: 'Alpha', rating: 2700);
    const beta = BracketParticipant(id: 'b', name: 'Beta', rating: 2680);
    const gamma = BracketParticipant(id: 'c', name: 'Gamma', rating: 2650);
    const delta = BracketParticipant(id: 'd', name: 'Delta', rating: 2640);

    KnockoutMatch match(
      String key,
      String stage,
      BracketParticipant p1,
      BracketParticipant p2, {
      bool live = false,
    }) => KnockoutMatch(
      key: key,
      stageKey: stage,
      participant1: p1,
      participant2: p2,
      games: const [],
      participant1Score: 1,
      participant2Score: 0,
      leader: p1,
      winner: live ? null : p1,
      minimumBoardOrder: 1,
      isComplete: !live,
      isLive: live,
    );

    KnockoutBracket bracket() => KnockoutBracket(
      stages: [
        KnockoutStage(
          key: 'semis',
          label: 'Semifinals',
          sourceTourIds: const ['t'],
          sourceRoundIds: const ['r1'],
          order: 0,
          state: KnockoutStageState.completed,
          isLive: false,
          matches: [
            match('s1', 'semis', alpha, beta),
            match('s2', 'semis', gamma, delta),
          ],
        ),
        KnockoutStage(
          key: 'final',
          label: 'Final',
          sourceTourIds: const ['t'],
          sourceRoundIds: const ['r2'],
          order: 1,
          state: KnockoutStageState.inProgress,
          isLive: true,
          matches: [match('f', 'final', alpha, gamma, live: true)],
        ),
      ],
      edges: const [
        KnockoutEdge(
          sourceMatchKey: 's1',
          destinationMatchKey: 'f',
          participantId: 'a',
        ),
        KnockoutEdge(
          sourceMatchKey: 's2',
          destinationMatchKey: 'f',
          participantId: 'c',
        ),
      ],
      selectedStageKey: 'final',
      currentStageKey: 'final',
      isPartial: false,
    );

    // Cards at the real card height (BracketGraphMetrics.matchHeight), in
    // columns narrow enough to fit a phone-width test view.
    const layout = BracketGraphLayout(
      size: Size(390, 300),
      stageHeaderRects: {
        'semis': Rect.fromLTWH(0, 0, 180, 24),
        'final': Rect.fromLTWH(206, 0, 180, 24),
      },
      matchRects: {
        's1': Rect.fromLTWH(0, 40, 180, 92),
        's2': Rect.fromLTWH(0, 180, 180, 92),
        'f': Rect.fromLTWH(206, 110, 180, 92),
      },
    );

    Future<dynamic> pumpCanvas(
      WidgetTester tester,
      Brightness brightness,
    ) async {
      await pumpThemed(
        tester,
        KnockoutBracketCanvas(
          bracket: bracket(),
          layout: layout,
          focusedMatchKey: 's1',
          onMatchTap: (_) {},
        ),
        brightness: brightness,
      );
      final paint = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byKey(const ValueKey('knockout-bracket-canvas')),
              matching: find.byType(CustomPaint),
            ),
          )
          .firstWhere(
            (p) =>
                p.painter.runtimeType.toString() == '_BracketConnectorPainter',
          );
      return paint.painter;
    }

    testWidgets('light connectors and focus path read on paper', (
      tester,
    ) async {
      final dynamic painter = await pumpCanvas(tester, Brightness.light);
      final Color line = painter.lineColor as Color;
      final double lineAlpha = painter.lineAlpha as double;
      final Color focus = painter.focusedColor as Color;

      final resting = line.withValues(alpha: lineAlpha);
      expect(contrast(resting, light.background), greaterThanOrEqualTo(kUi));
      expect(
        contrast(focus.withValues(alpha: 0.82), light.background),
        greaterThanOrEqualTo(kUi),
      );
    });

    testWidgets('dark connectors keep their historic paint', (tester) async {
      final dynamic painter = await pumpCanvas(tester, Brightness.dark);
      expect(painter.lineColor, dark.dividerStrong);
      expect(painter.lineAlpha, 0.62);
      expect(painter.focusedColor, kPrimaryColor);
    });

    Future<void> pumpLiveCard(WidgetTester tester, Brightness brightness) {
      return pumpThemed(
        tester,
        SizedBox(
          width: 180,
          height: 92,
          child: KnockoutMatchCard(
            match: match('f', 'final', alpha, gamma, live: true),
            onTap: () {},
          ),
        ),
        brightness: brightness,
      );
    }

    List<BoxDecoration> circles(WidgetTester tester) => tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(KnockoutMatchCard),
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle)
        .toList();

    testWidgets('live dot in light is an AA mark with no glow', (tester) async {
      await pumpLiveCard(tester, Brightness.light);
      final dots = circles(tester);
      expect(dots, hasLength(1));
      expect(dots.single.boxShadow, isNull);
      expect(
        contrast(dots.single.color!, light.popup),
        greaterThanOrEqualTo(kUi),
      );
    });

    testWidgets('live dot in dark keeps its cyan and glow', (tester) async {
      await pumpLiveCard(tester, Brightness.dark);
      final dots = circles(tester);
      expect(dots, hasLength(1));
      expect(dots.single.color, kPrimaryColor);
      expect(dots.single.boxShadow, isNotEmpty);
    });
  });

  group('Scoreboard piece disc', () {
    Widget card() => ScoreboardCardWidget(
      countryCode: 'NOR',
      name: 'Carlsen, Magnus',
      score: 2830,
      matchScore: '1',
      isWhite: true,
      index: 0,
      isFirst: true,
      isLast: true,
      onTap: () {},
    );

    BoxDecoration disc(WidgetTester tester) => tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere(
          (d) => d.shape == BoxShape.circle && d.color == Colors.white,
        );

    testWidgets('light edges the white disc so it reads on the card', (
      tester,
    ) async {
      await pumpThemed(tester, card(), brightness: Brightness.light);
      final border = disc(tester).border as Border?;
      expect(border, isNotNull);
      expect(
        contrast(border!.top.color, light.surface),
        greaterThanOrEqualTo(kUi),
      );
      // A bare white disc would vanish.
      expect(contrast(Colors.white, light.surface), lessThan(1.2));
    });

    testWidgets('dark keeps the bare white disc', (tester) async {
      await pumpThemed(tester, card(), brightness: Brightness.dark);
      expect(disc(tester).border, isNull);
    });
  });

  group('Knockout match header rail', () {
    Widget header({required bool complete}) => MatchHeader(
      match: MatchHeaderModel(
        matchKey: 'a-b',
        player1: 'Alpha',
        player2: 'Beta',
        player1Score: 1,
        player2Score: 0,
        games: const [],
        roundName: 'Final',
        isComplete: complete,
      ),
    );

    Color rail(WidgetTester tester) {
      final railFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_MatchStatusRail',
      );
      final box = tester.widget<Container>(
        find.descendant(of: railFinder, matching: find.byType(Container)),
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    testWidgets('a finished match keeps a visible rail on paper', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        header(complete: true),
        brightness: Brightness.light,
      );
      expect(contrast(rail(tester), light.surface), greaterThanOrEqualTo(kUi));
    });

    testWidgets('dark rail is the historic half cyan', (tester) async {
      await pumpThemed(
        tester,
        header(complete: true),
        brightness: Brightness.dark,
      );
      expect(rail(tester), kPrimaryColor.withValues(alpha: 0.5));
    });
  });
}

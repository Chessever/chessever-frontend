import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/widgets/player_profile_share_image_card.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/standings/widgets/player_event_share_image_card.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/streak_share_card.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_share_image_card.dart';
import 'package:chessever2/screens/tour_detail/team_tour/widgets/team_event_share_image_card.dart';
import 'package:chessever2/screens/tour_detail/widgets/standings_share_image_card.dart';
import 'package:chessever2/screens/tour_detail/widgets/team_standings_share_image_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/utils/share_card_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// --- Contrast ---------------------------------------------------------------

/// WCAG 2.x ratio of [ink] over [ground]; a translucent ink is composited
/// first, as it paints.
double _contrast(Color ink, Color ground) {
  final fg = Color.alphaBlend(ink, ground).computeLuminance();
  final bg = ground.computeLuminance();
  return (math.max(fg, bg) + 0.05) / (math.min(fg, bg) + 0.05);
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

/// Every opaque ground a piece of text can sit on inside a card: the fills of
/// its ancestors (colour or gradient stops), translucent layers composited
/// onto the first opaque one beneath them.
List<Color> _groundsBehind(Element element) {
  final layers = <List<Color>>[];
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    List<Color>? layer;
    if (widget is ColoredBox) {
      layer = [widget.color];
    } else if (widget is DecoratedBox &&
        widget.position == DecorationPosition.background &&
        widget.decoration is BoxDecoration) {
      final decoration = widget.decoration as BoxDecoration;
      layer =
          decoration.gradient?.colors ??
          [if (decoration.color != null) decoration.color!];
    } else if (widget is Material &&
        widget.type != MaterialType.transparency &&
        widget.color != null) {
      layer = [widget.color!];
    }
    if (layer == null || layer.isEmpty) return true;
    layers.add(layer);
    return layer.any((c) => c.a < 1);
  });
  if (layers.isEmpty) return const [];
  var grounds = layers.last;
  for (final layer in layers.reversed.skip(1)) {
    grounds = [
      for (final ground in grounds)
        for (final fill in layer) Color.alphaBlend(fill, ground),
    ];
  }
  return grounds;
}

Iterable<(String, Color)> _inks(InlineSpan span, TextStyle? inherited) sync* {
  if (span is! TextSpan) return;
  final style = inherited?.merge(span.style) ?? span.style;
  final text = span.text?.trim() ?? '';
  final color = style?.color;
  if (text.isNotEmpty && color != null) yield (text, color);
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _inks(child, style);
  }
}

/// Every text run on screen that reads under [min] against a ground it sits
/// on, as "text: ink on ground = ratio".
List<String> _contrastFailures(WidgetTester tester, {double min = 4.5}) {
  final failures = <String>[];
  var checked = 0;
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.widget as RichText;
    final grounds = _groundsBehind(element);
    for (final (text, ink) in _inks(paragraph.text, null)) {
      for (final ground in grounds) {
        checked++;
        final ratio = _contrast(ink, ground);
        if (ratio < min) {
          failures.add(
            '"$text": ${_hex(ink)} on ${_hex(ground)} = '
            '${ratio.toStringAsFixed(2)}',
          );
        }
      }
    }
  }
  expect(checked, greaterThan(0), reason: 'no text found to check');
  return failures;
}

// --- Fixtures ---------------------------------------------------------------

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

const _player = PlayerStandingModel(
  countryCode: 'CHN',
  title: 'GM',
  name: 'Ding, Liren',
  score: 3,
  scoreChange: 1,
  matchScore: null,
  fideId: 8603677,
);

const _rows = [
  PlayerEventShareGameRow(
    roundLabel: '1.',
    countryCode: 'NOR',
    title: 'GM',
    name: 'Carlsen, Magnus',
    rating: 2831,
    ratingChange: -3.2,
    result: '½',
    outcome: PlayerEventGameOutcome.draw,
    isWhite: true,
  ),
  PlayerEventShareGameRow(
    roundLabel: '2.',
    countryCode: 'USA',
    title: 'IM',
    name: 'Caruana, Fabiano',
    rating: 2795,
    ratingChange: 8.1,
    result: '1',
    outcome: PlayerEventGameOutcome.win,
    isWhite: false,
  ),
];

List<PlayerStandingModel> _standings() => [
  for (var i = 0; i < 6; i++)
    PlayerStandingModel(
      countryCode: ['NOR', 'USA', 'IND'][i % 3],
      title: i.isEven ? 'GM' : null,
      name: 'Player $i, Somebody',
      score: 6 - i ~/ 2,
      scoreChange: i % 3 - 1,
      matchScore: null,
      overallRank: i + 1,
    ),
];

TeamStandingModel _team(
  int i, {
  List<PlayerStandingModel> players = const [],
}) => TeamStandingModel(
  teamName: ['Norway', 'India', 'China'][i % 3],
  rank: i + 1,
  matchPoints: 14 - i,
  gamePoints: 25.5 - i,
  matchesWon: 6 - i,
  matchesDrawn: 2,
  matchesLost: i,
  boardsPlayed: 36,
  players: players,
);

PlayerStreaks _streaker() => PlayerStreaks.fromJson(
  {
    'fide_id': 8603677,
    'name': 'Ding, Liren',
    'title': 'GM',
    'fed': 'CHN',
    'rating': 2733,
  },
  [
    {
      'time_class': 'standard',
      'current_streak': 3,
      'best_streak': 5,
      'streak_start_game_day': '2026-09-01',
      'games': [
        {
          'game_id': 'l',
          'result': 'loss',
          'game_day': '2026-08-31',
          'round_name': 'Round 1',
          'tour_name': 'X',
          'opponent_name': 'A, B',
          'streak_after': 0,
        },
        for (var i = 1; i <= 3; i++)
          {
            'game_id': 'w$i',
            'result': 'win',
            'game_day': '2026-09-0${i + 1}',
            'round_name': 'Round ${i + 1}',
            'tour_name': 'X',
            'opponent_name': 'A, B',
            'streak_after': i,
          },
      ],
    },
  ],
)!;

const _analytics = PlayerAnalytics(
  openingStats: [
    OpeningStatistic(
      eco: 'C65',
      openingName: 'Ruy Lopez: Berlin Defense',
      count: 42,
      wins: 18,
      draws: 20,
      losses: 4,
    ),
    OpeningStatistic(
      eco: 'B90',
      openingName: 'Sicilian Defense: Najdorf Variation',
      count: 20,
      wins: 8,
      draws: 6,
      losses: 6,
    ),
  ],
  colorStats: ColorStatistics(
    whiteGames: 60,
    whiteWins: 25,
    whiteDraws: 28,
    whiteLosses: 7,
    blackGames: 58,
    blackWins: 15,
    blackDraws: 33,
    blackLosses: 10,
  ),
  resultStats: ResultStatistics(
    totalGames: 118,
    wins: 40,
    draws: 61,
    losses: 17,
  ),
  recentForm: [1, 0.5, 0, 1],
  avgOpponentRating: 2712,
);

/// Every card a share can produce, at the phone's narrowest width.
Map<String, Widget Function()> _cards() => {
  'player event': () => PlayerEventShareImageCard(
    width: 360,
    player: _player,
    photoFuture: null,
    initials: 'DL',
    eventName: 'Tata Steel Chess Tournament 2026 Masters',
    performanceRating: 2788,
    eventScore: 1.5,
    eventTotalGames: 2,
    ratingDiff: -4,
    standardRating: 2733,
    rapidRating: 2740,
    blitzRating: 2720,
    rows: _rows,
  ),
  'player profile': () => const PlayerProfileShareImageCard(
    width: 360,
    playerName: 'Ding, Liren',
    title: 'GM',
    countryCode: 'CHN',
    fideId: 8603677,
    photoFuture: null,
    initials: 'DL',
    standardRating: 2733,
    rapidRating: 2740,
    blitzRating: 2720,
    analytics: _analytics,
  ),
  'standings': () => StandingsShareImageCard(
    width: 360,
    eventName: 'Norway Chess 2026',
    standings: _standings(),
  ),
  'team standings': () => TeamStandingsShareImageCard(
    width: 360,
    eventName: 'Chess Olympiad 2026',
    standings: [for (var i = 0; i < 3; i++) _team(i)],
  ),
  'team event': () => TeamEventShareImageCard(
    width: 360,
    team: _team(1, players: _standings()),
    eventName: 'Chess Olympiad 2026',
    averageElo: 2701,
    matches: const [
      TeamEventShareMatchRow(
        opponentTeam: 'Norway',
        ourPointsLabel: '2.5',
        opponentPointsLabel: '1.5',
        result: TeamMatchResult.win,
        roundLabel: '1.',
      ),
      TeamEventShareMatchRow(
        opponentTeam: 'China',
        ourPointsLabel: '1',
        opponentPointsLabel: '3',
        result: TeamMatchResult.loss,
        roundLabel: '2.',
      ),
      TeamEventShareMatchRow(
        opponentTeam: 'Germany',
        ourPointsLabel: '2',
        opponentPointsLabel: '2',
        result: TeamMatchResult.draw,
        roundLabel: '3.',
      ),
      TeamEventShareMatchRow(
        opponentTeam: 'Spain',
        ourPointsLabel: '1',
        opponentPointsLabel: '0.5',
        result: TeamMatchResult.ongoing,
        roundLabel: '4.',
      ),
    ],
  ),
  'bracket': () => BracketShareImageCard(
    width: 360,
    eventName: 'FIDE World Cup 2026',
    snapshot: _onePixelPng,
    snapshotAspectRatio: 1,
  ),
  'streak': () => MediaQuery(
    data: const MediaQueryData(),
    child: StreakShareCard(
      player: _streaker(),
      timeClass: StreakTimeClass.standard,
    ),
  ),
};

/// Pumps [card] the way a capture renders it: inside the app theme, under the
/// palette the capture resolved for that theme.
Future<void> _pumpCard(
  WidgetTester tester,
  Widget card, {
  required bool light,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: ShareCardScope(
                palette: ShareCardPalette.forBrightness(
                  light ? Brightness.light : Brightness.dark,
                ),
                child: card,
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

// --- Tests ------------------------------------------------------------------

/// The cards are laid out for Inter; the test font's square glyphs are far
/// wider and would overflow rows that fit in the app.
Future<void> _loadInter() async {
  final loader = FontLoader('InterDisplay');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.otf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadInter);

  group('palette resolution', () {
    testWidgets('a card with no scope keeps the historical dark look', (
      tester,
    ) async {
      late ShareCardPalette seen;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = ShareCardPalette.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(seen, same(ShareCardPalette.dark));
    });

    testWidgets('a scope hands its palette down', (tester) async {
      late ShareCardPalette seen;
      await tester.pumpWidget(
        ShareCardScope(
          palette: ShareCardPalette.light,
          child: Builder(
            builder: (context) {
              seen = ShareCardPalette.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, same(ShareCardPalette.light));
      expect(
        ShareCardPalette.forBrightness(Brightness.light),
        same(ShareCardPalette.light),
      );
      expect(
        ShareCardPalette.forBrightness(Brightness.dark),
        same(ShareCardPalette.dark),
      );
    });

    Future<ShareCardPalette> captureFrom(
      WidgetTester tester, {
      required ThemeData appTheme,
      required ThemeData island,
      ShareCardPalette? palette,
    }) async {
      ShareCardPalette? seen;
      late BuildContext islandContext;
      await tester.pumpWidget(
        MaterialApp(
          // A fresh app: no animated lerp from the previous theme.
          key: UniqueKey(),
          theme: appTheme,
          home: Theme(
            // A forced local theme, like the always-dark feed.
            data: island,
            child: Builder(
              builder: (context) {
                islandContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final capture = captureCardPng(
        islandContext,
        width: 40,
        pixelRatio: 1,
        palette: palette,
        child: Builder(
          builder: (context) {
            seen = ShareCardPalette.of(context);
            return const SizedBox(width: 40, height: 50);
          },
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.runAsync(() => capture);
      await tester.pump();
      return seen!;
    }

    testWidgets('a capture follows the APP theme, not a local island', (
      tester,
    ) async {
      expect(
        await captureFrom(
          tester,
          appTheme: AppTheme.lightTheme,
          island: AppTheme.darkTheme,
        ),
        same(ShareCardPalette.light),
      );
      expect(
        await captureFrom(
          tester,
          appTheme: AppTheme.darkTheme,
          island: AppTheme.lightTheme,
        ),
        same(ShareCardPalette.dark),
      );
    });

    testWidgets('an explicit palette wins over the theme', (tester) async {
      expect(
        await captureFrom(
          tester,
          appTheme: AppTheme.lightTheme,
          island: AppTheme.lightTheme,
          palette: ShareCardPalette.dark,
        ),
        same(ShareCardPalette.dark),
      );
    });
  });

  group('palette values', () {
    test('dark keeps the brand colours with a flat, glowless header', () {
      const p = ShareCardPalette.dark;
      expect(p.isLight, isFalse);
      expect(p.bg, const Color(0xFF0A0B0D));
      expect(p.surface, const Color(0xFF15171C));
      expect(p.surfaceLow, const Color(0xFF101216));
      expect(p.hairline, const Color(0xFF23262E));
      expect(p.tileEdge, isNull);
      expect(p.accentFill, kPrimaryColor);
      expect(p.accentInk, kPrimaryColor);
      expect(p.gold, kLightYellowColor);
      expect(p.win, kGreenColor2);
      expect(p.loss, kRedColor);
      expect(p.textHi, Colors.white);
      expect(p.textMid, const Color(0xFFAEB4BF));
      expect(p.textLo, const Color(0xFF868C97));
      expect(p.pieceBlack, Colors.black);
      expect(p.pieceBlackEdge, Colors.white.withValues(alpha: 0.35));
      expect(p.wash, Colors.white.withValues(alpha: 0.04));
      expect(p.heroTint, 0);
      expect(p.glowOpacity, 0);
      expect(p.logoGlow, isFalse);
    });

    test('light is paper: flat header, no glow, no chip behind metadata', () {
      final p = ShareCardPalette.light;
      expect(p.isLight, isTrue);
      expect(p.bg, AppColors.light.surface);
      expect(p.textHi, AppColors.light.textPrimary);
      expect(p.accentInk, AppColors.light.accentText);
      expect(p.heroTint, 0);
      expect(p.glowOpacity, 0);
      expect(p.logoGlow, isFalse);
      expect(p.ecoTileAlpha, 0);
      expect(p.tileEdge, isNotNull);
      expect(p.pieceWhiteEdge, isNotNull);
    });

    for (final (name, p) in [
      ('dark', ShareCardPalette.dark),
      ('light', ShareCardPalette.light),
    ]) {
      test('$name: every ink clears AA on every ground', () {
        final grounds = {
          'bg': p.bg,
          'surface': p.surface,
          'surfaceLow': p.surfaceLow,
          'band': p.band,
        };
        final inks = {
          'textHi': p.textHi,
          'textMid': p.textMid,
          'textLo': p.textLo,
          'gold': p.gold,
          'win': p.win,
          'loss': p.loss,
          'draw': p.draw,
          'pending': p.pending,
          'accentInk': p.accentInk,
        };
        for (final ground in grounds.entries) {
          for (final ink in inks.entries) {
            expect(
              _contrast(ink.value, ground.value),
              greaterThanOrEqualTo(4.5),
              reason: '$name ${ink.key} on ${ground.key}',
            );
          }
        }
      });
    }

    test('light: piece discs and signal marks clear 3:1 as UI', () {
      final p = ShareCardPalette.light;
      for (final ground in [p.bg, p.surface, p.surfaceLow]) {
        // The white disc is held by its edge, the ink disc by itself.
        expect(_contrast(p.pieceWhiteEdge!, ground), greaterThanOrEqualTo(3));
        expect(_contrast(p.pieceBlack, ground), greaterThanOrEqualTo(3));
        for (final mark in [p.win, p.draw, p.loss]) {
          expect(_contrast(mark, ground), greaterThanOrEqualTo(3));
        }
      }
      // The score inside each disc.
      expect(_contrast(p.pieceBlack, p.pieceWhite), greaterThanOrEqualTo(4.5));
      expect(_contrast(p.pieceWhite, p.pieceBlack), greaterThanOrEqualTo(4.5));
    });
  });

  group('time-control icons', () {
    testWidgets(
      'light inks the white owl and rabbit; blitz and dark untouched',
      (tester) async {
        Future<bool> filtered(String asset, ShareCardPalette p) async {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: shareTimeControlIcon(asset, p),
            ),
          );
          return find.byType(ColorFiltered).evaluate().isNotEmpty;
        }

        final light = ShareCardPalette.light;
        const dark = ShareCardPalette.dark;
        expect(await filtered(PngAsset.classicalIcon, light), isTrue);
        expect(await filtered(PngAsset.rapidIcon, light), isTrue);
        expect(await filtered(PngAsset.blitzIcon, light), isFalse);
        expect(await filtered(PngAsset.classicalIcon, dark), isFalse);
        expect(await filtered(PngAsset.rapidIcon, dark), isFalse);
      },
    );
  });

  group('cards', () {
    testWidgets('the contrast walk catches faint ink on its real ground', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: Color(0xFFF4FAF9),
            child: DecoratedBox(
              // A translucent wash is composited onto the paper beneath it.
              decoration: BoxDecoration(color: Color(0x14000000)),
              child: Text('faint', style: TextStyle(color: Color(0xFF9AA0A6))),
            ),
          ),
        ),
      );
      final failures = _contrastFailures(tester);
      expect(failures, hasLength(1));
      expect(failures.single, contains('#9aa0a6 on #e1e6e5'));
    });

    for (final entry in _cards().entries) {
      testWidgets('${entry.key}: every text run clears AA on paper', (
        tester,
      ) async {
        await _pumpCard(tester, entry.value(), light: true);
        expect(tester.takeException(), isNull);
        final failures = _contrastFailures(tester);
        expect(failures, isEmpty, reason: failures.join('\n'));
      });

      testWidgets('${entry.key}: page follows the palette', (tester) async {
        for (final light in [false, true]) {
          await _pumpCard(tester, entry.value(), light: light);
          final page = light
              ? ShareCardPalette.light.bg
              : (entry.key == 'streak'
                    // The streak card keeps its own warmer black.
                    ? const Color(0xFF0C0C0E)
                    : ShareCardPalette.dark.bg);
          final painted = <Color>[
            for (final m in tester.widgetList<Material>(find.byType(Material)))
              if (m.color != null) m.color!,
            for (final b in tester.widgetList<ColoredBox>(
              find.byType(ColoredBox),
            ))
              b.color,
          ];
          expect(painted, contains(page), reason: 'light=$light');
          if (light) {
            expect(painted, isNot(contains(ShareCardPalette.dark.bg)));
          }
        }
      });
    }
  });

  testWidgets('a card padded to the floor pins its footer to the bottom', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Taller than every fixture, so each card has slack to hand out.
    const floor = 1200.0;
    for (final entry in _cards().entries) {
      // The streak card is fixed-size art with no footer row.
      if (entry.key == 'streak') continue;
      final frame = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              // Unbounded height with a floor, as captureCardPng lays out.
              return SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    key: frame,
                    constraints: const BoxConstraints(
                      minWidth: 360,
                      maxWidth: 360,
                      minHeight: floor,
                    ),
                    child: ShareCardScope(
                      palette: ShareCardPalette.dark,
                      child: entry.value(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: entry.key);

      final card = tester.getRect(find.byKey(frame));
      expect(card.height, floor, reason: entry.key);
      final lowestText = tester
          .elementList(find.byType(RichText))
          .map((e) => tester.getRect(find.byElementPredicate((c) => c == e)))
          .map((r) => r.bottom)
          .reduce(math.max);
      expect(card.bottom - lowestText, lessThan(40), reason: entry.key);
    }
  });

  group('preview sheet actions', () {
    for (final light in [true, false]) {
      testWidgets('clear contrast in ${light ? 'light' : 'dark'}', (
        tester,
      ) async {
        late AppColors colors;
        await tester.pumpWidget(
          MaterialApp(
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                colors = context.colors;
                return Scaffold(
                  backgroundColor: colors.surface,
                  body: SharePreviewSheet(
                    imageBytes: _onePixelPng,
                    onShareImage: () async {},
                    onShareLink: () async {},
                  ),
                );
              },
            ),
          ),
        );
        await tester.pump();

        final link = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
        final linkStyle = link.style!;
        final edge = linkStyle.side!.resolve(<WidgetState>{})!;
        if (light) {
          // Paper: a recessed fill, not an outline beside the filled primary.
          expect(edge.style, BorderStyle.none);
          final linkFill = linkStyle.backgroundColor!.resolve(
            <WidgetState>{},
          )!;
          final linkLabel = linkStyle.foregroundColor!.resolve(
            <WidgetState>{},
          )!;
          expect(_contrast(linkLabel, linkFill), greaterThanOrEqualTo(4.5));
        } else {
          expect(_contrast(edge.color, colors.surface), greaterThanOrEqualTo(3));
        }

        final image = tester.widget<FilledButton>(find.byType(FilledButton));
        final fill = image.style!.backgroundColor!.resolve(<WidgetState>{})!;
        final label = image.style!.foregroundColor!.resolve(<WidgetState>{})!;
        expect(_contrast(label, fill), greaterThanOrEqualTo(4.5));
      });
    }
  });
}

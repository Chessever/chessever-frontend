import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_tiers.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/smart_event_board_window.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_deck.dart';
import 'package:dartchess/dartchess.dart' show Role, Square;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

const _accent = Color(0xFFA3E635);

Future<void> _pump(
  WidgetTester tester, {
  required bool quiet,
  ThemeData? theme,
  int minElo = 2500,
  Set<String> formats = const {'standard', 'rapid'},
  bool live = false,
  String? summary = 'Game average 2500+, classical or rapid',
  SmartPlateLine? opening,
  bool stacked = false,
  bool fillPlate = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [boardSettingsProviderNew.overrideWith(_BoardSettings.new)],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            final card = SmartEventCard(
              tierLabel: 'GM',
              minElo: minElo,
              liveCount: 3,
              avgElo: 2728,
              accentColor: _accent,
              quiet: quiet,
              formatsAndStates: formats,
              summary: summary,
              live: live,
              opening: opening,
              stacked: stacked,
              fillPlate: fillPlate,
              onTap: () {},
            );
            return Scaffold(
              body: stacked
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(width: 174, child: card),
                    )
                  : card,
            );
          },
        ),
      ),
    ),
  );
}

/// The plate's board window, its window and its marked squares.
SmartEventBoardWindow _window(WidgetTester tester) =>
    tester.widget<SmartEventBoardWindow>(find.byType(SmartEventBoardWindow));

Iterable<Decoration> _decorations(WidgetTester tester) sync* {
  for (final e
      in find
          .descendant(
            of: find.byType(SmartEventCard),
            matching: find.byType(Container),
          )
          .evaluate()) {
    final decoration = (e.widget as Container).decoration;
    if (decoration != null) yield decoration;
  }
}

/// A 393pt phone, the layout's base: the half cards' real widths.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

bool _isAccent(Color c) => c.toARGB32() | 0xFF000000 == _accent.toARGB32();

void main() {
  for (final quiet in [true, false]) {
    testWidgets('fully there on its first frame (quiet: $quiet)', (
      tester,
    ) async {
      await _pump(tester, quiet: quiet);

      final faded = find.descendant(
        of: find.byType(SmartEventCard),
        matching: find.byWidgetPredicate(
          (w) =>
              (w is Opacity && w.opacity < 1) ||
              (w is FadeTransition && w.opacity.value < 1),
        ),
      );
      expect(faded, findsNothing);
      expect(find.text('GM Games'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    testWidgets('no hue anywhere: no accent fill, edge or bloom '
        '(${theme.brightness.name})', (tester) async {
      await _pump(tester, quiet: false, theme: theme);
      for (final d in _decorations(tester)) {
        if (d is! BoxDecoration) continue;
        if (d.color case final c?) expect(_isAccent(c), isFalse);
        final border = d.border;
        if (border is Border) expect(_isAccent(border.top.color), isFalse);
        for (final s in d.boxShadow ?? const <BoxShadow>[]) {
          expect(_isAccent(s.color), isFalse);
        }
      }
      expect(
        find.byType(CustomPaint).evaluate().where((e) {
          final w = e.widget as CustomPaint;
          return w.painter != null &&
              w.painter.runtimeType.toString().contains('Facet');
        }),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a level is its piece on its home square, its floor and time '
      'controls in the band under it', (tester) async {
    await _pump(tester, quiet: true);
    final window = _window(tester);
    // GM is the queen, alone on d1, its square marked; ranks 1-3 of one
    // board, centred on it.
    expect(window.fen, startsWith('8/8/8/8/8/8/8/3Q4'));
    expect(window.marks, {Square.d1});
    expect(window.window.label, 'b1-f3');
    final band = find.byType(SmartPlateBand);
    expect(
      find.descendant(of: band, matching: find.text('2500+')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: band, matching: find.byType(SmartPlateGlyph)),
      findsNWidgets(2),
    );
    expect(find.byType(SmartEventDeck), findsNothing);
    // The card's own lines are unchanged.
    expect(find.textContaining('3 events', findRichText: true), findsOneWidget);
    expect(find.textContaining('Ø 2728', findRichText: true), findsOneWidget);
    expect(find.text('Game average 2500+, classical or rapid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tier is its own piece: Super GM the king on e1, IM the '
      'rook in its corner', (tester) async {
    await _pump(tester, quiet: true, minElo: 2700, formats: const {});
    final king = _window(tester);
    expect(king.fen, startsWith('8/8/8/8/8/8/8/4K3'));
    expect(king.window.label, 'c1-g3');
    expect(find.text('2700+'), findsOneWidget);
    expect(find.byType(SmartPlateGlyph), findsNothing);

    await _pump(tester, quiet: true, minElo: 2400, formats: const {});
    final rook = _window(tester);
    expect(rook.fen, startsWith('8/8/8/8/8/8/8/R7'));
    expect(rook.window.label, 'a1-e3');

    expect(
      [for (final tier in kSmartEventTiers) tier.piece],
      [Role.king, Role.queen, Role.rook, Role.bishop, Role.knight],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an opening is its position, the defining move marked, framed '
      'where its line played', (tester) async {
    await _pump(
      tester,
      quiet: true,
      minElo: 0,
      formats: const {},
      opening: const SmartPlateLine(ecoCode: 'B20-B99', moves: ['e4', 'c5']),
    );
    final window = _window(tester);
    expect(window.marks, {Square.c7, Square.c5});
    // Four ranks: nothing to state, so no band.
    expect(window.window.label, 'b4-f7');
    expect(find.byType(SmartPlateBand), findsNothing);
    expect(find.byType(SmartEventDeck), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the window rule frames each line where it played', () {
    SmartBoardWindow frame(List<String> moves) =>
        resolveSmartPlateLine(SmartPlateLine(moves: moves))!.window();
    // c5 marked, e4 in view.
    expect(frame(['e4', 'c5']).label, 'b4-f7');
    // The Najdorf's ...a6.
    expect(
      frame([
        'e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'a6', //
      ]).label,
      'a4-e7',
    );
    // The Queen's Gambit Declined, Three Knights: 4.Nf3.
    expect(frame(['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'Nf3']).label, 'c1-g4');
    // A code alone plays its canonical line.
    expect(
      resolveSmartPlateLine(const SmartPlateLine(ecoCode: 'B90')),
      isNotNull,
    );
    // Nothing that replays: no position (the plate falls back to the deck).
    expect(
      resolveSmartPlateLine(const SmartPlateLine(moves: ['Ke2', 'Ke7'])),
      isNull,
    );
  });

  testWidgets('a time control alone keeps the deck, its fastest glyph on the '
      'front board, never squares that mean nothing', (tester) async {
    await _pump(tester, quiet: true, minElo: 0, formats: const {'blitz'});
    final blitz = tester.widget<SmartEventDeck>(find.byType(SmartEventDeck));
    expect(blitz.glyph, PngAsset.blitzIcon);
    expect(blitz.pace, SmartDeckPace.blitz);
    expect(blitz.behind, 3);
    expect(find.byType(SmartEventBoardWindow), findsNothing);

    await _pump(
      tester,
      quiet: true,
      minElo: 0,
      formats: const {'standard', 'rapid'},
    );
    final both = tester.widget<SmartEventDeck>(find.byType(SmartEventDeck));
    expect(both.glyph, PngAsset.rapidIcon);
    expect(both.seed, isNot(blitz.seed));

    // A status alone: the deck's face stays bare.
    await _pump(tester, quiet: true, minElo: 0, formats: const {'live'});
    expect(
      tester.widget<SmartEventDeck>(find.byType(SmartEventDeck)).glyph,
      isNull,
    );
    // The seed holds across launches: it never leans on String.hashCode.
    expect(smartDeckSeed(['GM', 2500]), smartDeckSeed(['GM', 2500]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the filled half card (Search) lays the plate across its whole '
      'width, in whole squares, the star clear of the board', (tester) async {
    await _pump(tester, quiet: true, stacked: true, fillPlate: true);
    final card = tester.getRect(find.byType(SmartEventCard));
    final plate = tester.getRect(find.byType(SmartEventPlate));
    final window = tester.getRect(find.byType(SmartEventBoardWindow));
    final band = tester.getRect(find.byType(SmartPlateBand));
    // The card's 6pt padding on both sides, nothing more.
    expect(plate.width, moreOrLessEquals(card.width - 2 * 6.sp));
    final square = plate.width / kSmartPlateFiles;
    expect(window.width, moreOrLessEquals(square * 5));
    expect(window.height, moreOrLessEquals(square * 3));
    expect(band.height, moreOrLessEquals(square));
    expect(plate.height, moreOrLessEquals(square * 4));
    // Its chevron (the star's slot) sits under the plate, by the title.
    final chevron = tester.getRect(find.byIcon(Icons.chevron_right_rounded));
    expect(chevron.top, greaterThan(plate.bottom));
    // Centred on the title's first line (the title holds two lines' room).
    final title = tester.getRect(find.text('GM Games'));
    expect(
      chevron.center.dy,
      moreOrLessEquals(title.top + title.height / 4, epsilon: 1.5),
    );
    expect(chevron.left, greaterThan(title.left));
    expect(tester.takeException(), isNull);
  });

  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    testWidgets('a half card that does not fill (My Space) keeps the event '
        'card\'s 108 plate, so a pair\'s rows line up '
        '(${theme.brightness.name})', (tester) async {
      _phone(tester);
      await _pump(tester, quiet: true, stacked: true, theme: theme);
      final card = tester.getRect(find.byType(SmartEventCard));
      final plate = tester.getRect(find.byType(SmartEventPlate));
      // EventCard's, the saved rows' and the collections' half plate.
      expect(plate.width, moreOrLessEquals(108.w));
      expect(plate.height, moreOrLessEquals(108.w * 4 / 5));
      expect(plate.center.dx, moreOrLessEquals(card.center.dx));
      // CardPlateLayout's stacked gap and inset round the words, as on
      // those cards: the same height beside them.
      final border = theme.brightness == Brightness.light ? 1.0 : 0.0;
      expect(plate.top - card.top, moreOrLessEquals(6.sp + border));
      final title = tester.getRect(find.text('GM Games'));
      expect(title.top - plate.bottom, moreOrLessEquals(10.sp + 6.sp));
      final last = tester.getRect(
        find.text('Game average 2500+, classical or rapid'),
      );
      expect(card.bottom - last.bottom, moreOrLessEquals(6.sp + 6.sp + border));
      // Its chevron (the star's slot) ends the title, clear of the board:
      // a piece can stand in the plate's corner.
      final chevron = tester.getRect(find.byIcon(Icons.chevron_right_rounded));
      expect(chevron.top, greaterThan(plate.bottom));
      expect(chevron.left, greaterThan(title.left));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a lead card sits on the grid of filled half cards under it: '
        'its plate over the first column, its words and chevron where the '
        'second column\'s stand (${theme.brightness.name})', (tester) async {
      // Search on a 393pt phone: 20pt gutters, 12pt between cards.
      _phone(tester);
      const column = 170.5;
      const gap = 12.0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            boardSettingsProviderNew.overrideWith(_BoardSettings.new),
          ],
          child: MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                SmartEventCard card(String tier, int floor, {bool? half}) =>
                    SmartEventCard(
                      key: ValueKey(tier),
                      tierLabel: tier,
                      minElo: floor,
                      liveCount: 0,
                      avgElo: 0,
                      metaText: 'Game average $floor+',
                      summary: '$tier level',
                      stacked: half ?? false,
                      fillPlate: half ?? false,
                      lead: half == null
                          ? const SmartCardLead(column: column, gap: gap)
                          : null,
                      onTap: () {},
                    );
                return Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 2 * column + gap,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          card('Super GM', 2700),
                          const SizedBox(height: gap),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: card('GM', 2500, half: true)),
                              const SizedBox(width: gap),
                              Expanded(child: card('IM', 2400, half: true)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      Rect within(String tier, Finder of) => tester.getRect(
        find.descendant(of: find.byKey(ValueKey(tier)), matching: of),
      );
      final plate = find.byType(SmartEventPlate);
      final chevron = find.byIcon(Icons.chevron_right_rounded);
      final lead = within('Super GM', plate);
      final first = within('GM', plate);
      // The lead never draws the smallest board: the half cards' own, over
      // the first column.
      expect(lead.width, moreOrLessEquals(first.width));
      expect(lead.height, moreOrLessEquals(first.height));
      expect(lead.left, moreOrLessEquals(first.left));
      expect(lead.width, greaterThan(108.w));
      // Its words and its chevron stand where the second column's do.
      final leadTitle = tester.getRect(find.text('Super GM Games'));
      final secondTitle = tester.getRect(find.text('IM Games'));
      expect(leadTitle.left, moreOrLessEquals(secondTitle.left));
      final leadChevron = within('Super GM', chevron);
      final secondChevron = within('IM', chevron);
      expect(leadChevron.right, moreOrLessEquals(secondChevron.right));
      // Centred on its title's first line, clear of it.
      final line = tester.getRect(find.text('Super GM Games'));
      expect(leadChevron.left, greaterThan(line.right));
      expect(
        tester.getRect(find.text('Game average 2700+')).right,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('Super GM'))).right,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('the board window clips on square lines: no square is sliced', () {
    for (final tier in kSmartEventTiers) {
      final w = smartBoardWindowAround(tier.home, ranks: 3);
      expect(w.contains(tier.home), isTrue, reason: tier.name);
      expect(w.files, 5);
      expect(w.file + w.files, lessThanOrEqualTo(8));
    }
    expect(
      smartTierPlateFen(kSmartEventTiers.last),
      startsWith('8/8/8/8/8/8/8/6N1'),
    );
  });

  testWidgets('a live member event reads LIVE, as an event card does', (
    tester,
  ) async {
    await _pump(tester, quiet: true, live: true);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Game average 2500+, classical or rapid'), findsNothing);
  });
}

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Speed Chess Championship game 2: Erdogmus has White, but the match's side
/// A (Nakamura, White in game 1) stays on the left. Position no longer tells
/// the colour, so each player carries a White/Black mark.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpCard(
    WidgetTester tester, {
    required MatchComparison comparison,
    required bool showPieceColorMarks,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          engineSettingsProviderNew.overrideWith(
            () => _TestEngineSettingsNotifier(const EngineSettings()),
          ),
          eventNoSpoilersProvider.overrideWith(
            (ref, tourId) =>
                _TestEventNoSpoilersController(ref: ref, tourId: tourId),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 360,
                    child: GameCard(
                      matchComparison: MatchWithComparison(
                        game: _gameTwo(),
                        comparison: comparison,
                      ),
                      onPinToggle: (_) {},
                      pinnedIds: const [],
                      onTap: () {},
                      showPieceColorMarks: showPieceColorMarks,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('side A stays left and each player shows their colour', (
    tester,
  ) async {
    await pumpCard(
      tester,
      comparison: matchComparisonForSelectedTeamSide(
        selectedTeamIsWhite: false,
      ),
      showPieceColorMarks: true,
    );

    final nakamura = tester.getCenter(find.textContaining('Nakamura'));
    final erdogmus = tester.getCenter(find.textContaining('Erdogmus'));
    expect(nakamura.dx, lessThan(erdogmus.dx));

    final marks = tester
        .widgetList<PieceColorMark>(find.byType(PieceColorMark))
        .toList();
    expect(marks, hasLength(2));
    final markCenters = [
      for (final mark in marks) tester.getCenter(find.byWidget(mark)),
    ];
    final left = markCenters[0].dx < markCenters[1].dx ? 0 : 1;
    // Nakamura (left) has Black in game 2, Erdogmus (right) has White.
    expect(marks[left].side, Side.black);
    expect(marks[1 - left].side, Side.white);
    // Each mark sits on its player's name line.
    expect(
      (markCenters[left].dy - nakamura.dy).abs(),
      lessThan(2),
      reason: 'mark is centred on the name line',
    );
    // Result reads from side A: Erdogmus won with White, so 0-1 for the left.
    expect(find.text('0–1'), findsOneWidget);
  });

  testWidgets('every other card draws no colour marks', (tester) async {
    await pumpCard(
      tester,
      comparison: MatchComparison.sameOrder,
      showPieceColorMarks: false,
    );

    expect(find.byType(PieceColorMark), findsNothing);
    final white = tester.getCenter(find.textContaining('Erdogmus'));
    final black = tester.getCenter(find.textContaining('Nakamura'));
    expect(white.dx, lessThan(black.dx));
    expect(find.text('1–0'), findsOneWidget);
  });
}

GamesTourModel _gameTwo() => GamesTourModel(
  gameId: '60IswAYI-1md2dlh',
  whitePlayer: _player('Erdogmus, Yagiz Kaan', 44599790),
  blackPlayer: _player('Nakamura, Hikaru', 2016192),
  whiteTimeDisplay: '--:--',
  blackTimeDisplay: '--:--',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.whiteWins,
  roundId: '60IswAYI',
  tourId: 'fqCjSUpE',
  lastMove: 'e2e4',
);

PlayerCard _player(String name, int fideId) => PlayerCard(
  name: name,
  federation: 'USA',
  title: 'GM',
  rating: 2700,
  countryCode: 'USA',
  team: null,
  fideId: fideId,
);

class _TestEventNoSpoilersController extends EventNoSpoilersController {
  _TestEventNoSpoilersController({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _TestEngineSettingsNotifier extends EngineSettingsNotifierNew {
  _TestEngineSettingsNotifier(this.settings);

  final EngineSettings settings;

  @override
  Future<EngineSettings> build() async => settings;
}

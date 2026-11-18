import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Regression: game-selector dropdown cards use
/// `PlayerFirstRowDetailWidget(compactName: true)`. The compact path used to
/// skip `TextPainter.layout()` then read `.width`, throwing
/// "Text layout not available / The TextPainter has never been laid out".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Match the focused board's glyph widths instead of the test font's.
  setUpAll(() async {
    final font = FontLoader('InterDisplay');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
    }
    await font.load();
  });

  Future<void> pumpCompactRow(
    WidgetTester tester, {
    required String whiteName,
    required String blackName,
    double maxWidth = 168,
    bool compactName = true,
    PlayerView playerView = PlayerView.gridView,
    TextScaler textScaler = TextScaler.noScaling,
    bool showClock = false,
    EngineSettings engineSettings = const EngineSettings(
      showEngineAnalysis: false,
    ),
    EventNoSpoilersState spoilerState = const EventNoSpoilersState(
      enabled: false,
      isLoading: false,
    ),
    GameSource source = GameSource.gamebase,
    bool hasStarted = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final game = GamesTourModel(
      gameId: 'compact-name-test',
      source: source,
      whitePlayer: _player(whiteName),
      blackPlayer: _player(blackName),
      whiteTimeDisplay: showClock ? '46:24' : '--:--',
      blackTimeDisplay: showClock ? '44:28' : '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.ongoing,
      roundId: 'r1',
      tourId: 't1',
      fen:
          hasStarted
              ? 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2'
              : 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      lastMove: hasStarted ? 'e7e5' : null,
    );

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          engineSettingsProviderNew.overrideWith(
            () => _TestEngineSettingsNotifier(engineSettings),
          ),
          eventNoSpoilersProvider.overrideWith(
            (ref, tourId) => _TestEventNoSpoilersController(
              ref: ref,
              tourId: tourId,
              loadedState: spoilerState,
            ),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Center(
                  child: SizedBox(
                    width: maxWidth,
                    // gridView row height is fixed at 20.h; give a little room.
                    height: 40,
                    child: PlayerFirstRowDetailWidget(
                      playerView: playerView,
                      isWhitePlayer: true,
                      gamesTourModel: game,
                      showClock: showClock,
                      showSubSecondClock: playerView == PlayerView.boardView,
                      replayMoveTimes: showClock ? const [] : null,
                      compactName: compactName,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    // The second frame applies the overridden async settings and spoiler state.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a long surname fits on a narrow board without dots', (
    tester,
  ) async {
    await pumpCompactRow(
      tester,
      whiteName: 'Wiśniewska-Kowalczyk, Aleksandra',
      blackName: 'Firouzja, Alireza',
      maxWidth: 260,
      compactName: false,
      playerView: PlayerView.boardView,
      textScaler: const TextScaler.linear(1.5),
      showClock: true,
      hasStarted: true,
    );

    final label = find.text('GM Wiśniewska-Kowalczyk 2830', findRichText: true);
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getRect(label).width, lessThan(paragraph.size.width));
    expect(
      tester.getRect(label).right,
      lessThan(tester.getRect(find.text('46:24')).left),
    );
  });

  for (final scale in [0.85, 1.0, 1.5]) {
    testWidgets('focused board paints the full player label at scale $scale', (
      tester,
    ) async {
      await pumpCompactRow(
        tester,
        whiteName: 'Caruana, Fabiano',
        blackName: 'Firouzja, Alireza',
        maxWidth: 400,
        compactName: false,
        playerView: PlayerView.boardView,
        textScaler: TextScaler.linear(scale),
        showClock: true,
        hasStarted: true,
      );

      final label = find.text('GM Caruana, Fabiano 2830', findRichText: true);
      final clock = find.text('46:24');
      expect(label, findsOneWidget);
      expect(clock, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(paragraph.textSize.height),
      );
      expect(tester.getRect(label).right, lessThan(tester.getRect(clock).left));
      expect(tester.widget<RichText>(label).textScaler.scale(14), 14 * scale);
    });
  }

  testWidgets(
    'compactName builds without TextPainter layout error (full name)',
    (tester) async {
      final flutterErrors = <Object>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        flutterErrors.add(details.exception);
        oldOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldOnError);

      await pumpCompactRow(
        tester,
        whiteName: 'Carlsen, Magnus',
        blackName: 'Nakamura, Hikaru',
        maxWidth: 168,
      );

      expect(find.byType(PlayerFirstRowDetailWidget), findsOneWidget);
      expect(
        flutterErrors.where(
          (e) =>
              e.toString().contains('Text layout not available') ||
              e.toString().contains('TextPainter has never been laid out'),
        ),
        isEmpty,
        reason: 'compactName must layout TextPainter before reading width',
      );
    },
  );

  testWidgets(
    'compactName builds without TextPainter layout error (surname only)',
    (tester) async {
      final flutterErrors = <Object>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        flutterErrors.add(details.exception);
        oldOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldOnError);

      await pumpCompactRow(
        tester,
        whiteName: 'Carlsen',
        blackName: 'Nakamura',
        maxWidth: 120,
      );

      expect(find.byType(PlayerFirstRowDetailWidget), findsOneWidget);
      expect(
        flutterErrors.where(
          (e) =>
              e.toString().contains('Text layout not available') ||
              e.toString().contains('TextPainter has never been laid out'),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'compactName builds without TextPainter layout error (empty-ish name)',
    (tester) async {
      final flutterErrors = <Object>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        flutterErrors.add(details.exception);
        oldOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldOnError);

      await pumpCompactRow(
        tester,
        whiteName: '',
        blackName: ', ',
        maxWidth: 100,
      );

      expect(find.byType(PlayerFirstRowDetailWidget), findsOneWidget);
      expect(
        flutterErrors.where(
          (e) =>
              e.toString().contains('Text layout not available') ||
              e.toString().contains('TextPainter has never been laid out'),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'non-compact full truncation path still lays out before width read',
    (tester) async {
      final flutterErrors = <Object>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        flutterErrors.add(details.exception);
        oldOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldOnError);

      await pumpCompactRow(
        tester,
        whiteName: 'Verylongsurname, Extremely Long Given Names',
        blackName: 'Other, Player',
        maxWidth: 90,
        compactName: false,
      );

      expect(
        flutterErrors.where(
          (e) =>
              e.toString().contains('Text layout not available') ||
              e.toString().contains('TextPainter has never been laid out'),
        ),
        isEmpty,
      );
    },
  );

  testWidgets('grid rows follow Grid View rather than Board View', (
    tester,
  ) async {
    await pumpCompactRow(
      tester,
      whiteName: 'Carlsen, Magnus',
      blackName: 'Nakamura, Hikaru',
      hasStarted: true,
      engineSettings: const EngineSettings(
        showEngineAnalysis: true,
        showEngineGaugeOnBoard: true,
        showEngineGaugeInGrid: false,
      ),
    );
    final withoutGridGauge =
        tester
            .getSize(find.byKey(const ValueKey('player-row-evaluation-space')))
            .width;

    await pumpCompactRow(
      tester,
      whiteName: 'Carlsen, Magnus',
      blackName: 'Nakamura, Hikaru',
      hasStarted: true,
      engineSettings: const EngineSettings(
        showEngineAnalysis: true,
        showEngineGaugeOnBoard: false,
        showEngineGaugeInGrid: true,
      ),
    );
    final withGridGauge =
        tester
            .getSize(find.byKey(const ValueKey('player-row-evaluation-space')))
            .width;

    expect(withoutGridGauge, 0);
    expect(withGridGauge, greaterThan(0));
  });

  testWidgets('No Spoilers removes live evaluation space from grid rows', (
    tester,
  ) async {
    const settings = EngineSettings(
      showEngineAnalysis: true,
      showEngineGaugeInGrid: true,
    );
    await pumpCompactRow(
      tester,
      whiteName: 'Carlsen, Magnus',
      blackName: 'Nakamura, Hikaru',
      hasStarted: true,
      source: GameSource.supabase,
      engineSettings: settings,
    );
    final visibleGaugeWidth =
        tester
            .getSize(find.byKey(const ValueKey('player-row-evaluation-space')))
            .width;

    await pumpCompactRow(
      tester,
      whiteName: 'Carlsen, Magnus',
      blackName: 'Nakamura, Hikaru',
      hasStarted: true,
      source: GameSource.supabase,
      engineSettings: settings,
      spoilerState: const EventNoSpoilersState(enabled: true, isLoading: false),
    );
    final hiddenGaugeWidth =
        tester
            .getSize(find.byKey(const ValueKey('player-row-evaluation-space')))
            .width;

    expect(visibleGaugeWidth, greaterThan(0));
    expect(hiddenGaugeWidth, 0);
  });
}

PlayerCard _player(String name) {
  return PlayerCard(
    name: name,
    federation: 'NOR',
    title: 'GM',
    rating: 2830,
    countryCode: 'NOR',
    team: null,
  );
}

class _TestEventNoSpoilersController extends EventNoSpoilersController {
  _TestEventNoSpoilersController({
    required super.ref,
    required super.tourId,
    required this.loadedState,
  });

  final EventNoSpoilersState loadedState;

  @override
  Future<void> load() async {
    state = loadedState;
  }
}

class _TestEngineSettingsNotifier extends EngineSettingsNotifierNew {
  _TestEngineSettingsNotifier(this.settings);

  final EngineSettings settings;

  @override
  Future<EngineSettings> build() async => settings;
}

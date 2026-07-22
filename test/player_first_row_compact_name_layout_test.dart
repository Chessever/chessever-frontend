import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Regression: game-selector dropdown cards use
/// `PlayerFirstRowDetailWidget(compactName: true)`. The compact path used to
/// skip `TextPainter.layout()` then read `.width`, throwing
/// "Text layout not available / The TextPainter has never been laid out".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final providerOverrides = <Override>[
    engineSettingsProviderNew.overrideWith(_TestEngineSettingsNotifier.new),
    eventNoSpoilersProvider.overrideWith(
      (ref, tourId) =>
          _TestEventNoSpoilersController(ref: ref, tourId: tourId),
    ),
  ];

  Future<void> pumpCompactRow(
    WidgetTester tester, {
    required String whiteName,
    required String blackName,
    double maxWidth = 168,
    bool compactName = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final game = GamesTourModel(
      gameId: 'compact-name-test',
      source: GameSource.gamebase,
      whitePlayer: _player(whiteName),
      blackPlayer: _player(blackName),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.ongoing,
      roundId: 'r1',
      tourId: 't1',
      fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: providerOverrides,
        child: MaterialApp(
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
                      playerView: PlayerView.gridView,
                      isWhitePlayer: true,
                      gamesTourModel: game,
                      showClock: false,
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
    // One frame is enough to run LayoutBuilder + TextPainter measure path.
    await tester.pump();
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
  _TestEventNoSpoilersController({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _TestEngineSettingsNotifier extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false);
}

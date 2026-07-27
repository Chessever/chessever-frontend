import 'dart:io' as io;

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EngineSettings search-time options (exact mapping)', () {
    test('every searchTimeIndex maps to the published label seconds', () {
      // Source of truth: EngineSettings._searchTimeSecondsOptions / labels.
      const expectedSeconds = <int?>[5, 10, 20, 30, 60, null];
      const expectedLabels = <String>['5s', '10s', '20s', '30s', '60s', '∞'];

      expect(
        EngineSettings.searchTimeLabels,
        expectedLabels,
        reason: 'labels are the settings UI contract',
      );

      for (var i = 0; i < expectedSeconds.length; i++) {
        final settings = EngineSettings(searchTimeIndex: i);
        expect(settings.searchTimeLabel(), expectedLabels[i]);
        expect(settings.baseSearchTimeSeconds(), expectedSeconds[i]);

        final gauge = settings.searchDurationFor(
          EngineComponent.evaluationGauge,
        );
        final pv = settings.searchDurationFor(
          EngineComponent.principalVariation,
        );

        if (expectedSeconds[i] == null) {
          expect(gauge, isNull, reason: '∞ → unlimited gauge');
          expect(pv, isNull, reason: '∞ → unlimited PV');
        } else {
          expect(
            gauge,
            Duration(seconds: expectedSeconds[i]!),
            reason: 'gauge duration for index $i',
          );
          expect(
            pv,
            Duration(seconds: expectedSeconds[i]!),
            reason: 'PV duration for index $i',
          );
        }
      }
    });
  });

  group('EngineSettings principal-variation options (exact mapping)', () {
    test('every principalVariationIndex maps to MultiPV 1–5', () {
      const expected = <int>[1, 2, 3, 4, 5];
      expect(EngineSettings.principalVariationLabels, ['1', '2', '3', '4', '5']);

      for (var i = 0; i < expected.length; i++) {
        final settings = EngineSettings(principalVariationIndex: i);
        expect(settings.principalVariationLabel(), '${expected[i]}');
        expect(settings.multiPvForStockfish(), expected[i]);
        expect(settings.multiPvForLichess(), expected[i]);
        expect(
          settings.resolveBoardSearchProfile().multiPv,
          expected[i],
          reason: 'board profile multiPv for index $i',
        );
      }
    });

    test('out-of-range principalVariationIndex is clamped', () {
      expect(
        const EngineSettings(principalVariationIndex: -3).multiPvForStockfish(),
        1,
      );
      expect(
        const EngineSettings(principalVariationIndex: 99).multiPvForStockfish(),
        5,
      );
    });
  });

  group('EngineSettings.resolveBoardSearchProfile', () {
    test('applies search time and MultiPV together for board jobs', () {
      final settings = EngineSettings(
        searchTimeIndex: 2, // 20s
        principalVariationIndex: 2, // 3 lines
      );
      final profile = settings.resolveBoardSearchProfile();

      expect(profile.multiPv, 3);
      expect(profile.searchDuration, const Duration(seconds: 20));
      expect(profile.isUnlimitedSearch, isFalse);
      // Tighter of gauge(99) and PV(50).
      expect(profile.maxDepth, 50);
    });

    test('unlimited search time yields null duration (∞)', () {
      final settings = EngineSettings(
        searchTimeIndex: EngineSettings.searchTimeLabels.length - 1,
        principalVariationIndex: 4,
      );
      final profile = settings.resolveBoardSearchProfile();

      expect(profile.searchDuration, isNull);
      expect(profile.isUnlimitedSearch, isTrue);
      expect(profile.multiPv, 5);
      expect(profile.maxDepth, greaterThanOrEqualTo(1));
      expect(profile.maxDepth, lessThanOrEqualTo(99));
    });

    test('default settings match product defaults (5s, 5 lines)', () {
      const settings = EngineSettings();
      final profile = settings.resolveBoardSearchProfile();
      // Default searchTimeIndex 0 → 5s; principalVariationIndex 4 → 5 lines.
      expect(profile.searchDuration, const Duration(seconds: 5));
      expect(profile.multiPv, 5);
    });

    test('max arrows options are 1–5 by index', () {
      for (var i = 0; i < 5; i++) {
        final settings = EngineSettings(maxArrowsOnBoard: i);
        expect(settings.getMaxArrowsOnBoard(), i + 1);
      }
    });

    test('component max depths match the settings contract', () {
      const settings = EngineSettings();
      expect(
        settings.maxDepthFor(EngineComponent.evaluationGauge),
        99,
      );
      expect(
        settings.maxDepthFor(EngineComponent.principalVariation),
        50,
      );
      expect(settings.maxDepthFor(EngineComponent.cascadeEval), 99);
      expect(settings.maxDepthFor(EngineComponent.moveImpact), 20);
    });

    test(
      'board profile maxDepth is the tighter of gauge and PV component caps',
      () {
        const settings = EngineSettings();
        final profile = settings.resolveBoardSearchProfile();
        final gauge = settings.maxDepthFor(EngineComponent.evaluationGauge);
        final pv = settings.maxDepthFor(EngineComponent.principalVariation);
        final expected = gauge <= pv ? gauge : pv;
        expect(profile.maxDepth, expected);
      },
    );
  });

  group('board path wiring (shipped code uses profile)', () {
    test('chess_board_screen_provider_new resolves board profile', () {
      final source = io.File(
        'lib/screens/chessboard/provider/chess_board_screen_provider_new.dart',
      ).readAsStringSync();
      expect(source.contains('resolveBoardSearchProfile()'), isTrue);
      expect(source.contains('boardProfile.multiPv'), isTrue);
      expect(source.contains('boardProfile.searchDuration'), isTrue);
      expect(source.contains('boardProfile.maxDepth'), isTrue);
      // Local re-derivation / artificial caps must not reappear.
      expect(source.contains('fallbackCap'), isFalse);
      expect(source.contains('const Duration(seconds: 10)'), isFalse);
      expect(source.contains('const Duration(milliseconds: 800)'), isFalse);
      // evaluatePosition must be fed profile fields, not hard-coded multipv.
      expect(
        RegExp(
          r'evaluatePosition\s*\([\s\S]*?multiPV:\s*multiPV',
        ).hasMatch(source),
        isTrue,
      );
      expect(
        RegExp(
          r'evaluatePosition\s*\([\s\S]*?searchDuration:\s*combinedSearchDuration',
        ).hasMatch(source),
        isTrue,
      );
      expect(
        RegExp(
          r'evaluatePosition\s*\([\s\S]*?maxDepth:\s*combinedMaxDepth',
        ).hasMatch(source),
        isTrue,
      );
    });

    test('stockfish applies MultiPV + movetime/depth from job params', () {
      final source = io.File(
        'lib/screens/chessboard/provider/stockfish_singleton.dart',
      ).readAsStringSync();
      expect(
        source.contains("setoption name MultiPV value \$multiPV"),
        isTrue,
      );
      expect(source.contains('go movetime'), isTrue);
      expect(source.contains('go depth'), isTrue);
    });
  });
}

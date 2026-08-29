import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evaluation bar surface settings', () {
    test('defaults to enabled globally, on the board, and in the grid', () {
      const settings = EngineSettings();

      expect(settings.showEngineGauge, isTrue);
      expect(settings.showEngineGaugeOnBoard, isTrue);
      expect(settings.showEngineGaugeInGrid, isTrue);
      expect(settings.shouldShowEngineGaugeOnBoard, isTrue);
      expect(settings.shouldShowEngineGaugeInGrid, isTrue);
    });

    test(
      'master switch hides both surfaces without changing their choices',
      () {
        final settings = const EngineSettings().copyWith(
          showEngineGauge: false,
        );

        expect(settings.showEngineGaugeOnBoard, isTrue);
        expect(settings.showEngineGaugeInGrid, isTrue);
        expect(settings.shouldShowEngineGaugeOnBoard, isFalse);
        expect(settings.shouldShowEngineGaugeInGrid, isFalse);

        final restored = settings.copyWith(showEngineGauge: true);
        expect(restored.shouldShowEngineGaugeOnBoard, isTrue);
        expect(restored.shouldShowEngineGaugeInGrid, isTrue);
      },
    );

    test('board and grid choices can be customized independently', () {
      final boardOnly = const EngineSettings().copyWith(
        showEngineGaugeOnBoard: true,
        showEngineGaugeInGrid: false,
      );
      final gridOnly = const EngineSettings().copyWith(
        showEngineGaugeOnBoard: false,
        showEngineGaugeInGrid: true,
      );

      expect(boardOnly.shouldShowEngineGaugeOnBoard, isTrue);
      expect(boardOnly.shouldShowEngineGaugeInGrid, isFalse);
      expect(gridOnly.shouldShowEngineGaugeOnBoard, isFalse);
      expect(gridOnly.shouldShowEngineGaugeInGrid, isTrue);
    });

    test('local surface choices overlay synced master settings', () {
      final merged = applyCachedEngineGaugeSurfaceSettings(
        const EngineSettings(showEngineGauge: true),
        const {'showEngineGaugeOnBoard': false, 'showEngineGaugeInGrid': true},
      );

      expect(merged.showEngineGauge, isTrue);
      expect(merged.showEngineGaugeOnBoard, isFalse);
      expect(merged.showEngineGaugeInGrid, isTrue);
    });

    test('missing cached surface choices retain enabled defaults', () {
      final merged = applyCachedEngineGaugeSurfaceSettings(
        const EngineSettings(),
        const {},
      );

      expect(merged.showEngineGaugeOnBoard, isTrue);
      expect(merged.showEngineGaugeInGrid, isTrue);
    });
  });
}

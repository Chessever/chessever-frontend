import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Toby switch', () {
    test('Toby is on and the engine is Stockfish by default', () {
      const settings = EngineSettings();
      expect(settings.tobyEnabled, isTrue);
      expect(settings.engineSource, EngineSource.stockfish);
      expect(settings.usesToby, isFalse);
    });

    test('Toby lines need both the choice and the switch', () {
      const chosen = EngineSettings(engineSource: EngineSource.toby);
      expect(chosen.usesToby, isTrue);
      expect(chosen.copyWith(tobyEnabled: false).usesToby, isFalse);
      // Turning Toby back on restores the reader's choice.
      expect(
        chosen
            .copyWith(tobyEnabled: false)
            .copyWith(tobyEnabled: true)
            .usesToby,
        isTrue,
      );
    });

    test('the device copy fills in when the account has nothing', () {
      final settings = applyDeviceLocalEngineSettings(
        const EngineSettings(),
        const {'engineSource': 'toby', 'tobyEnabled': false},
      );
      expect(settings.engineSource, EngineSource.toby);
      expect(settings.tobyEnabled, isFalse);
      expect(settings.usesToby, isFalse);
    });

    test('an empty device copy keeps the defaults', () {
      final settings = applyDeviceLocalEngineSettings(
        const EngineSettings(),
        const {},
      );
      expect(settings.tobyEnabled, isTrue);
      expect(settings.engineSource, EngineSource.stockfish);
    });
  });
}

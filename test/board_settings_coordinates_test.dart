import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/board_settings/models/board_settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoardSettingsNew coordinates', () {
    test('defaults to showing board coordinates', () {
      const settings = BoardSettingsNew();

      expect(settings.showCoordinates, isTrue);
    });

    test('copyWith can hide and restore board coordinates', () {
      const settings = BoardSettingsNew();

      expect(
        settings.copyWith(showCoordinates: false).showCoordinates,
        isFalse,
      );
      expect(
        settings
            .copyWith(showCoordinates: false)
            .copyWith(showCoordinates: true)
            .showCoordinates,
        isTrue,
      );
    });
  });

  group('BoardSettingsModel coordinates', () {
    test('fromSupabase falls back to showing coordinates for older rows', () {
      final model = BoardSettingsModel.fromSupabase({
        'id': 'settings-1',
        'user_id': 'user-1',
        'created_at': '2026-05-26T00:00:00.000Z',
        'updated_at': '2026-05-26T00:00:00.000Z',
      });

      expect(model.showCoordinates, isTrue);
    });

    test('serializes show_coordinates for Supabase upserts', () {
      final model = BoardSettingsModel.defaultSettings(
        'user-1',
      ).copyWith(showCoordinates: false);

      expect(model.toSupabaseUpsert('user-1')['show_coordinates'], isFalse);
    });
  });
}

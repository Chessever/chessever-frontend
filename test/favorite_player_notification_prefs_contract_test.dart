// Contract: Flutter notification_settings writes the same columns the
// onesignal-dispatch applyPreferences / player_game_recipients path reads for
// favorite-player game notifications.

import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('favorite-player notification prefs contract', () {
    test('Flutter provider reads/writes dispatcher columns', () {
      final source =
          io.File(
            'lib/providers/notification_preferences_provider.dart',
          ).readAsStringSync();
      for (final col in [
        'favorite_player_alerts',
        'fp_classical',
        'fp_rapid',
        'fp_blitz',
      ]) {
        expect(source, contains(col), reason: 'missing column $col');
      }
      expect(source, contains('setFavoritePlayerAlerts'));
      expect(source, contains('fpClassical'));
      // Master push toggle lives on the push service; dispatcher still reads it.
      final push =
          io.File(
            'lib/services/push_notifications_service.dart',
          ).readAsStringSync();
      expect(push, contains('push_enabled'));
    });

    test('notification_settings UI exposes Favorite Players + TC chips', () {
      final push =
          io.File(
            'lib/widgets/notification_settings/notif_push_card.dart',
          ).readAsStringSync();
      expect(push, contains('Favorite Players'));
      expect(push, contains('fpClassical'));
      final body =
          io.File(
            'lib/screens/settings/widgets/notification_settings_body.dart',
          ).readAsStringSync();
      expect(body, contains('setFavoritePlayerAlerts'));
      expect(body, contains('setFpClassical'));
    });

    test('dispatcher uses same prefs keys for game_started player path', () {
      final dispatch =
          io.File(
            'supabase/functions/onesignal-dispatch/index.ts',
          ).readAsStringSync();
      expect(dispatch, contains('favorite_player_alerts'));
      expect(dispatch, contains('fp_classical'));
      expect(dispatch, contains('filterGameStartedPlayerRecipients'));
      // Must not mark zero-recipient game_started as silently sent.
      expect(dispatch, contains('no_game_started_recipients'));
      expect(
        dispatch,
        isNot(contains('if (favCount !== 1) filteredUserIds.delete(uid)')),
      );

      final pure =
          io.File(
            'supabase/functions/onesignal-dispatch/player_game_recipients.ts',
          ).readAsStringSync();
      expect(pure, contains('shouldReceiveGameStartedForPlayerFavorite'));
      expect(pure, contains('return !alreadyCoveredByGameStartWindow'));
      expect(pure, isNot(contains('favoriteCountInRound >= 2')));
    });
  });
}

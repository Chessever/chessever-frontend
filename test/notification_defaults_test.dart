import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/live_activity_mode_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/providers/pip_mode_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('phone notification defaults', () {
    test('keeps favorite player blitz alerts off by default', () {
      expect(NotificationPreferences.defaults.favoritePlayerAlerts, isTrue);
      expect(NotificationPreferences.defaults.fpClassical, isTrue);
      expect(NotificationPreferences.defaults.fpRapid, isTrue);
      expect(NotificationPreferences.defaults.fpBlitz, isFalse);
    });

    test('defaults live widgets to live games for new users', () {
      const settings = BoardSettingsNew();

      expect(settings.pipMode, PipMode.live);
      expect(settings.liveActivityMode, LiveActivityMode.live);
    });

    test('missing persisted live widget modes use live game defaults', () {
      expect(PipModeInfo.fromIndex(null), PipMode.live);
      expect(LiveActivityModeInfo.fromIndex(null), LiveActivityMode.live);
    });
  });
}

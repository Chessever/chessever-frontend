import 'package:chessever2/providers/notification_permission_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'refresh and toggle before SDK init do not throw or report denial',
    () async {
      final notifier = NotificationPermissionNotifier();
      addTearDown(notifier.dispose);

      await expectLater(notifier.refresh(), completes);
      expect(notifier.state.hasError, isTrue);
      expect(notifier.state.valueOrNull, isNull);

      await expectLater(notifier.handleMasterToggle(), completes);
      expect(notifier.state.hasError, isTrue);
      expect(notifier.state.valueOrNull, isNull);
    },
  );
}

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:patrol/patrol.dart';

import 'support/e2e_test_support.dart';

void main() {
  patrolTest(
    'completes onboarding and reaches the signed-in home shell',
    ($) async {
      await launchAppAndReachSignedInShell($);

      await expectVisible($, E2eIds.homeRoot);
      await expectVisible($, E2eIds.eventsRoot);
      await expectVisible($, E2eIds.navCalendar);
      await expectVisible($, E2eIds.navLibrary);
    },
    config: patrolE2eConfig,
  );
}

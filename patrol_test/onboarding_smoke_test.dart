import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:patrol/patrol.dart';

import 'support/e2e_test_support.dart';

void main() {
  patrolTest(
    'completes onboarding and reaches the signed-in home shell',
    ($) async {
      await launchAppAndReachSignedInShell($);

      // Home opens on For You (its Today page).
      await expectVisible($, E2eIds.homeRoot);
      await expectVisible($, E2eIds.forYouRoot);
      await expectVisible($, E2eIds.navEvents);
      await expectVisible($, E2eIds.navFeed);
      await expectVisible($, E2eIds.navLibrary);
    },
    config: patrolE2eConfig,
  );
}

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:patrol/patrol.dart';

import 'support/e2e_test_support.dart';

void main() {
  patrolTest(
    'regresses common report flow: startup, home tabs, search, and filters stay usable',
    ($) async {
      await launchAppAndReachSignedInShell($);
      final seed = await seedBaselineData($);
      final player = seed.seededPlayers.first;
      final query = player.queryToken;

      try {
        await resetToHome($);
        await expectVisible($, E2eIds.eventsRoot);
        await expectVisible($, E2eIds.eventsSearchField);
        await searchFor($, fieldId: E2eIds.eventsSearchField, query: query);
        await byId($, E2eIds.eventsFilterButton).tap();
        await expectTextVisible($, 'Filters');
        await $('Rapid').tap();
        await $('Apply Filters').tap();
        await expectVisible($, E2eIds.eventsRoot);
        await byId($, E2eIds.eventsFilterButton).tap();
        await $('Reset').tap();
        await expectVisible($, E2eIds.eventsRoot);

        await tapBottomNavRoot(
          $,
          navId: E2eIds.navCalendar,
          expectedRoot: E2eIds.calendarRoot,
        );
        await expectVisible($, E2eIds.calendarSearchField);

        await tapBottomNavRoot(
          $,
          navId: E2eIds.navLibrary,
          expectedRoot: E2eIds.libraryRoot,
        );
        await expectVisible($, E2eIds.libraryOpeningExplorerButton);
        await expectVisible($, E2eIds.libraryBoardEditorButton);
        await expectVisible($, E2eIds.libraryCreateFolderButton);
        await searchFor($, fieldId: E2eIds.librarySearchField, query: query);
        await expectVisible($, E2eIds.libraryRoot);
      } finally {
        await cleanupSeedData(seed);
      }
    },
    config: patrolE2eConfig,
  );

  patrolTest(
    'regresses board stability: engine, notation, move buttons, swipe, selector, and flip',
    ($) async {
      await launchAppAndReachSignedInShell($);

      await openSyntheticBoard($);
      await assertBoardEngineReady($);
      await expectVisible($, E2eIds.boardNotationRoot);
      await tapBoardNotationToken($, 'Bb5');
      await stressMoveNavigation($, forwardTaps: 6, backwardTaps: 6);
      await swipeBoardBetweenGames(
        $,
        forward: true,
        expectedVisibleToken: 'Gamma Scout',
      );
      await selectBoardGame($, 'Alpha Tester');
      await assertBoardEngineReady($);
      await byId($, E2eIds.boardFlip).tap();
      await $.pumpAndTrySettle(timeout: const Duration(seconds: 8));
      await assertBoardEngineReady($);
    },
    config: patrolE2eConfig,
  );

  patrolTest(
    'regresses saved-game surfaces: favorites, player games, and library detail routes reopen cleanly',
    ($) async {
      await launchAppAndReachSignedInShell($);
      final seed = await seedBaselineData($);
      final player = seed.seededPlayers.first;
      final query = player.queryToken;

      try {
        await pushNamedRoute($, '/favorites_screen');
        await expectVisible($, E2eIds.favoritesRoot);
        await $('Games').tap();
        await expectVisible($, E2eIds.favoritesGamesSearchField);
        await searchFor(
          $,
          fieldId: E2eIds.favoritesGamesSearchField,
          query: query,
        );
        await expectVisible($, E2eIds.favoritesRoot);
        await popRoute($);

        await openSeededPlayerProfile($, player);
        await $('Games').tap();
        await expectVisible($, E2eIds.playerGamesSearchField);
        await searchFor(
          $,
          fieldId: E2eIds.playerGamesSearchField,
          query: query,
        );
        await expectVisible($, E2eIds.playerProfileRoot);
        await popRoute($);

        await openSeededFolder($, seed);
        await expectVisible($, E2eIds.folderContentsRoot);
        await popRoute($);
        await openSharedBookPreview($, seed);
        await expectVisible($, E2eIds.bookPreviewRoot);
        await popRoute($);
      } finally {
        await cleanupSeedData(seed);
      }
    },
    config: patrolE2eConfig,
  );
}

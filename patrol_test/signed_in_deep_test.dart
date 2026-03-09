import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/premium_games/providers/premium_games_provider.dart';
import 'package:chessever2/screens/premium_games/widgets/twic_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:patrol/patrol.dart';

import 'support/e2e_test_support.dart';

PlayerProfileKey _playerKey(SeededPlayerData player) => PlayerProfileKey(
  fideId: player.fideId,
  playerName: player.name,
  source: PlayerProfileDataSource.supabase,
);

void main() {
  patrolTest(
    'walks the named-route and widget-route matrix and asserts every page root',
    ($) async {
      await launchAppAndReachSignedInShell($);
      final seed = await seedBaselineData($);

      try {
        await resetToHome($);

        await pushNamedRoute($, '/home_screen');
        await expectVisible($, E2eIds.homeRoot);
        await popRoute($);

        await pushNamedRoute($, '/group_event_screen');
        await expectVisible($, E2eIds.eventsRoot);
        await popRoute($);

        await pushNamedRoute($, '/calendar_screen');
        await expectVisible($, E2eIds.calendarRoot);
        await popRoute($);

        await pushNamedRoute($, '/library_screen');
        await expectVisible($, E2eIds.libraryRoot);
        await popRoute($);

        await pushNamedRoute($, '/favorites_screen');
        await expectVisible($, E2eIds.favoritesRoot);
        await popRoute($);

        await pushNamedRoute($, '/player_list_screen');
        await expectVisible($, E2eIds.playersRoot);
        await popRoute($);

        await pushNamedRoute($, '/countryman_games_screen');
        await expectVisible($, E2eIds.countrymenRoot);
        await popRoute($);

        await pushNamedRoute($, '/standings');
        await expectVisible($, E2eIds.standingsRoot);
        await popRoute($);

        await pushNamedRoute($, '/calendar_detail_screen');
        await expectVisible($, E2eIds.calendarDetailRoot);
        await popRoute($);

        await pushNamedRoute($, '/Board_sheet');
        await expectVisible($, E2eIds.boardColorDialogRoot);
        await popRoute($);

        await pushNamedRoute($, '/auth_screen');
        await expectVisible($, E2eIds.authRoot);
        await popRoute($);

        await pushNamedRoute($, '/onboarding');
        await expectVisible($, E2eIds.onboardingRoot);
        await popRoute($);

        await pushNamedRoute($, '/player_selection_screen');
        await expectVisible($, E2eIds.playerSelectionRoot);
        await popRoute($);

        await openSettingsDialog($);
        await expectVisible($, E2eIds.settingsRoot);
        await popRoute($);
        if (byId($, E2eIds.homeDrawer).isVisibleAt()) {
          await popRoute($);
        }

        await openPremiumScreen($);
        await expectVisible($, E2eIds.premiumRoot);
        await popRoute($);

        await openPremiumFavoritesGames($);
        await expectVisible($, E2eIds.premiumGamesRoot);
        await popRoute($);

        await openPremiumCountrymenGames($);
        await expectVisible($, E2eIds.premiumGamesRoot);
        await popRoute($);

        await pushWidgetRoute($, const TwicContentsScreen());
        await expectVisible($, E2eIds.twicContentsRoot);
        await popRoute($);

        await openBoardEditor($);
        await expectVisible($, E2eIds.boardEditorRoot);
        await popRoute($);

        await openOpeningExplorer($);
        await expectVisible($, E2eIds.openingExplorerRoot);
        await popRoute($);

        await openSeededScorecard($, seed.seededPlayers.first);
        await expectVisible($, E2eIds.scorecardRoot);
        await popRoute($);

        await ensureHomeShell($);
      } finally {
        await cleanupSeedData(seed);
      }
    },
    config: patrolE2eConfig,
  );

  patrolTest(
    'jumps across unrelated routes and deep-link-only pages',
    ($) async {
      await launchAppAndReachSignedInShell($);
      final seed = await seedBaselineData($);

      try {
        await resetToHome($);
        await openSeededScorecard($, seed.seededPlayers.first);
        await expectVisible($, E2eIds.scorecardRoot);
        await popRoute($);

        await openSeededPlayerProfile($, seed.seededPlayers.first);
        await expectVisible($, E2eIds.playerProfileRoot);
        await $('Events').tap();
        await $('Games').tap();
        await $('About').tap();
        await popRoute($);

        await openBoardEditor($);
        await expectVisible($, E2eIds.boardEditorRoot);
        await expectVisible($, E2eIds.boardEvalBar);
        await byId($, E2eIds.boardEditorDoneButton).tap();
        await expectVisible($, E2eIds.chessBoardRoot);
        await assertBoardEngineReady($);
        await popRoute($);
        await popRoute($);

        await openOpeningExplorer($);
        await expectVisible($, E2eIds.openingExplorerRoot);
        await expectVisible($, E2eIds.boardEvalBar);
        await expectVisible($, E2eIds.openingExplorerEngineLines);
        await byId($, E2eIds.openingExplorerDoneButton).tap();
        await expectVisible($, E2eIds.chessBoardRoot);
        await assertBoardEngineReady($);
        await popRoute($);
        await popRoute($);

        await openSeededFolder($, seed);
        await popRoute($);
        await openSharedBookPreview($, seed);
        await popRoute($);
        await openSeededCalendarEvent($, seed);
        await popRoute($);

        await pushNamedRoute($, '/auth_screen');
        await expectVisible($, E2eIds.authRoot);
        await popRoute($);

        await ensureHomeShell($);
      } finally {
        await cleanupSeedData(seed);
      }
    },
    config: patrolE2eConfig,
  );

  patrolTest(
    'stresses engine analysis, notation taps, move traversal, and game switching',
    ($) async {
      await launchAppAndReachSignedInShell($);
      final seed = await seedBaselineData($);

      try {
        await openSyntheticBoard($);
        await assertBoardEngineReady($);
        await expectVisible($, E2eIds.boardNotationRoot);
        await tapBoardNotationToken($, 'Bb5');
        await stressMoveNavigation($, forwardTaps: 14, backwardTaps: 12);
        await swipeBoardBetweenGames(
          $,
          forward: true,
          expectedVisibleToken: 'Gamma Scout',
        );
        await tapBoardNotationToken($, 'Bg5');

        await swipeBoardBetweenGames(
          $,
          forward: true,
          expectedVisibleToken: 'Epsilon Trace',
        );
        await tapBoardNotationToken($, 'Be3');
        await stressMoveNavigation($, forwardTaps: 10, backwardTaps: 10);
        await swipeBoardBetweenGames(
          $,
          forward: false,
          expectedVisibleToken: 'Gamma Scout',
        );
        await selectBoardGame($, 'Alpha Tester');
        await assertBoardEngineReady($);
        await byId($, E2eIds.boardFlip).tap();
        await $.pumpAndTrySettle(timeout: const Duration(seconds: 8));
        await assertBoardEngineReady($);
        await popRoute($);

        await pushNamedRoute($, '/favorites_screen');
        await expectVisible($, E2eIds.favoritesRoot);
        await $('Games').tap();
        await pumpUntil(
          $,
          () =>
              providerContainer()
                  .read(favoritesCombinedGamesProvider)
                  .filteredGames
                  .isNotEmpty,
          reason: 'favorite games loaded',
          timeout: const Duration(seconds: 45),
        );
        await openFirstVisibleBoardFromPrefixes($, const [
          'fav_board_game_',
          'fav_grid_game_',
          'fav_game_',
        ]);
        await assertBoardEngineReady($);
        await assertBoardEngineRefreshesAfterMove($, forward: true);
        await popRoute($);
        await popRoute($);

        await tapBottomNavRoot(
          $,
          navId: E2eIds.navLibrary,
          expectedRoot: E2eIds.libraryRoot,
        );
        final query = seed.seededPlayers.first.queryToken;
        await searchFor($, fieldId: E2eIds.librarySearchField, query: query);
        await pumpUntil(
          $,
          () {
            final result = providerContainer().read(
              libraryCombinedSearchProvider(query),
            );
            final value = result is AsyncData ? result.value : null;
            return result.hasValue && (value?.games.isNotEmpty ?? false);
          },
          reason: 'library game search results',
          timeout: const Duration(seconds: 45),
        );
        await openFirstVisibleBoardFromPrefixes($, const [
          'lib_board_game_',
          'lib_grid_game_',
        ]);
        await assertBoardEngineReady($);
        await assertBoardEngineRefreshesAfterMove($, forward: true);
        await popRoute($);
        await resetToHome($);

        await openPremiumFavoritesGames($);
        await pumpUntil(
          $,
          () {
            final state = providerContainer().read(
              premiumGamesProvider(PremiumGamesType.favorites),
            );
            final value = state is AsyncData ? state.value : null;
            return state.hasValue && (value?.games.isNotEmpty ?? false);
          },
          reason: 'premium favorite games loaded',
          timeout: const Duration(seconds: 45),
        );
        expect(find.byType(TwicGameCard), findsWidgets);
        await $(TwicGameCard).at(0).tap();
        await expectVisible($, E2eIds.chessBoardRoot);
        await assertBoardEngineReady($);
        await assertBoardEngineRefreshesAfterMove($, forward: true);
        await popRoute($);
        await popRoute($);

        await openPremiumCountrymenGames($);
        await pumpUntil(
          $,
          () {
            final state = providerContainer().read(
              premiumGamesProvider(PremiumGamesType.countrymen),
            );
            final value = state is AsyncData ? state.value : null;
            return state.hasValue && (value?.games.isNotEmpty ?? false);
          },
          reason: 'premium countrymen games loaded',
          timeout: const Duration(seconds: 45),
        );
        expect(find.byType(TwicGameCard), findsWidgets);
        await $(TwicGameCard).at(0).tap();
        await expectVisible($, E2eIds.chessBoardRoot);
        await assertBoardEngineReady($);
        await assertBoardEngineRefreshesAfterMove($, forward: true);
        await popRoute($);
        await popRoute($);
        await ensureHomeShell($);
      } finally {
        await cleanupSeedData(seed);
      }
    },
    config: patrolE2eConfig,
  );

  patrolTest(
    'repeats search and filter mutations while preserving route stability',
    ($) async {
      await launchAppAndReachSignedInShell($);
      final seed = await seedBaselineData($);
      final player = seed.seededPlayers.first;
      final query = player.queryToken;

      try {
        await resetToHome($);
        await openSeededPlayerProfile($, player);
        await $('Games').tap();
        await searchFor(
          $,
          fieldId: E2eIds.playerGamesSearchField,
          query: query,
        );
        await pumpUntil(
          $,
          () =>
              providerContainer()
                  .read(playerProfileGamesKeyProvider(_playerKey(player)))
                  .searchQuery ==
              query,
          reason: 'deep player profile search',
        );
        await byId($, E2eIds.playerGamesFilterButton).tap();
        await $('Rapid').tap();
        await $('Apply Filters').tap();
        await pumpUntil(
          $,
          () =>
              providerContainer()
                  .read(playerProfileGamesKeyProvider(_playerKey(player)))
                  .hasActiveFilters,
          reason: 'deep player profile filter applied',
        );
        await byId($, E2eIds.playerGamesFilterButton).tap();
        await $('Reset').tap();
        await popRoute($);

        await pushNamedRoute($, '/favorites_screen');
        await expectVisible($, E2eIds.favoritesRoot);
        await $('Games').tap();
        await searchFor(
          $,
          fieldId: E2eIds.favoritesGamesSearchField,
          query: query,
        );
        await pumpUntil(
          $,
          () =>
              providerContainer()
                  .read(favoritesCombinedGamesProvider)
                  .searchQuery ==
              query,
          reason: 'deep favorites search',
        );
        await byId($, E2eIds.favoritesGamesFilterButton).tap();
        await $('Rapid').tap();
        await $('Apply Filters').tap();
        await pumpUntil(
          $,
          () =>
              providerContainer()
                  .read(favoritesCombinedGamesProvider)
                  .filter
                  .hasActiveFilters,
          reason: 'deep favorites filter applied',
        );
        await byId($, E2eIds.favoritesGamesFilterButton).tap();
        await $('Reset').tap();
        await $('Players').tap();
        providerContainer().read(selectedFavoritesModeProvider.notifier).state =
            FavoritesScreenMode.games;
        await popRoute($);

        await pushNamedRoute($, '/countryman_games_screen');
        await expectVisible($, E2eIds.countrymenRoot);
        if (find.byType(GameCard).evaluate().isNotEmpty) {
          await $(GameCard).at(0).tap();
          await expectVisible($, E2eIds.chessBoardRoot);
          await assertBoardEngineReady($);
          await popRoute($);
        }
      } finally {
        await cleanupSeedData(seed);
      }
    },
    config: patrolE2eConfig,
  );
}

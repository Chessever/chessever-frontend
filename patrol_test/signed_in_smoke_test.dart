import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/group_event/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/calendar/provider/calendar_screen_provider.dart';
import 'package:chessever2/screens/library/providers/gamebase_filter_provider.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/players/providers/player_providers.dart';
import 'package:chessever2/screens/premium_games/providers/premium_games_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:patrol/patrol.dart';

import 'support/e2e_test_support.dart';

String _searchToken(String text) {
  final normalized = text.replaceAll(RegExp(r'[^A-Za-z0-9\s]'), ' ');
  final tokens =
      normalized
          .split(RegExp(r'\s+'))
          .map((token) => token.trim())
          .where((token) => token.length >= 3)
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  return tokens.isNotEmpty ? tokens.first : text;
}

PlayerProfileKey _playerKey(SeededPlayerData player) => PlayerProfileKey(
  fideId: player.fideId,
  playerName: player.name,
  source: PlayerProfileDataSource.supabase,
);

void main() {
  patrolTest(
    'visits signed-in home roots, drawer surfaces, and guarded shells',
    ($) async {
      await launchAppAndReachSignedInShell($);
      final seed = await seedBaselineData($);

      try {
        await expectVisible($, E2eIds.eventsRoot);

        await tapBottomNavRoot(
          $,
          navId: E2eIds.navCalendar,
          expectedRoot: E2eIds.calendarRoot,
        );
        await tapBottomNavRoot(
          $,
          navId: E2eIds.navLibrary,
          expectedRoot: E2eIds.libraryRoot,
        );
        await expectVisible($, E2eIds.libraryOpeningExplorerButton);
        await expectVisible($, E2eIds.libraryBoardEditorButton);
        await expectVisible($, E2eIds.libraryCreateFolderButton);
        await tapBottomNavRoot(
          $,
          navId: E2eIds.navEvents,
          expectedRoot: E2eIds.eventsRoot,
        );

        await openSettingsDialog($);
        await popRoute($);
        if (byId($, E2eIds.homeDrawer).isVisibleAt()) {
          await popRoute($);
        }

        await openDrawerDestination(
          $,
          drawerItemId: E2eIds.drawerPlayers,
          expectedRoot: E2eIds.playersRoot,
        );
        await popRoute($);

        await openDrawerDestination(
          $,
          drawerItemId: E2eIds.drawerPremium,
          expectedRoot: E2eIds.premiumRoot,
        );
        await popRoute($);

        await openDrawerDestination(
          $,
          drawerItemId: E2eIds.drawerOpeningExplorer,
          expectedRoot: E2eIds.openingExplorerRoot,
        );
        await popRoute($);

        await openDrawerDestination(
          $,
          drawerItemId: E2eIds.drawerAnalysisBoard,
          expectedRoot: E2eIds.boardEditorRoot,
        );
        await popRoute($);

        await pushNamedRoute($, '/favorites_screen');
        await expectVisible($, E2eIds.favoritesRoot);
        await popRoute($);

        await pushNamedRoute($, '/countryman_games_screen');
        await expectVisible($, E2eIds.countrymenRoot);
        await popRoute($);

        await pushNamedRoute($, '/auth_screen');
        await expectVisible($, E2eIds.authRoot);
        await popRoute($);

        await openHomeDrawer($);
        await byId($, E2eIds.drawerLogout).tap();
        await expectTextVisible($, 'Logout');
        await $('Cancel').tap();
        await ensureHomeShell($);
      } finally {
        await cleanupSeedData(seed);
      }
    },
    config: patrolE2eConfig,
  );

  patrolTest(
    'covers tournament, calendar, library, player profile, and board smoke flows',
    ($) async {
      await launchAppAndReachSignedInShell($);
      final seed = await seedBaselineData($);

      try {
        await resetToHome($);
        await pumpUntil(
          $,
          () => visibleCountForPrefixes($, const ['event_']) > 0,
          reason: 'event cards on home',
          timeout: const Duration(seconds: 45),
        );
        expect(await tapFirstVisibleByPrefixes($, const ['event_']), isTrue);
        await expectVisible($, E2eIds.tournamentDetailRoot);
        await expectAnyTextVisible($, const ['About', 'Games', 'Players']);
        await $('About').tap();
        await expectVisible($, E2eIds.tournamentDetailRoot);
        await $('Players').tap();
        await expectVisible($, E2eIds.standingsRoot);
        await $('Games').tap();
        await pumpUntil(
          $,
          () => visibleCountForPrefixes($, const ['game_', 'grid_game_']) > 0,
          reason: 'tournament game cards',
          timeout: const Duration(seconds: 45),
        );
        await openFirstVisibleBoardFromPrefixes($, const [
          'game_',
          'grid_game_',
          'board_game_',
        ]);
        await assertBoardEngineReady($);
        await assertBoardEngineRefreshesAfterMove($, forward: true);
        await popRoute($);
        await popRoute($);

        await pushNamedRoute($, '/calendar_detail_screen');
        await expectVisible($, E2eIds.calendarDetailRoot);
        await popRoute($);

        await openSeededCalendarEvent($, seed);
        await expectVisible($, E2eIds.calendarEventDetailRoot);
        await popRoute($);

        await openSeededFolder($, seed);
        await expectVisible($, E2eIds.folderContentsRoot);
        await popRoute($);

        await openSharedBookPreview($, seed);
        await expectVisible($, E2eIds.bookPreviewRoot);
        await expectAnyTextVisible($, [seed.folder.name]);
        await popRoute($);

        await openSeededPlayerProfile($, seed.seededPlayers.first);
        await expectVisible($, E2eIds.playerProfileRoot);
        await expectAnyTextVisible($, const ['About', 'Games', 'Events']);
        await $('Games').tap();
        await expectVisible($, E2eIds.playerGamesSearchField);
        await popRoute($);
      } finally {
        await cleanupSeedData(seed);
      }
    },
    config: patrolE2eConfig,
  );

  patrolTest(
    'runs smoke search and filter assertions across signed-in pages',
    ($) async {
      await launchAppAndReachSignedInShell($);
      final seed = await seedBaselineData($);
      final player = seed.seededPlayers.first;
      final query = player.queryToken;
      final calendarQuery =
          seed.calendarEvent == null
              ? null
              : _searchToken(seed.calendarEvent!.name);

      try {
        await resetToHome($);
        await expectVisible($, E2eIds.eventsSearchField);
        await byId($, E2eIds.eventsFilterButton).tap();
        await expectTextVisible($, 'Filters');
        await $('Rapid').tap();
        await $('Apply Filters').tap();
        await pumpUntil(
          $,
          () =>
              providerContainer()
                  .read(forYouAppliedFilterProvider)
                  .formatsAndStates
                  .isNotEmpty,
          reason: 'events filter applied',
        );
        await byId($, E2eIds.eventsFilterButton).tap();
        await $('Reset').tap();
        await pumpUntil(
          $,
          () =>
              providerContainer()
                  .read(forYouAppliedFilterProvider)
                  .formatsAndStates
                  .isEmpty,
          reason: 'events filter reset',
        );
        await searchFor($, fieldId: E2eIds.eventsSearchField, query: query);
        await pumpUntil(
          $,
          () {
            final result = providerContainer().read(
              supabaseCombinedSearchProvider(query),
            );
            final value = result is AsyncData ? result.value : null;
            return result.hasValue &&
                !((value?.tournamentResults.isEmpty ?? true) &&
                    (value?.playerResults.isEmpty ?? true));
          },
          reason: 'events search results',
          timeout: const Duration(seconds: 45),
        );

        await tapBottomNavRoot(
          $,
          navId: E2eIds.navCalendar,
          expectedRoot: E2eIds.calendarRoot,
        );
        if (calendarQuery != null && calendarQuery.isNotEmpty) {
          await searchFor(
            $,
            fieldId: E2eIds.calendarSearchField,
            query: calendarQuery,
          );
          await pumpUntil(
            $,
            () =>
                providerContainer().read(calendarSearchQueryProvider) ==
                calendarQuery,
            reason: 'calendar search query',
          );
        }

        await pushNamedRoute($, '/player_list_screen');
        await expectVisible($, E2eIds.playersRoot);
        await searchFor($, fieldId: E2eIds.playersSearchField, query: query);
        await pumpUntil(
          $,
          () {
            final results = providerContainer().read(filteredPlayersProvider);
            return results.isNotEmpty &&
                results.any(
                  (entry) => (entry['name'] as String? ?? '')
                      .toLowerCase()
                      .contains(query.toLowerCase()),
                );
          },
          reason: 'player search state',
          timeout: const Duration(seconds: 45),
        );
        await popRoute($);

        await tapBottomNavRoot(
          $,
          navId: E2eIds.navLibrary,
          expectedRoot: E2eIds.libraryRoot,
        );
        await searchFor($, fieldId: E2eIds.librarySearchField, query: query);
        await pumpUntil(
          $,
          () {
            final result = providerContainer().read(
              libraryCombinedSearchProvider(query),
            );
            final value = result is AsyncData ? result.value : null;
            return result.hasValue && !(value?.isEmpty ?? true);
          },
          reason: 'library search results',
          timeout: const Duration(seconds: 45),
        );

        await pushWidgetRoute($, const TwicContentsScreen());
        await expectVisible($, E2eIds.twicContentsRoot);
        await byId($, E2eIds.libraryFilterButton).tap();
        await expectTextVisible($, 'Filters');
        await $('Rapid').tap();
        await $('Apply Filters').tap();
        await pumpUntil(
          $,
          () => providerContainer().read(hasActiveGamebaseFiltersProvider),
          reason: 'library filter applied',
        );
        await byId($, E2eIds.libraryFilterButton).tap();
        await $('Reset').tap();
        await pumpUntil(
          $,
          () => !providerContainer().read(hasActiveGamebaseFiltersProvider),
          reason: 'library filter reset',
        );
        await popRoute($);

        await pushNamedRoute($, '/favorites_screen');
        await expectVisible($, E2eIds.favoritesRoot);
        await $('Games').tap();
        await expectVisible($, E2eIds.favoritesGamesSearchField);
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
          reason: 'favorites search query',
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
          reason: 'favorites filter applied',
        );
        await byId($, E2eIds.favoritesGamesFilterButton).tap();
        await $('Reset').tap();
        await pumpUntil(
          $,
          () =>
              !providerContainer()
                  .read(favoritesCombinedGamesProvider)
                  .filter
                  .hasActiveFilters,
          reason: 'favorites filter reset',
        );
        await popRoute($);

        await openSeededPlayerProfile($, player);
        await $('Games').tap();
        await expectVisible($, E2eIds.playerGamesSearchField);
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
          reason: 'player profile search query',
        );
        await byId($, E2eIds.playerGamesFilterButton).tap();
        await $('Rapid').tap();
        await $('Apply Filters').tap();
        await pumpUntil(
          $,
          () =>
              providerContainer()
                  .read(playerProfileGamesKeyProvider(_playerKey(player)))
                  .filter
                  .hasActiveFilters,
          reason: 'player profile filter applied',
        );
        await byId($, E2eIds.playerGamesFilterButton).tap();
        await $('Reset').tap();
        await pumpUntil(
          $,
          () =>
              !providerContainer()
                  .read(playerProfileGamesKeyProvider(_playerKey(player)))
                  .filter
                  .hasActiveFilters,
          reason: 'player profile filter reset',
        );
        await popRoute($);

        await openPremiumFavoritesGames($);
        await byId($, E2eIds.premiumGamesFilterButton).tap();
        await $('Last 30 days').tap();
        await $('Apply').tap();
        await pumpUntil(
          $,
          () =>
              providerContainer()
                  .read(premiumGamesFilterProvider(PremiumGamesType.favorites))
                  .hasActiveFilters,
          reason: 'premium filter applied',
        );
        await byId($, E2eIds.premiumGamesFilterButton).tap();
        await $('Reset').tap();
        await pumpUntil(
          $,
          () =>
              !providerContainer()
                  .read(premiumGamesFilterProvider(PremiumGamesType.favorites))
                  .hasActiveFilters,
          reason: 'premium filter reset',
        );
        await popRoute($);

        await openPremiumCountrymenGames($);
        await byId($, E2eIds.premiumGamesFilterButton).tap();
        await $('Last 30 days').tap();
        await $('Apply').tap();
        await pumpUntil(
          $,
          () =>
              providerContainer()
                  .read(premiumGamesFilterProvider(PremiumGamesType.countrymen))
                  .hasActiveFilters,
          reason: 'premium countrymen filter applied',
        );
        await byId($, E2eIds.premiumGamesFilterButton).tap();
        await $('Reset').tap();
        await pumpUntil(
          $,
          () =>
              !providerContainer()
                  .read(premiumGamesFilterProvider(PremiumGamesType.countrymen))
                  .hasActiveFilters,
          reason: 'premium countrymen filter reset',
        );
        await popRoute($);

        await pushNamedRoute($, '/countryman_games_screen');
        await expectVisible($, E2eIds.countrymenRoot);
        await byId($, E2eIds.countrymenSearchToggle).tap();
        await searchFor(
          $,
          fieldId: E2eIds.countrymenSearchField,
          query: query,
          debounce: const Duration(milliseconds: 500),
        );
        await pumpUntil(
          $,
          () {
            final state = providerContainer().read(
              countrymanGamesTourScreenProvider,
            );
            final value = state is AsyncData ? state.value : null;
            return value != null &&
                value.isSearchMode &&
                value.searchQuery == query;
          },
          reason: 'countrymen search state',
          timeout: const Duration(seconds: 45),
        );
      } finally {
        await cleanupSeedData(seed);
      }
    },
    config: patrolE2eConfig,
  );
}

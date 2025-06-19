import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_typography.dart';
import '../../widgets/blur_background.dart';
import '../../widgets/rounded_search_bar.dart';
import '../../widgets/segmented_switcher.dart';
import '../../widgets/event_card/live_event_card.dart';
import '../../widgets/event_card/completed_event_card.dart';
import '../../widgets/event_card/upcoming_event_card.dart';
import '../../widgets/hamburger_menu.dart';
import 'providers/tournament_provider.dart';

// Create providers for UI state
final searchQueryProvider = StateProvider<String>((ref) => '');
final selectedTabIndexProvider = StateProvider<int>((ref) => 0);

// Provider for filtered tournaments
final filteredTournamentsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final tournamentNotifier = ref.watch(tournamentNotifierProvider.notifier);
  final searchQuery = ref.watch(searchQueryProvider);
  final isUpcomingTab = ref.watch(selectedTabIndexProvider) == 1;

  return tournamentNotifier.getFilteredTournaments(searchQuery, isUpcomingTab);
});

class TournamentScreen extends ConsumerWidget {
  const TournamentScreen({super.key});

  // Add a global key for the Scaffold
  static final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = TextEditingController();
    final selectedTabIndex = ref.watch(selectedTabIndexProvider);
    final tournamentAsync = ref.watch(tournamentNotifierProvider);


    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kBackgroundColor,
      drawer: const HamburgerMenu(),
      // appBar: AppBar(
      //   backgroundColor: Colors.transparent,
      //   elevation: 0,
      //   title: const Text(
      //     'Tournaments',
      //     style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      //   ),
      // ),
      body: Stack(
        children: [
          const BlurBackground(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Add top padding
              SizedBox(height: 48 + MediaQuery.of(context).viewPadding.top),
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: RoundedSearchBar(
                  controller: searchController,
                  hintText: 'Search tournaments or players',
                  onChanged: (value) {
                    ref.read(searchQueryProvider.notifier).state = value;
                  },
                  onFilterTap: () {
                    // Show filter popup
                  },
                  onProfileTap: () {
                    // Open hamburger menu drawer using the static _scaffoldKey
                    _scaffoldKey.currentState?.openDrawer();
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Segmented switcher for "All Events" and "Upcoming Events"
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: SegmentedSwitcher(
                  options: const ['All Events', 'Upcoming Events'],
                  initialSelection: selectedTabIndex,
                  onSelectionChanged: (index) {
                    ref.read(selectedTabIndexProvider.notifier).state = index;
                  },
                ),
              ),

              const SizedBox(height: 12),
              // Tournament list
              Expanded(
                child: tournamentAsync.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (error, stack) => Center(
                        child: Text(
                          'Error loading tournaments: $error',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                  data:
                      (_) =>
                          selectedTabIndex == 0
                              ? const AllEventsTabWidget()
                              : const UpcomingEventsTabWidget(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: AppTypography.textMdBold.copyWith(color: Colors.white),
      ),
    );
  }
}

class AllEventsTabWidget extends ConsumerWidget {
  const AllEventsTabWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredEvents = ref.watch(filteredTournamentsProvider);

    if (filteredEvents.isEmpty) {
      return const Center(
        child: Text(
          'No tournaments found',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      itemCount: filteredEvents.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final event = filteredEvents[index];
        final type = event['type'] as String;

        if (type == 'live') {
          return LiveEventCard(
            title: event['title'] as String,
            dates: event['dates'] as String,
            location: event['location'] as String,
            playerCount: event['playerCount'] as int,
            elo: event['elo'] as int,
            onTap: () {
              // Navigate to event details
            },
          );
        } else {
          return CompletedEventCard(
            title: event['title'] as String,
            dates: event['dates'] as String,
            location: event['location'] as String,
            playerCount: event['playerCount'] as int,
            elo: event['elo'] as int,
            onTap: () {
              // Navigate to event details
            },
            onDownloadTournament: () {
              // Download tournament
            },
            onAddToLibrary: () {
              // Add to library
            },
          );
        }
      },
    );
  }
}

class UpcomingEventsTabWidget extends ConsumerWidget {
  const UpcomingEventsTabWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredEvents = ref.watch(filteredTournamentsProvider);

    if (filteredEvents.isEmpty) {
      return const Center(
        child: Text(
          'No upcoming tournaments found',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      itemCount: filteredEvents.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final event = filteredEvents[index];
        return UpcomingEventCard(
          title: event['title'] as String,
          dates: event['dates'] as String,
          location: event['location'] as String,
          playerCount: event['playerCount'] as int,
          elo: event['elo'] as int,
          timeUntilStart: event['timeUntilStart'] as String,
          onTap: () {
            // Navigate to event details
          },
        );
      },
    );
  }
}

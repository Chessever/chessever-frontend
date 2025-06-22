import 'package:chessever2/screens/home_screen.dart';
import 'package:chessever2/screens/tournaments/providers/tournament_screen_provider.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../widgets/rounded_search_bar.dart';
import '../../widgets/segmented_switcher.dart';
import '../../widgets/event_card/completed_event_card.dart';

enum TournamentCategory { all, upcoming }

final _mappedName = {
  TournamentCategory.all: 'All Events',
  TournamentCategory.upcoming: 'Upcoming Events',
};

final selectedTourEventProvider = StateProvider<TournamentCategory>(
  (ref) => TournamentCategory.all,
);

class TournamentScreen extends HookConsumerWidget {
  const TournamentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final selectedTourEvent = ref.watch(selectedTourEventProvider);
    return Material(
      color: kBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Add top padding
          SizedBox(height: 24 + MediaQuery.of(context).viewPadding.top),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Hero(
              tag: 'search_bar',
              child: RoundedSearchBar(
                profileInitials: 'Vi'.substring(0, 2),
                controller: searchController,
                hintText: 'Search tournaments or players',
                onChanged: (value) {
                  ref
                      .read(tournamentNotifierProvider.notifier)
                      .searchForTournament(value, selectedTourEvent);
                },
                onFilterTap: () {
                  // Show filter popup
                },
                onProfileTap: () {
                  // Open hamburger menu drawer using the static _scaffoldKey
                  HomeScreen.scaffoldKey.currentState?.openDrawer();
                },
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Segmented switcher for "All Events" and "Upcoming Events"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: SegmentedSwitcher(
              options: _mappedName.values.toList(),
              initialSelection: _mappedName.values.toList().indexOf(
                _mappedName[selectedTourEvent]!,
              ),
              onSelectionChanged: (index) {
                ref.read(selectedTourEventProvider.notifier).state =
                    TournamentCategory.values[index];
              },
            ),
          ),

          const SizedBox(height: 12),

          // Tournament list
          Expanded(
            child: ref
                .watch(tournamentNotifierProvider)
                .when(
                  data: (filteredEvents) {
                    return AllEventsTabWidget(filteredEvents: filteredEvents);
                  },
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (error, stackTrace) =>
                          Center(child: Text('Error: $error')),
                ),
          ),
        ],
      ),
    );
  }
}

class AllEventsTabWidget extends ConsumerWidget {
  const AllEventsTabWidget({required this.filteredEvents, super.key});

  final List<TourEventCardModel> filteredEvents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (filteredEvents.isEmpty) {
      return const Center(
        child: Text(
          'No tournaments found',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(
        left: 20.0,
        right: 20,
        bottom: MediaQuery.of(context).viewPadding.bottom + 12,
      ),
      itemCount: filteredEvents.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final tourEventCardModel = filteredEvents[index];

        switch (tourEventCardModel.tourEventCategory) {
          case TourEventCategory.live:
            return EventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () {
                ref
                    .read(tournamentNotifierProvider.notifier)
                    .onSelectTournament(
                      context: context,
                      id: tourEventCardModel.id,
                    );
              },
            );
          case TourEventCategory.upcoming:
            return EventCard(
              tourEventCardModel: tourEventCardModel,
              //todo:
              onTap: () {
                ref
                    .read(tournamentNotifierProvider.notifier)
                    .onSelectTournament(
                      context: context,
                      id: tourEventCardModel.id,
                    );
              },
            );
          case TourEventCategory.completed:
            return CompletedEventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () {
                ref
                    .read(tournamentNotifierProvider.notifier)
                    .onSelectTournament(
                      context: context,
                      id: tourEventCardModel.id,
                    );
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

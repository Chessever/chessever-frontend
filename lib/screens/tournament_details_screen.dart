import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/favorites/tournament_favorites_provider.dart';

class TournamentDetailsScreen extends ConsumerWidget {
  const TournamentDetailsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get the arguments passed from the calendar screen
    final Map<String, dynamic> args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
        {'month': 'May', 'year': 2025}; // Default values if no args passed

    final String month = args['month'] as String;
    final int year = args['year'] as int;

    // Watch the tournament favorites provider
    final tournamentFavoritesAsync = ref.watch(
      tournamentFavoritesNotifierProvider,
    );

    return SizedBox();

    // return Scaffold(
    //   backgroundColor: Colors.black,
    //   body: SafeArea(
    //     child: Padding(
    //       padding: const EdgeInsets.symmetric(horizontal: 16.0),
    //       child: Column(
    //         crossAxisAlignment: CrossAxisAlignment.start,
    //         children: [
    //           const SizedBox(height: 33),
    //           // Search bar
    //           SimpleSearchBar(
    //             controller: TextEditingController(),
    //             hintText: 'Search tournaments or players',
    //             onChanged: (value) {
    //               // Handle search
    //             },
    //             onFilterTap: () {
    //               // Show filter popup
    //               showDialog(
    //                 context: context,
    //                 builder: (BuildContext context) {
    //                   return const FilterPopup();
    //                 },
    //               );
    //             },
    //             onMenuTap: () {
    //               // Handle menu tap
    //             },
    //           ),
    //           const SizedBox(height: 33),
    //           // Title - Tournaments in Month Year
    //           Text(
    //             'Tournaments in $month $year',
    //             style: AppTypography.displayXsMedium.copyWith(
    //               color: kWhiteColor,
    //               fontWeight: FontWeight.w600,
    //             ),
    //           ),
    //           const SizedBox(height: 20),
    //           // List of tournaments
    //           Expanded(
    //             child: tournamentFavoritesAsync.when(
    //               loading:
    //                   () => const Center(child: CircularProgressIndicator()),
    //               error:
    //                   (error, stack) => Center(
    //                     child: Text(
    //                       'Error loading favorites: $error',
    //                       style: const TextStyle(color: Colors.white),
    //                     ),
    //                   ),
    //               data: (favoriteTournaments) {
    //                 // Create a map for quick lookup of starred_repository status
    //                 final favoritesMap = {
    //                   for (var tournament in favoriteTournaments)
    //                     tournament.title: true,
    //                 };
    //
    //                 return ListView(
    //                   children: [
    //                     // All tournaments in a single list without section headers
    //                     CompletedEventCard(
    //                       title: 'Polish Chess Championship 2025',
    //                       dates: 'May 5-12, 2025',
    //                       location: 'Warsaw',
    //                       playerCount: 12,
    //                       elo: 2590,
    //                       onTap: () {
    //                         // Navigate to tournament details
    //                       },
    //                       onDownloadTournament: () {
    //                         // Download tournament PGN
    //                       },
    //                       onAddToLibrary: () {
    //                         // Add to library
    //                       },
    //                     ),
    //                     const SizedBox(height: 24),
    //                     CompletedEventCard(
    //                       title: 'Women World Chess Championship 2025',
    //                       dates: 'May 8-20, 2025',
    //                       location: 'China',
    //                       playerCount: 2,
    //                       elo: 2590,
    //                       onTap: () {
    //                         // Navigate to tournament details
    //                       },
    //                       onDownloadTournament: () {
    //                         // Download tournament PGN
    //                       },
    //                       onAddToLibrary: () {
    //                         // Add to library
    //                       },
    //                     ),
    //                     const SizedBox(height: 24),
    //                     LiveEventCard(
    //                       title: 'European Championship 2025',
    //                       dates: 'May 15-25, 2025',
    //                       location: 'Prague',
    //                       playerCount: 8,
    //                       elo: 2680,
    //                       isFavorite:
    //                           favoritesMap['European Championship 2025'] ??
    //                           false,
    //                       onTap: () {
    //                         // Navigate to tournament details
    //                       },
    //                       onFavoriteToggle: () {
    //                         _toggleFavorite(
    //                           ref,
    //                           'European Championship 2025',
    //                           'May 15-25, 2025',
    //                           'Prague',
    //                           8,
    //                           2680,
    //                         );
    //                       },
    //                     ),
    //                     const SizedBox(height: 24),
    //                     UpcomingEventCard(
    //                       title: 'Superbet Championship 2025',
    //                       dates: 'May 26-30, 2025',
    //                       location: 'Warsaw',
    //                       playerCount: 12,
    //                       elo: 2590,
    //                       timeUntilStart: 'Starts in 3 days',
    //                       isFavorite:
    //                           favoritesMap['Superbet Championship 2025'] ??
    //                           false,
    //                       onTap: () {
    //                         // Navigate to tournament details
    //                       },
    //                       onAddToFavorites: () {
    //                         _toggleFavorite(
    //                           ref,
    //                           'Superbet Championship 2025',
    //                           'May 26-30, 2025',
    //                           'Warsaw',
    //                           12,
    //                           2590,
    //                         );
    //                       },
    //                     ),
    //                     const SizedBox(height: 24),
    //                     UpcomingEventCard(
    //                       title: 'Dutch Chess Championship 2025',
    //                       dates: 'May 26-30, 2025',
    //                       location: 'Amsterdam',
    //                       playerCount: 12,
    //                       elo: 2590,
    //                       timeUntilStart: 'Starts in 9 days',
    //                       isFavorite:
    //                           favoritesMap['Dutch Chess Championship 2025'] ??
    //                           false,
    //                       onTap: () {
    //                         // Navigate to tournament details
    //                       },
    //                       onAddToFavorites: () {
    //                         _toggleFavorite(
    //                           ref,
    //                           'Dutch Chess Championship 2025',
    //                           'May 26-30, 2025',
    //                           'Amsterdam',
    //                           12,
    //                           2590,
    //                         );
    //                       },
    //                     ),
    //                     const SizedBox(height: 24),
    //                     UpcomingEventCard(
    //                       title: 'Qatar Masters',
    //                       dates: 'May 26-June 5, 2025',
    //                       location: 'Doha',
    //                       playerCount: 12,
    //                       elo: 2590,
    //                       timeUntilStart: 'Starts in 27 days',
    //                       isFavorite: favoritesMap['Qatar Masters'] ?? false,
    //                       onTap: () {
    //                         // Navigate to tournament details
    //                       },
    //                       onAddToFavorites: () {
    //                         _toggleFavorite(
    //                           ref,
    //                           'Qatar Masters',
    //                           'May 26-June 5, 2025',
    //                           'Doha',
    //                           12,
    //                           2590,
    //                         );
    //                       },
    //                     ),
    //                   ],
    //                 );
    //               },
    //             ),
    //           ),
    //         ],
    //       ),
    //     ),
    //   ),
    // );
  }

  void _toggleFavorite(
    WidgetRef ref,
    String title,
    String dates,
    String location,
    int playerCount,
    int elo,
  ) {
    final tournament = Tournament(
      title: title,
      dates: dates,
      location: location,
      playerCount: playerCount,
      elo: elo,
    );

    ref
        .read(tournamentFavoritesNotifierProvider.notifier)
        .toggleFavorite(tournament);
  }
}

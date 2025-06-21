import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../widgets/rounded_search_bar.dart';
import '../widgets/blur_background.dart';
import '../widgets/event_card/completed_event_card.dart';
import '../widgets/country_dropdown.dart';
import '../widgets/hamburger_menu/hamburger_menu.dart';

class ChesseverScreen extends ConsumerWidget {
  const ChesseverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
    final TextEditingController searchController = TextEditingController();
    return SizedBox();

    // return Scaffold(
    //   key: scaffoldKey,
    //   drawer: HamburgerMenu(
    //     onSettingsPressed: () {
    //       Navigator.pop(context);
    //     },
    //     onPlayersPressed: () {
    //       Navigator.pop(context);
    //       Navigator.pushNamed(context, '/playerList');
    //     },
    //     onFavoritesPressed: () {
    //       Navigator.pop(context);
    //       Navigator.pushNamed(context, '/favorites');
    //     },
    //     onCountrymanPressed: () {
    //       Navigator.pop(context);
    //       Navigator.pushNamed(context, '/countryman_screen');
    //     },
    //     onAnalysisBoardPressed: () {
    //       Navigator.pop(context);
    //       // Add your analysis board navigation logic here
    //     },
    //     onSupportPressed: () {
    //       Navigator.pop(context);
    //       // Add your support navigation logic here
    //     },
    //     onPremiumPressed: () {
    //       Navigator.pop(context);
    //       // Add your premium navigation logic here
    //     },
    //     onLogoutPressed: () {
    //       Navigator.pop(context);
    //       // Add your logout logic here
    //     },
    //   ),
    //   appBar: AppBar(
    //     backgroundColor: Colors.transparent,
    //     elevation: 0,
    //     leading: IconButton(
    //       icon: const Icon(Icons.menu, color: Colors.white),
    //       onPressed: () {
    //         scaffoldKey.currentState?.openDrawer();
    //       },
    //     ),
    //     title: const Text(
    //       'Tournaments',
    //       style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    //     ),
    //   ),
    //   body: Stack(
    //     children: [
    //       const BlurBackground(),
    //       SafeArea(
    //         child: SingleChildScrollView(
    //           child: Column(
    //             children: [
    //               const SizedBox(height: 16),
    //               // Add search bar at the top of the content
    //               Padding(
    //                 padding: const EdgeInsets.symmetric(horizontal: 16.0),
    //                 child: RoundedSearchBar(
    //                   controller: searchController,
    //                   onChanged: (value) {
    //                     // Handle search query
    //                     print('Search query: $value');
    //                   },
    //                   hintText: 'Search tournaments or players',
    //                   onFilterTap: () {
    //                     // Show filter options
    //                     ScaffoldMessenger.of(context).showSnackBar(
    //                       const SnackBar(
    //                         content: Text("Filter options"),
    //                         duration: Duration(seconds: 1),
    //                       ),
    //                     );
    //                   },
    //                   onProfileTap: () {
    //                     // Open hamburger menu drawer
    //                     scaffoldKey.currentState?.openDrawer();
    //                   },
    //                   profileInitials: "VD", // Match what's shown in the design
    //                 ),
    //               ),
    //               const SizedBox(height: 16),
    //               LiveEventCard(
    //                 title: 'Norway Chess 2025',
    //                 dates: 'Feb 27-29, 2025',
    //                 location: 'Netherlands',
    //                 playerCount: 12,
    //                 elo: 2714,
    //               ),
    //               CompletedEventCard(
    //                 title: "Candidates Chess Tournament 2026",
    //                 dates: "April 18 - May 6, 2025",
    //                 location: "Spain",
    //                 playerCount: 8,
    //                 elo: 2720,
    //                 onDownloadTournament: () {
    //                   ScaffoldMessenger.of(context).showSnackBar(
    //                     const SnackBar(
    //                       content: Text("Downloading tournaments PGN..."),
    //                     ),
    //                   );
    //                 },
    //                 onAddToLibrary: () {
    //                   ScaffoldMessenger.of(context).showSnackBar(
    //                     const SnackBar(content: Text("Added to library")),
    //                   );
    //                 },
    //               ),
    //               UpcomingEventCard(
    //                 title: 'World Rapid Championship 2025',
    //                 dates: 'March 15-17, 2025',
    //                 location: 'Germany',
    //                 playerCount: 16,
    //                 elo: 2690,
    //                 timeUntilStart: 'In 2 weeks',
    //                 onTap: () {
    //                   ScaffoldMessenger.of(context).showSnackBar(
    //                     const SnackBar(content: Text("Tapped on event")),
    //                   );
    //                 },
    //                 isFavorite: true,
    //                 onAddToFavorites: () {
    //                   ScaffoldMessenger.of(context).showSnackBar(
    //                     const SnackBar(content: Text("Added to favorites")),
    //                   );
    //                 },
    //               ),
    //
    //               // Button to navigate to the new Tournament Screen
    //               Padding(
    //                 padding: const EdgeInsets.all(16.0),
    //                 child: ElevatedButton(
    //                   onPressed: () {
    //                     Navigator.pushNamed(context, '/tournament_screen');
    //                   },
    //                   style: ElevatedButton.styleFrom(
    //                     backgroundColor: const Color(0xFF0FB4E5),
    //                     minimumSize: const Size(double.infinity, 48),
    //                     shape: RoundedRectangleBorder(
    //                       borderRadius: BorderRadius.circular(8),
    //                     ),
    //                   ),
    //                   child: const Text(
    //                     'View All Tournaments',
    //                     style: TextStyle(
    //                       color: Colors.white,
    //                       fontWeight: FontWeight.bold,
    //                     ),
    //                   ),
    //                 ),
    //               ),
    //
    //               Padding(
    //                 padding: EdgeInsets.symmetric(horizontal: 12),
    //                 child: CountryDropdown(
    //                   selectedCountryCode: 'US',
    //                   onChanged: (value) {},
    //                 ),
    //               ),
    //               SizedBox(height: 24),
    //             ],
    //           ),
    //         ),
    //       ),
    //     ],
    //   ),
    // );
  }

  Widget _buildSearchSheet(
    BuildContext context,
    TextEditingController controller,
  ) {
    // Access the global scaffold through context instead of using scaffoldKey
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Column(
            children: [
              // Handle indicator
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: RoundedSearchBar(
                  controller: controller,
                  onChanged: (value) {
                    // Handle search query
                    print('Searching for: $value');
                  },
                  autofocus: true,
                  onProfileTap: () {
                    // Open hamburger menu drawer
                    Navigator.pop(context); // Close the search sheet first
                    // Use Scaffold.of(context) instead of scaffoldKey
                    Scaffold.of(context).openDrawer();
                  },
                  profileInitials: "VD", // Match the main search bar
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: 20,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text('Search Result ${index + 1}'),
                      subtitle: Text('Sample result description'),
                      leading: const Icon(Icons.event),
                      onTap: () {
                        Navigator.pop(context);
                        // Handle selection
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Selected result ${index + 1}'),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../widgets/rounded_search_bar.dart';
import '../widgets/blur_background.dart';
import '../widgets/completed_event_card.dart';
import '../widgets/country_dropdown.dart';
import '../widgets/hamburger_menu.dart';
import '../widgets/live_event_card.dart';

class ChesseverScreen extends ConsumerWidget {
  const ChesseverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
    final TextEditingController searchController = TextEditingController();

    return Scaffold(
      key: scaffoldKey,
      drawer: HamburgerMenu(
        onSettingsPressed: () {
          Navigator.pop(context);
          Navigator.pushNamed(context, '/settings');
        },
        onPlayersPressed: () {
          Navigator.pop(context);
          // Add your players navigation logic here
        },
        onFavoritesPressed: () {
          Navigator.pop(context);
          // Add your favorites navigation logic here
        },
        onCountrymanPressed: () {
          Navigator.pop(context);
          // Add your countryman navigation logic here
        },
        onAnalysisBoardPressed: () {
          Navigator.pop(context);
          // Add your analysis board navigation logic here
        },
        onSupportPressed: () {
          Navigator.pop(context);
          // Add your support navigation logic here
        },
        onPremiumPressed: () {
          Navigator.pop(context);
          // Add your premium navigation logic here
        },
        onLogoutPressed: () {
          Navigator.pop(context);
          // Add your logout logic here
        },
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {
            scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: const Text(
          'ChessEver',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              // Show search bar dialog/sheet
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder:
                    (context) => _buildSearchSheet(context, searchController),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const BlurBackground(),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  // Add search bar at the top of the content
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: RoundedSearchBar(
                      controller: searchController,
                      onChanged: (value) {
                        // Handle search query
                        print('Search query: $value');
                      },
                      hintText: 'Search tournaments or players',
                      onFilterTap: () {
                        // Show filter options
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Filter options"),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      onProfileTap: () {
                        // Handle profile tap
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Profile selected"),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      profileInitials:
                          "VD", // You can customize this or get it from user data
                    ),
                  ),
                  const SizedBox(height: 16),
                  LiveEventCard(
                    title: 'Norway Chess 2025',
                    dates: 'Feb 27-29, 2025',
                    location: 'Netherlands',
                    playerCount: 12,
                    elo: 2714,
                  ),
                  CompletedEventCard(
                    title: "Candidates Chess Tournament 2026",
                    dates: "April 18 - May 6, 2025",
                    location: "Spain",
                    playerCount: 8,
                    elo: 2720,
                    onDownloadTournament: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Downloading tournament PGN..."),
                        ),
                      );
                    },
                    onAddToLibrary: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Added to library")),
                      );
                    },
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: CountryDropdown(onChanged: (value) {}),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSheet(
    BuildContext context,
    TextEditingController controller,
  ) {
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
                    // Handle profile tap in search sheet
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Profile selected from search"),
                        duration: Duration(seconds: 1),
                      ),
                    );
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

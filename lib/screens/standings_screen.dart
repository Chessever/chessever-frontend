import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/standings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/standing_score_card.dart';
import '../utils/app_typography.dart';
import '../widgets/segmented_switcher.dart';
import '../widgets/round_selector.dart';

class StandingsScreen extends ConsumerStatefulWidget {
  const StandingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends ConsumerState<StandingsScreen> {
  int _selectedTabIndex = 2; // Starting with "Standings" selected (index 2)
  bool _isLoading = false;

  // Tab options
  final List<String> _tabOptions = ['About', 'Games', 'Standings'];

  // Handle tab changes
  void _handleTabChange(int index) {
    setState(() {
      _selectedTabIndex = index;
    });
  }

  // Handle round selection
  void _handleRoundSelection(int round) async {
    // Update the current round provider
    ref.read(currentRoundProvider.notifier).state = round;

    // Set loading state
    setState(() {
      _isLoading = true;
    });

    // Fetch data for the selected round
    await ref.read(standingsProvider.notifier).loadStandingsForRound(round);

    // Clear loading state
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get data from providers
    final currentRound = ref.watch(currentRoundProvider);
    final totalRounds = ref.watch(totalRoundsProvider);
    final playerStandings = ref.watch(standingsProvider);

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        backgroundColor: kBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: true,
        centerTitle: true,
        title: Column(
          children: [
            // Round selector with correct dimensions
            RoundSelector(
              currentRound: currentRound,
              totalRounds: totalRounds,
              onRoundSelected: _handleRoundSelection,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              // Segmented switcher
              SegmentedSwitcher(
                options: _tabOptions,
                initialSelection: _selectedTabIndex,
                onSelectionChanged: _handleTabChange,
                backgroundColor: kBlack2Color,
                selectedBackgroundColor: kBlack2Color,
                textColor: kInactiveTabColor,
                selectedTextColor: kWhiteColor,
                borderRadius: 12.0,
              ),
              const SizedBox(height: 19),
              // Standings header
              // In your StandingsScreen, replace the header section with this:

              // Standings header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                ), // Match ScoreCard padding
                child: Row(
                  children: [
                    // Player column (matches Expanded in ScoreCard)
                    Expanded(
                      child: Text(
                        'Player',
                        style: AppTypography.textSmMedium.copyWith(
                          color: kWhiteColor,
                        ),
                      ),
                    ),
                    // Elo column (matches ScoreCard width of 100)
                    SizedBox(
                      width: 100,
                      child: Text(
                        'Elo',
                        style: AppTypography.textSmMedium.copyWith(
                          color: kWhiteColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Score column (matches ScoreCard width of 60)
                    SizedBox(
                      width: 60,
                      child: Text(
                        'Score',
                        style: AppTypography.textSmMedium.copyWith(
                          color: kWhiteColor,
                        ),
                        textAlign: TextAlign.end, // Match ScoreCard's textAlign
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 23),
              // List of players with score cards
              Expanded(
                child:
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : playerStandings.isEmpty
                        ? const Center(
                          child: Text(
                            'No data available',
                            style: TextStyle(color: kWhiteColor),
                          ),
                        )
                        : ListView.builder(
                          itemCount: playerStandings.length,
                          itemBuilder: (context, index) {
                            final player = playerStandings[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: ScoreCard(
                                countryCode: player.countryCode,
                                title: player.title,
                                name: player.name,
                                score: player.score,
                                scoreChange: player.scoreChange,
                                matchScore: player.matchScore,
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

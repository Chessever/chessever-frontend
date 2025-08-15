import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SearchOverlay extends ConsumerWidget {
  final String query;
  final Function(TourEventCardModel) onTournamentTap;

  const SearchOverlay({
    super.key,
    required this.query,
    required this.onTournamentTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FutureBuilder<EnhancedSearchResult>(
          future: ref
              .read(groupBroadcastLocalStorage(TournamentCategory.current))
              .searchWithScoring(query),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingState();
            }

            final searchResult =
                snapshot.data ??
                const EnhancedSearchResult(
                  tournamentResults: [],
                  playerResults: [],
                );

            if (searchResult.tournamentResults.isEmpty &&
                searchResult.playerResults.isEmpty) {
              return _buildEmptyState();
            }

            return _buildSearchResults(searchResult);
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      height: 300,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              strokeWidth: 2,
            ),
            SizedBox(height: 16),
            Text(
              'Searching...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try different keywords for "$query"',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(EnhancedSearchResult searchResult) {
    final hasTournaments = searchResult.tournamentResults.isNotEmpty;
    final hasPlayers = searchResult.playerResults.isNotEmpty;

    return Container(
      height: 400,
      child: Column(
        children: [
          // Header with search stats
          _buildHeader(searchResult),

          Expanded(
            child:
                hasTournaments && hasPlayers
                    ? _buildTwoColumnLayout(searchResult)
                    : _buildSingleColumnLayout(searchResult),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(EnhancedSearchResult searchResult) {
    final totalResults =
        searchResult.tournamentResults.length +
        searchResult.playerResults.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 16,
            color: Colors.blue,
          ),
          const SizedBox(width: 8),
          Text(
            '$totalResults result${totalResults != 1 ? 's' : ''} for "$query"',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTwoColumnLayout(EnhancedSearchResult searchResult) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tournament Results Column
        Expanded(
          child: _buildResultColumn(
            title: 'Tournaments',
            count: searchResult.tournamentResults.length,
            results: searchResult.tournamentResults,
            icon: Icons.emoji_events,
          ),
        ),

        // Divider
        Container(
          width: 1,
          color: Colors.white.withOpacity(0.1),
        ),

        // Player Results Column
        Expanded(
          child: _buildResultColumn(
            title: 'Players',
            count: searchResult.playerResults.length,
            results: searchResult.playerResults,
            icon: Icons.person,
          ),
        ),
      ],
    );
  }

  Widget _buildSingleColumnLayout(EnhancedSearchResult searchResult) {
    final hasTournaments = searchResult.tournamentResults.isNotEmpty;
    final results =
        hasTournaments
            ? searchResult.tournamentResults
            : searchResult.playerResults;
    final title = hasTournaments ? 'Tournaments' : 'Players';
    final icon = hasTournaments ? Icons.emoji_events : Icons.person;

    return _buildResultColumn(
      title: title,
      count: results.length,
      results: results,
      icon: icon,
      isFullWidth: true,
    );
  }

  Widget _buildResultColumn({
    required String title,
    required int count,
    required List<SearchResult> results,
    required IconData icon,
    bool isFullWidth = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: Colors.blue,
              ),
              const SizedBox(width: 8),
              Text(
                '$title ($count)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: results.length,
            itemBuilder: (context, index) {
              return AnimatedContainer(
                duration: Duration(milliseconds: 100 + (index * 50)),
                child: _SearchResultTile(
                  result: results[index],
                  onTap: () => onTournamentTap(results[index].tournament),
                  isFullWidth: isFullWidth,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchResultTile extends StatefulWidget {
  final SearchResult result;
  final VoidCallback onTap;
  final bool isFullWidth;

  const _SearchResultTile({
    required this.result,
    required this.onTap,
    this.isFullWidth = false,
  });

  @override
  State<_SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<_SearchResultTile>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      _isHovered
                          ? Colors.white.withOpacity(0.05)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        _isHovered
                            ? Colors.blue.withOpacity(0.3)
                            : Colors.transparent,
                  ),
                ),
                child: _buildContent(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tournament title
        Text(
          widget.result.tournament.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        // Player match info (if applicable)
        if (widget.result.type == SearchResultType.player) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Player: ${widget.result.matchedText}',
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],

        const SizedBox(height: 8),

        // Bottom row with date and score
        if (widget.result.tournament.dates.isNotEmpty)
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 12,
                color: Colors.grey[400],
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.result.tournament.dates,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Match score badge
              if (kDebugMode)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.withOpacity(0.8),
                        Colors.purple.withOpacity(0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${widget.result.score.toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

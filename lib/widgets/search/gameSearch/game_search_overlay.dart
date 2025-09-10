// Games Search Overlay Widget
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesSearchOverlay extends ConsumerWidget {
  final String query;
  final Function(Games game) onGameTap;

  const GamesSearchOverlay({
    super.key,
    required this.query,
    required this.onGameTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTourId =
        ref.watch(tourDetailScreenProvider).value?.aboutTourModel.id;

    if (selectedTourId == null) {
      return _buildErrorState('No tournament selected');
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<EnhancedGameSearchResult>(
          future: ref
              .read(gamesLocalStorage)
              .searchGamesWithScoring(tourId: selectedTourId, query: query),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingState();
            }

            final searchResult =
                snapshot.data ?? const EnhancedGameSearchResult(results: []);

            if (searchResult.results.isEmpty) {
              return _buildEmptyState();
            }

            return _buildSearchResults(searchResult.results);
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      height: 200,
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
              'Searching games...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 150,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 40, color: Colors.grey[600]),
            const SizedBox(height: 12),
            const Text(
              'No games found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try different keywords for "$query"',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20),
      height: 100,
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: Colors.red, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildSearchResults(List<GameSearchResult> results) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: results.length,
        itemBuilder: (context, index) {
          return AnimatedContainer(
            duration: Duration(milliseconds: 100 + (index * 50)),
            child: _GameSearchResultTile(
              result: results[index],
              onTap: () => onGameTap(results[index].game),
            ),
          );
        },
      ),
    );
  }
}

// Game Search Result Tile Widget
class _GameSearchResultTile extends StatefulWidget {
  final GameSearchResult result;
  final VoidCallback onTap;

  const _GameSearchResultTile({
    required this.result,
    required this.onTap,
  });

  @override
  State<_GameSearchResultTile> createState() => _GameSearchResultTileState();
}

class _GameSearchResultTileState extends State<_GameSearchResultTile>
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
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.result.game;
    final playerNames =
        game.players
            ?.map((p) => p.name)
            .where((name) => name != null)
            .join(' vs ') ??
        'Unknown players';

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Player names
                    Text(
                      playerNames,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Divider(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

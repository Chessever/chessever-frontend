import 'package:chessever2/models/tournament.dart';
import 'package:flutter/material.dart';
import '../models/game.dart';
import '../services/lichess_api_service.dart';
import '../widgets/searchable_list_layout.dart';
import 'in_game_view.dart';

class GameListView extends StatefulWidget {
  final Tournament tournament;

  const GameListView({super.key, required this.tournament});

  @override
  State<GameListView> createState() => _GameListViewState();
}

class _GameListViewState extends State<GameListView> {
  final TextEditingController _searchController = TextEditingController();
  final LichessApiService _apiService = LichessApiService.instance;

  late Future<List<BroadcastGame>> _gamesFuture;
  List<BroadcastGame> _allGames = [];
  List<BroadcastGame> _filteredGames = [];

  @override
  void initState() {
    super.initState();
    _gamesFuture = _fetchAndSetGames();
    _searchController.addListener(_filterGames);
  }

  Future<List<BroadcastGame>> _fetchAndSetGames() async {
    try {
      final games = await _apiService.fetchBroadcastRoundGames(widget.tournament.slug, widget.tournament.rounds[0].slug, widget.tournament.rounds[0].id);
      _allGames = games;
      _updateFilteredList();
      return games;
    } catch (e) {
      debugPrint('Error fetching games: $e');
      rethrow;
    }
  }

  void _updateFilteredList() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      _filteredGames = List.from(_allGames);
    } else {
      _filteredGames = _allGames.where((game) {
        final whiteMatch = game.players[0].toLowerCase().contains(query);
        final blackMatch = game.players[1].toLowerCase().contains(query);
        return whiteMatch || blackMatch;
      }).toList();
    }
  }

  void _filterGames() {
    setState(_updateFilteredList);
  }

  void _refreshGames() {
    setState(() {
      _gamesFuture = _fetchAndSetGames();
      _searchController.clear();
    });
  }

  void _navigateToGameView(BroadcastGame game) {
    if (game.fen.isNotEmpty) {
      final detailedGame = DetailedGame(broadcastGame: game);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => InGameView(game: detailedGame)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game data incomplete or not started.')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tournament.name),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshGames),
        ],
      ),
      body: FutureBuilder<List<BroadcastGame>>(
        future: _gamesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Error loading games.'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _refreshGames,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No games found.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _refreshGames,
                    child: const Text('Refresh'),
                  ),
                ],
              ),
            );
          } else {
            return SearchableListViewLayout<BroadcastGame>(
              searchController: _searchController,
              onSearchChanged: (_) => _filterGames(),
              searchHintText: 'Search Games by Player Name…',
              items: _filteredGames,
              itemBuilder: (context, index, game) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      title: Text('${game.players[0]} vs ${game.players[1]}'),
                    ),
                    FutureBuilder<String>(
                      future: game.evaluation.evalString,
                      builder: (ctx, snap) {
                        final isReady =
                            snap.connectionState == ConnectionState.done && !snap.hasError;
                        final rawEval =
                            isReady ? double.tryParse(snap.data!) ?? 0 : null;
                        const double maxCp = 7;
                        final normalized = isReady
                            ? ((rawEval! + maxCp) / (2 * maxCp)).clamp(0.0, 1.0)
                            : 0.5;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 4,
                              child: LinearProgressIndicator(
                                value: normalized,
                                backgroundColor: Colors.black,
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isReady
                                  ? '${rawEval!.toStringAsFixed(2)}'
                                  : '–',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        );
                      },
                    ),
                    const Divider(height: 1),
                  ],
                );
              },
              onItemTap: _navigateToGameView,
            );
          }
        },
      ),
    );
  }
}

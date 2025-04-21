// lib/views/game_list_view.dart
import 'package:chessever2/models/tournament.dart';
import 'package:flutter/material.dart';
import '../models/game.dart';
import '../services/lichess_api_service.dart';
import '../widgets/searchable_list_layout.dart';
import 'in_game_view.dart';

class GameListView extends StatefulWidget {
  final Tournament tournament;
  // final String tournamentId;
  // final String tournamentName;
  // final String roundSlug;
  // final String roundID;
  // final bool isSwiss;

  const GameListView({
    super.key,
    required this.tournament
    // required this.tournamentId,
    // required this.tournamentName,
  });

  @override
  State<GameListView> createState() => _GameListViewState();
}

class _GameListViewState extends State<GameListView> {
  final TextEditingController _searchController = TextEditingController();
  final LichessApiService _apiService = LichessApiService();

  late Future<List<BroadcastGame>> _gamesFuture;
  List<BroadcastGame> _allGames = [];       // Initialized to empty list
  List<BroadcastGame> _filteredGames = [];  // Initialized to empty list

  @override
  void initState() {
    super.initState();
    _gamesFuture = _fetchAndSetGames();
    _searchController.addListener(_filterGames);
  }

  Future<List<BroadcastGame>> _fetchAndSetGames() async {
    try {
      final games = await _apiService.fetchBroadcastRoundGames(
        broadcastTournamentSlug:widget.tournament.slug,
        broadcastRoundSlug:widget.tournament.rounds[0].slug,
        broadcastRoundId:widget.tournament.rounds[0].id
      );
      _allGames = games;
      _updateFilteredList();
      return games;
    } catch (e) {
      print("Error fetching games: $e");
      rethrow;
    }
  }

  void _updateFilteredList() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      _filteredGames = List.from(_allGames);
    } else {
      _filteredGames = _allGames.where((game) {
        final whiteMatch = game.players[0]
            .toLowerCase()
            .contains(query);
        final blackMatch = game.players[1]
            .toLowerCase()
            .contains(query);
        // Use || for boolean OR
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
    // if (game.moves.isNotEmpty) {
    if (false) { // todo
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InGameView(game: game),
        ),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshGames,
          ),
        ],
      ),
      body: FutureBuilder<List<BroadcastGame>>(
        future: _gamesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            // Error state
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
            // No-data state
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
            // Data loaded, show searchable list
            return SearchableListViewLayout<BroadcastGame>(
              searchController: _searchController,
              onSearchChanged: (_) => _filterGames(),
              searchHintText: 'Search Games by Player Name…',
              items: _filteredGames,
              itemBuilder: (context, index, game) {
                return ListTile(
                  title: Text(game.players[0]),
                  // title: Text(game.playerVsText),
                  // trailing: Text(game.status),
                  trailing: Text(game.fen),
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

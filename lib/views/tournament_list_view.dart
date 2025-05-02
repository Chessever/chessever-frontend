import 'package:chessever2/views/game_list_view.dart';
import 'package:chessever2/views/in_tournament_view.dart';
import 'package:flutter/material.dart';
import '../models/tournament.dart';
import '../services/lichess_api_service.dart';
import '../widgets/searchable_list_layout.dart';

class TournamentListView extends StatefulWidget {
  const TournamentListView({super.key});

  @override
  State<TournamentListView> createState() => _TournamentListViewState();
}

class _TournamentListViewState extends State<TournamentListView>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final LichessApiService _apiService = LichessApiService.instance;

  late Future<Map<String, List<Tournament>>> _tournamentsFuture;
  late TabController _tabController;

  Map<String, List<Tournament>> _allTournaments = {};
  List<Tournament> _filteredTournaments = [];
  Set<String> _favoriteTournamentIds = {};

  static const _categories = ['upcoming', 'started', 'finished'];

  @override
  void initState() {
    super.initState();
    _tournamentsFuture = _fetchAndSetTournaments();
    _searchController.addListener(_filterTournaments);

    _tabController = TabController(length: _categories.length, vsync: this);
    _tabController.addListener(_filterTournaments);
  }

  Future<Map<String, List<Tournament>>> _fetchAndSetTournaments() async {
    try {
      final tournamentsByCategory = await _apiService.fetchBroadcasts();
      _allTournaments = tournamentsByCategory;
      _updateFilteredList();
      return tournamentsByCategory;
    } catch (e) {
      debugPrint('Error fetching tournaments: $e');
      rethrow;
    }
  }

  void _toggleFavorite(Tournament tournament) {
    setState(() {
      if (_favoriteTournamentIds.contains(tournament.id)) {
        _favoriteTournamentIds.remove(tournament.id);
      } else {
        _favoriteTournamentIds.add(tournament.id);
      }
      _updateFilteredList();
    });
  }

  void _updateFilteredList() {
    final query = _searchController.text.toLowerCase();
    final currentKey = _categories[_tabController.index];

    var list = List<Tournament>.from(_allTournaments[currentKey] ?? []);

    if (query.isNotEmpty) {
      list = list
          .where((t) => t.name.toLowerCase().contains(query))
          .toList();
    }

    list.sort((a, b) {
      final aFav = _favoriteTournamentIds.contains(a.id) ? 0 : 1;
      final bFav = _favoriteTournamentIds.contains(b.id) ? 0 : 1;
      return aFav.compareTo(bFav);
    });

    _filteredTournaments = list;
  }

  void _filterTournaments() {
    setState(_updateFilteredList);
  }

  void _refreshTournaments() {
    setState(() {
      _tournamentsFuture = _fetchAndSetTournaments();
      _searchController.clear();
    });
  }

void _navigateToTournamentDetail(Tournament t) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => InTournamentView(tournament: t)),
  );
}


  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _categories.length,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chess Tournaments'),
          bottom: TabBar(
            controller: _tabController,
            tabs: _categories
                .map((cat) => Tab(text: cat[0].toUpperCase() + cat.substring(1)))
                .toList(),
          ),
        ),
        body: FutureBuilder<Map<String, List<Tournament>>>(
          future: _tournamentsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Error loading tournaments.'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _refreshTournaments,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            } else if (!snapshot.hasData ||
                _categories.every(
                    (key) => (snapshot.data![key]?.isEmpty ?? true))) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('No tournaments found.'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _refreshTournaments,
                      child: const Text('Refresh'),
                    ),
                  ],
                ),
              );
            } else {
              return TabBarView(
                controller: _tabController,
                children: _categories.map((_) {
                  return SearchableListViewLayout<Tournament>(
                    searchController: _searchController,
                    onSearchChanged: (_) => _filterTournaments(),
                    searchHintText: 'Search Tournaments by Name…',
                    items: _filteredTournaments,
                    itemBuilder: (context, index, tournament) {
                      final isFavorite = _favoriteTournamentIds.contains(
                        tournament.id,
                      );
                      return ListTile(
                        title: Text(tournament.name),
                        subtitle: Text('Round ${tournament.rounds.length}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                isFavorite ? Icons.star : Icons.star_border,
                                color: isFavorite ? Colors.amber : null,
                              ),
                              onPressed: () => _toggleFavorite(tournament),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      );
                    },
                    onItemTap: _navigateToTournamentDetail,
                  );
                }).toList(),
              );
            }
          },
        ),
      ),
    );
  }
}

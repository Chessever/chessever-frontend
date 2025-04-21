// lib/views/tournament_list_view.dart
import 'package:flutter/material.dart';
import '../models/tournament.dart';
import '../services/lichess_api_service.dart';
import '../widgets/searchable_list_layout.dart';
import 'game_list_view.dart';

class TournamentListView extends StatefulWidget {
  const TournamentListView({super.key});

  @override
  State<TournamentListView> createState() => _TournamentListViewState();
}

class _TournamentListViewState extends State<TournamentListView> {
  final TextEditingController _searchController = TextEditingController();
  final LichessApiService _apiService = LichessApiService();

  late Future<Map<String, List<Tournament>>> _tournamentsFuture;
  Map<String, List<Tournament>> _allTournaments = {};
  List<Tournament> _filteredTournaments = [];

  @override
  void initState() {
    super.initState();
    _tournamentsFuture = _fetchAndSetTournaments();
    _searchController.addListener(_filterTournaments);
  }

  Future<Map<String, List<Tournament>>> _fetchAndSetTournaments() async {
    try {
      final tournaments = await _apiService.fetchArenaTournamentsParsed();
      _allTournaments = tournaments;
      _updateFilteredList();
      return tournaments;
    } catch (e) {
      print("Error fetching tournaments: $e");
      rethrow;
    }
  }

  void _updateFilteredList() {
    final query = _searchController.text.toLowerCase();
    var combinedList = <Tournament>[];

    combinedList.addAll(_allTournaments['started'] ?? []);
    combinedList.addAll(_allTournaments['created'] ?? []);

    if (query.isEmpty) {
      _filteredTournaments = combinedList;
    } else {
      _filteredTournaments = combinedList.where((t) {
        final nameMatch = t.name.toLowerCase().contains(query);
        return nameMatch;
      }).toList();
    }
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

  void _navigateToGameList(Tournament tournament) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameListView(
          tournament: tournament,
          // tournamentId: tournament.id,
          // tournamentName: tournament.name,
          // roundID: tournament.roundID,
          // roundSlug: tournament.slug,
          // isSwiss: tournament.system == 'swiss',
          // isSwiss: false,
        ),
      ),
    );
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
        title: const Text('Chess Tournaments'),
        actions: [], // no extra actions for now
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
                     (snapshot.data!['started']!.isEmpty &&
                      snapshot.data!['created']!.isEmpty)) {
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
            return SearchableListViewLayout<Tournament>(
              searchController: _searchController,
              onSearchChanged: (_) => _filterTournaments(),
              searchHintText: 'Search Tournaments by Name…',
              items: _filteredTournaments,
              itemBuilder: (context, index, tournament) {
                return ListTile(
                  title: Text(tournament.name),
                  subtitle: Text("placeholder"
                    // 'Status: ${tournament.status} | Starts: ${tournament.startsAt?.toLocal() ?? 'N/A'}',
                    // 'Status: ${tournament.status} | Starts: ${tournament.startsAt?.toLocal() ?? 'N/A'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                );
              },
              onItemTap: _navigateToGameList,
            );
          }
        },
      ),
    );
  }
}

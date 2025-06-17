import 'package:flutter/material.dart';
import '../models/player.dart';
import 'player_card.dart';

class PlayerListWidget extends StatefulWidget {
  const PlayerListWidget({Key? key}) : super(key: key);

  @override
  State<PlayerListWidget> createState() => _PlayerListWidgetState();
}

class _PlayerListWidgetState extends State<PlayerListWidget> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _playersData = [
    {
      'name': 'Magnus, Carlsen',
      'countryCode': 'NO',
      'elo': 2837,
      'age': 35,
      'isFavorite': true,
    },
    {
      'name': 'Hikaru, Nakamura',
      'countryCode': 'US',
      'elo': 2804,
      'age': 38,
      'isFavorite': false,
    },
    {
      'name': 'Erigaisi, Arjun',
      'countryCode': 'IN',
      'elo': 2782,
      'age': 22,
      'isFavorite': false,
    },
    {
      'name': 'Carauna, Fabiano',
      'countryCode': 'US',
      'elo': 2777,
      'age': 33,
      'isFavorite': false,
    },
    {
      'name': 'Gukesh, D',
      'countryCode': 'IN',
      'elo': 2776,
      'age': 19,
      'isFavorite': false,
    },
    {
      'name': 'Abdusattorov, N',
      'countryCode': 'UZ',
      'elo': 2767,
      'age': 21,
      'isFavorite': false,
    },
    {
      'name': 'Praggnanandhaa, R',
      'countryCode': 'IN',
      'elo': 2766,
      'age': 20,
      'isFavorite': false,
    },
  ];
  List<Map<String, dynamic>> _filteredPlayers = [];

  @override
  void initState() {
    super.initState();
    _filteredPlayers = _playersData;
  }

  void _filterPlayers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredPlayers = _playersData;
      } else {
        _filteredPlayers =
            _playersData
                .where(
                  (player) => player['name'].toLowerCase().contains(
                    query.toLowerCase(),
                  ),
                )
                .toList();
      }
    });
  }

  void _toggleFavorite(int index) {
    setState(() {
      _filteredPlayers[index]['isFavorite'] =
          !_filteredPlayers[index]['isFavorite'];

      // Also update in the original data
      final name = _filteredPlayers[index]['name'];
      final dataIndex = _playersData.indexWhere(
        (player) => player['name'] == name,
      );
      if (dataIndex != -1) {
        _playersData[dataIndex]['isFavorite'] =
            _filteredPlayers[index]['isFavorite'];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              // Search bar
              Container(
                height: 48,
                margin: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1C),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _filterPlayers,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search players',
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.filter_list, color: Colors.white),
                      onPressed: () {
                        // Filter functionality would go here
                      },
                    ),
                  ),
                ),
              ),

              // Column headers
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
                child: Row(
                  children: [
                    const SizedBox(width: 24), // Space for rank number
                    const SizedBox(width: 28), // Space for flag
                    // Player header
                    const Expanded(
                      child: Text(
                        'Player',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Elo header - perfectly aligned with the values
                    Container(
                      width: 60,
                      child: const Text(
                        'Elo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    // Age header - perfectly aligned with the values
                    Container(
                      width: 50,
                      child: const Text(
                        'Age',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    // Space for favorite icon
                    const SizedBox(width: 30),
                  ],
                ),
              ),

              // Player list
              Expanded(
                child: ListView.separated(
                  itemCount: _filteredPlayers.length,
                  separatorBuilder:
                      (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final player = _filteredPlayers[index];
                    return PlayerCard(
                      rank: index + 1,
                      playerName: player['name'],
                      countryCode: player['countryCode'],
                      elo: player['elo'],
                      age: player['age'],
                      isFavorite: player['isFavorite'],
                      onFavoriteToggle: () => _toggleFavorite(index),
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

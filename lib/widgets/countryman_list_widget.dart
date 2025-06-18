import 'package:flutter/material.dart';
import '../widgets/countryman_card.dart';
import '../widgets/rounded_search_bar.dart';

class CountrymanListWidget extends StatefulWidget {
  const CountrymanListWidget({Key? key}) : super(key: key);

  @override
  State<CountrymanListWidget> createState() => _CountrymanListWidgetState();
}

class _CountrymanListWidgetState extends State<CountrymanListWidget> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _countrymenData = [
    {'name': 'Hikaru, Nakamura', 'countryCode': 'US', 'elo': 2804, 'age': 38},
    {'name': 'Caruana, Fabiano', 'countryCode': 'US', 'elo': 2777, 'age': 33},
    {'name': 'So, Wesley', 'countryCode': 'US', 'elo': 2745, 'age': 32},
    {'name': 'Aronian Levon', 'countryCode': 'US', 'elo': 2742, 'age': 43},
    {'name': 'Dominguez Leinier', 'countryCode': 'US', 'elo': 2738, 'age': 42},
    {'name': 'Niemann, Hans', 'countryCode': 'US', 'elo': 2736, 'age': 22},
    {'name': 'Liang, Awonder', 'countryCode': 'US', 'elo': 2693, 'age': 22},
    {'name': 'Sevian, Samuel', 'countryCode': 'US', 'elo': 2687, 'age': 25},
  ];
  List<Map<String, dynamic>> _filteredCountrymen = [];

  @override
  void initState() {
    super.initState();
    _loadCountrymen();
  }

  void _loadCountrymen() {
    setState(() {
      _filteredCountrymen = [..._countrymenData];
    });
  }

  void _filterCountrymen(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCountrymen = _countrymenData;
      } else {
        _filteredCountrymen =
            _countrymenData
                .where(
                  (player) => player['name'].toLowerCase().contains(
                    query.toLowerCase(),
                  ),
                )
                .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Countrymen',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: RoundedSearchBar(
                  controller: _searchController,
                  onChanged: _filterCountrymen,
                  hintText: 'Search tournaments or players',
                  onFilterTap: () {
                    // Show filter options if needed
                  },
                ),
              ),

              // Column headers
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    // Space for rank number
                    const SizedBox(width: 32),

                    // Player name header
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

                    // Elo header
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

                    // Age header
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
                  ],
                ),
              ),

              // Player list
              Expanded(
                child: ListView.separated(
                  itemCount: _filteredCountrymen.length,
                  separatorBuilder:
                      (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final player = _filteredCountrymen[index];
                    return CountrymanCard(
                      rank: index + 1,
                      playerName: player['name'],
                      countryCode: player['countryCode'],
                      elo: player['elo'],
                      age: player['age'],
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

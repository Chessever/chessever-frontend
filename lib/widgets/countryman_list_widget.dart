import 'package:chessever2/utils/app_typography.dart';
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
                  hintText: 'Search players',
                  showProfile: false,
                  showFilter: false,
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
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Player',
                        style: AppTypography.textSmRegular.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),

                    // Elo header
                    Expanded(
                      flex: 1,
                      child: Text(
                        'Elo',
                        style: AppTypography.textSmRegular.copyWith(
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    // Age header
                    Expanded(
                      flex: 1,
                      child: Text(
                        'Age',
                        style: AppTypography.textSmRegular.copyWith(
                          color: Colors.white,
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

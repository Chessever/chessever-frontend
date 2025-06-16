import 'package:flutter/material.dart';
import 'rounded_search_bar.dart';

class SearchBarExample extends StatefulWidget {
  const SearchBarExample({Key? key}) : super(key: key);

  @override
  State<SearchBarExample> createState() => _SearchBarExampleState();
}

class _SearchBarExampleState extends State<SearchBarExample> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Search'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // This is the search bar from your image
            RoundedSearchBar(
              controller: _searchController,
              onChanged: (value) {
                // Handle search input
                print('Searching for: $value');
              },
              onFilterTap: () {
                // Handle filter button tap
                print('Filter button tapped');
              },
              hintText: 'Search tournaments or players',
              autofocus: false,
              height: 48.0,
            ),
            const SizedBox(height: 20),
            // Usage instructions
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'The search bar above matches the one in your image. '
                'It uses your existing RoundedSearchBar widget which already '
                'has the exact styling you need.',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

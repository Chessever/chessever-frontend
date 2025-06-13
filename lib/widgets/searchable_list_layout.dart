import 'package:flutter/material.dart';

class SearchableListViewLayout<T> extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String searchHintText;
  final List<T> items;
  final Widget Function(BuildContext context, int index, T item) itemBuilder;
  final void Function(T item)? onItemTap; // Optional tap callback per item

  const SearchableListViewLayout({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.searchHintText,
    required this.items,
    required this.itemBuilder,
    this.onItemTap,
  });

@override
  Widget build(BuildContext context) {
    return Column( // Use Column for vertical arrangement [1, 2]
      children: [ // Ensure children are in a list
        Padding( // Add padding around the TextField [1, 3]
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: searchController, // Control text input [4, 5]
            onChanged: onSearchChanged, // Notify parent on change [4, 5]
            decoration: InputDecoration(
              hintText: searchHintText,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
          ),
        ),
        Expanded( // Ensure ListView fills remaining space [1]
          child: ListView.builder(
            itemCount: items.length,
            // Efficiently build list items only when visible [6]
            itemBuilder: (context, index) {
              final item = items[index];
              // Use InkWell or GestureDetector for tap handling if itemBuilder doesn't return a tappable widget like ListTile
              return InkWell( // Provides tap feedback [6]
                onTap: onItemTap!= null? () => onItemTap!(item) : null, // Handle item tap [7, 6, 8, 9, 10, 11, 12, 13, 14, 15]
                child: itemBuilder(context, index, item),
              );
            },
          ),
        ),
      ],
    );
  }

}
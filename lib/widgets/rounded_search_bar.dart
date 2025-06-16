import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../utils/svg_asset.dart';

class RoundedSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final bool autofocus;
  final VoidCallback? onSearchTap;
  final VoidCallback? onFilterTap;
  final double height;
  final bool showFilterButton;
  final VoidCallback? onProfileTap;
  final String? profileInitials;
  final bool showProfileIcon;

  const RoundedSearchBar({
    Key? key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search tournaments or players',
    this.autofocus = false,
    this.onSearchTap,
    this.onFilterTap,
    this.height = 48.0,
    this.showFilterButton = true,
    this.onProfileTap,
    this.profileInitials = "VD",
    this.showProfileIcon = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const profileBackgroundColor = Color(
      0xFF0FB4E5,
    ); // Blue color for profile circle (#0FB4E5)

    return Row(
      children: [
        // Profile Icon (outside the search bar)
        if (showProfileIcon)
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: GestureDetector(
              onTap: onProfileTap,
              child: Container(
                width: 32, // Set to 32px as specified
                height: 32, // Set to 32px as specified
                decoration: const BoxDecoration(
                  color: profileBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    profileInitials ?? 'VD',
                    style: const TextStyle(
                      fontFamily: 'Inter', // Use Inter Display font
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 14, // Adjusted for the smaller container
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Search Bar (as a rounded rectangle)
        Expanded(
          child: Container(
            height: 40, // Adjusted height to match the design
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E), // Darker shade for search bar
              borderRadius: BorderRadius.circular(8), // Less rounded corners
            ),
            child: Row(
              children: [
                // Search Icon
                const Padding(
                  padding: EdgeInsets.only(left: 16.0, right: 8.0),
                  child: Icon(
                    Icons.search,
                    color: Colors.grey,
                    size: 20.0, // Slightly smaller to match the design
                  ),
                ),

                // TextField
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    autofocus: autofocus,
                    style: const TextStyle(
                      fontFamily: 'Inter', // Use Inter Display font
                      color: Colors.white,
                      fontSize: 14.0, // xs size
                      fontWeight: FontWeight.normal, // regular weight
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Search tournaments or players',
                      hintStyle: TextStyle(
                        fontFamily: 'Inter', // Use Inter Display font
                        color: Colors.grey,
                        fontSize: 14.0, // xs size
                        fontWeight: FontWeight.normal, // regular weight
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10.0),
                      isDense: true,
                    ),
                    cursorColor: kPrimaryColor,
                  ),
                ),

                // Filter Button with three horizontal lines icon
                if (showFilterButton)
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: InkWell(
                      onTap: onFilterTap,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Three horizontal lines
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(bottom: 4),
                                  child: SizedBox(
                                    width: 18,
                                    height: 2,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(bottom: 4),
                                  child: SizedBox(
                                    width: 18,
                                    height: 2,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 18,
                                  height: 2,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

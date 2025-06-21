import 'package:flutter/material.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';

class FilterPopup extends StatefulWidget {
  const FilterPopup({Key? key}) : super(key: key);

  @override
  State<FilterPopup> createState() => _FilterPopupState();
}

class _FilterPopupState extends State<FilterPopup> {
  bool _isFormatExpanded = false;
  String _selectedFormat = 'All Formats';
  String _selectedType = 'All Types';
  final _playerSearchController = TextEditingController();
  final _countrySearchController = TextEditingController();

  @override
  void dispose() {
    _playerSearchController.dispose();
    _countrySearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use fixed dimensions for the popup
    const double dialogWidth = 280.0;
    const double horizontalPadding = 20.0;
    const double verticalPadding = 16.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: 448, // Fixed height as specified
        ),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(4), // Changed from 16px to 4px
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Make the content scrollable
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: horizontalPadding,
                    right: horizontalPadding,
                    top: verticalPadding,
                    bottom: 0, // Bottom padding handled by SizedBox at the end
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tournament Type
                      Text(
                        'Tournament Type',
                        style: AppTypography.textXsMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1C),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedType,
                              icon: const Icon(
                                Icons.keyboard_arrow_down,
                                color: Colors.white,
                              ),
                              isExpanded: true,
                              dropdownColor: const Color(0xFF1A1A1C),
                              style: AppTypography.textXsMedium.copyWith(
                                color: Colors.white,
                              ),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _selectedType = newValue;
                                  });
                                }
                              },
                              items:
                                  [
                                    'All Types',
                                    'Tournament',
                                    'Match',
                                  ].map<DropdownMenuItem<String>>((
                                    String value,
                                  ) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(
                                        value,
                                        style: AppTypography.textXsMedium
                                            .copyWith(color: Colors.white),
                                      ),
                                    );
                                  }).toList(),
                            ),
                          ),
                        ),
                      ),

                      // Format
                      const SizedBox(height: 24),
                      Text(
                        'Format',
                        style: AppTypography.textXsMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isFormatExpanded = !_isFormatExpanded;
                          });
                        },
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                _isFormatExpanded
                                    ? kPrimaryColor
                                    : const Color(0xFF1A1A1C),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _selectedFormat,
                                style: AppTypography.textXsMedium.copyWith(
                                  color:
                                      _isFormatExpanded
                                          ? Colors.black
                                          : Colors.white,
                                ),
                              ),
                              Icon(
                                _isFormatExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color:
                                    _isFormatExpanded
                                        ? Colors.black
                                        : Colors.white,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isFormatExpanded)
                        Container(
                          margin: const EdgeInsets.only(
                            top: 4,
                          ), // Changed from 1px to 4px gap
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1C),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              _buildFormatOption('Classical'),
                              const Divider(
                                height: 1,
                                thickness: 0.5,
                                color: Color(0xFF2C2C2E),
                                // margin: EdgeInsets.zero,
                              ),
                              _buildFormatOption('Rapid'),
                              const Divider(
                                height: 1,
                                thickness: 0.5,
                                color: Color(0xFF2C2C2E),
                                // margin: EdgeInsets.zero,
                              ),
                              _buildFormatOption('Blitz'),
                            ],
                          ),
                        ),

                      // Players
                      const SizedBox(height: 20),
                      Text(
                        'Players',
                        style: AppTypography.textXsMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1C),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: TextField(
                            controller: _playerSearchController,
                            decoration: InputDecoration(
                              hintText: 'Search by player name',
                              hintStyle: AppTypography.textXsMedium.copyWith(
                                color: Colors.white.withOpacity(0.6),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: AppTypography.textXsMedium.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      // Country
                      const SizedBox(height: 20),
                      Text(
                        'Country',
                        style: AppTypography.textXsMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1C),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: TextField(
                            controller: _countrySearchController,
                            decoration: InputDecoration(
                              hintText: 'Search by country or city',
                              hintStyle: AppTypography.textXsMedium.copyWith(
                                color: Colors.white.withOpacity(0.6),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: AppTypography.textXsMedium.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      // Add space at the bottom for padding
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

            // Buttons - Keep outside the scrollable area to remain fixed at the bottom
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Reset button (left) with fixed width
                  SizedBox(
                    width: 116,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _selectedFormat = 'All Formats';
                          _selectedType = 'All Types';
                          _playerSearchController.clear();
                          _countrySearchController.clear();
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: kBlack2Color,
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        'Reset',
                        style: const TextStyle(
                          fontFamily: 'InterDisplay',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          height: 1, // Adjusted line height to prevent wrapping
                          color: Colors.white,
                        ),
                        maxLines: 1, // Force single line
                        overflow: TextOverflow.visible, // Show all text
                      ),
                    ),
                  ),
                  // Apply button (right) with fixed width
                  SizedBox(
                    width: 116,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: () {
                        // Apply filters and close dialog
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: EdgeInsets.zero, // Remove default padding
                      ),
                      child: Text(
                        'Apply Filters',
                        style: const TextStyle(
                          fontFamily: 'InterDisplay',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          height: 1, // Adjusted line height to prevent wrapping
                          color: Colors.black,
                        ),
                        maxLines: 1, // Force single line
                        overflow: TextOverflow.visible, // Show all text
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatOption(String format) {
    final bool isSelected = _selectedFormat == format;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFormat = format;
          _isFormatExpanded = false;
        });
      },
      child: Container(
        height: 40, // Match height of other inputs
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
        ), // Match other inputs
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2C2C2E) : Colors.transparent,
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          format,
          style: AppTypography.textXsMedium.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

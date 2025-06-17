import 'package:flutter/material.dart';
import 'package:chessever2/utils/app_typography.dart';

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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24.0,
        vertical: 24.0,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dialog title
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Text(
                'Filter',
                style: AppTypography.textLgBold.copyWith(color: Colors.white),
              ),
            ),

            // Tournament Type
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'Tournament Type',
                style: AppTypography.textSmMedium.copyWith(color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
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
                          ].map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(
                                value,
                                style: AppTypography.textXsMedium.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                ),
              ),
            ),

            // Format
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                'Format',
                style: AppTypography.textSmMedium.copyWith(color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isFormatExpanded = !_isFormatExpanded;
                  });
                },
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1C),
                    borderRadius:
                        _isFormatExpanded
                            ? const BorderRadius.only(
                              topLeft: Radius.circular(8),
                              topRight: Radius.circular(8),
                            )
                            : BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedFormat,
                        style: AppTypography.textXsMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      Icon(
                        _isFormatExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_isFormatExpanded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A1C),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildFormatOption('Classical'),
                      const Divider(
                        height: 1,
                        thickness: 0.5,
                        color: Color(0xFF2C2C2E),
                      ),
                      _buildFormatOption('Rapid'),
                      const Divider(
                        height: 1,
                        thickness: 0.5,
                        color: Color(0xFF2C2C2E),
                      ),
                      _buildFormatOption('Blitz'),
                    ],
                  ),
                ),
              ),

            // Players
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                'Players',
                style: AppTypography.textSmMedium.copyWith(color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1C),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _playerSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search by player name',
                    hintStyle: AppTypography.textXsMedium.copyWith(
                      color: Colors.white.withOpacity(0.6),
                    ),
                    border: InputBorder.none,
                  ),
                  style: AppTypography.textXsMedium.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // Country
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                'Country',
                style: AppTypography.textSmMedium.copyWith(color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1C),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _countrySearchController,
                  decoration: InputDecoration(
                    hintText: 'Search by country or city',
                    hintStyle: AppTypography.textXsMedium.copyWith(
                      color: Colors.white.withOpacity(0.6),
                    ),
                    border: InputBorder.none,
                  ),
                  style: AppTypography.textXsMedium.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Row(
                children: [
                  Expanded(
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
                        side: BorderSide(color: Colors.grey.shade800),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text('Reset', style: AppTypography.textXsMedium),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Apply filters and close dialog
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0FB4E5),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Apply Filters',
                        style: AppTypography.textXsMedium,
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
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
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

import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';

class FilterPopup extends StatefulWidget {
  const FilterPopup({super.key});

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
    final dialogWidth = 280.w;
    final horizontalPadding = 20.w;
    final verticalPadding = 16.h;

    return GestureDetector(
      // Close the dialog when tapping outside
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          // Backdrop filter for blur effect
          const Positioned.fill(child: BackDropFilterWidget()),
          // Dialog content
          Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            // Prevent dialog from closing when clicking on the dialog itself
            child: GestureDetector(
              onTap: () {}, // Absorb the tap
              child: Container(
                width: dialogWidth,
                constraints: BoxConstraints(
                  maxHeight: 448.h, // Fixed height as specified
                ),
                decoration: BoxDecoration(
                  color: kBlackColor,
                  borderRadius: BorderRadius.circular(
                    4.br,
                  ), // Changed from 16px to 4px
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Make the content scrollable
                    Flexible(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: horizontalPadding,
                            right: horizontalPadding,
                            top: verticalPadding,
                            bottom:
                                0, // Bottom padding handled by SizedBox at the end
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Tournament Type
                              Text(
                                'Tournament Type',
                                style: AppTypography.textXsMedium.copyWith(
                                  color: kWhiteColor,
                                ),
                              ),
                              SizedBox(height: 8.h),
                              Container(
                                height: 40.h,
                                decoration: BoxDecoration(
                                  color: kBlack2Color,
                                  borderRadius: BorderRadius.circular(8.br),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16.sp,
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedType,
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down,
                                        color: kWhiteColor,
                                      ),
                                      isExpanded: true,
                                      dropdownColor: kBlack2Color,
                                      style: AppTypography.textXsMedium
                                          .copyWith(color: Colors.white),
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
                                                style: AppTypography
                                                    .textXsMedium
                                                    .copyWith(
                                                      color: kWhiteColor,
                                                    ),
                                              ),
                                            );
                                          }).toList(),
                                    ),
                                  ),
                                ),
                              ),

                              // Format
                              SizedBox(height: 24.h),
                              Text(
                                'Format',
                                style: AppTypography.textXsMedium.copyWith(
                                  color: kWhiteColor,
                                ),
                              ),
                              SizedBox(height: 8.h),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isFormatExpanded = !_isFormatExpanded;
                                  });
                                },
                                child: Container(
                                  height: 40.h,
                                  decoration: BoxDecoration(
                                    color:
                                        _isFormatExpanded
                                            ? kPrimaryColor
                                            : kBlack2Color,
                                    borderRadius: BorderRadius.circular(8.br),
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16.sp,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _selectedFormat,
                                        style: AppTypography.textXsMedium
                                            .copyWith(
                                              color:
                                                  _isFormatExpanded
                                                      ? kBlackColor
                                                      : kWhiteColor,
                                            ),
                                      ),
                                      Icon(
                                        _isFormatExpanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        color:
                                            _isFormatExpanded
                                                ? kBlackColor
                                                : kWhiteColor,
                                        size: 24.ic,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Format expansion container - moved outside of the if statement
                              _isFormatExpanded
                                  ? Container(
                                    margin: EdgeInsets.only(
                                      top: 4.sp,
                                    ), // Changed from 1px to 4px gap
                                    decoration: BoxDecoration(
                                      color: kBlack2Color,
                                      borderRadius: BorderRadius.circular(8.br),
                                    ),
                                    child: Column(
                                      children: [
                                        _buildFormatOption('Classical'),
                                        DividerWidget(),
                                        _buildFormatOption('Rapid'),
                                        DividerWidget(),
                                        _buildFormatOption('Blitz'),
                                      ],
                                    ),
                                  )
                                  : const SizedBox.shrink(),

                              // Players
                              SizedBox(height: 20.h),
                              Text(
                                'Players',
                                style: AppTypography.textXsMedium.copyWith(
                                  color: kWhiteColor,
                                ),
                              ),
                              SizedBox(height: 8.h),
                              Container(
                                height: 40.h,
                                decoration: BoxDecoration(
                                  color: kBlack2Color,
                                  borderRadius: BorderRadius.circular(8.br),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16.sp,
                                ),
                                child: Center(
                                  child: TextField(
                                    controller: _playerSearchController,
                                    decoration: InputDecoration(
                                      hintText: 'Search by player name',
                                      hintStyle: AppTypography.textXsMedium
                                          .copyWith(color: kWhiteColor70),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    style: AppTypography.textXsMedium.copyWith(
                                      color: kWhiteColor,
                                    ),
                                  ),
                                ),
                              ),

                              // Country
                              SizedBox(height: 20.h),
                              Text(
                                'Country',
                                style: AppTypography.textXsMedium.copyWith(
                                  color: kWhiteColor,
                                ),
                              ),
                              SizedBox(height: 8.h),
                              Container(
                                height: 40.h,
                                decoration: BoxDecoration(
                                  color: kBlack2Color,
                                  borderRadius: BorderRadius.circular(8.br),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16.sp,
                                ),
                                child: Center(
                                  child: TextField(
                                    controller: _countrySearchController,
                                    decoration: InputDecoration(
                                      hintText: 'Search by country or city',
                                      hintStyle: AppTypography.textXsMedium
                                          .copyWith(color: kWhiteColor70),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    style: AppTypography.textXsMedium.copyWith(
                                      color: kWhiteColor,
                                    ),
                                  ),
                                ),
                              ),

                              // Add space at the bottom for padding
                              SizedBox(height: 16.h),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Buttons - Keep outside the scrollable area to remain fixed at the bottom
                    Padding(
                      padding: EdgeInsets.all(20.sp),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Reset button (left) with fixed width
                          SizedBox(
                            width: 116.w,
                            height: 40.h,
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
                                foregroundColor: kWhiteColor,
                                backgroundColor: kBlack2Color,
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4.br),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              child: Text(
                                'Reset',
                                style: AppTypography.textSmMedium.copyWith(
                                  color: kWhiteColor,
                                ),
                                maxLines: 1, // Force single line
                                overflow: TextOverflow.visible, // Show all text
                              ),
                            ),
                          ),
                          // Apply button (right) with fixed width
                          SizedBox(
                            width: 116.w,
                            height: 40.h,
                            child: ElevatedButton(
                              onPressed: () {
                                // Apply filters and close dialog
                                Navigator.of(context).pop();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryColor,
                                foregroundColor: kBlackColor,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4.br),
                                ),
                                padding:
                                    EdgeInsets.zero, // Remove default padding
                              ),
                              child: Text(
                                'Apply Filters',
                                style: AppTypography.textSmMedium,
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
            ),
          ),
        ],
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
        height: 40.h,
        // Match height of other inputs
        padding: EdgeInsets.symmetric(horizontal: 16.sp),
        // Match other inputs
        decoration: BoxDecoration(
          color: isSelected ? kDividerColor : Colors.transparent,
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          format,
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
        ),
      ),
    );
  }
}

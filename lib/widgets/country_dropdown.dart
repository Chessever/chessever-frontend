import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CountryDropdown extends ConsumerStatefulWidget {
  final String selectedCountryCode;
  final ValueChanged<Country> onChanged;
  final String? hintText;
  final bool isLoading;

  const CountryDropdown({
    super.key,
    required this.selectedCountryCode,
    required this.onChanged,
    this.hintText,
    this.isLoading = false,
  });

  @override
  ConsumerState<CountryDropdown> createState() => _CountryDropdownState();
}

class _CountryDropdownState extends ConsumerState<CountryDropdown> {
  var isDropDownOpen = false;
  var selectedCountryCode = 'US';

  @override
  void initState() {
    selectedCountryCode = widget.selectedCountryCode;
    super.initState();
  }

  @override
  void didUpdateWidget(covariant CountryDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update selectedCountryCode if prop changed
    if (oldWidget.selectedCountryCode != widget.selectedCountryCode) {
      selectedCountryCode = widget.selectedCountryCode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius =
        isDropDownOpen
            ? BorderRadius.circular(
              10.br, // Use 8.br for consistent border radius with other widgets
            )
            : BorderRadius.circular(8.br);

    final dropDownBorderRadius = BorderRadius.circular(10.br);

    // final allCountries =
    //     ref.read(countryDropdownProvider.notifier).getAllCountries();

    // CHANGE: Get countries directly from CountryService to avoid triggering provider init on first tap
    final allCountries = CountryService().getAll();

    return ClipRRect(
      borderRadius: borderRadius,
      child: AnimatedContainer(
        padding: EdgeInsets.symmetric(vertical: 7.sp),
        duration: const Duration(milliseconds: 200),
        // height: 4.h, // Set fixed height to 40px
        decoration: BoxDecoration(
          color: kBackgroundColor,
          borderRadius: borderRadius,
          border:
              isDropDownOpen
                  ? null
                  : Border.all(color: kDarkGreyColor, width: 1.w),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton2<String>(
            isExpanded: true,
            customButton: Container(
              height: 40.h, // Match container height
              padding: EdgeInsets.symmetric(
                horizontal: 20.sp,
              ), // Proper padding
              child: Row(
                children: [
                  Expanded(
                    child:
                        widget.isLoading
                            ? Text(
                              widget.hintText ?? 'Loading...',
                              style: AppTypography.textSmMedium.copyWith(
                                color: kWhiteColor70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            )
                            : Text(
                              ref
                                  .read(countryDropdownProvider.notifier)
                                  .getCountryName(selectedCountryCode ?? ''),
                              style: AppTypography.textSmMedium.copyWith(
                                color: kWhiteColor70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                  ),
                  SizedBox(width: 12.w), // 12px gap

                  if (!widget.isLoading &&
                      selectedCountryCode.isNotEmpty &&
                      selectedCountryCode.isNotEmpty)
                    CountryFlag.fromCountryCode(
                      selectedCountryCode,
                      width: 16.w,
                      height: 12.h,
                    ),
                  SizedBox(width: 2.w),
                  Icon(
                    isDropDownOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: kWhiteColor,
                    size: 20.ic,
                  ),
                ],
              ),
            ),
            dropdownStyleData: DropdownStyleData(
              padding: EdgeInsets.zero,
              offset: const Offset(0, -4),
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: dropDownBorderRadius,
                border: Border.all(color: kDarkGreyColor),
              ),
              maxHeight: 240.h,
            ),
            buttonStyleData: ButtonStyleData(
              height: 40.h,
              padding: EdgeInsets.zero,
            ),
            menuItemStyleData: MenuItemStyleData(
              height: 40.h,
              padding: EdgeInsets.zero,
            ),
            value: widget.isLoading ? null : selectedCountryCode,
            onChanged:
                widget.isLoading
                    ? null
                    : (value) {
                      if (value != null) {
                        final country = allCountries.firstWhere(
                          (c) => c.countryCode == value,
                        );
                        widget.onChanged(country);
                      }
                    },

            onMenuStateChange: (isOpen) {
              isDropDownOpen = isOpen;
              setState(() {});
            },
            // Show empty items list when loading, else full list
            items:
                widget.isLoading
                    ? []
                    : List.generate(allCountries.length, (index) {
                      final country = allCountries[index];

                      return DropdownMenuItem<String>(
                        value: country.countryCode,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: kDarkGreyColor,
                                width: 1.w,
                              ),
                            ),
                          ),
                          height: 44.h,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              SizedBox(width: 16.w),
                              CountryFlag.fromCountryCode(
                                country.countryCode,
                                width: 16.w,
                                height: 12.h,
                              ),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: Text(
                                  country.name,
                                  style: AppTypography.textMdMedium.copyWith(
                                    color: kWhiteColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
          ),
        ),
      ),
    );
  }
}

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CountryDropdown extends ConsumerStatefulWidget {
  final String selectedCountryCode;
  final ValueChanged<String> onChanged;
  final String? hintText;

  const CountryDropdown({
    super.key,
    required this.selectedCountryCode,
    required this.onChanged,
    this.hintText,
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
  Widget build(BuildContext context) {
    final borderRadius =
        isDropDownOpen
            ? const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
              bottomLeft: Radius.zero,
              bottomRight: Radius.zero,
            )
            : BorderRadius.circular(8);

    final dropDownBorderRadius = const BorderRadius.only(
      bottomLeft: Radius.circular(8),
      bottomRight: Radius.circular(8),
      topLeft: Radius.zero,
      topRight: Radius.zero,
    );

    final allCountries =
        ref.read(countryDropdownProvider.notifier).getAllCountries();

    return ClipRRect(
      borderRadius: borderRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 40, // Set fixed height to 40px
        decoration: BoxDecoration(
          color: kBackgroundColor,
          borderRadius: borderRadius,
          border:
              isDropDownOpen
                  ? null
                  : Border.all(color: kDarkGreyColor, width: 1),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton2<String>(
            isExpanded: true,
            customButton: Container(
              height: 40, // Match container height
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
              ), // Proper padding
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // Find the country name using the selected code
                      ref
                          .read(countryDropdownProvider.notifier)
                          .getCountryName(selectedCountryCode),
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12), // 12px gap
                  CountryFlag.fromCountryCode(
                    selectedCountryCode,
                    width: 16,
                    height: 12,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isDropDownOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: kWhiteColor,
                    size: 20,
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
              maxHeight: 240,
            ),
            buttonStyleData: const ButtonStyleData(
              height: 40,
              padding: EdgeInsets.zero,
            ),
            menuItemStyleData: const MenuItemStyleData(
              height: 40,
              padding: EdgeInsets.zero,
            ),
            value: selectedCountryCode,
            onChanged: (value) {
              if (value != null) {
                selectedCountryCode = value;
                widget.onChanged(value);
              }
            },
            onMenuStateChange: (isOpen) {
              isDropDownOpen = isOpen;
              setState(() {});
            },
            items: List.generate(allCountries.length, (index) {
              final country = allCountries[index];

              return DropdownMenuItem<String>(
                value: country.countryCode,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: kDarkGreyColor, width: 1),
                    ),
                  ),
                  height: 40,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      SizedBox(width: 16),
                      CountryFlag.fromCountryCode(
                        country.countryCode,
                        width: 16,
                        height: 12,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          country.name,
                          style: AppTypography.textXsMedium.copyWith(
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

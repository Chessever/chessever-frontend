import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:country_picker/country_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CountryDropdown extends ConsumerWidget {
  final String? selectedCountry;
  final ValueChanged<String> onChanged;
  final String? hintText;

  const CountryDropdown({
    super.key,
    this.selectedCountry,
    required this.onChanged,
    this.hintText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(
      countryDropdownNotifierProvider(
        initialCountry: selectedCountry ?? "US",
      ).notifier,
    );

    final state = ref.watch(
      countryDropdownNotifierProvider(initialCountry: selectedCountry ?? "US"),
    );

    final borderRadius =
        state.isDropdownOpen
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

    return ClipRRect(
      borderRadius: borderRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: kBackgroundColor,
          borderRadius: borderRadius,

          border:
              state.isDropdownOpen
                  ? null
                  : Border.all(color: kDarkGreyColor, width: 1),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton2<String>(
            isExpanded: true,
            dropdownStyleData: DropdownStyleData(
              padding: EdgeInsets.zero,
              offset: const Offset(0, -4),
              decoration: BoxDecoration(
                color: kBlack2Color, // Use theme color
                borderRadius: dropDownBorderRadius,
                border: Border.all(color: kDarkGreyColor),
              ),
              maxHeight: 240,
            ),
            buttonStyleData: const ButtonStyleData(height: 40),
            iconStyleData: IconStyleData(
              icon: Padding(
                padding: EdgeInsets.only(right: 16),
                child: Icon(
                  state.isDropdownOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: kWhiteColor, // Use theme color
                ),
              ),
            ),
            menuItemStyleData: const MenuItemStyleData(
              height: 40,
              padding: EdgeInsets.zero,
            ),
            value: state.selectedCountryCode,
            onChanged: (value) {
              if (value != null) {
                notifier.selectCountry(value);
                onChanged(value);
              }
            },
            onMenuStateChange: (isOpen) {
              notifier.setDropdownState(isOpen);
            },
            items: List.generate(state.countries.length, (index) {
              final country = state.countries[index];

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
                      SizedBox(width: 4),
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
            selectedItemBuilder: (context) {
              return state.countries.map((Country country) {
                if (country.countryCode == state.selectedCountryCode) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      SizedBox(width: 16),
                      Text(
                        country.name,
                        style: AppTypography.textXsMedium.copyWith(
                          color: kWhiteColor,
                        ),
                      ),
                      Spacer(),
                      CountryFlag.fromCountryCode(
                        country.countryCode,
                        width: 16,
                        height: 12,
                      ),
                      SizedBox(width: 4),
                    ],
                  );
                } else {
                  return SizedBox.shrink();
                }
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}

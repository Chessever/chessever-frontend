import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:country_flags/country_flags.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RoundedSearchBar extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onFilterTap;
  final Function(String)? onChanged;
  final String hintText;
  final bool autofocus;
  final VoidCallback? onProfileTap;
  final bool showProfile;
  final bool showFilter;
  final Key? textFieldKey;
  final Key? filterButtonKey;

  const RoundedSearchBar({
    super.key,
    required this.controller,
    required this.onFilterTap,
    this.onChanged,
    this.hintText = 'Search',
    this.autofocus = false,
    this.onProfileTap,
    this.showProfile = true,
    this.showFilter = true,
    this.textFieldKey,
    this.filterButtonKey,
  });

  @override
  ConsumerState<RoundedSearchBar> createState() => _RoundedSearchBarState();
}

class _RoundedSearchBarState extends ConsumerState<RoundedSearchBar> {
  String selectedCountryCode = 'US';

  @override
  Widget build(BuildContext context) {
    final allCountries =
        ref.read(countryDropdownProvider.notifier).getAllCountries();

    return Row(
      children: [
        if (widget.showProfile)
          UserAvatar(size: 32, onTap: widget.onProfileTap),

        if (widget.showProfile) SizedBox(width: 20.w),

        // Search bar container
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.circular(4.br),
            ),
            padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 8.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 6.sp),
                  child: SvgWidget(
                    SvgAsset.searchIcon,
                    height: 16.h,
                    width: 16.w,
                  ),
                ),
                SizedBox(width: 4.w),

                Expanded(
                  child: TextField(
                    key: widget.textFieldKey,
                    controller: widget.controller,
                    onChanged: widget.onChanged,
                    autofocus: widget.autofocus,
                    textAlignVertical: TextAlignVertical.center,
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor70,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (widget.showFilter && widget.onFilterTap != null)
                  Padding(
                    padding: EdgeInsets.only(right: 10.sp),
                    child: InkWell(
                      key: widget.filterButtonKey,
                      onTap: widget.onFilterTap,
                      borderRadius: BorderRadius.zero,
                      child: SvgWidget(
                        SvgAsset.listFilterIcon,
                        height: 24.h,
                        width: 24.w,
                      ),
                    ),
                  )
                else
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedCountryCode,
                      icon: Icon(Icons.keyboard_arrow_down, color: kWhiteColor),
                      dropdownColor: kBlack2Color,
                      isDense: true,
                      onChanged: (String? value) {
                        if (value != null) {
                          final country = allCountries.firstWhere(
                            (c) => c.countryCode == value,
                          );
                          setState(() {
                            selectedCountryCode = value;
                          });
                          widget.onChanged?.call(country.toString());
                        }
                      },
                      items:
                          allCountries.map((country) {
                            return DropdownMenuItem<String>(
                              value: country.countryCode,
                              child: CountryFlag.fromCountryCode(
country.countryCode,
  theme: ImageTheme(width: 12.w,
                                height: 9.h,),
),
                            );
                          }).toList(),
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

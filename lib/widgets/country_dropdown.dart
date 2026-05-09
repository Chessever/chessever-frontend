import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';

class CountryDropdown extends ConsumerStatefulWidget {
  final String selectedCountryCode;
  final ValueChanged<Country> onChanged;
  final String? hintText;
  final bool isLoading;
  final bool requireAuthToChange;
  final bool compact;

  const CountryDropdown({
    super.key,
    required this.selectedCountryCode,
    required this.onChanged,
    this.hintText,
    this.isLoading = false,
    this.requireAuthToChange = true,
    this.compact = false,
  });

  @override
  ConsumerState<CountryDropdown> createState() => _CountryDropdownState();
}

class _CountryDropdownState extends ConsumerState<CountryDropdown> {
  final GlobalKey<DropdownButton2State<String>> _dropdownKey =
      GlobalKey<DropdownButton2State<String>>();
  var isDropDownOpen = false;
  var selectedCountryCode = 'US';
  final TextEditingController _searchController = TextEditingController();
  DateTime? _openedAt;
  bool _reopenAttempted = false;
  bool _isReopening = false;
  // Tablet phantom-tap guard: keep menu open briefly before allowing dismiss.
  static const _minOpenDuration = Duration(milliseconds: 600);

  @override
  void initState() {
    selectedCountryCode = widget.selectedCountryCode;
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final isCompact = widget.compact;
    final buttonHeight = isCompact ? 36.h : 40.h;
    final horizontalPadding = isCompact ? 12.sp : 20.sp;
    final verticalPadding = isCompact ? 0.sp : 7.sp;

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
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isCompact ? context.colors.surface : context.colors.background,
          borderRadius: borderRadius,
          border:
              isDropDownOpen
                  ? null
                  : isCompact
                  ? null
                  : Border.all(color: kDarkGreyColor, width: 1.w),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton2<String>(
            key: _dropdownKey,
            isExpanded: true,
            customButton: Container(
              height: buttonHeight,
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Row(
                children: [
                  if (!widget.isLoading && selectedCountryCode.isNotEmpty)
                    CountryFlag.fromCountryCode(
selectedCountryCode,
  theme: ImageTheme(width: isCompact ? 20.w : 16.w,
                      height: isCompact ? 14.h : 12.h,),
),
                  SizedBox(width: isCompact ? 8.w : 12.w),
                  Expanded(
                    child:
                        widget.isLoading
                            ? Text(
                              widget.hintText ?? 'Loading...',
                              style: AppTypography.textSmMedium.copyWith(
                                color: context.colors.textPrimaryMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            )
                            : Text(
                              ref
                                  .read(countryDropdownProvider.notifier)
                                  .getCountryName(selectedCountryCode),
                              style: (isCompact
                                      ? AppTypography.textXsMedium
                                      : AppTypography.textSmMedium)
                                  .copyWith(color: context.colors.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                  ),
                  SizedBox(width: 4.w),
                  Icon(
                    isDropDownOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: context.colors.textPrimaryMuted,
                    size: isCompact ? 18.ic : 20.ic,
                  ),
                ],
              ),
            ),
            dropdownStyleData: DropdownStyleData(
              padding: EdgeInsets.zero,
              offset: const Offset(0, -4),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: dropDownBorderRadius,
                border: Border.all(color: kDarkGreyColor),
              ),
              maxHeight: 300.h,
            ),
            dropdownSearchData: DropdownSearchData(
              searchController: _searchController,
              searchInnerWidgetHeight: 56.h,
              searchInnerWidget: Container(
                height: 56.h,
                padding: EdgeInsets.only(
                  top: 8.h,
                  bottom: 4.h,
                  left: 12.w,
                  right: 12.w,
                ),
                child: TextFormField(
                  expands: true,
                  maxLines: null,
                  controller: _searchController,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 10.h,
                    ),
                    hintText: 'Search',
                    hintStyle: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.5),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20.ic,
                      color: context.colors.textPrimary.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: context.colors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.br),
                      borderSide: BorderSide(color: kDarkGreyColor, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.br),
                      borderSide: BorderSide(color: kDarkGreyColor, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.br),
                      borderSide: BorderSide(
                        color: context.colors.textPrimary.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
              searchMatchFn: (item, searchValue) {
                final countryCode = item.value;
                if (countryCode == null) return false;
                final country = allCountries.firstWhere(
                  (c) => c.countryCode == countryCode,
                  orElse: () => allCountries.first,
                );
                return country.name.toLowerCase().contains(
                  searchValue.toLowerCase(),
                );
              },
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
                    : (value) async {
                      if (value != null) {
                        if (widget.requireAuthToChange) {
                          final allowed = await requireFullAuthGuard(context);
                          if (!allowed) return;
                        }

                        final country = allCountries.firstWhere(
                          (c) => c.countryCode == value,
                        );
                        widget.onChanged(country);
                      }
                    },

            onMenuStateChange: (isOpen) {
              if (isOpen) {
                _openedAt = DateTime.now();
                if (_isReopening) {
                  _isReopening = false;
                } else {
                  _reopenAttempted = false;
                }
              } else if (ResponsiveHelper.isTablet && _openedAt != null) {
                final elapsed = DateTime.now().difference(_openedAt!);
                if (elapsed < _minOpenDuration && !_reopenAttempted) {
                  _reopenAttempted = true;
                  _isReopening = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _dropdownKey.currentState?.callTap();
                    }
                  });
                  return;
                }
              }

              isDropDownOpen = isOpen;
              if (!isOpen) {
                _searchController.clear();
              }
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
  theme: ImageTheme(width: 16.w,
                                height: 12.h,),
),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: Text(
                                  country.name,
                                  style: AppTypography.textMdMedium.copyWith(
                                    color: context.colors.textPrimary,
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

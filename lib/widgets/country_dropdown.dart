import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/text_scale.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/glass_dropdown.dart';

class CountryDropdown extends ConsumerStatefulWidget {
  final String selectedCountryCode;
  final ValueChanged<Country> onChanged;
  final String? hintText;
  final bool isLoading;
  final bool requireAuthToChange;
  final bool compact;

  /// Sizes the button to its flag, name and chevron instead of filling the
  /// width it is given, as a smaller plate (tighter padding, smaller flag,
  /// name and chevron) so the name keeps its letters in a busy row; it
  /// ellipsizes only when that width runs short. The open menu keeps its own
  /// usable width. Off by default, so every existing caller renders exactly
  /// as before.
  final bool hugContent;

  /// When set, the open menu leads with "Pin `country` as default": a tap
  /// closes the menu and calls this. For rows with no room for a Pin of
  /// their own. Null (the default) leaves the menu as it was.
  final VoidCallback? onPinAsDefault;

  const CountryDropdown({
    super.key,
    required this.selectedCountryCode,
    required this.onChanged,
    this.hintText,
    this.isLoading = false,
    this.requireAuthToChange = true,
    this.compact = false,
    this.hugContent = false,
    this.onPinAsDefault,
  });

  @override
  ConsumerState<CountryDropdown> createState() => _CountryDropdownState();
}

class _CountryDropdownState extends ConsumerState<CountryDropdown> {
  final GlobalKey<GlassDropdownState<String>> _dropdownKey =
      GlobalKey<GlassDropdownState<String>>();
  var isDropDownOpen = false;
  var selectedCountryCode = 'US';
  final TextEditingController _searchController = TextEditingController();
  DateTime? _openedAt;
  bool _reopenAttempted = false;
  bool _isReopening = false;
  // A pick closes the menu on purpose; the tablet quick-close guard below
  // must not reopen it (seen on an unfolded iPhone Duo).
  bool _selectedSinceOpen = false;
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

  /// Puts the Pin entry ([CountryDropdown.onPinAsDefault]) above [search].
  /// It is the menu's fixed header, so it shows even though the list opens
  /// scrolled to the selected country.
  Widget _withPinEntry(VoidCallback? onPin, double height, Widget search) {
    if (onPin == null) return search;
    final name = ref
        .read(countryDropdownProvider.notifier)
        .getCountryName(selectedCountryCode);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Builder(
          builder: (menuContext) => _PinMenuEntry(
            label: 'Pin $name as default',
            height: height,
            onTap: () {
              // Closed on purpose: the tablet quick-close guard below must
              // not reopen it.
              _selectedSinceOpen = true;
              Navigator.of(menuContext).pop();
              onPin();
            },
          ),
        ),
        search,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = widget.compact;
    final hug = widget.hugContent;
    final buttonHeight = isCompact ? 36.h : 40.h;
    final horizontalPadding = hug ? 6.sp : (isCompact ? 12.sp : 20.sp);
    final verticalPadding = isCompact ? 0.sp : 7.sp;
    final flagWidth = hug ? 16.w : (isCompact ? 20.w : 16.w);
    final flagHeight = hug ? 11.h : (isCompact ? 14.h : 12.h);
    final nameGap = hug ? 6.w : (isCompact ? 8.w : 12.w);
    final chevronGap = hug ? 2.w : 4.w;
    final chevronSize = hug ? 14.ic : (isCompact ? 18.ic : 20.ic);
    final nameStyle = hug
        ? AppTypography.textXsMedium.copyWith(fontSize: 11.f)
        : (isCompact ? AppTypography.textXsMedium : AppTypography.textSmMedium);
    final onPin = widget.onPinAsDefault;
    final searchHeight = context.textExtent(56.h);
    final pinHeight = onPin == null ? 0.0 : context.textExtent(44.h);

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
                  : Border.all(color: context.colors.surfaceRecessed, width: 1.w),
        ),
        child: DropdownButtonHideUnderline(
          child: GlassDropdown<String>(
            key: _dropdownKey,
            isExpanded: true,
            customButton: Container(
              height: buttonHeight,
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Row(
                mainAxisSize: hug ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  if (!widget.isLoading && selectedCountryCode.isNotEmpty)
                    CountryFlag.fromCountryCode(
selectedCountryCode,
  theme: ImageTheme(width: flagWidth,
                      height: flagHeight,),
),
                  SizedBox(width: nameGap),
                  Flexible(
                    fit: hug ? FlexFit.loose : FlexFit.tight,
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
                              style: nameStyle.copyWith(
                                color: context.colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                  ),
                  SizedBox(width: chevronGap),
                  Icon(
                    isDropDownOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: context.colors.textPrimaryMuted,
                    size: chevronSize,
                  ),
                ],
              ),
            ),
            // The menu: the popover glass, toned to the surface it was, the
            // button's width (a hugging button's menu keeps a usable width
            // for the search field and full country names), flush under it.
            menuWidth: hug ? 300.w : null,
            menuMargin: EdgeInsets.zero,
            menuPadding: EdgeInsets.zero,
            menuItemPadding: EdgeInsets.zero,
            menuOffset: const Offset(0, -4),
            dropdownColor: context.colors.surface,
            menuBorderRadius: dropDownBorderRadius,
            menuMaxHeight: 300.h,
            highlightSelected: false,
            searchController: _searchController,
            menuHeaderHeight: pinHeight + searchHeight,
            menuHeader: _withPinEntry(
                onPin,
                pinHeight,
                Container(
                  height: searchHeight,
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
                        color: context.textInk(0.5),
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
                        borderSide: BorderSide(color: context.colors.surfaceRecessed, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.br),
                        borderSide: BorderSide(color: context.colors.surfaceRecessed, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.br),
                        // The focus ring must clear 3:1; ink at 0.3 is ~2:1
                        // on paper, so light rings in accent-text teal.
                        borderSide: BorderSide(
                          color:
                              context.isLightTheme
                                  ? context.colors.accentText
                                  : context.colors.textPrimary.withValues(
                                    alpha: 0.3,
                                  ),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            searchMatch: (item, searchValue) {
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
            itemHeight: context.textExtent(40.h),
            value: widget.isLoading ? null : selectedCountryCode,
            onChanged:
                widget.isLoading
                    ? null
                    : (value) async {
                      _selectedSinceOpen = true;
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
              if (!mounted) return;
              if (isOpen) {
                _openedAt = DateTime.now();
                _selectedSinceOpen = false;
                if (_isReopening) {
                  _isReopening = false;
                } else {
                  _reopenAttempted = false;
                }
              } else if (ResponsiveHelper.isTablet && _openedAt != null) {
                final elapsed = DateTime.now().difference(_openedAt!);
                if (elapsed < _minOpenDuration &&
                    !_reopenAttempted &&
                    !_selectedSinceOpen) {
                  _reopenAttempted = true;
                  _isReopening = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (_selectedSinceOpen) {
                      // The pick landed just after the close: stay closed.
                      _isReopening = false;
                      isDropDownOpen = false;
                      _searchController.clear();
                      setState(() {});
                      return;
                    }
                    _dropdownKey.currentState?.open();
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
                                color: context.colors.surfaceRecessed,
                                width: 1.w,
                              ),
                            ),
                          ),
                          height: context.textExtent(44.h),
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

/// The country menu's Pin entry: a bare pin and its words, in the accent
/// text ink, with the label on the country names' left edge.
class _PinMenuEntry extends StatelessWidget {
  const _PinMenuEntry({
    required this.label,
    required this.height,
    required this.onTap,
  });

  final String label;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.accentText;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: context.colors.surfaceRecessed,
                width: 1.w,
              ),
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Row(
            children: [
              // As wide as a country row's flag, so the words line up with
              // the names below.
              SizedBox(
                width: 16.w,
                child: Icon(Icons.push_pin_rounded, size: 16.ic, color: ink),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textMdMedium.copyWith(color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

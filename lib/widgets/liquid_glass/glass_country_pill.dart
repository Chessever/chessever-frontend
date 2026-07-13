import 'dart:ui';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_flags/country_flags.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// A floating liquid-glass pill showing the current country (flag + name), that
/// opens a liquid-glass popup with a scrollable, searchable country list.
///
/// Replaces the old boxed `dropdown_button2` country selector — the pill IS a
/// glass island (matches the page's floating chrome) and its menu is a blurred
/// glass panel instead of a flat opaque dropdown.
class GlassCountryPill extends StatelessWidget {
  const GlassCountryPill({
    super.key,
    required this.countryCode,
    required this.countryName,
    required this.onSelected,
    this.minWidth = 120,
    this.maxWidth = 220,
    this.height = 40,
  });

  final String countryCode;
  final String countryName;
  final ValueChanged<Country> onSelected;
  final double minWidth;
  final double maxWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth.w, maxWidth: maxWidth.w),
      child: GlassContainer(
        useOwnLayer: true,
        height: height,
        padding: EdgeInsets.zero,
        shape: LiquidRoundedSuperellipse(borderRadius: height / 2),
        quality: GlassQuality.standard,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            HapticFeedbackService.light();
            final picked = await showLiquidCountryPicker(
              context: context,
              selectedCountryCode: countryCode,
            );
            if (picked != null) onSelected(picked);
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (countryCode.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3.br),
                    child: CountryFlag.fromCountryCode(
                      countryCode,
                      theme: ImageTheme(width: 20.w, height: 14.h),
                    ),
                  ),
                SizedBox(width: 8.w),
                Flexible(
                  child: Text(
                    countryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(width: 4.w),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18.ic,
                  color: colors.textPrimaryMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the blurred liquid-glass country picker and returns the chosen country
/// (or `null` if dismissed).
Future<Country?> showLiquidCountryPicker({
  required BuildContext context,
  required String selectedCountryCode,
}) {
  return showGeneralDialog<Country>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Select country',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, _, __) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: _LiquidCountryPickerPanel(
            selectedCountryCode: selectedCountryCode,
          ),
        ),
      );
    },
  );
}

class _LiquidCountryPickerPanel extends StatefulWidget {
  const _LiquidCountryPickerPanel({required this.selectedCountryCode});

  final String selectedCountryCode;

  @override
  State<_LiquidCountryPickerPanel> createState() =>
      _LiquidCountryPickerPanelState();
}

class _LiquidCountryPickerPanelState extends State<_LiquidCountryPickerPanel> {
  final TextEditingController _searchController = TextEditingController();
  late final List<Country> _all;
  late List<Country> _filtered;

  @override
  void initState() {
    super.initState();
    _all = CountryService().getAll();
    _filtered = _all;
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all
              .where((c) => c.name.toLowerCase().contains(q))
              .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;

    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420.w,
              maxHeight: maxHeight,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24.br),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: GlassContainer(
                  useOwnLayer: true,
                  padding: EdgeInsets.zero,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                  settings: const LiquidGlassSettings(
                    glassColor: Color(0xC22A2A2E),
                    thickness: 20,
                    blur: 14,
                    lightIntensity: 0,
                    ambientStrength: 0,
                    glowIntensity: 0,
                    ambientRim: 0,
                    chromaticAberration: 0,
                  ),
                  // Material ancestor so the row InkWells can paint their
                  // splashes (a bare glass overlay has none).
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Search field.
                        Padding(
                          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
                          child: _SearchField(
                            controller: _searchController,
                            colors: colors,
                          ),
                        ),
                        // Bounded + shrink-wrapped so the list never demands
                        // infinite height (the glass panel hugs its child).
                        _filtered.isEmpty
                            ? Padding(
                                padding: EdgeInsets.symmetric(vertical: 32.h),
                                child: Text(
                                  'No countries found',
                                  style: AppTypography.textSmRegular.copyWith(
                                    color: colors.textPrimaryMuted,
                                  ),
                                ),
                              )
                            : ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: maxHeight - 88.h,
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.only(bottom: 8.h),
                                  itemCount: _filtered.length,
                                  itemBuilder: (context, i) {
                                    final country = _filtered[i];
                                    final selected =
                                        country.countryCode ==
                                        widget.selectedCountryCode;
                                    return _CountryRow(
                                      country: country,
                                      selected: selected,
                                      colors: colors,
                                      onTap: () =>
                                          Navigator.of(context).pop(country),
                                    );
                                  },
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.colors});

  final TextEditingController controller;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: false,
      style: AppTypography.textSmRegular.copyWith(color: colors.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search country',
        hintStyle: AppTypography.textSmRegular.copyWith(
          color: colors.textPrimary.withValues(alpha: 0.5),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20.ic,
          color: colors.textPrimary.withValues(alpha: 0.5),
        ),
        filled: true,
        fillColor: colors.textPrimary.withValues(alpha: 0.06),
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.br),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.country,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final Country country;
  final bool selected;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 48.h,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        color: selected
            ? colors.brand.withValues(alpha: 0.18)
            : Colors.transparent,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3.br),
              child: CountryFlag.fromCountryCode(
                country.countryCode,
                theme: ImageTheme(width: 22.w, height: 15.h),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                country.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textMdMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                size: 18.ic,
                color: colors.brand,
              ),
          ],
        ),
      ),
    );
  }
}

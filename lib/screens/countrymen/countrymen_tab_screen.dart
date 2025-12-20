import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_mode_provider.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_events_tab.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_games_tab.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CountrymenTabScreen extends ConsumerStatefulWidget {
  const CountrymenTabScreen({super.key});

  @override
  ConsumerState<CountrymenTabScreen> createState() =>
      _CountrymenTabScreenState();
}

class _CountrymenTabScreenState extends ConsumerState<CountrymenTabScreen> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    final initialPage = CountrymenScreenMode.values.indexOf(
      ref.read(selectedCountrymenModeProvider),
    );
    _pageController = PageController(initialPage: initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _handleTabSelection(int index) {
    try {
      ref
          .read(selectedCountrymenModeProvider.notifier)
          .update((_) => CountrymenScreenMode.values[index]);
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      debugPrint('Error handling tab selection: $e');
    }
  }

  void _handlePageChanged(int index) {
    try {
      final currentModeIndex = CountrymenScreenMode.values.indexOf(
        ref.read(selectedCountrymenModeProvider),
      );
      if (currentModeIndex != index) {
        ref
            .read(selectedCountrymenModeProvider.notifier)
            .update((_) => CountrymenScreenMode.values[index]);
      }
    } catch (e) {
      debugPrint('Error handling page change: $e');
    }
  }

  void _setAsDefault() {
    final countryAsync = ref.read(countryDropdownProvider);
    countryAsync.whenData((country) {
      HapticFeedbackService.medium();
      ref.read(countryDropdownProvider.notifier).selectCountry(country.countryCode);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${country.name} set as default country'),
          backgroundColor: kBlack2Color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.br),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedMode = ref.watch(selectedCountrymenModeProvider);
    final countryAsync = ref.watch(countryDropdownProvider);

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
          _buildAppBar(context, countryAsync),
          SizedBox(height: 8.h),
          _buildSegmentedSwitcher(selectedMode),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: 3,
              onPageChanged: _handlePageChanged,
              itemBuilder: (context, index) {
                switch (index) {
                  case 0:
                    return const CountrymenEventsTab();
                  case 1:
                    return const CountrymenGamesTab();
                  case 2:
                    return const CountrymenPlayersTab();
                  default:
                    return Center(
                      child: Text(
                        'Invalid page index: $index',
                        style: const TextStyle(color: kWhiteColor),
                      ),
                    );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, AsyncValue<Country> countryAsync) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36.w,
              height: 36.h,
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_outlined,
                size: 18.ic,
                color: kWhiteColor,
              ),
            ),
          ),
          SizedBox(width: 10.w),
          // Country dropdown - flexible but not full width
          Expanded(
            child: countryAsync.when(
              data: (country) => _buildCountrySelector(country),
              loading: () => Container(
                height: 36.h,
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                decoration: BoxDecoration(
                  color: kBlack2Color,
                  borderRadius: BorderRadius.circular(8.br),
                ),
                child: Center(
                  child: Text(
                    'Loading...',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor70,
                    ),
                  ),
                ),
              ),
              error: (_, __) => Container(
                height: 36.h,
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                decoration: BoxDecoration(
                  color: kBlack2Color,
                  borderRadius: BorderRadius.circular(8.br),
                ),
                child: Center(
                  child: Text(
                    'Error',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kRedColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          // Set as Default button
          countryAsync.maybeWhen(
            data: (_) => GestureDetector(
              onTap: _setAsDefault,
              child: Container(
                height: 36.h,
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                decoration: BoxDecoration(
                  color: kBlack2Color,
                  borderRadius: BorderRadius.circular(8.br),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.push_pin_outlined,
                      size: 14.ic,
                      color: const Color(0xFFA1A1AA),
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      'Pin',
                      style: AppTypography.textXsMedium.copyWith(
                        color: const Color(0xFFA1A1AA),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            orElse: () => SizedBox(width: 36.w),
          ),
        ],
      ),
    );
  }

  Widget _buildCountrySelector(Country country) {
    return CountryDropdown(
      selectedCountryCode: country.countryCode,
      onChanged: (newCountry) {
        ref.read(countryDropdownProvider.notifier).selectCountry(
          newCountry.countryCode,
        );
      },
      requireAuthToChange: false,
      compact: true,
    );
  }

  Widget _buildSegmentedSwitcher(CountrymenScreenMode selectedMode) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.sp),
      child: SegmentedSwitcher(
        backgroundColor: kPopUpColor,
        selectedBackgroundColor: kPopUpColor,
        options: countrymenModeNames.values.toList(),
        initialSelection: countrymenModeNames.values.toList().indexOf(
          countrymenModeNames[selectedMode]!,
        ),
        currentSelection: CountrymenScreenMode.values.indexOf(selectedMode),
        onSelectionChanged: _handleTabSelection,
      ),
    );
  }
}

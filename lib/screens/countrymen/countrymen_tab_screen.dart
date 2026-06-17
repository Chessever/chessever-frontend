import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_mode_provider.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_events_tab.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_games_tab.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
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
  final ScrollToTopBus _scrollToTopBus = ScrollToTopBus();

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
    _scrollToTopBus.dispose();
    super.dispose();
  }

  void _handleBackPressed() {
    // Clear temporary country selection when leaving the screen
    ref.read(temporaryCountryProvider.notifier).state = null;
    Navigator.of(context).pop();
  }

  void _handleTabSelection(int index) {
    try {
      final currentIndex = CountrymenScreenMode.values.indexOf(
        ref.read(selectedCountrymenModeProvider),
      );
      if (index == currentIndex) {
        _scrollToTopBus.request();
        return;
      }
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

  void _pinCurrentCountry() {
    // Get the current displayed country (temporary or persisted)
    final tempCountry = ref.read(temporaryCountryProvider);
    final persistedCountry = ref.read(countryDropdownProvider).valueOrNull;
    final currentCountry = tempCountry ?? persistedCountry;

    if (currentCountry != null) {
      HapticFeedbackService.medium();
      // Persist this country as the default
      ref
          .read(countryDropdownProvider.notifier)
          .selectCountry(currentCountry.countryCode);
      // Clear temporary selection since it's now the default
      ref.read(temporaryCountryProvider.notifier).state = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${currentCountry.name} pinned as default'),
          backgroundColor: context.colors.surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.br),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Check if the current displayed country is different from the pinned one
  bool _isTemporarySelection() {
    final tempCountry = ref.watch(temporaryCountryProvider);
    return tempCountry != null;
  }

  @override
  Widget build(BuildContext context) {
    final selectedMode = ref.watch(selectedCountrymenModeProvider);
    final persistedCountryAsync = ref.watch(countryDropdownProvider);
    final tempCountry = ref.watch(temporaryCountryProvider);

    // Effective country: temporary selection takes precedence
    final effectiveCountryAsync =
        tempCountry != null
            ? AsyncValue.data(tempCountry)
            : persistedCountryAsync;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
              _buildAppBar(context, effectiveCountryAsync, selectedMode),
              SizedBox(height: 8.h),
              _buildSegmentedSwitcher(selectedMode),
              Expanded(
                child: ScrollToTopScope(
                  bus: _scrollToTopBus,
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
                              style: TextStyle(
                                color: context.colors.textPrimary,
                              ),
                            ),
                          );
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    AsyncValue<Country> countryAsync,
    CountrymenScreenMode selectedMode,
  ) {
    final isTemporary = _isTemporarySelection();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: _handleBackPressed,
            child: Container(
              width: 36.w,
              height: 36.h,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_outlined,
                size: 18.ic,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: 10.w),
          // Country dropdown - flexible but not full width
          Expanded(
            child: countryAsync.when(
              data: (country) => _buildCountrySelector(country),
              loading:
                  () => Container(
                    height: 36.h,
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(8.br),
                    ),
                    child: Center(
                      child: Text(
                        'Loading...',
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimaryMuted,
                        ),
                      ),
                    ),
                  ),
              error:
                  (_, __) => Container(
                    height: 36.h,
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
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
          // Pin button - only show when there's a temporary selection
          countryAsync.maybeWhen(
            data:
                (_) =>
                    isTemporary
                        ? GestureDetector(
                          onTap: _pinCurrentCountry,
                          child: Container(
                            height: 36.h,
                            padding: EdgeInsets.symmetric(horizontal: 10.w),
                            decoration: BoxDecoration(
                              color: kPrimaryColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8.br),
                              border: Border.all(
                                color: kPrimaryColor.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 14.ic,
                                  color: kPrimaryColor,
                                ),
                                SizedBox(width: 4.w),
                                Text(
                                  'Pin',
                                  style: AppTypography.textXsMedium.copyWith(
                                    color: kPrimaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        : const SizedBox.shrink(), // Hide when already pinned
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildCountrySelector(Country country) {
    return CountryDropdown(
      selectedCountryCode: country.countryCode,
      onChanged: (newCountry) {
        // Set as temporary selection (not persisted)
        // User must tap "Pin" to make it permanent
        ref.read(temporaryCountryProvider.notifier).state = newCountry;
      },
      requireAuthToChange: false,
      compact: true,
    );
  }

  Widget _buildSegmentedSwitcher(CountrymenScreenMode selectedMode) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: SegmentedSwitcher(
        backgroundColor: context.colors.popup,
        selectedBackgroundColor: context.colors.popup,
        options: countrymenModeNames.values.toList(),
        initialSelection: countrymenModeNames.values.toList().indexOf(
          countrymenModeNames[selectedMode]!,
        ),
        currentSelection: CountrymenScreenMode.values.indexOf(selectedMode),
        onSelectionChanged: _handleTabSelection,
        notifyOnReselect: true,
      ),
    );
  }
}

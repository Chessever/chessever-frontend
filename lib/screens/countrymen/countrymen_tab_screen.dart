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
import 'package:chessever2/widgets/liquid_glass/chrome_scroll_collapse.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_floating_segments.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_stack.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
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
  final ChromeScrollCollapse _chromeCollapse = ChromeScrollCollapse();

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
        if (!_chromeCollapse.expanded) {
          setState(_chromeCollapse.reset);
        }
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
      if (!_chromeCollapse.expanded) {
        setState(_chromeCollapse.reset);
      }
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
      if (!_chromeCollapse.expanded) {
        setState(_chromeCollapse.reset);
      }
    } catch (e) {
      debugPrint('Error handling page change: $e');
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    if (_chromeCollapse.onScrollUpdate(notification) && mounted) {
      setState(() {});
    }
    return false;
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

    // GlassPage composition (via ScreenWrapper) so glass chrome islands
    // sample backdrop correctly per liquid_glass_widgets package contract.
    return ScreenWrapper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Column(
              children: [
                GlassIslandStack(
                  gap: 6,
                  children: [
                    _buildAppBar(
                      context,
                      effectiveCountryAsync,
                      selectedMode,
                    ),
                    GlassFloatingSegments(
                      options: countrymenModeNames.values.toList(),
                      selectedIndex: CountrymenScreenMode.values
                          .indexOf(selectedMode)
                          .clamp(0, countrymenModeNames.length - 1),
                      onSelected: _handleTabSelection,
                      expanded: _chromeCollapse.expanded,
                      notifyOnReselect: true,
                    ),
                  ],
                ),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
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
                ),
              ],
            ),
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

    // Compact islands: back + content-sized country chip (not full-bleed title).
    return GlassIslandTopBar(
      horizontalPadding: 12.w,
      topPadding: 0,
      leading: GlassBackButton(onPressed: _handleBackPressed),
      title: countryAsync.when(
        data:
            (country) => ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 200.w, minWidth: 120.w),
              child: GlassContainer(
                useOwnLayer: true,
                height: 40,
                padding: EdgeInsets.zero,
                shape: const LiquidRoundedSuperellipse(borderRadius: 20),
                quality: GlassQuality.standard,
                clipBehavior: Clip.antiAlias,
                child: _buildCountrySelector(country),
              ),
            ),
        loading:
            () => GlassTitleChip(
              label: 'Loading…',
              textStyle: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimaryMuted,
              ),
            ),
        error:
            (_, __) => GlassTitleChip(
              label: 'Error',
              textStyle: AppTypography.textSmMedium.copyWith(color: kRedColor),
            ),
      ),
      trailing: [
        if (isTemporary)
          GlassIconButton(
            icon: Icon(
              Icons.push_pin_rounded,
              color: kPrimaryColor,
              size: 18.ic,
            ),
            onPressed: _pinCurrentCountry,
            size: 40,
            iconSize: 18,
            useOwnLayer: true,
          ),
      ],
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
}

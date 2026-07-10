import 'package:chessever2/e2e/e2e_ids.dart';
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
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_stack.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
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
      _showPage(index);
      if (!_chromeCollapse.expanded) {
        setState(_chromeCollapse.reset);
      }
    } catch (e) {
      debugPrint('Error handling tab selection: $e');
    }
  }

  void _showPage(int index) {
    if (GlassMotion.reduceMotion(context)) {
      _pageController.jumpToPage(index);
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
    final selectedIndex = CountrymenScreenMode.values.indexOf(selectedMode);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(14) * 1.2;
    final controlHeight = (scaledLabelHeight + 24).clamp(48.0, 72.0).toDouble();
    final contentTopInset = viewPadding.top + controlHeight * 2 + 24;
    final keepSegmentsExpanded = GlassMotion.reduceMotion(context);

    return GlassFullScreenPage(
      key: e2eKey(E2eIds.countrymenRoot),
      backgroundColor: context.colors.background,
      includeContentSafeArea: false,
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Countrymen controls',
            child: GlassIslandStack(
              key: const ValueKey<String>('countrymen-floating-controls'),
              includeStatusBar: false,
              gap: 6,
              children: [
                _buildAppBar(context, effectiveCountryAsync, controlHeight),
                Semantics(
                  container: true,
                  label: 'Countrymen sections',
                  value: countrymenModeNames[selectedMode],
                  child: SizedBox(
                    key: const ValueKey<String>('countrymen-segments'),
                    height: controlHeight,
                    child: Center(
                      child: GlassFloatingSegments(
                        options: countrymenModeNames.values.toList(),
                        selectedIndex: selectedIndex.clamp(
                          0,
                          countrymenModeNames.length - 1,
                        ),
                        onSelected: _handleTabSelection,
                        expanded:
                            keepSegmentsExpanded || _chromeCollapse.expanded,
                        notifyOnReselect: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ScrollToTopScope(
              bus: _scrollToTopBus,
              child: PageView.builder(
                key: const ValueKey<String>('countrymen-page-view'),
                controller: _pageController,
                itemCount: 3,
                onPageChanged: _handlePageChanged,
                itemBuilder: (context, index) {
                  final page = switch (index) {
                    0 => const CountrymenEventsTab(),
                    1 => const CountrymenGamesTab(),
                    2 => const CountrymenPlayersTab(),
                    _ => Center(
                      child: Text(
                        'Invalid page index: $index',
                        style: TextStyle(color: context.colors.textPrimary),
                      ),
                    ),
                  };
                  return Padding(
                    padding: EdgeInsets.only(
                      top: contentTopInset,
                      bottom: viewPadding.bottom,
                    ),
                    child: page,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    AsyncValue<Country> countryAsync,
    double controlHeight,
  ) {
    final isTemporary = _isTemporarySelection();

    // Compact islands: back + content-sized country chip (not full-bleed title).
    return GlassIslandTopBar(
      horizontalPadding: 12.w,
      topPadding: 0,
      height: controlHeight,
      leading: GlassBackButton(onPressed: _handleBackPressed),
      title: countryAsync.when(
        data:
            (country) => Semantics(
              container: true,
              button: true,
              label: 'Choose country',
              value: country.name,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 200.w, minWidth: 120.w),
                child: GlassContainer(
                  useOwnLayer: true,
                  height: controlHeight,
                  padding: EdgeInsets.zero,
                  shape: LiquidRoundedSuperellipse(
                    borderRadius: controlHeight / 2,
                  ),
                  quality: GlassQuality.standard,
                  clipBehavior: Clip.antiAlias,
                  child: _buildCountrySelector(country),
                ),
              ),
            ),
        loading:
            () => GlassTitleChip(
              label: 'Loading…',
              height: controlHeight,
              textStyle: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimaryMuted,
              ),
            ),
        error:
            (_, __) => GlassTitleChip(
              label: 'Error',
              height: controlHeight,
              textStyle: AppTypography.textSmMedium.copyWith(color: kRedColor),
            ),
      ),
      trailing: [
        if (isTemporary)
          Semantics(
            button: true,
            label: 'Pin selected country as default',
            onTap: _pinCurrentCountry,
            child: ExcludeSemantics(
              child: GlassIconButton(
                icon: Icon(
                  Icons.push_pin_rounded,
                  color: kPrimaryColor,
                  size: 18.ic,
                ),
                onPressed: _pinCurrentCountry,
                size: 48,
                iconSize: 18,
                useOwnLayer: true,
              ),
            ),
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

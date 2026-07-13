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
import 'package:chessever2/widgets/liquid_glass/chrome_scroll_collapse.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_country_pill.dart';
import 'package:chessever2/widgets/liquid_glass/liquid_tab_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:chessever2/widgets/liquid_glass/liquid_glass_halo.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/cupertino.dart';
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
    // Hide the floating bottom country pill while the Games-tab search is open.
    final searchActive = ref.watch(countrymenSearchActiveProvider);

    // Effective country: temporary selection takes precedence
    final effectiveCountryAsync =
        tempCountry != null
            ? AsyncValue.data(tempCountry)
            : persistedCountryAsync;

    // Page content owns the whole screen edge-to-edge; the discrete glass
    // islands float on top and the list scrolls *underneath* them. Each tab
    // gets this inset as leading padding so its first row clears the islands
    // (status bar + control row + gap + segment island) without a reserved
    // opaque strip that would read as a traditional appbar.
    final statusTop = MediaQuery.viewPaddingOf(context).top;
    // Single-line header now (back + country pill + segments).
    final topInset = statusTop + 64;

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
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Full-bleed page content.
                Positioned.fill(
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
                              return CountrymenEventsTab(topPadding: topInset);
                            case 1:
                              return CountrymenGamesTab(topPadding: topInset);
                            case 2:
                              return CountrymenPlayersTab(topPadding: topInset);
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
                // Floating glass chrome — scales down on scroll-down and back up
                // on scroll-up, mirroring the home bottom nav bar's behaviour.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedScale(
                    scale: _chromeCollapse.expanded ? 1.0 : 0.94,
                    alignment: Alignment.topCenter,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _chromeCollapse.expanded ? 1.0 : 0.96,
                      duration: const Duration(milliseconds: 240),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(12.w, statusTop + 8, 12.w, 0),
                        // One line: back button + the mode tabs hugging the
                        // right. Tabs are the SAME bare LiquidTabBar (with icons)
                        // used on Home / Tournaments / Calendar. The country
                        // selector moved to a floating pill at the bottom.
                        child: SizedBox(
                          height: 44,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              LiquidGlassHalo(
                                borderRadius: 20,
                                child: GlassBackButton(
                                  onPressed: _handleBackPressed,
                                ),
                              ),
                              const Spacer(),
                              LiquidTabBar(
                                options: countrymenModeNames.values.toList(),
                                icons: const [
                                  CupertinoIcons.calendar,
                                  CupertinoIcons.square_grid_2x2,
                                  CupertinoIcons.person_2,
                                ],
                                selectedIndex: CountrymenScreenMode.values
                                    .indexOf(selectedMode)
                                    .clamp(0, countrymenModeNames.length - 1),
                                onSelected: _handleTabSelection,
                                separated: !_chromeCollapse.expanded,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Floating country selector at the BOTTOM — mirrors the
                // tournament-detail bottom category pill. No room for it up top.
                // Hidden while the Games-tab search field is expanded.
                if (!searchActive)
                  Positioned(
                    bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
                    left: 0,
                    right: 0,
                    child: AnimatedScale(
                      scale: _chromeCollapse.expanded ? 1.0 : 0.9,
                      alignment: Alignment.bottomCenter,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: _buildBottomCountrySelector(
                        context,
                        effectiveCountryAsync,
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

  /// Floating country selector pill (+ optional pin) centred at the bottom of
  /// the screen — the tournament-detail bottom-selector pattern. Content scrolls
  /// underneath; the top row only carries the back button and mode tabs.
  Widget _buildBottomCountrySelector(
    BuildContext context,
    AsyncValue<Country> countryAsync,
  ) {
    final isTemporary = _isTemporarySelection();

    // Perfect centring (tournament-detail pattern): a left spacer equal to the
    // trailing pin (40 + 8 gap) balances the row so the pill sits dead-centre.
    const double pinSlot = 48;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          if (isTemporary) const SizedBox(width: pinSlot),
          Expanded(
            child: Center(
              child: countryAsync.when(
                data:
                    (country) => LiquidGlassHalo(
                      borderRadius: 20,
                      child: GlassCountryPill(
                        height: 40,
                        countryCode: country.countryCode,
                        countryName: country.name,
                        onSelected: (newCountry) {
                          // Temporary selection — user taps Pin to persist it.
                          ref.read(temporaryCountryProvider.notifier).state =
                              newCountry;
                        },
                      ),
                    ),
                loading:
                    () => LiquidGlassHalo(
                      borderRadius: 20,
                      child: GlassTitleChip(
                        height: 40,
                        label: 'Loading…',
                        textStyle: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimaryMuted,
                        ),
                      ),
                    ),
                error:
                    (_, __) => LiquidGlassHalo(
                      borderRadius: 20,
                      child: GlassTitleChip(
                        height: 40,
                        label: 'Error',
                        textStyle: AppTypography.textSmMedium.copyWith(
                          color: kRedColor,
                        ),
                      ),
                    ),
              ),
            ),
          ),
          if (isTemporary) ...[
            const SizedBox(width: 8),
            LiquidGlassHalo(
              borderRadius: 20,
              child: GlassIconButton(
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
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_combined_games_provider.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_mode_provider.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_events_tab.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_games_tab.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/favorite_player_identity.dart'
    show countryCodeToIso2;
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/ink_fab.dart' show InkFabStack, SearchInkFab;
import 'package:chessever2/widgets/page_spring.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CountrymenTabScreen extends ConsumerStatefulWidget {
  const CountrymenTabScreen({super.key, this.initialCountryCode});

  /// Opens on this federation (ISO alpha-2 like `NO`, or a FIDE code like
  /// `NOR`) as a temporary pick, exactly as if it were chosen in the country
  /// dropdown: "Pin" still makes it the default. Null opens on the user's
  /// own country, as always.
  final String? initialCountryCode;

  /// The picker's country for [code], or null when it names none.
  static Country? countryFor(String? code) {
    final raw = code?.trim() ?? '';
    if (raw.isEmpty) return null;
    final iso2 = countryCodeToIso2(raw);
    if (iso2.isEmpty) return null;
    return CountryService().findByCode(iso2);
  }

  /// Selects [code] before the screen is pushed, so its first frame and its
  /// tabs' first fetch are already for that country. Returns false when the
  /// code names no country.
  static bool preselect(WidgetRef ref, String? code) {
    final country = countryFor(code);
    if (country == null) return false;
    _selectTemporary(ref, country);
    return true;
  }

  static void _selectTemporary(WidgetRef ref, Country country) {
    final persisted = ref.read(countryDropdownProvider).valueOrNull;
    // The user's own country is not a temporary pick; it would only show a
    // redundant "Pin".
    ref.read(temporaryCountryProvider.notifier).state =
        persisted?.countryCode == country.countryCode ? null : country;
  }

  @override
  ConsumerState<CountrymenTabScreen> createState() =>
      _CountrymenTabScreenState();
}

class _CountrymenTabScreenState extends ConsumerState<CountrymenTabScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  final ScrollToTopBus _scrollToTopBus = ScrollToTopBus();

  /// The header (app bar row and tabs) and the floating buttons scroll away
  /// with the list and come back as it scrolls up (X-style).
  late final ScrollChromeController _chrome = ScrollChromeController(
    vsync: this,
  );

  /// The page's full-page search (Trello #1420), one on every tab: the
  /// floating button's glass becomes the field in the header's place, over
  /// the same list, which the query narrows. The host ([SearchModeHost]) runs
  /// the morph, back, focus and the query; the page sends the query to the
  /// tab it was opened on ([_searchedMode]).
  final SearchModeController _search = SearchModeController();

  /// The tab the open search belongs to: set as it opens, and the pages hold
  /// still while it is open ([SearchModeController.pagePhysics]).
  CountrymenScreenMode? _searchedMode;

  CountrymenCombinedGamesNotifier get _games =>
      ref.read(countrymenCombinedGamesProvider.notifier);

  /// The country [CountrymenTabScreen.initialCountryCode] selected, cleared
  /// again when the screen goes (the back button already does, a swipe back
  /// did not), so it never leaks into the next plain visit.
  String? _seededCode;
  ProviderContainer? _container;

  @override
  void initState() {
    super.initState();
    final initialPage = CountrymenScreenMode.values.indexOf(
      ref.read(selectedCountrymenModeProvider),
    );
    _pageController = PageController(initialPage: initialPage);

    final country = CountrymenTabScreen.countryFor(widget.initialCountryCode);
    if (country != null) {
      _seededCode = country.countryCode;
      _container = ProviderScope.containerOf(context, listen: false);
      final showing = ref.read(effectiveCountryProvider).valueOrNull;
      if (showing?.countryCode != country.countryCode) {
        // Providers cannot change while the tree builds. Callers that went
        // through [CountrymenTabScreen.preselect] never get here.
        Future.microtask(() {
          if (!mounted) return;
          CountrymenTabScreen._selectTemporary(ref, country);
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollToTopBus.dispose();
    _search.dispose();
    _chrome.dispose();
    final code = _seededCode;
    final container = _container;
    if (code != null && container != null) {
      Future.microtask(() {
        final temporary = container.read(temporaryCountryProvider.notifier);
        if (temporary.state?.countryCode == code) temporary.state = null;
      });
    }
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
      _chrome.show();
      ref
          .read(selectedCountrymenModeProvider.notifier)
          .update((_) => CountrymenScreenMode.values[index]);
      // On the spring every part of the page's chrome moves on.
      _pageController.springTo(index, context: context);
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
        _chrome.show();
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
      showAppSnack(context, '${currentCountry.name} pinned as default');
    }
  }

  /// Check if the current displayed country is different from the pinned one
  bool _isTemporarySelection() {
    final tempCountry = ref.watch(temporaryCountryProvider);
    return tempCountry != null;
  }

  /// The settled query, to the tab the search was opened on: every list
  /// here asks the server.
  void _onSearchQuery(String query) {
    switch (_searchedMode) {
      case CountrymenScreenMode.games:
        if (query.isNotEmpty) {
          unawaited(_games.searchGames(query));
        } else if (_search.isSearching) {
          // The field emptied while still searching: the plain list again.
          unawaited(_games.clearSearch());
        }
      case CountrymenScreenMode.events:
        unawaited(ref.read(countrymenEventsProvider.notifier).search(query));
      case CountrymenScreenMode.players:
        unawaited(ref.read(countrymenPlayersProvider.notifier).search(query));
      case null:
        break;
    }
  }

  /// In the tap's tick, once: only the query goes with the search, and only
  /// on the tab it searched (reading another tab's list would start its
  /// fetch). Classical, Filters and the ranking filters stay applied.
  void _onSearchClosed() {
    final mode = _searchedMode;
    _searchedMode = null;
    switch (mode) {
      case CountrymenScreenMode.games:
        unawaited(_games.clearSearch());
      case CountrymenScreenMode.events:
        unawaited(ref.read(countrymenEventsProvider.notifier).clearSearch());
      case CountrymenScreenMode.players:
        unawaited(ref.read(countrymenPlayersProvider.notifier).clearSearch());
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedMode = ref.watch(selectedCountrymenModeProvider);
    // Effective country: a temporary selection takes precedence.
    final effectiveCountryAsync = ref.watch(effectiveCountryProvider);

    return SearchModeHost(
      controller: _search,
      chrome: _chrome,
      debounce: const Duration(milliseconds: 400),
      onOpen: () => _searchedMode = ref.read(selectedCountrymenModeProvider),
      onQuery: _onSearchQuery,
      onClose: _onSearchClosed,
      child: Scaffold(
        backgroundColor: context.colors.background,
        // Every tab floats its search in the thumb's reach, and Games Live
        // first above it while a game is in play (Trello #1420). They stay
        // mounted while searching: the host steps them back, and the glass
        // flies back into the search as it closes.
        floatingActionButton: SlidingFabs(
          controller: _chrome,
          child: _CountrymenFabs(mode: selectedMode),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Column(
              children: [
                SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4.h),
                // Folds up under the status bar as the list scrolls down,
                // comes back as it scrolls up.
                CollapsingChrome(
                  controller: _chrome,
                  child: SearchModeHeaderSlot(
                    header: Column(
                      children: [
                        _buildAppBar(
                          context,
                          effectiveCountryAsync,
                          selectedMode,
                        ),
                        SizedBox(height: 8.h),
                        _buildSegmentedSwitcher(selectedMode),
                        SizedBox(height: 4.h),
                      ],
                    ),
                    // The chevron (and on Games, Classical and Filters) stay
                    // where the app bar has them; the country and the board
                    // view give way to the field.
                    search: _buildSearchHeader(selectedMode),
                  ),
                ),
                Expanded(
                  child: ScrollChromeRegion(
                    controller: _chrome,
                    child: ScrollToTopScope(
                      bus: _scrollToTopBus,
                      // Searching holds the page: the search belongs to the
                      // tab it opened on.
                      child: ListenableBuilder(
                        listenable: _search,
                        builder: (context, _) => PageView.builder(
                          controller: _pageController,
                          physics: _search.pagePhysics(),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The search header for the tab it opens on: the field searches that
  /// tab's list. Games keeps Classical and Filters beside it, held still
  /// where the app bar has them.
  Widget _buildSearchHeader(CountrymenScreenMode mode) {
    return switch (mode) {
      CountrymenScreenMode.games => const SearchModeHeader(
        hintText: 'Search',
        rotatingHints: CountrymenGamesToolbar.searchHints,
        closeKey: ValueKey('games_search_close'),
        trailing: [CountrymenGamesToolbar.inSearch],
      ),
      CountrymenScreenMode.events => const SearchModeHeader(
        hintText: 'Search events',
        textFieldKey: ValueKey('countrymen_events_search_field'),
        closeKey: ValueKey('countrymen_search_close'),
      ),
      CountrymenScreenMode.players => const SearchModeHeader(
        hintText: 'Search players',
        textFieldKey: ValueKey('countrymen_players_search_field'),
        closeKey: ValueKey('countrymen_search_close'),
      ),
    };
  }

  /// Room the picker and the Pin keep beside each other in the row: what
  /// they had beside the four controls the row carried before Trello #1420
  /// (a 480pt row less back, four 44pt controls and the gaps).
  static const double _pickerAndPinRoom = 260;

  /// Below this row width (inside the row's margins) the Games page's toolbar
  /// takes the Pin out of the row: it leads the country menu instead, so the
  /// country name keeps the room. With the toolbar's three controls that is
  /// every phone; tablets and other pages keep the Pin in the row.
  static double get _inlinePinMinRowWidth =>
      SearchHeaderMetrics.backTarget +
      4.w +
      _pickerAndPinRoom +
      4.w +
      CountrymenGamesToolbar.width;

  /// Back, the country picker (and Pin) beside it, and on the Games page the
  /// list's toolbar at the far end (board view, Classical, Filters). Back,
  /// Classical and Filters sit exactly where the search header puts its
  /// chevron and its Classical and Filters, so opening the search only trades
  /// the country (and the board view) for the field.
  Widget _buildAppBar(
    BuildContext context,
    AsyncValue<Country> countryAsync,
    CountrymenScreenMode selectedMode,
  ) {
    final isTemporary = _isTemporarySelection();
    final country = countryAsync.valueOrNull;
    final showToolbar = selectedMode == CountrymenScreenMode.games;
    final gutter = SearchHeaderMetrics.gutter;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        SearchHeaderMetrics.leadingInset,
        0,
        showToolbar
            ? math.max(0.0, gutter - SearchHeaderMetrics.trailingReach)
            : gutter,
        0,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pinInMenu =
              showToolbar && constraints.maxWidth < _inlinePinMinRowWidth;
          return ConstrainedBox(
            // The back row of every header: the search header's too.
            constraints: const BoxConstraints(
              minHeight: SearchHeaderMetrics.rowHeight,
            ),
            child: Row(
              children: [
                PageBackButton(onPressed: _handleBackPressed),
                SizedBox(width: 4.w),
                // The picker hugs its flag and name, with the Pin beside it
                // when the row has room; short of room the name ellipsizes.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: countryAsync.when(
                          data: (country) => _buildCountrySelector(
                            country,
                            offerPin: isTemporary && pinInMenu,
                          ),
                          loading: () => _buildCountryPlaceholder(
                            context,
                            'Loading...',
                            context.colors.textPrimaryMuted,
                          ),
                          error: (_, __) => _buildCountryPlaceholder(
                            context,
                            'Error',
                            context.colors.danger,
                          ),
                        ),
                      ),
                      if (isTemporary && country != null && !pinInMenu)
                        _buildPinButton(context, country),
                    ],
                  ),
                ),
                if (showToolbar) ...[
                  const SizedBox(width: 4),
                  const CountrymenGamesToolbar(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCountryPlaceholder(
    BuildContext context,
    String label,
    Color color,
  ) {
    return Container(
      height: 36.h,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.textSmMedium.copyWith(color: color),
      ),
    );
  }

  /// Pins the country on screen as the default. A bare glyph and its word,
  /// never a tinted box.
  Widget _buildPinButton(BuildContext context, Country country) {
    final ink = context.colors.accentText;
    final label = 'Pin ${country.name} as default';
    return Semantics(
      button: true,
      label: label,
      onTap: _pinCurrentCountry,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _pinCurrentCountry,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: 36.w, minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.push_pin_rounded, size: 16.ic, color: ink),
                  SizedBox(width: 4.w),
                  Text(
                    'Pin',
                    maxLines: 1,
                    style: AppTypography.textXsMedium.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// With [offerPin] the open menu leads with the Pin action, for rows too
  /// narrow to carry it beside the name.
  Widget _buildCountrySelector(Country country, {bool offerPin = false}) {
    return CountryDropdown(
      selectedCountryCode: country.countryCode,
      onChanged: (newCountry) {
        // Set as temporary selection (not persisted)
        // User must tap "Pin" to make it permanent
        ref.read(temporaryCountryProvider.notifier).state = newCountry;
      },
      requireAuthToChange: false,
      compact: true,
      hugContent: true,
      onPinAsDefault: offerPin ? _pinCurrentCountry : null,
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
        dotScope: 'countrymen.tab',
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

/// The floating buttons over the tab in view: Games floats its own (Live
/// first above the search, [CountrymenGamesFabs]); Events and Rankings
/// float the search alone, searching their own list, through the same stack
/// ([InkFabStack]) as every page's buttons.
class _CountrymenFabs extends StatelessWidget {
  const _CountrymenFabs({required this.mode});

  final CountrymenScreenMode mode;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      CountrymenScreenMode.games => const CountrymenGamesFabs(),
      CountrymenScreenMode.events => const InkFabStack(
        children: [
          SearchInkFab(
            key: ValueKey('countrymen_search_fab'),
            label: 'Search events',
          ),
        ],
      ),
      CountrymenScreenMode.players => const InkFabStack(
        children: [
          SearchInkFab(
            key: ValueKey('countrymen_search_fab'),
            label: 'Search players',
          ),
        ],
      ),
    };
  }
}

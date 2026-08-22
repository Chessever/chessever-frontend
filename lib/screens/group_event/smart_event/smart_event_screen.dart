import 'dart:async';

import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/utils/event_time_control.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/fluid_shimmer_painter.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/game_search_filter_bar.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

const smartEventTabLabels = <String>['About', 'Games', 'Events'];

/// Full event view for generated level games — an aggregate of every matching
/// game across broadcasts, not just currently-running events. Renders the
/// familiar About / Games / Events tabbed shell. Games paginate one day
/// at a time ([smartAggregateEventRepositoryProvider]) so first paint is the
/// newest day rather than a multi-thousand-row fetch.
class SmartEventScreen extends ConsumerStatefulWidget {
  const SmartEventScreen({required this.request, super.key});

  final SmartEventRequest request;

  @override
  ConsumerState<SmartEventScreen> createState() => _SmartEventScreenState();
}

class _SmartEventScreenState extends ConsumerState<SmartEventScreen> {
  static const _tabs = smartEventTabLabels;
  static const _validTiers = <String>{'GM', 'IM', 'FM', 'CM', 'All'};

  // Default to Games because this surface is opened from a generated games card.
  int _index = 1;
  late final PageController _page = PageController(initialPage: _index);

  // Search lives on the screen (not the Games tab) so the field can sit
  // pinned above the tab switcher like the regular event view, and so the
  // one query drives both the Games and Events tabs.
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';
  Timer? _searchDebounce;

  // Local tier filter: starts from the saved request's tier (first word so
  // "GM Rapid" defaults the filter to GM) and is mutated by the app bar
  // dropdown without leaving the screen.
  late String _tier = _initialTier(widget.request);

  /// In-event dialog filter, owned here (not by the Games tab) so the exit
  /// flow can compare it against the request's generating criteria and offer
  /// to apply + save the overrides. Seeded from those criteria, so the root
  /// filters that created this smart event arrive pre-selected and counted
  /// by the filter-button badge.
  late GameFilter _filter = widget.request.seedGameFilter();

  /// The last applied/saved identity of this smart event. Starts as the
  /// opening request and is re-pointed every time the user confirms an
  /// apply — so dirty-tracking measures against what is actually persisted,
  /// not against the (stale) opening request.
  late SmartEventRequest _baselineRequest = widget.request;

  final ScrollToTopBus _scrollToTopBus = ScrollToTopBus();

  static String _initialTier(SmartEventRequest request) {
    final first = request.tierLabel.split(' ').first;
    return _validTiers.contains(first) ? first : 'All';
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _page.dispose();
    _scrollToTopBus.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (_index == i) {
      _scrollToTopBus.request();
      return;
    }
    // Drop the keyboard when switching tabs so the field and the keyboard
    // collapse together instead of the keyboard hovering over About.
    _searchFocusNode.unfocus();
    setState(() => _index = i);
    _page.animateToPage(
      i,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// The request as the user currently sees it: the saved one re-keyed by
  /// the dialog's criteria overrides ([SmartEventRequest
  /// .withGameFilterOverrides]) and the tier dropdown ([SmartEventRequest
  /// .withTierSelection]) so naming, caption, Elo floor and favorite
  /// identity all follow the overridden config. The Games / Events tabs
  /// load through [SmartEventRequest.withNeutralEloRange] and carry the
  /// selected tier threshold in the query filter instead, so any tier —
  /// including ones BELOW the saved floor — can actually fetch its games.
  SmartEventRequest get _effectiveRequest {
    var updated = _baselineRequest.withGameFilterOverrides(_filter);
    if (_tier != _initialTier(_baselineRequest)) {
      updated = updated.withTierSelection(_tier);
    }
    return updated;
  }

  /// Whether the user diverged from the criteria this smart event was
  /// generated from — the dimensions a smart event is keyed on (tier
  /// threshold, live/completed state, time control, opening). Result / year /
  /// OTB-online / sort tweaks are view-only narrowing and never dirty the
  /// config.
  bool get _isConfigDirty {
    final seed = _baselineRequest.seedGameFilter();
    return _tier != _initialTier(_baselineRequest) ||
        _filter.live != seed.live ||
        _filter.timeControl != seed.timeControl ||
        _filter.eco != seed.eco;
  }

  // Overrides stay local until the user confirms them on the way out (back
  // navigation or the save button) — nothing is persisted while exploring.
  void _setTier(String tier) {
    if (_tier == tier) return;
    setState(() => _tier = tier);
  }

  void _setFilter(GameFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
  }

  /// Persists the overridden config: writes it back into the tabs' filter
  /// popup state — the smart event IS a projection of that state, so the
  /// generated cards on For You / Current rename and regenerate — and, when
  /// this smart event is saved, rewrites the favorite row to the re-keyed
  /// request (identity embeds the Elo floor, and even an identity-stable
  /// change must refresh the stored criteria metadata).
  Future<void> _applyConfigChanges() async {
    final updated = _effectiveRequest;

    final filter = ref.read(eventAppliedFilterProvider);
    ref.read(eventAppliedFilterProvider.notifier).state = filter.copyWith(
      formatsAndStates: updated.formatsAndStates,
      eco: updated.eco,
      eloRange: RangeValues(
        updated.minElo
            .toDouble()
            .clamp(kFilterMinElo, kFilterMaxElo)
            .toDouble(),
        updated.maxElo
            .toDouble()
            .clamp(kFilterMinElo, kFilterMaxElo)
            .toDouble(),
      ),
    );

    // Criteria-based lookup so legacy (v1, event-set-keyed) rows are found
    // and rewritten to the criteria-keyed v2 identity.
    final savedFavorite = ref.read(
      smartEventSavedFavoriteProvider(_baselineRequest.criteriaKey),
    );

    // Re-point dirty-tracking at what is now persisted, so a later exit
    // doesn't re-prompt for already-applied changes.
    if (mounted) setState(() => _baselineRequest = updated);

    if (savedFavorite == null) return;

    final notifier = ref.read(favoriteEventsProvider.notifier);
    await notifier.removeFavorite(savedFavorite.eventId);
    await notifier.addFavorite(
      eventId: updated.favoriteEventId,
      eventName: updated.displayName,
      maxAvgElo: updated.minElo > 0 ? updated.minElo : null,
      extraMetadata: updated.toFavoriteMetadata(),
    );
  }

  /// Back navigation with a dirty config: confirm that the new configuration
  /// gets applied + saved, or let the user discard it and leave as-is.
  /// Dismissing the dialog (tap outside) stays on the screen.
  Future<void> _confirmLeaveWithChanges() async {
    final navigator = Navigator.of(context);
    final confirmed = await showSmoothConfirmDialog(
      context: context,
      title: 'Apply changes?',
      message:
          'You changed the filters this smart event was built from. '
          'Leaving will apply and save the new configuration.',
      confirmText: 'Apply & leave',
      cancelText: 'Discard',
    );
    if (!mounted || confirmed == null) return;
    if (confirmed) await _applyConfigChanges();
    if (!mounted) return;
    navigator.pop();
  }

  /// The pinned row: search field + filter button (+ view-mode toggle).
  /// Lives at the screen level so it renders above the tab switcher; the
  /// committed query travels to the tabs through [_SmartTierFilterScope].
  Widget _buildSearchFilterBar(BuildContext context) {
    return GameSearchFilterBar(
      controller: _searchController,
      focusNode: _searchFocusNode,
      // The badge counts every root/override criterion that's narrowing the
      // list — including the tier threshold picked in the app bar dropdown —
      // so the red indicator mirrors the smart event's full active config.
      currentFilter: _mergeTierIntoFilter(_filter, _tier) ?? _filter,
      hintText: _index == 2 ? 'Search events' : 'Search games',
      onChanged: (value) {
        // Debounce: every committed query is a server-side search across ALL
        // games of the included events, so don't fire one per keystroke.
        _searchDebounce?.cancel();
        _searchDebounce = Timer(const Duration(milliseconds: 350), () {
          if (mounted) setState(() => _query = value.trim());
        });
      },
      onClear: () {
        _searchDebounce?.cancel();
        setState(() {
          _query = '';
          _searchController.clear();
        });
      },
      onFilterTap: _openFilterDialog,
      trailing:
          _index != 0
              ? GestureDetector(
                onTap:
                    () => ref.read(gamesListViewModeSwitcher).toggleViewMode(),
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colors.background,
                    borderRadius: BorderRadius.circular(12.br),
                    border: Border.all(color: context.colors.surfaceRecessed),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      SvgAsset.chase_grid,
                      width: 20.sp,
                      height: 20.sp,
                      colorFilter: ColorFilter.mode(
                        context.colors.textSecondary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              )
              : null,
    );
  }

  /// Every dimension is offered — including the ones that GENERATED this
  /// smart event, which arrive pre-selected (seeded on the screen state) and
  /// act as overrides of the event's config, applied + saved on confirmed
  /// exit.
  Future<void> _openFilterDialog() async {
    final result = await showGameFilterDialog(
      context: context,
      // Level mirrors the app bar tier dropdown — seed it from the current
      // tier so both override surfaces present one config.
      currentFilter: _filter.copyWith(minRating: _tierFloor(_tier)),
      showSortSection: _index == 1,
      // Color filters by a target player's color; this aggregate has no
      // target player, so the section would be inert.
      showColorFilter: false,
      // Smart events aggregate ongoing broadcasts — every game is from the
      // current year, so a year range is redundant.
      showYearFilter: false,
    );
    if (result != null && mounted) {
      // The Level pick routes back into the tier dropdown (single owner of
      // the Elo dimension); the threshold is re-merged per query by
      // [_mergeTierIntoFilter].
      _setFilter(result.copyWith(minRating: GameFilter.defaultMinRating));
      _setTier(_tierForMinRating(result.minRating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        ResponsiveHelper.isTablet ? 24.sp.toDouble() : 16.sp.toDouble();

    return _SmartEventRequestScope(
      request: widget.request,
      child: _SmartTierFilterScope(
        tier: _tier,
        onTierChanged: _setTier,
        filter: _filter,
        onFilterChanged: _setFilter,
        tabIndex: _index,
        searchQuery: _query,
        child: PopScope(
          // A dirty config intercepts the pop (back button, system back,
          // swipe-back) so the changes can be confirmed-applied or discarded.
          canPop: !_isConfigDirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeaveWithChanges();
          },
          child: Scaffold(
            backgroundColor: context.colors.background,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _AppBar(
                    request: _effectiveRequest,
                    savedRequest: _baselineRequest,
                    isDirty: _isConfigDirty,
                    onApplyChanges: _applyConfigChanges,
                  ),
                  SizedBox(height: 8.h),
                  // Search + filter pinned ABOVE the tab switcher — identical
                  // placement to the regular event view, with the smart
                  // event's extra filter button kept on the row.
                  _PinnedSearchFilterBar(
                    pageController: _page,
                    fallbackPage: _index.toDouble(),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: horizontalPadding,
                        right: horizontalPadding,
                        top: 4.h,
                        bottom: 8.h,
                      ),
                      child: _buildSearchFilterBar(context),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: SegmentedSwitcher(
                      options: _tabs,
                      initialSelection: _index,
                      currentSelection: _index,
                      onSelectionChanged: _select,
                      notifyOnReselect: true,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Expanded(
                    child: ScrollToTopScope(
                      bus: _scrollToTopBus,
                      child: PageView(
                        controller: _page,
                        onPageChanged: (i) {
                          if (_index != i) _searchFocusNode.unfocus();
                          setState(() => _index = i);
                        },
                        children: const [
                          _AboutTab(),
                          _GamesTab(),
                          _EventsTab(),
                        ],
                      ),
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
}

/// Carries the screen's tier filter, the dialog filter and the active tab
/// index down to the app bar and tab content. The dropdown writes through
/// [onTierChanged], the Games tab's filter dialog through [onFilterChanged];
/// the Games/Events tabs read [tier] + [filter] to filter what they
/// render. The app bar hides the dropdown when [tabIndex] is 0 (About) since
/// the About tab summarizes the saved aggregate, not a filtered view.
class _SmartTierFilterScope extends InheritedWidget {
  const _SmartTierFilterScope({
    required this.tier,
    required this.onTierChanged,
    required this.filter,
    required this.onFilterChanged,
    required this.tabIndex,
    required this.searchQuery,
    required super.child,
  });

  final String tier;
  final ValueChanged<String> onTierChanged;
  final GameFilter filter;
  final ValueChanged<GameFilter> onFilterChanged;
  final int tabIndex;

  /// Committed (debounced) text of the screen-level search field. The Games
  /// tab keys its server query on it; the Events tab uses the same query to
  /// narrow its event cards.
  final String searchQuery;

  static _SmartTierFilterScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_SmartTierFilterScope>();
    assert(scope != null, '_SmartTierFilterScope was not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(_SmartTierFilterScope oldWidget) {
    return tier != oldWidget.tier ||
        filter != oldWidget.filter ||
        tabIndex != oldWidget.tabIndex ||
        searchQuery != oldWidget.searchQuery;
  }
}

/// Mirrors the regular event view's pinned search bar: hidden on About
/// (page 0), fully shown on Games/Events (page 1+), with height and
/// opacity following the swipe progress between them.
class _PinnedSearchFilterBar extends StatelessWidget {
  const _PinnedSearchFilterBar({
    required this.pageController,
    required this.fallbackPage,
    required this.child,
  });

  final PageController pageController;
  final double fallbackPage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        final page =
            pageController.hasClients
                ? (pageController.page ?? fallbackPage)
                : fallbackPage;
        final t = page.clamp(0.0, 1.0);
        if (t <= 0.0) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            child: Opacity(opacity: t, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

/// The server-bound filter: the user's dialog filter tightened by the
/// selected tier threshold. The tier travels HERE (not in the request) so
/// switching tiers refetches exactly that floor — including floors below the
/// saved request's Elo floor.
GameFilter? _mergeTierIntoFilter(GameFilter filter, String tier) {
  final floor = _tierFloor(tier);
  var merged = filter;
  if (floor > merged.minRating) {
    merged = merged.copyWith(minRating: floor);
  }
  return merged.hasActiveFilters ? merged : null;
}

/// Tier thresholds keyed off the game's average Elo — the same scalar the
/// smart event pipeline uses to build, filter and sort these events. Every
/// tier is an open-ended floor (CM 2200+, FM 2300+, IM 2400+, GM 2500+),
/// matching the "+2200"-style chips in the filter dialog. Product decision
/// (2026-06-11): a closed band like CM 2200–2299 surfaces games nobody asked
/// for; every tier should behave like GM — that level and everything above.
int _tierFloor(String tier) {
  switch (tier) {
    case 'GM':
      return 2500;
    case 'IM':
      return 2400;
    case 'FM':
      return 2300;
    case 'CM':
      return 2200;
    default:
      return 0;
  }
}

/// Reverse of [_tierFloor]: maps the filter dialog's Level pick back onto
/// the app bar tier dropdown, keeping the two Elo override surfaces in sync.
String _tierForMinRating(int minRating) {
  switch (RatingTierFilter.normalizeMinRating(minRating)) {
    case 2500:
      return 'GM';
    case 2400:
      return 'IM';
    case 2300:
      return 'FM';
    case 2200:
      return 'CM';
    default:
      return 'All';
  }
}

bool _gameMatchesTier(GamesTourModel game, String tier) {
  if (tier == 'All') return true;
  final avgElo = smartGameAverageElo(game);
  if (avgElo <= 0) return false;
  return avgElo >= _tierFloor(tier);
}

/// Exposes the tier gate so the reported GM+ boards (2591-2371 and 2521-2440,
/// both averaging 2481) stay excluded no matter how this file is refactored.
@visibleForTesting
bool smartGameMatchesTierForTest(GamesTourModel game, String tier) =>
    _gameMatchesTier(game, tier);

class _AppBar extends ConsumerWidget {
  const _AppBar({
    required this.request,
    required this.savedRequest,
    required this.isDirty,
    required this.onApplyChanges,
  });

  /// The request with the user's current tier + filter overrides folded in.
  final SmartEventRequest request;

  /// The request the screen was opened with — a saved favorite still lives
  /// under THIS identity until the overrides are applied.
  final SmartEventRequest savedRequest;
  final bool isDirty;
  final Future<void> Function() onApplyChanges;

  Future<bool> _confirmFavoriteChange(
    BuildContext context, {
    required bool isSaved,
  }) async {
    final confirmed = await showSmoothConfirmDialog(
      context: context,
      title:
          isSaved
              ? 'Remove ${request.displayName}?'
              : 'Save ${request.displayName}?',
      message:
          isSaved
              ? 'This will remove ${request.displayName} from your For You.'
              : isDirty
              ? 'Your changed filter configuration will be applied and '
                  'saved — this adds ${request.displayName} to your '
                  'For You tab.'
              : 'This will add ${request.displayName} to your For You tab.',
      confirmText: isSaved ? 'Remove' : 'Save',
      isDangerous: isSaved,
    );
    return confirmed == true;
  }

  Future<bool> _confirmApplyChanges(BuildContext context) async {
    final confirmed = await showSmoothConfirmDialog(
      context: context,
      title: 'Apply changes?',
      message:
          'Your new filter configuration will be applied and saved to '
          '${request.displayName}.',
      confirmText: 'Apply',
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Criteria-based match (works for legacy v1 and v2 rows alike): saved if
    // any smart favorite carries the saved OR the overridden criteria.
    final savedFavorite =
        ref.watch(smartEventSavedFavoriteProvider(savedRequest.criteriaKey)) ??
        ref.watch(smartEventSavedFavoriteProvider(request.criteriaKey));
    final isSaved = savedFavorite != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 16.w, 0),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 24.ic,
            icon: Icon(
              Icons.arrow_back_ios_new_outlined,
              size: 24.ic,
              color: context.colors.textPrimary,
            ),
            // maybePop so the screen's PopScope can intercept a dirty config
            // and offer to apply + save it.
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(child: Center(child: _AppBarTitle(request: request))),
          IconButton(
            tooltip:
                isSaved
                    ? (isDirty
                        ? 'Apply changes to ${request.displayName}'
                        : 'Remove ${request.displayName}')
                    : 'Save ${request.displayName}',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 26.ic,
            icon: Icon(
              isSaved
                  ? (isDirty
                      ? Icons.check_circle_outline_rounded
                      : Icons.remove_circle_outline_rounded)
                  : Icons.add_circle_outline_rounded,
              color: context.colors.textPrimary,
            ),
            onPressed: () async {
              final allowed = await requireFullAuthGuard(context);
              if (!allowed || !context.mounted) return;

              // Saved + overridden: the button applies + saves the new
              // config onto the saved smart event (after confirmation).
              if (isSaved && isDirty) {
                final confirmed = await _confirmApplyChanges(context);
                if (!confirmed || !context.mounted) return;
                await onApplyChanges();
                return;
              }

              final confirmed = await _confirmFavoriteChange(
                context,
                isSaved: isSaved,
              );
              if (!confirmed || !context.mounted) return;

              final notifier = ref.read(favoriteEventsProvider.notifier);
              if (isSaved) {
                // Remove by the matched row's actual id — a legacy v1 row's
                // id differs from the criteria-keyed id we'd compute today.
                await notifier.removeFavorite(savedFavorite.eventId);
                // Removing the saved smart event must also wipe the applied
                // filter that generates its card on home — otherwise the
                // generated card lingers even though the favorite is gone.
                ref.read(eventAppliedFilterProvider.notifier).state =
                    defaultFilterPopupState;
                ref
                    .read(filterPopupProvider.notifier)
                    .setState(defaultFilterPopupState);
                if (context.mounted) Navigator.of(context).pop();
                return;
              }

              // Unsaved + overridden: persist the new config first (filter
              // popup write-back) so the saved card and the generated cards
              // reflect the same criteria.
              if (isDirty) await onApplyChanges();
              await notifier.addFavorite(
                eventId: request.favoriteEventId,
                eventName: request.displayName,
                maxAvgElo: request.minElo > 0 ? request.minElo : null,
                extraMetadata: request.toFavoriteMetadata(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Tab-aware app bar title.
///
/// About tab (index 0): plain static label — the saved request's display
/// name — since the About tab summarizes the aggregate that was actually
/// saved, not a filtered slice.
///
/// Games / Events tabs: the stadium-chip dropdown, which writes the
/// selected tier into [_SmartTierFilterScope] so the visible games / events
/// re-filter without leaving the screen.
class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.request});

  final SmartEventRequest request;

  @override
  Widget build(BuildContext context) {
    final scope = _SmartTierFilterScope.of(context);

    if (scope.tabIndex == 0) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder:
            (child, animation) =>
                FadeTransition(opacity: animation, child: child),
        child: Text(
          request.displayName,
          key: const ValueKey('smart_title_static'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.textMdMedium.copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder:
          (child, animation) =>
              FadeTransition(opacity: animation, child: child),
      child: _TitleSelector(
        key: const ValueKey('smart_title_dropdown'),
        selectedTier: scope.tier,
        onSelected: scope.onTierChanged,
      ),
    );
  }
}

/// Stadium-chip dropdown that swaps the active tier filter
/// (GM / IM / FM / CM / All) for the current screen. Visual language
/// matches the regular event view's [CategoryDropdown] — shimmer-bordered
/// chip when closed, kPrimary tint when open, scale + fade overlay panel.
class _TitleSelector extends StatefulWidget {
  const _TitleSelector({
    required this.selectedTier,
    required this.onSelected,
    super.key,
  });

  final String selectedTier;
  final ValueChanged<String> onSelected;

  @override
  State<_TitleSelector> createState() => _TitleSelectorState();
}

class _TitleSelectorState extends State<_TitleSelector>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final AnimationController _shimmerController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat();

  OverlayEntry? _overlay;
  bool _isOpen = false;

  @override
  void dispose() {
    _overlay?.remove();
    _overlay = null;
    _shimmerController.dispose();
    _controller.dispose();
    super.dispose();
  }

  static const _tierOptions = <String>['GM', 'IM', 'FM', 'CM'];

  void _open() {
    if (_isOpen) return;
    HapticFeedbackService.selection();
    setState(() => _isOpen = true);
    _shimmerController.stop();
    _controller.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlayState = Overlay.of(context);
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      final triggerSize = renderBox.size;
      final triggerOffset = renderBox.localToGlobal(Offset.zero);
      final screenSize = MediaQuery.of(context).size;

      _overlay = OverlayEntry(
        builder:
            (_) => _TierOverlay(
              triggerSize: triggerSize,
              triggerOffset: triggerOffset,
              screenWidth: screenSize.width,
              animation: _animation,
              options: _tierOptions,
              currentTier: widget.selectedTier,
              onDismiss: _close,
              onSelect: _onSelect,
            ),
      );
      overlayState.insert(_overlay!);
    });
  }

  void _close() {
    if (!_isOpen) return;
    _controller.reverse().then((_) {
      if (!mounted) return;
      _overlay?.remove();
      _overlay = null;
      if (mounted) {
        setState(() => _isOpen = false);
        _shimmerController.repeat();
      }
    });
  }

  void _onSelect(String next) {
    HapticFeedbackService.selection();
    _controller.reverse().then((_) {
      if (!mounted) return;
      _overlay?.remove();
      _overlay = null;
      if (mounted) setState(() => _isOpen = false);
      if (next != widget.selectedTier) widget.onSelected(next);
    });
  }

  String _triggerLabel() {
    // Every tier is an open-ended threshold now, so each gets the "+".
    return widget.selectedTier == 'All'
        ? widget.selectedTier
        : '${widget.selectedTier}+';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _isOpen ? _close() : _open(),
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          return CustomPaint(
            painter:
                _isOpen
                    ? null
                    : FluidShimmerPainter(
                      progress: _shimmerController.value,
                      shimmerColor: kPrimaryColor.withValues(alpha: 0.4),
                      borderRadius: 14.br,
                    ),
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 8.sp),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.br),
            color:
                _isOpen
                    ? kPrimaryColor.withValues(alpha: 0.15)
                    : context.colors.textPrimary.withValues(alpha: 0.06),
            border: Border.all(
              color:
                  _isOpen
                      ? kPrimaryColor.withValues(alpha: 0.4)
                      : context.colors.textPrimary.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _triggerLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    color: _isOpen ? kPrimaryColor : context.colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              SizedBox(width: 6.sp),
              AnimatedRotation(
                turns: _isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18.ic,
                  color:
                      _isOpen
                          ? kPrimaryColor
                          : context.colors.textPrimary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating panel anchored under [_TitleSelector]'s chip. Scale + fade in
/// from the top, surface bg, kPrimary check mark on the active tier.
class _TierOverlay extends StatelessWidget {
  const _TierOverlay({
    required this.triggerSize,
    required this.triggerOffset,
    required this.screenWidth,
    required this.animation,
    required this.options,
    required this.currentTier,
    required this.onDismiss,
    required this.onSelect,
  });

  final Size triggerSize;
  final Offset triggerOffset;
  final double screenWidth;
  final Animation<double> animation;
  final List<String> options;
  final String currentTier;
  final VoidCallback onDismiss;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final panelWidth = (screenWidth - 32.w).clamp(220.0, 320.w);
    final leftOffset = (screenWidth - panelWidth) / 2;
    final topOffset = triggerOffset.dy + triggerSize.height + 8.sp;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: leftOffset,
          top: topOffset,
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final progress = animation.value.clamp(0.0, 1.0);
                return Transform.scale(
                  scale: 0.94 + (progress * 0.06),
                  alignment: Alignment.topCenter,
                  child: Opacity(opacity: progress, child: child),
                );
              },
              child: GestureDetector(
                onTap: () {},
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: panelWidth,
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(16.br),
                    border: Border.all(
                      color: context.colors.textPrimary.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 24,
                        spreadRadius: -6,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.br),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.symmetric(vertical: 6.sp),
                      children: [
                        for (var i = 0; i < options.length; i++)
                          _TierOptionRow(
                            index: i,
                            animation: animation,
                            tier: options[i],
                            isSelected: options[i] == currentTier,
                            onTap: () => onSelect(options[i]),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TierOptionRow extends StatelessWidget {
  const _TierOptionRow({
    required this.index,
    required this.animation,
    required this.tier,
    required this.isSelected,
    required this.onTap,
  });

  final int index;
  final Animation<double> animation;
  final String tier;
  final bool isSelected;
  final VoidCallback onTap;

  String get _displayLabel {
    switch (tier) {
      case 'GM':
        return 'Grandmaster · 2500+';
      case 'IM':
        return 'International Master · 2400+';
      case 'FM':
        return 'FIDE Master · 2300+';
      case 'CM':
        return 'Candidate Master · 2200+';
      case 'All':
      default:
        return 'All games';
    }
  }

  @override
  Widget build(BuildContext context) {
    final stagger = (index * 0.06).clamp(0.0, 0.4);
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        stagger,
        (stagger + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final v = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 10 * (1 - v)),
          child: Opacity(opacity: v, child: child),
        );
      },
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
          color:
              isSelected
                  ? kPrimaryColor.withValues(alpha: 0.10)
                  : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    color:
                        isSelected ? kPrimaryColor : context.colors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_rounded, size: 18.ic, color: kPrimaryColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmartEventRequestScope extends InheritedWidget {
  const _SmartEventRequestScope({required this.request, required super.child});

  final SmartEventRequest request;

  static SmartEventRequest of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_SmartEventRequestScope>();
    assert(scope != null, 'SmartEventRequestScope was not found');
    return scope!.request;
  }

  @override
  bool updateShouldNotify(_SmartEventRequestScope oldWidget) {
    return request != oldWidget.request;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.message = 'No games right now', super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sports_esports_outlined,
              size: 40.sp,
              color: context.colors.textPrimaryMuted,
            ),
            SizedBox(height: 12.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimaryMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-tab shimmer for the Games tab's first load — same padding as the
/// loaded list so swapping in the real cards doesn't shift layout.
class _GamesShimmerList extends StatelessWidget {
  const _GamesShimmerList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16.sp, 8.sp, 16.sp, 24.sp),
      physics: const NeverScrollableScrollPhysics(),
      children: const [_GameCardShimmerColumn(cardCount: 8)],
    );
  }
}

/// Shimmer game-card placeholders — the mock-card technique from
/// TourLoadingWidget. Rendered inside the Games tab list while a re-keyed
/// query (tier switch, filter edit, committed search) is fetching and the
/// stale aggregate filters down to nothing.
class _GameCardShimmerColumn extends StatelessWidget {
  const _GameCardShimmerColumn({this.cardCount = 6, super.key});

  final int cardCount;

  @override
  Widget build(BuildContext context) {
    final mockPlayer = PlayerCard(
      name: 'name',
      federation: 'federation',
      title: 'title',
      rating: 0,
      countryCode: 'USA',
      team: 'team',
    );
    final mockGame = GamesTourModel(
      roundId: 'roundId',
      tourId: 'tourId',
      gameId: 'gameId',
      whitePlayer: mockPlayer,
      blackPlayer: mockPlayer,
      whiteTimeDisplay: 'whiteTimeDisplay',
      blackTimeDisplay: 'blackTimeDisplay',
      whiteClockCentiseconds: 180000,
      blackClockCentiseconds: 180000,
      gameStatus: GameStatus.whiteWins,
    );
    return Column(
      children: [
        for (var i = 0; i < cardCount; i++)
          SkeletonWidget(
            ignoreContainers: true,
            child: Padding(
              padding: EdgeInsets.only(bottom: 12.sp),
              child: GameCard(
                onTap: () {},
                matchComparison: MatchWithComparison(
                  game: mockGame,
                  comparison: MatchComparison.sameOrder,
                ),
                onPinToggle: (_) {},
                pinnedIds: const [],
              ),
            ),
          ),
      ],
    );
  }
}

class _GamesTab extends ConsumerStatefulWidget {
  const _GamesTab();

  @override
  ConsumerState<_GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends ConsumerState<_GamesTab>
    with
        WidgetsBindingObserver,
        RouteAware,
        AutomaticKeepAliveClientMixin,
        ScrollToTopListenerMixin {
  // Keep the tab alive when the PageView swaps it offscreen: disposal would
  // drop the autoDispose aggregate provider (full refetch on return) plus
  // the search text, scroll offset and collapsed sections.
  @override
  bool get wantKeepAlive => true;

  final ScrollController _scrollController = ScrollController();

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  static const Duration _scrollIdleDelay = Duration(milliseconds: 180);

  Timer? _scrollIdleTimer;
  bool _routeSubscribed = false;
  bool _routeIsCurrent = true;
  bool _appIsResumed = true;
  bool _liveCardsPausedForScroll = false;
  late final StateController<Set<String>> _liveGameCardsPauseReasons;

  String get _liveCardsPauseReason => 'smart_event_games_scroll_$hashCode';

  /// The dialog filter is owned by the screen state (seeded from the smart
  /// event's generating criteria, applied + saved on confirmed exit); this
  /// tab reads and writes it through the scope.
  GameFilter get _filter => _SmartTierFilterScope.of(context).filter;

  /// Search is owned by the screen too (the field sits pinned above the tab
  /// switcher); this tab keys its server query on the committed text.
  String get _query => _SmartTierFilterScope.of(context).searchQuery;

  /// Last successfully loaded aggregate. Tier switches, search keystrokes and
  /// filter edits re-key the query provider; rendering this while the new
  /// fetch is in flight keeps the list on screen instead of flashing a
  /// spinner or a false empty state.
  SmartAggregateEvent? _lastLoadedEvent;

  /// Track collapsed state for chronological date sections — mirrors the
  /// Countrymen / Favorites games tabs.
  final Set<String> _collapsedDates = {};

  @override
  void initState() {
    super.initState();
    _liveGameCardsPauseReasons = ref.read(
      liveGameCardsPauseReasonsProvider.notifier,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    routeObserver.subscribe(this, route);
    _routeSubscribed = true;
    _routeIsCurrent = route.isCurrent;
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      routeObserver.unsubscribe(this);
    }
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didPush() {
    _setRouteActive(true);
  }

  @override
  void didPopNext() {
    _setRouteActive(true);
  }

  @override
  void didPushNext() {
    _setRouteActive(false);
  }

  @override
  void didPop() {
    _setRouteActive(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _setAppResumed(state == AppLifecycleState.resumed);
  }

  void _setRouteActive(bool isActive) {
    if (!mounted || _routeIsCurrent == isActive) return;
    setState(() => _routeIsCurrent = isActive);
    if (!isActive) {
      _scrollIdleTimer?.cancel();
      _setLiveCardsPausedForScroll(false);
    }
  }

  void _setAppResumed(bool isResumed) {
    if (!mounted || _appIsResumed == isResumed) return;
    setState(() => _appIsResumed = isResumed);
    if (!isResumed) {
      _scrollIdleTimer?.cancel();
      _setLiveCardsPausedForScroll(false);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification.metrics.extentAfter <= 420) {
      _requestOlderDays();
    }

    if (notification is ScrollEndNotification) {
      _scheduleScrollIdle();
      return false;
    }

    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _scheduleScrollIdle();
      return false;
    }

    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification ||
        notification is UserScrollNotification) {
      _markScrolling();
    }

    return false;
  }

  void _requestOlderDays() {
    if (!mounted) return;
    final request = _SmartEventRequestScope.of(context);
    final tabScope = _SmartTierFilterScope.of(context);
    final query = SmartEventGamesQuery(
      request: request.withNeutralEloRange(),
      filter: _dataFilterForTier(tabScope.tier),
      searchQuery: tabScope.searchQuery,
    );
    ref.read(smartAggregateEventRepositoryProvider(query).notifier).loadMore();
  }

  void _markScrolling() {
    _setLiveCardsPausedForScroll(true);
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(_scrollIdleDelay, _markScrollIdle);
  }

  void _scheduleScrollIdle() {
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(_scrollIdleDelay, _markScrollIdle);
  }

  void _markScrollIdle() {
    _setLiveCardsPausedForScroll(false);
  }

  void _setLiveCardsPausedForScroll(bool paused) {
    if (_liveCardsPausedForScroll == paused) return;
    _liveCardsPausedForScroll = paused;
    setLiveGameCardsPausedWithNotifier(
      _liveGameCardsPauseReasons,
      reason: _liveCardsPauseReason,
      paused: paused,
    );
  }

  void _toggleDateSection(String dateKey) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_collapsedDates.contains(dateKey)) {
        _collapsedDates.remove(dateKey);
      } else {
        _collapsedDates.add(dateKey);
      }
    });
  }

  /// The server-bound filter: the dialog filter tightened by the selected
  /// tier threshold (see [_mergeTierIntoFilter]).
  GameFilter? _dataFilterForTier(String tier) =>
      _mergeTierIntoFilter(_filter, tier);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tabScope = _SmartTierFilterScope.of(context);
    // Keep the Games subtree mounted beneath pushed routes and sibling tabs.
    // Replacing it with an empty box used to detach the ListView, release the
    // autoDispose aggregate provider, and recreate both on return. This makes
    // AutomaticKeepAlive fulfill its contract for the data and scroll tree,
    // not only for this State object's fields.
    final request = _SmartEventRequestScope.of(context);
    final tier = tabScope.tier;
    const allowStockfishFallback = true;
    final smartQuery = SmartEventGamesQuery(
      request: request.withNeutralEloRange(),
      filter: _dataFilterForTier(tier),
      searchQuery: _query,
    );
    final async = ref.watch(smartAggregateEventRepositoryProvider(smartQuery));
    final viewMode = ref.watch(gamesListViewModeProvider);

    Widget buildLoaded(SmartAggregateEvent event) {
      final games = _applySmartGameControls(event.games, event.gameEventNames);
      final gamesData = GamesScreenModel(
        gamesTourModels: games,
        pinnedGamedIs: event.pinnedGameIds,
      );
      final liveBatchKeyByGameId = liveBatchKeysForGames(
        games: games,
        scopePrefix: 'smart_event:${request.scopeId}',
      );

      final isGrid = viewMode == GamesListViewMode.chessBoardGrid;
      // Tablet landscape: 4 columns; tablet portrait / phone: 2 — mirrors
      // the Favorites / Countrymen games tabs.
      final gridColumns =
          ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape ? 4 : 2;
      final rows = _buildDayRows(games, gridColumns: isGrid ? gridColumns : 1);
      return NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: RefreshIndicator(
          color: kPrimaryColor,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            // Re-resolve the criteria's membership from the server, then
            // refresh every tab's slice of the aggregate, not just this query.
            ref.invalidate(smartEventResolvedEventsProvider);
            ref.invalidate(smartAggregateEventRepositoryProvider);
          },
          child: ListView.builder(
            key: PageStorageKey<String>('smart_event_games_${request.scopeId}'),
            controller: _scrollController,
            scrollCacheExtent: kListScrollCacheExtent,
            padding: EdgeInsets.fromLTRB(16.sp, 8.sp, 16.sp, 24.sp),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            itemCount:
                games.isEmpty
                    ? 1
                    : rows.length +
                        (event.hasMore || event.isLoadingMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (games.isEmpty) {
                final hasNarrowingControls =
                    _query.isNotEmpty ||
                    _filter.hasActiveFilters ||
                    _SmartTierFilterScope.of(context).tier != 'All';
                // A tier switch / filter edit / committed search re-keys the
                // query; while the new fetch is in flight the stale aggregate
                // may filter down to nothing. That's "loading", not "no
                // results" — shimmer instead of a false empty state.
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child:
                      async.isLoading
                          ? const _GameCardShimmerColumn(
                            key: ValueKey('smart_games_filter_shimmer'),
                          )
                          : _EmptyState(
                            key: const ValueKey('smart_games_filter_empty'),
                            message:
                                hasNarrowingControls
                                    ? 'No games match your filters'
                                    : 'No games right now',
                          ),
                );
              }
              if (i >= rows.length) {
                if (event.isLoadingMore) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return const SizedBox(height: 24);
              }
              final row = rows[i];
              if (row.header != null) {
                final header = row.header!;
                return Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: _DateHeader(
                    dateLabel: _formatDateHeader(header.dateKey),
                    gameCount: header.gameCount,
                    isExpanded: !_collapsedDates.contains(header.dateKey),
                    onToggle: () => _toggleDateSection(header.dateKey),
                  ),
                );
              }
              if (row.gridGames != null) {
                final rowGames = row.gridGames!;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: row.isLastInSection ? 16.h : 12.h,
                  ),
                  child: Row(
                    children: [
                      for (int j = 0; j < gridColumns; j++) ...[
                        if (j > 0) SizedBox(width: 12.sp),
                        Expanded(
                          child:
                              j < rowGames.length
                                  ? _buildGridGame(
                                    rowGames[j],
                                    games,
                                    gamesData,
                                    liveBatchKeyByGameId[rowGames[j].gameId],
                                    allowStockfishFallback,
                                  )
                                  : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                );
              }
              final game = row.game!;
              final gameIndex = games.indexWhere(
                (g) => g.gameId == game.gameId,
              );
              return Padding(
                padding: EdgeInsets.only(
                  bottom: row.isLastInSection ? 16.h : 12.h,
                ),
                child: GameCardWrapperWidget(
                  key: ValueKey('smart_${game.gameId}'),
                  game: game,
                  gamesData: gamesData,
                  gameIndex: gameIndex < 0 ? 0 : gameIndex,
                  isChessBoardVisible: viewMode == GamesListViewMode.chessBoard,
                  viewSource: ChessboardView.smartEvent,
                  onReturnFromChessboard: (_) {},
                  liveBatchKey: liveBatchKeyByGameId[game.gameId],
                  allowStockfishFallback: allowStockfishFallback,
                  onBeforeOpen: () => _guardGameOpen(context),
                ),
              );
            },
          ),
        ),
      );
    }

    if (async.hasValue) {
      _lastLoadedEvent = async.requireValue;
    }
    final event =
        async.valueOrNull ?? (async.isLoading ? _lastLoadedEvent : null);

    // Fade between the three tab-level states (shimmer / error / content)
    // instead of hard-swapping; rebuilds within the data state keep the same
    // key, so the list itself never re-animates.
    Widget content;
    if (event != null) {
      content = KeyedSubtree(
        key: const ValueKey('smart_games_data'),
        child: buildLoaded(event),
      );
    } else if (async.hasError) {
      content = GenericErrorWidget(
        key: const ValueKey('smart_games_error'),
        onRetry:
            () => ref.invalidate(
              smartAggregateEventRepositoryProvider(smartQuery),
            ),
      );
    } else {
      content = const _GamesShimmerList(key: ValueKey('smart_games_loading'));
    }
    return TickerMode(
      // Preserve the subtree and provider while a child route covers it, but
      // do not spend frames animating an invisible list or a backgrounded app.
      enabled: _routeIsCurrent && _appIsResumed && tabScope.tabIndex == 1,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: content,
      ),
    );
  }

  List<GamesTourModel> _applySmartGameControls(
    List<GamesTourModel> source,
    Map<String, String> gameEventNames,
  ) {
    final query = _query.toLowerCase();
    final tier = _SmartTierFilterScope.of(context).tier;
    final filtered = source
        .where((game) {
          if (!_gameMatchesTier(game, tier)) return false;
          if (!_matchesSmartGameFilter(game, _filter)) return false;
          if (query.isEmpty) return true;
          final eventName = gameEventNames[game.gameId]?.toLowerCase() ?? '';
          return game.whitePlayer.name.toLowerCase().contains(query) ||
              game.blackPlayer.name.toLowerCase().contains(query) ||
              eventName.contains(query) ||
              (game.eco?.toLowerCase().contains(query) ?? false) ||
              (game.openingName?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);

    if (_filter.sorts.isEmpty) return filtered;

    final sorted = List<GamesTourModel>.from(filtered);
    sorted.sort((a, b) {
      for (final criterion in _filter.sorts) {
        final comparison = _compareBySortCriterion(a, b, criterion);
        if (comparison != 0) return comparison;
      }
      return 0;
    });
    return sorted;
  }

  bool _matchesSmartGameFilter(GamesTourModel game, GameFilter filter) {
    if (filter.live != GameLiveFilter.all) {
      final isLive = GameFilterHelper.isLiveNow(game);
      final isCompleted = game.effectiveGameStatus.isFinished;
      if (filter.live == GameLiveFilter.live && !isLive) return false;
      if (filter.live == GameLiveFilter.completed && !isCompleted) {
        return false;
      }
    }

    if (!filter.result.matches(game.gameStatus)) return false;
    if (!_matchesTimeControl(game, filter.timeControl)) return false;
    if (filter.online != GameOnlineFilter.all) {
      if (filter.online == GameOnlineFilter.online && !game.isOnline) {
        return false;
      }
      if (filter.online == GameOnlineFilter.otb && game.isOnline) return false;
    }
    if (!filter.eco.matches(game.eco)) return false;

    final gameAvgElo = smartGameAverageElo(game);
    if (gameAvgElo < filter.minRating || gameAvgElo > filter.maxRating) {
      return false;
    }
    return true;
  }

  bool _matchesTimeControl(GamesTourModel game, GameTimeControlFilter filter) {
    if (filter == GameTimeControlFilter.all) return true;
    final bucket = timeControlBucketFor(game.timeControl);
    if (bucket == null) return true;
    return switch (filter) {
      GameTimeControlFilter.classical => bucket == TimeControlBucket.classical,
      GameTimeControlFilter.rapid => bucket == TimeControlBucket.rapid,
      GameTimeControlFilter.blitz => bucket == TimeControlBucket.blitz,
      GameTimeControlFilter.all => true,
    };
  }

  Future<bool> _guardGameOpen(BuildContext context) async {
    if (ref.read(subscriptionProvider).isSubscribed) return true;
    if (!context.mounted) return false;
    return await showPremiumPaywallSheet(context: context);
  }

  Widget _buildGridGame(
    GamesTourModel game,
    List<GamesTourModel> games,
    GamesScreenModel gamesData,
    LiveGamesBatchKey? liveBatchKey,
    bool allowStockfishFallback,
  ) {
    final gameIndex = games.indexWhere((g) => g.gameId == game.gameId);
    final safeIndex = gameIndex < 0 ? 0 : gameIndex;
    return GridGameCardWrapperWidget(
      key: ValueKey('smart_grid_${game.gameId}'),
      game: game,
      orderedGames: games,
      gameIndex: safeIndex,
      pinnedIds: gamesData.pinnedGamedIs,
      liveBatchKey: liveBatchKey,
      allowStockfishFallback: allowStockfishFallback,
      // Carried for the player-name tap, which opens the score card straight
      // from the card without going through [navigateToChessBoard].
      viewSource: ChessboardView.smartEvent,
      onPinToggle:
          (g) async => await ref
              .read(gamesTourScreenProvider.notifier)
              .togglePinGame(g.gameId, sourceTourId: g.tourId),
      onChangedWithLiveGames: (updatedGames) async {
        final allowed = await _guardGameOpen(context);
        if (!allowed || !mounted) return;
        ref
            .read(gameCardWrapperProvider)
            .navigateToChessBoard(
              context: context,
              orderedGames: updatedGames,
              gameIndex: safeIndex,
              onReturnFromChessboard: (_) {},
              viewSource: ChessboardView.smartEvent,
            );
      },
    );
  }

  /// Group games by day and flatten into header + game rows, honoring the
  /// collapsed state. Games arrive pre-sorted (day desc, pinned, avg Elo).
  /// With [gridColumns] > 1 each section's games are chunked into grid rows.
  List<_GameListRow> _buildDayRows(
    List<GamesTourModel> games, {
    int gridColumns = 1,
  }) {
    final gamesByDate = <String, List<GamesTourModel>>{};
    for (final game in games) {
      final dateKey = DateFormat('yyyy-MM-dd').format(_gameDay(game));
      gamesByDate.putIfAbsent(dateKey, () => []).add(game);
    }
    final sortedKeys =
        gamesByDate.keys.toList()..sort((a, b) => b.compareTo(a));

    final rows = <_GameListRow>[];
    for (final dateKey in sortedKeys) {
      final dateGames = gamesByDate[dateKey]!;
      rows.add(
        _GameListRow.header(
          _DateHeaderData(dateKey: dateKey, gameCount: dateGames.length),
        ),
      );
      if (_collapsedDates.contains(dateKey)) continue;
      if (gridColumns > 1) {
        for (var i = 0; i < dateGames.length; i += gridColumns) {
          final end =
              i + gridColumns < dateGames.length
                  ? i + gridColumns
                  : dateGames.length;
          rows.add(
            _GameListRow.grid(
              dateGames.sublist(i, end),
              isLastInSection: end == dateGames.length,
            ),
          );
        }
        continue;
      }
      for (var i = 0; i < dateGames.length; i++) {
        rows.add(
          _GameListRow.game(
            dateGames[i],
            isLastInSection: i == dateGames.length - 1,
          ),
        );
      }
    }
    return rows;
  }

  DateTime _gameDay(GamesTourModel game) {
    final raw = game.gameDay ?? game.bucketDate ?? DateTime.now();
    return DateTime(raw.year, raw.month, raw.day);
  }

  String _formatDateHeader(String dateKey) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final gameDate = DateTime(date.year, date.month, date.day);

    if (gameDate == today) {
      return 'Today';
    } else if (gameDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE, MMM d').format(date);
    }
  }

  int _compareBySortCriterion(
    GamesTourModel a,
    GamesTourModel b,
    GameSortCriterion criterion,
  ) {
    int comparison;
    switch (criterion.field) {
      case GamebaseSortField.date:
        final ad = a.lastMoveTime ?? a.bucketDate ?? DateTime(0);
        final bd = b.lastMoveTime ?? b.bucketDate ?? DateTime(0);
        comparison = ad.compareTo(bd);
        break;
      case GamebaseSortField.whiteElo:
        comparison = a.whitePlayer.rating.compareTo(b.whitePlayer.rating);
        break;
      case GamebaseSortField.blackElo:
        comparison = a.blackPlayer.rating.compareTo(b.blackPlayer.rating);
        break;
      case GamebaseSortField.avgElo:
        comparison = smartGameAverageElo(a).compareTo(smartGameAverageElo(b));
        break;
    }
    return criterion.direction == GamebaseSortDirection.asc
        ? comparison
        : -comparison;
  }
}

class _DateHeaderData {
  const _DateHeaderData({required this.dateKey, required this.gameCount});

  final String dateKey;
  final int gameCount;
}

class _GameListRow {
  const _GameListRow._({
    this.header,
    this.game,
    this.gridGames,
    this.isLastInSection = false,
  });

  factory _GameListRow.header(_DateHeaderData value) =>
      _GameListRow._(header: value);

  factory _GameListRow.game(
    GamesTourModel value, {
    required bool isLastInSection,
  }) => _GameListRow._(game: value, isLastInSection: isLastInSection);

  factory _GameListRow.grid(
    List<GamesTourModel> value, {
    required bool isLastInSection,
  }) => _GameListRow._(gridGames: value, isLastInSection: isLastInSection);

  final _DateHeaderData? header;
  final GamesTourModel? game;

  /// One grid row of boards (chessBoardGrid mode); null in list modes.
  final List<GamesTourModel>? gridGames;
  final bool isLastInSection;
}

class _EventGameListRow {
  const _EventGameListRow._({
    this.event,
    this.game,
    this.gridGames,
    this.isFirstSection = false,
    this.isLastInSection = false,
  });

  factory _EventGameListRow.event(
    GroupEventCardModel value, {
    required bool isFirstSection,
  }) => _EventGameListRow._(event: value, isFirstSection: isFirstSection);

  factory _EventGameListRow.game(
    GamesTourModel value, {
    required bool isLastInSection,
  }) => _EventGameListRow._(game: value, isLastInSection: isLastInSection);

  factory _EventGameListRow.grid(
    List<GamesTourModel> value, {
    required bool isLastInSection,
  }) => _EventGameListRow._(gridGames: value, isLastInSection: isLastInSection);

  final GroupEventCardModel? event;
  final GamesTourModel? game;
  final List<GamesTourModel>? gridGames;
  final bool isFirstSection;
  final bool isLastInSection;
}

List<_EventGameListRow> _buildEventGameRows(
  SmartAggregateEvent event, {
  required int gridColumns,
}) {
  final groups = groupSmartEventGames(event: event, visibleGames: event.games);
  final rows = <_EventGameListRow>[];
  for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
    final group = groups[groupIndex];
    rows.add(
      _EventGameListRow.event(group.event, isFirstSection: groupIndex == 0),
    );
    if (gridColumns > 1) {
      for (var i = 0; i < group.games.length; i += gridColumns) {
        final end =
            i + gridColumns < group.games.length
                ? i + gridColumns
                : group.games.length;
        rows.add(
          _EventGameListRow.grid(
            group.games.sublist(i, end),
            isLastInSection: end == group.games.length,
          ),
        );
      }
      continue;
    }
    for (var i = 0; i < group.games.length; i++) {
      rows.add(
        _EventGameListRow.game(
          group.games[i],
          isLastInSection: i == group.games.length - 1,
        ),
      );
    }
  }
  return rows;
}

/// Date section header — identical to the Countrymen / Favorites games tabs.
class _DateHeader extends StatelessWidget {
  const _DateHeader({
    required this.dateLabel,
    required this.gameCount,
    required this.isExpanded,
    this.onToggle,
  });

  final String dateLabel;
  final int gameCount;
  final bool isExpanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                '$dateLabel • $gameCount ${gameCount == 1 ? 'game' : 'games'}',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onToggle != null) ...[
              SizedBox(width: 12.w),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: context.colors.textPrimary.withValues(alpha: 0.5),
                size: 20.sp,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SmartIncludedEventCard extends ConsumerWidget {
  const _SmartIncludedEventCard({
    required this.event,
    required this.heroTagSuffix,
  });

  final GroupEventCardModel event;
  final String heroTagSuffix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = EventCard(
      tourEventCardModel: event,
      showHeartIndicator: true,
      favoritePlayersSource: EventFavoritePlayersSource.cacheOnly,
      heroTagSuffix: heroTagSuffix,
      onTap:
          () => ref
              .read(groupEventScreenProvider.notifier)
              .onSelectTournament(context: context, id: event.id),
    );

    if (!ResponsiveHelper.isTablet) return card;
    return AspectRatio(
      aspectRatio: ResponsiveHelper.isLandscape ? 1.4 : 1.2,
      child: card,
    );
  }
}

class _AboutTab extends ConsumerStatefulWidget {
  const _AboutTab();

  @override
  ConsumerState<_AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends ConsumerState<_AboutTab>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  // Keep-alive so swapping tabs doesn't dispose this page's listener on the
  // autoDispose aggregate provider (which would refetch on every return).
  @override
  bool get wantKeepAlive => true;

  final ScrollController _scrollController = ScrollController();

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Last successfully loaded aggregate. Filter / tier / search changes
  /// re-key the query provider; rendering this while the new fetch is in
  /// flight keeps the included tournaments + stats on screen instead of
  /// flashing a spinner or a false empty state — mirrors the Games tab.
  SmartAggregateEvent? _lastLoadedEvent;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final request = _SmartEventRequestScope.of(context);
    final scope = _SmartTierFilterScope.of(context);
    // Same query key as the Games tab so the included tournaments, stats
    // and live count narrow with the user's filter / tier / search. About
    // is "what's currently in Games, summarized" — never a stale snapshot
    // of the saved aggregate.
    final query = SmartEventGamesQuery(
      request: request.withNeutralEloRange(),
      filter: _mergeTierIntoFilter(scope.filter, scope.tier),
      searchQuery: scope.searchQuery,
    );
    final async = ref.watch(smartAggregateEventRepositoryProvider(query));

    if (async.hasValue) {
      _lastLoadedEvent = async.requireValue;
    }
    final event =
        async.valueOrNull ?? (async.isLoading ? _lastLoadedEvent : null);

    if (event == null) {
      if (async.hasError) {
        return GenericErrorWidget(
          onRetry:
              () =>
                  ref.invalidate(smartAggregateEventRepositoryProvider(query)),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    final hasNarrowingControls =
        scope.searchQuery.isNotEmpty ||
        scope.filter.hasActiveFilters ||
        scope.tier != 'All';
    final emptyMessage =
        hasNarrowingControls
            ? 'No tournaments match your filters'
            : 'No games right now';
    final opening = request.openingExplanation;
    final dateSpan = TimeUtils.formatDateRange(event.dateStart, event.dateEnd);

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16.sp, 8.sp, 16.sp, 24.sp),
      children: [
        Container(
          padding: EdgeInsets.all(16.sp),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12.br),
            border: Border.all(color: kPrimaryColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (opening != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      opening.codeLabel,
                      key: const ValueKey('smart-opening-scope-code'),
                      style: AppTypography.textSmBold.copyWith(
                        color: kDarkBlue,
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        opening.title,
                        key: const ValueKey('smart-opening-scope-title'),
                        style: AppTypography.textSmBold.copyWith(
                          color: context.colors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Text(
                  opening.scope,
                  key: const ValueKey('smart-opening-scope-summary'),
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (opening.classificationNote case final note?) ...[
                  SizedBox(height: 7.h),
                  Text(
                    note,
                    key: const ValueKey('smart-opening-classification-note'),
                    style: AppTypography.textXsRegular.copyWith(
                      color: context.colors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
                if (opening.moves case final moves?) ...[
                  SizedBox(height: 9.h),
                  Text(
                    'Selected line',
                    style: AppTypography.textXxsMedium.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    moves,
                    key: const ValueKey('smart-opening-moves'),
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ],
              ] else
                Text(
                  'This database gathers the strongest games from every '
                  'ongoing broadcast into one place, so you never have to '
                  'switch between tournaments.',
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary,
                    height: 1.4,
                  ),
                ),
              SizedBox(height: 16.h),
              Wrap(
                spacing: 10.w,
                runSpacing: 10.h,
                children: [
                  _Stat(
                    label: 'Tournaments',
                    value: '${event.tournamentCount}',
                  ),
                  _Stat(label: 'Live games', value: '${event.liveGameCount}'),
                  if (event.avgElo > 0)
                    _Stat(label: 'Avg ELO', value: 'Ø ${event.avgElo}'),
                ],
              ),
              if (dateSpan.isNotEmpty) ...[
                SizedBox(height: 14.h),
                _MetaRow(icon: Icons.calendar_today_rounded, text: dateSpan),
              ],
              if (event.timeControls.isNotEmpty) ...[
                SizedBox(height: 8.h),
                _MetaRow(
                  icon: Icons.timer_outlined,
                  text: event.timeControls.join(' · '),
                ),
              ],
            ],
          ),
        ),
        if (event.events.isEmpty) ...[
          SizedBox(height: 24.h),
          Center(
            child: Text(
              emptyMessage,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ] else ...[
          SizedBox(height: 20.h),
          Text(
            'Included tournaments',
            style: AppTypography.textSmBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 10.h),
          ...event.events.map(
            (includedEvent) => Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: EventCard(
                tourEventCardModel: includedEvent,
                forceCompactLayout: true,
                heroTagSuffix: 'smart_about_${request.scopeId}',
                onTap:
                    () => ref
                        .read(groupEventScreenProvider.notifier)
                        .onSelectTournament(
                          context: context,
                          id: includedEvent.id,
                        ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: kPrimaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            label,
            style: AppTypography.textXxsMedium.copyWith(
              color: context.colors.textPrimaryMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14.sp, color: context.colors.textPrimaryMuted),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            text,
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimaryMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Chronological event sections for the smart collection. Each event card is
/// immediately followed by the games fetched for that exact event ID.
class _EventsTab extends ConsumerStatefulWidget {
  const _EventsTab();

  @override
  ConsumerState<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends ConsumerState<_EventsTab>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  @override
  bool get wantKeepAlive => true;

  final ScrollController _scrollController = ScrollController();
  SmartAggregateEvent? _lastLoadedEvent;

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.metrics.extentAfter <= 420) _requestOlderDays();
    return false;
  }

  void _requestOlderDays() {
    if (!mounted) return;
    final request = _SmartEventRequestScope.of(context);
    final scope = _SmartTierFilterScope.of(context);
    final query = SmartEventGamesQuery(
      request: request.withNeutralEloRange(),
      filter: _mergeTierIntoFilter(scope.filter, scope.tier),
      searchQuery: scope.searchQuery,
    );
    ref.read(smartAggregateEventRepositoryProvider(query).notifier).loadMore();
  }

  Future<bool> _guardGameOpen(BuildContext context) async {
    if (ref.read(subscriptionProvider).isSubscribed) return true;
    if (!context.mounted) return false;
    return await showPremiumPaywallSheet(context: context);
  }

  Widget _buildGridGame({
    required GamesTourModel game,
    required List<GamesTourModel> games,
    required GamesScreenModel gamesData,
    required LiveGamesBatchKey? liveBatchKey,
    required bool streamEnabled,
  }) {
    final gameIndex = games.indexWhere((item) => item.gameId == game.gameId);
    final safeIndex = gameIndex < 0 ? 0 : gameIndex;
    return GridGameCardWrapperWidget(
      key: ValueKey('smart_event_grouped_grid_${game.gameId}'),
      game: game,
      orderedGames: games,
      gameIndex: safeIndex,
      pinnedIds: gamesData.pinnedGamedIs,
      liveBatchKey: liveBatchKey,
      allowStockfishFallback: true,
      streamEnabled: streamEnabled,
      viewSource: ChessboardView.smartEvent,
      onPinToggle:
          (updated) async => await ref
              .read(gamesTourScreenProvider.notifier)
              .togglePinGame(updated.gameId, sourceTourId: updated.tourId),
      onChangedWithLiveGames: (updatedGames) async {
        final allowed = await _guardGameOpen(context);
        if (!allowed || !mounted) return;
        ref
            .read(gameCardWrapperProvider)
            .navigateToChessBoard(
              context: context,
              orderedGames: updatedGames,
              gameIndex: safeIndex,
              onReturnFromChessboard: (_) {},
              viewSource: ChessboardView.smartEvent,
            );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final request = _SmartEventRequestScope.of(context);
    final scope = _SmartTierFilterScope.of(context);
    final query = SmartEventGamesQuery(
      request: request.withNeutralEloRange(),
      filter: _mergeTierIntoFilter(scope.filter, scope.tier),
      searchQuery: scope.searchQuery,
    );
    final async = ref.watch(smartAggregateEventRepositoryProvider(query));
    final streamEnabled =
        scope.tabIndex == 2 && (ModalRoute.of(context)?.isCurrent ?? true);

    if (async.hasValue) _lastLoadedEvent = async.requireValue;
    final event =
        async.valueOrNull ?? (async.isLoading ? _lastLoadedEvent : null);

    Widget content;
    if (event == null) {
      content =
          async.hasError
              ? GenericErrorWidget(
                key: const ValueKey('smart_events_error'),
                onRetry:
                    () => ref.invalidate(
                      smartAggregateEventRepositoryProvider(query),
                    ),
              )
              : const _GamesShimmerList(key: ValueKey('smart_events_loading'));
    } else if (event.games.isEmpty) {
      content = _EmptyState(
        key: const ValueKey('smart_events_empty'),
        message:
            scope.searchQuery.isNotEmpty ||
                    scope.filter.hasActiveFilters ||
                    scope.tier != 'All'
                ? 'No events match your filters'
                : 'No events right now',
      );
    } else {
      final games = event.games;
      final gamesData = GamesScreenModel(
        gamesTourModels: games,
        pinnedGamedIs: event.pinnedGameIds,
      );
      final liveBatchKeyByGameId = liveBatchKeysForGames(
        games: games,
        scopePrefix: 'smart_event_events:${request.scopeId}',
      );
      final viewMode = ref.watch(gamesListViewModeProvider);
      final isGrid = viewMode == GamesListViewMode.chessBoardGrid;
      final gridColumns =
          ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape ? 4 : 2;
      final rows = _buildEventGameRows(
        event,
        gridColumns: isGrid ? gridColumns : 1,
      );
      final horizontalPadding = ResponsiveHelper.adaptive(
        phone: 16.sp,
        tablet: 24.sp,
      );

      content = NotificationListener<ScrollNotification>(
        key: const ValueKey('smart_events_data'),
        onNotification: _handleScrollNotification,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: RefreshIndicator(
              color: kPrimaryColor,
              backgroundColor: context.colors.surface,
              onRefresh: () async {
                ref.invalidate(smartEventResolvedEventsProvider);
                ref.invalidate(smartAggregateEventRepositoryProvider);
              },
              child: ListView.builder(
                key: PageStorageKey<String>(
                  'smart_event_events_${request.scopeId}',
                ),
                controller: _scrollController,
                scrollCacheExtent: kListScrollCacheExtent,
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8.sp,
                  horizontalPadding,
                  24.sp,
                ),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                itemCount:
                    rows.length +
                    (event.hasMore || event.isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= rows.length) {
                    if (!event.isLoadingMore) {
                      return const SizedBox(height: 24);
                    }
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }

                  final row = rows[index];
                  if (row.event != null) {
                    return Padding(
                      padding: EdgeInsets.only(
                        top: row.isFirstSection ? 0 : 16.h,
                        bottom: 12.h,
                      ),
                      child: _SmartIncludedEventCard(
                        event: row.event!,
                        heroTagSuffix: 'smart_events_${request.scopeId}',
                      ),
                    );
                  }
                  if (row.gridGames != null) {
                    final rowGames = row.gridGames!;
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: row.isLastInSection ? 16.h : 12.h,
                      ),
                      child: Row(
                        children: [
                          for (
                            var column = 0;
                            column < gridColumns;
                            column++
                          ) ...[
                            if (column > 0) SizedBox(width: 12.sp),
                            Expanded(
                              child:
                                  column < rowGames.length
                                      ? _buildGridGame(
                                        game: rowGames[column],
                                        games: games,
                                        gamesData: gamesData,
                                        liveBatchKey:
                                            liveBatchKeyByGameId[rowGames[column]
                                                .gameId],
                                        streamEnabled: streamEnabled,
                                      )
                                      : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  final game = row.game!;
                  final gameIndex = games.indexWhere(
                    (item) => item.gameId == game.gameId,
                  );
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: row.isLastInSection ? 16.h : 12.h,
                    ),
                    child: GameCardWrapperWidget(
                      key: ValueKey('smart_event_grouped_${game.gameId}'),
                      game: game,
                      gamesData: gamesData,
                      gameIndex: gameIndex < 0 ? 0 : gameIndex,
                      isChessBoardVisible:
                          viewMode == GamesListViewMode.chessBoard,
                      viewSource: ChessboardView.smartEvent,
                      onReturnFromChessboard: (_) {},
                      liveBatchKey: liveBatchKeyByGameId[game.gameId],
                      allowStockfishFallback: true,
                      streamEnabled: streamEnabled,
                      onBeforeOpen: () => _guardGameOpen(context),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return TickerMode(
      enabled: streamEnabled,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: content,
      ),
    );
  }
}

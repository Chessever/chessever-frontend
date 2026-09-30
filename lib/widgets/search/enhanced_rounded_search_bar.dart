import 'dart:async';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/search/search_motion.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

class EnhancedRoundedSearchBar extends ConsumerStatefulWidget {
  const EnhancedRoundedSearchBar({
    super.key,
    required this.controller,
    this.onPlayerSelected,
    this.onOpeningSelected,
    this.onChanged,
    this.onTournamentSelected,
    this.hintText = 'Search',
    this.autofocus = false,
    this.onFilterTap,
    this.onProfileTap,
    this.showProfile = true,
    this.showFilter = true,
    this.focusNode,
    this.onClearSearchField,
    this.filterBadgeCount = 0,
    this.textFieldKey,
    this.filterButtonKey,
    this.rotatingHints,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<GroupEventCardModel>? onTournamentSelected;
  final String hintText;
  final bool autofocus;
  final ValueChanged<SearchPlayer>? onPlayerSelected;
  final ValueChanged<OpeningSearchSelection>? onOpeningSelected;
  final VoidCallback? onFilterTap;
  final VoidCallback? onProfileTap;

  /// Whether the profile avatar belongs in this bar at all. The avatar also
  /// collapses on focus without the host having to drive it (the shared
  /// [HomeTopBarRow] listens to the focus node), so a host that just wants
  /// "avatar on the home bar" can leave this `true` and never rebuild on
  /// focus.
  final bool showProfile;
  final bool showFilter;
  final FocusNode? focusNode;
  final VoidCallback? onClearSearchField;
  final int filterBadgeCount;
  final Key? textFieldKey;
  final Key? filterButtonKey;
  final List<String>? rotatingHints;

  @override
  ConsumerState<EnhancedRoundedSearchBar> createState() =>
      _EnhancedRoundedSearchBarState();
}

class _EnhancedRoundedSearchBarState
    extends ConsumerState<EnhancedRoundedSearchBar>
    with SingleTickerProviderStateMixin {
  final FocusNode _internalFocusNode = FocusNode();
  late final FocusNode _effectiveNode;

  /// 0 = resting, 1 = focused. Drives the field edge and the results reveal.
  /// The avatar collapse runs the same [SearchMotion.morph] from the same
  /// frame, so the whole morph shares one timeline.
  late final BoundedSingleMotionController _morph;

  /// Mounting the overlay is a rebuild, so it is scoped to its own notifier —
  /// gaining focus must not rebuild the text field underneath it (that is what
  /// used to churn the IME on every focus change).
  final ValueNotifier<bool> _overlayMounted = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _effectiveNode = widget.focusNode ?? _internalFocusNode;
    _effectiveNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);

    _morph = BoundedSingleMotionController(
      motion: SearchMotion.morph,
      vsync: this,
    );
    _morph.addStatusListener(_onMorphStatus);
    _morph.addListener(_onMorphValue);

    // Warm the recent-search history now rather than on first tap. Reading it
    // lazily meant the SQLite round-trip started on the same frame the panel
    // began unrolling, so the very first open resolved its contents mid-reveal.
    ref.read(recentSearchesProvider);
  }

  @override
  void dispose() {
    _effectiveNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _internalFocusNode.dispose();
    widget.controller.removeListener(_onTextChange);
    EasyDebounce.cancel('search_debounce');
    cancelSearchDebounce();
    _morph.removeListener(_onMorphValue);
    _morph.removeStatusListener(_onMorphStatus);
    _morph.dispose();
    _overlayMounted.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final focused = _effectiveNode.hasFocus;
    ref.read(isSearchingProvider.notifier).state = focused;
    if (focused) {
      _overlayMounted.value = true;
      _morph.forward();
    } else {
      _collapse();
    }
  }

  /// Parks the spring the moment it is visually at rest.
  void _onMorphValue() {
    if (!_morph.isAnimating) return;
    if (_effectiveNode.hasFocus) {
      if (_morph.value >= 1 - SearchMotion.restEpsilon) _park(1);
    } else if (_morph.value <= SearchMotion.restEpsilon) {
      _park(0);
      _overlayMounted.value = false;
    }
  }

  /// Stops the ticker, then snaps the value home.
  ///
  /// The stop is not optional. `BoundedMotionController` overrides the `value`
  /// setter and — unlike the unbounded base class — does not stop its own
  /// ticker, so assigning alone would leave the spring running and this
  /// listener would re-enter itself until the stack blew.
  void _park(double value) {
    _morph.stop(canceled: true);
    _morph.value = value;
  }

  /// Backstop for the case where the spring reaches the simulation's own
  /// tolerance before [_onMorphValue] parks it.
  void _onMorphStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_effectiveNode.hasFocus) {
      _overlayMounted.value = false;
    }
  }

  void _onTextChange() {
    final text = widget.controller.text;
    final hasText = text.isNotEmpty;
    final isActivelySearching = _effectiveNode.hasFocus || hasText;
    if (ref.read(isSearchingProvider) != isActivelySearching) {
      ref.read(isSearchingProvider.notifier).state = isActivelySearching;
    }
    if (ref.read(searchQueryProvider) != text) {
      ref.read(searchQueryProvider.notifier).state = text;
    }

    updateDebouncedSearchQuery(ref, text);
    EasyDebounce.debounce(
      'search_debounce',
      const Duration(milliseconds: 300),
      () => widget.onChanged?.call(widget.controller.text),
    );
  }

  /// Runs the morph back to rest. When it is already parked at rest the spring
  /// never ticks, so no `dismissed` status is reported and the overlay would
  /// stay mounted — unmount it here instead of waiting for a callback that is
  /// not coming.
  void _collapse() {
    if (_morph.value <= SearchMotion.restEpsilon && !_morph.isAnimating) {
      _overlayMounted.value = false;
      return;
    }
    _morph.reverse();
  }

  void _hideOverlay() {
    final wasFocused = _effectiveNode.hasFocus;
    dismissSoftwareKeyboard(focusNode: _effectiveNode);
    if (!wasFocused) {
      _collapse();
    }
  }

  void _clearSearchAndHide() {
    widget.controller.clear();
    ref.read(isSearchingProvider.notifier).state = false;
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(debouncedSearchQueryProvider.notifier).state = '';
    cancelSearchDebounce();
    _hideOverlay();
    widget.onClearSearchField?.call();
  }

  void _onTournamentSelected(GroupEventCardModel tournament) {
    unawaited(
      ref
          .read(recentSearchesProvider.notifier)
          .record(RecentSearchEntry.tournament(tournament)),
    );
    _hideOverlay();
    widget.onTournamentSelected?.call(tournament);
  }

  void _onPlayerSelected(SearchPlayer player) {
    unawaited(
      ref
          .read(recentSearchesProvider.notifier)
          .record(RecentSearchEntry.player(player)),
    );
    _hideOverlay();
    widget.onPlayerSelected?.call(player);
  }

  void _onOpeningSelected(OpeningSearchSelection opening) {
    unawaited(
      ref
          .read(recentSearchesProvider.notifier)
          .record(RecentSearchEntry.openingSelection(opening)),
    );
    _hideOverlay();
    widget.onOpeningSelected?.call(opening);
  }

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      onTapOutside: (_) => _hideOverlay(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildSearchBar(), _buildOverlaySlot()],
      ),
    );
  }

  Widget _buildOverlaySlot() {
    return ValueListenableBuilder<bool>(
      valueListenable: _overlayMounted,
      builder: (context, mounted, _) {
        // Keep the populated panel alive while closed. Offstage still lays the
        // child out, but reports zero size and skips paint/hit testing. That
        // pays widget construction, provider subscription, recent-search text
        // measurement and the first layout before the user taps the field,
        // instead of spending that work inside the keyboard's 8.33ms frames.
        //
        // The same element subtree is revealed on focus, so the established
        // SizeTransition geometry and timing remain unchanged.
        return TickerMode(
          enabled: mounted,
          child: Offstage(
            offstage: !mounted,
            child: SizeTransition(
              sizeFactor: _morph,
              alignment: AlignmentDirectional.topStart,
              child: Padding(
                padding: EdgeInsets.only(top: 12.sp),
                child: KeyboardDismissExclusion(
                  focusNode: _effectiveNode,
                  // The panel owns its own layer so unrolling it never
                  // repaints the page content sliding down behind it.
                  child: RepaintBoundary(
                    child: AnimatedSize(
                      duration: SearchMotion.morphDuration,
                      curve: SearchMotion.morphCurve,
                      alignment: Alignment.topCenter,
                      child: SearchOverlay(
                        query: widget.controller.text,
                        onTournamentTap: _onTournamentSelected,
                        onPlayerTap: _onPlayerSelected,
                        onOpeningTap: _onOpeningSelected,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The home bar's shared row (see [HomeTopBarRow]): the avatar squeezes
  /// out as the field takes focus, on the same spring as the field's morph.
  Widget _buildSearchBar() {
    return HomeTopBarRow(
      showAvatar: widget.showProfile,
      onAvatarTap: widget.onProfileTap,
      focusNode: _effectiveNode,
      content: AnimatedBuilder(
        animation: _morph,
        // Built once. Everything the morph touches on this side is paint, so
        // the field never rebuilds mid-animation.
        child: SimpleSearchBar(
          textFieldKey: widget.textFieldKey,
          filterButtonKey: widget.filterButtonKey,
          hintText: widget.hintText,
          rotatingHints: widget.rotatingHints,
          controller: widget.controller,
          focusNode: _effectiveNode,
          onCloseTap: _clearSearchAndHide,
          onOpenFilter: widget.onFilterTap,
          filterBadgeCount: widget.filterBadgeCount,
        ),
        builder:
            (context, child) => HomeSearchFieldSurface(
              lift: _morph.value,
              child: RepaintBoundary(child: child),
            ),
      ),
    );
  }
}

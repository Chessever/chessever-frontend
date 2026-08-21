import 'dart:async';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';

class EnhancedRoundedSearchBar extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final Function(String)? onChanged;
  final Function(GroupEventCardModel)? onTournamentSelected;
  final String hintText;
  final bool autofocus;
  final Function(SearchPlayer)? onPlayerSelected;
  final ValueChanged<GameEcoFilter>? onOpeningSelected;
  final VoidCallback? onFilterTap;
  final VoidCallback? onProfileTap;
  final bool showProfile;
  final bool showFilter;
  final FocusNode? focusNode;
  final VoidCallback? onClearSearchField;
  final int filterBadgeCount;
  final Key? textFieldKey;
  final Key? filterButtonKey;
  final List<String>? rotatingHints;

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

  @override
  ConsumerState<EnhancedRoundedSearchBar> createState() =>
      _EnhancedRoundedSearchBarState();
}

class _EnhancedRoundedSearchBarState
    extends ConsumerState<EnhancedRoundedSearchBar> {
  bool _showOverlay = false;
  final FocusNode _internalFocusNode = FocusNode();
  late final FocusNode _effectiveNode;

  @override
  void initState() {
    super.initState();
    _effectiveNode = widget.focusNode ?? _internalFocusNode;
    _effectiveNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _effectiveNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _internalFocusNode.dispose();
    widget.controller.removeListener(_onTextChange);
    EasyDebounce.cancel('search_debounce');
    cancelSearchDebounce(); // Cancel debounced search timer
    super.dispose();
  }

  void _onFocusChange() {
    ref.read(isSearchingProvider.notifier).state = _effectiveNode.hasFocus;
    setState(() {
      _showOverlay = _effectiveNode.hasFocus;
    });
  }

  void _onTextChange() {
    final text = widget.controller.text;
    final hasText = text.isNotEmpty;
    final isActivelySearching = _effectiveNode.hasFocus || hasText;
    // Only push state when it actually changes; StateProvider notifies (and
    // rebuilds every watcher) on each assignment, so setting the same value
    // per keystroke is wasted work.
    if (ref.read(isSearchingProvider) != isActivelySearching) {
      ref.read(isSearchingProvider.notifier).state = isActivelySearching;
    }
    if (ref.read(searchQueryProvider) != text) {
      ref.read(searchQueryProvider.notifier).state = text;
    }

    // Trigger debounced search query update (prevents heavy search on every keystroke)
    updateDebouncedSearchQuery(ref, widget.controller.text);

    EasyDebounce.debounce(
      'search_debounce',
      const Duration(milliseconds: 300),
      () => widget.onChanged?.call(widget.controller.text),
    );
  }

  void _hideOverlay() {
    setState(() {
      _showOverlay = false;
    });
    _effectiveNode.unfocus();
  }

  void _clearSearchAndHide() {
    widget.controller.clear(); // Clear the search text
    ref.read(isSearchingProvider.notifier).state = false; // Clear search state
    ref.read(searchQueryProvider.notifier).state = ''; // Clear query state
    ref.read(debouncedSearchQueryProvider.notifier).state =
        ''; // Clear debounced state
    cancelSearchDebounce(); // Cancel any pending debounce
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

  void _onOpeningSelected(GameEcoFilter opening) {
    unawaited(
      ref
          .read(recentSearchesProvider.notifier)
          .record(RecentSearchEntry.opening(opening)),
    );
    _hideOverlay();
    widget.onOpeningSelected?.call(opening);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_showOverlay)
          Positioned.fill(
            child: GestureDetector(
              // Just hide the overlay, don't clear the search
              // This allows users to dismiss the dropdown while keeping search results
              onTap: _hideOverlay,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),
        Column(
          children: [
            AnimatedPadding(
              padding: EdgeInsets.symmetric(
                horizontal: _effectiveNode.hasFocus ? 12.w : 0,
              ),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(
                    color:
                        _effectiveNode.hasFocus
                            ? kPrimaryColor.withValues(alpha: 0.5)
                            : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: _buildSearchBar(),
              ),
            ),
            if (_showOverlay)
              Container(
                margin: EdgeInsets.only(top: 12.sp),
                child: SearchOverlay(
                  onTournamentTap: _onTournamentSelected,
                  onPlayerTap: _onPlayerSelected,
                  onOpeningTap: _onOpeningSelected,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        if (widget.showProfile) ...[
          _buildProfileAvatar(),
          SizedBox(width: 16.w),
        ],
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12.br),
            ),
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
          ),
        ),
      ],
    );
  }

  Widget _buildProfileAvatar() {
    return UserAvatar(size: 44, onTap: widget.onProfileTap);
  }
}

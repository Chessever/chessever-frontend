import 'dart:async';

import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Search bar rendered as the top-most item inside each event-view tab's
/// scrollable so it scrolls off with the content instead of staying pinned
/// above the tab bar.
class EventSearchBar extends ConsumerStatefulWidget {
  const EventSearchBar({super.key, this.includeHorizontalPadding = true});

  /// When the caller already applies horizontal padding (e.g. the About tab
  /// wraps all content in a Container with `margin`), set this to false to
  /// avoid doubling the inset.
  final bool includeHorizontalPadding;

  @override
  ConsumerState<EventSearchBar> createState() => _EventSearchBarState();
}

class _EventSearchBarState extends ConsumerState<EventSearchBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(standingsSearchQueryProvider);
    _controller = TextEditingController(text: initial);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final trimmed = query.trim();
      ref.read(standingsSearchQueryProvider.notifier).state = trimmed;
      final gamesNotifier = ref.read(gamesTourScreenProvider.notifier);
      if (trimmed.isEmpty) {
        gamesNotifier.clearSearch();
      } else {
        gamesNotifier.searchGamesEnhanced(trimmed);
      }
    });
  }

  void _handleCleared() {
    _debounce?.cancel();
    _controller.clear();
    _focusNode.unfocus();
    ref.read(standingsSearchQueryProvider.notifier).state = '';
    ref.read(gamesTourScreenProvider.notifier).clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = widget.includeHorizontalPadding
        ? ResponsiveHelper.adaptive(phone: 16.sp, tablet: 24.sp)
        : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        12.h,
        horizontalPadding,
        12.h,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 6.h),
        decoration: BoxDecoration(
          color: kGrey900,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: SimpleSearchBar(
          controller: _controller,
          focusNode: _focusNode,
          hintText: 'Search',
          rotatingHints: const ['player', 'openings', 'FIDE country code'],
          onChanged: _handleChanged,
          onCloseTap: _handleCleared,
          onOpenFilter: null,
        ),
      ),
    );
  }
}

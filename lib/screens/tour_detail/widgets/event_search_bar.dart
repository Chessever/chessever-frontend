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
/// above the tab bar. Horizontal inset is inherited from the enclosing list
/// / column so this widget matches the full width of the surrounding cards.
class EventSearchBar extends ConsumerStatefulWidget {
  const EventSearchBar({super.key});

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
    _controller = TextEditingController(
      text: ref.read(standingsSearchQueryProvider),
    );
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _syncControllerText(String query) {
    if (_controller.text == query) return;
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _handleChanged(String query) {
    final trimmed = query.trim();
    // Standings filter is a cheap in-widget operation over a cached list —
    // update it instantly for a snappy feel.
    ref.read(standingsSearchQueryProvider.notifier).state = query;

    // Games search hits the DB — keep a short debounce so we don't fire a
    // query per keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
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
    ref.listen<String>(standingsSearchQueryProvider, (_, next) {
      _syncControllerText(next);
    });

    // Breathing room above (clear gap from the tab switcher) and below
    // (separation from the first card). Internal vertical padding is kept
    // modest so the field reads as a compact row, visually in harmony with
    // the tab chips and round cards.
    return Padding(
      padding: EdgeInsets.only(top: 14.h, bottom: 14.h),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        decoration: BoxDecoration(
          color: kGrey900,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: SimpleSearchBar(
          controller: _controller,
          focusNode: _focusNode,
          hintText: 'Search',
          // No rotating hints: keep the field static, no word-swap animation.
          onChanged: _handleChanged,
          onCloseTap: _handleCleared,
          onOpenFilter: null,
        ),
      ),
    );
  }
}

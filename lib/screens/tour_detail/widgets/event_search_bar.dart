import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_placeholder.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_search.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Expand-on-tap glass search island above the event tab switcher.
///
/// Collapsed by default (circle only) — expands horizontally when tapped.
/// No permanent full-width surfaceRecessed slab.
class EventSearchBar extends ConsumerStatefulWidget {
  const EventSearchBar({super.key});

  @override
  ConsumerState<EventSearchBar> createState() => _EventSearchBarState();
}

class _EventSearchBarState extends ConsumerState<EventSearchBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final int _placeholderIndex;
  Timer? _debounce;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(standingsSearchQueryProvider),
    );
    _focusNode = FocusNode();
    _placeholderIndex = math.Random().nextInt(eventSearchPlaceholderCount);
    if (_controller.text.trim().isNotEmpty) {
      _expanded = true;
    }
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
    if (query.trim().isNotEmpty && !_expanded) {
      setState(() => _expanded = true);
    }
  }

  void _handleChanged(String query) {
    final trimmed = query.trim();
    ref.read(standingsSearchQueryProvider.notifier).state = query;

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
    final countryCode =
        ref.watch(countryDropdownProvider).valueOrNull?.countryCode;
    final hintText = eventSearchPlaceholderForIndex(
      _placeholderIndex,
      countryCode: countryCode,
    );

    ref.listen<String>(standingsSearchQueryProvider, (_, next) {
      _syncControllerText(next);
    });

    return Padding(
      padding: EdgeInsets.only(top: 2.h, bottom: 4.h),
      child: Align(
        alignment: Alignment.centerRight,
        child: GlassIslandSearch(
          controller: _controller,
          focusNode: _focusNode,
          expanded: _expanded,
          hintText: hintText,
          onExpandedChanged: (v) => setState(() => _expanded = v),
          onChanged: _handleChanged,
          onClear: _handleCleared,
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_placeholder.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Search bar pinned above the event-view tab switcher (About/Games/
/// Standings). Stays visible while the inner tab content scrolls. Horizontal
/// inset comes from the enclosing column.
class EventSearchBar extends ConsumerStatefulWidget {
  const EventSearchBar({super.key, this.focusNode, this.autofocus = false});

  /// The page's own node, so it can tell when the keyboard is up. Null: the
  /// bar keeps one of its own.
  final FocusNode? focusNode;

  /// Puts the cursor in the field as it appears (the search page opening).
  final bool autofocus;

  @override
  ConsumerState<EventSearchBar> createState() => _EventSearchBarState();
}

class _EventSearchBarState extends ConsumerState<EventSearchBar> {
  late final TextEditingController _controller;
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());
  late final int _placeholderIndex;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(standingsSearchQueryProvider),
    );
    _placeholderIndex = math.Random().nextInt(eventSearchPlaceholderCount);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _ownFocusNode?.dispose();
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
      // Closing the search clears the query before this bar is disposed
      // (which cancels the timer); a keystroke still pending in between
      // must not run the closed query again behind the closed field.
      if (!mounted ||
          ref.read(standingsSearchQueryProvider).trim() != trimmed) {
        return;
      }
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
    final countryCode = ref
        .watch(countryDropdownProvider)
        .valueOrNull
        ?.countryCode;
    final hintText = eventSearchPlaceholderForIndex(
      _placeholderIndex,
      countryCode: countryCode,
    );

    ref.listen<String>(standingsSearchQueryProvider, (_, next) {
      _syncControllerText(next);
    });

    // Sits between the app-bar row and the tab switcher, in a row the
    // event screen spaces itself (with the Games tab's list controls beside
    // it). Compact keeps the field slim so the tab chips stay near the top
    // of the viewport.
    return EventSearchBarFrame(
      compact: true,
      child: SimpleSearchBar(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        hintText: hintText,
        onChanged: _handleChanged,
        onCloseTap: _handleCleared,
        onOpenFilter: null,
      ),
    );
  }
}

/// Shared tournament-detail search surface; collections use the same geometry.
class EventSearchBarFrame extends StatelessWidget {
  const EventSearchBarFrame({
    super.key,
    required this.child,
    this.horizontalPadding = 0,
    this.compact = false,
  });
  final Widget child;
  final double horizontalPadding;

  /// A slimmer field for the event screen's search row: no padding inside
  /// the field above and below the bar, and no strip around it, so the row
  /// it sits in sets the spacing. Off everywhere else.
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: compact
        ? EdgeInsets.symmetric(horizontal: horizontalPadding)
        : EdgeInsets.fromLTRB(horizontalPadding, 4.h, horizontalPadding, 8.h),
    child: Container(
      padding: compact ? EdgeInsets.zero : EdgeInsets.symmetric(vertical: 4.h),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: child,
    ),
  );
}

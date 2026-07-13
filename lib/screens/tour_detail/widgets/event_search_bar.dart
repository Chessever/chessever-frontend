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
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Bulky collapsed search button — identical size + glass to the home bottom-nav
/// search button (64px circle, thick graphite lens). See BottomNavBar.
const double kEventSearchCollapsedSize = 64;
const double kEventSearchExpandedHeight = 50;
const LiquidGlassSettings _kEventSearchGlass = LiquidGlassSettings(
  glassColor: Color(0xA62A2A2E),
  thickness: 26,
  blur: 14,
  lightIntensity: 0,
  ambientStrength: 0,
  glowIntensity: 0,
  ambientRim: 0,
  chromaticAberration: 0,
);

/// Whether the tournament bottom search is morphed open (home-style in-place
/// morph). Hoisted so the bottom chrome can collapse the category pill and let
/// the search field span the full width while it's expanded.
final eventBottomSearchExpandedProvider = StateProvider<bool>((ref) => false);

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

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(standingsSearchQueryProvider),
    );
    _focusNode = FocusNode();
    _placeholderIndex = math.Random().nextInt(eventSearchPlaceholderCount);
    if (_controller.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(eventBottomSearchExpandedProvider.notifier).state = true;
        }
      });
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
    if (query.trim().isNotEmpty &&
        !ref.read(eventBottomSearchExpandedProvider)) {
      ref.read(eventBottomSearchExpandedProvider.notifier).state = true;
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

    final expanded = ref.watch(eventBottomSearchExpandedProvider);

    return Padding(
      padding: EdgeInsets.only(top: 2.h, bottom: 4.h),
      child: Align(
        alignment: Alignment.centerRight,
        child: GlassIslandSearch(
          controller: _controller,
          focusNode: _focusNode,
          expanded: expanded,
          hintText: hintText,
          collapsedSize: kEventSearchCollapsedSize,
          expandedHeight: kEventSearchExpandedHeight,
          collapsedIconSize: 18,
          collapsedSettings: _kEventSearchGlass,
          onExpandedChanged:
              (v) =>
                  ref.read(eventBottomSearchExpandedProvider.notifier).state = v,
          onChanged: _handleChanged,
          onClear: _handleCleared,
        ),
      ),
    );
  }
}

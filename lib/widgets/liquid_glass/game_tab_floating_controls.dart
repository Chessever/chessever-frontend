import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_search.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Floating liquid-glass control cluster pinned to the bottom-right of a game
/// list. Replaces the old inline "search field + filter + layout" header row and
/// the standalone scroll-to-top FAB with a single cohesive glass stack:
///
/// ```
///                       ( ▲ )   ← scroll-to-top (only past a threshold)
///        ( ⌗ ) ( ▦ ) ( 🔍 )    ← filter · layout-mode · search
/// ```
///
/// Tapping the search circle expands it into a full-width glass search bar in
/// place; the other buttons hide while searching. The whole cluster is meant to
/// be dropped straight into the tab's outer `Stack` (it positions itself).
class GameTabFloatingControls extends StatefulWidget {
  const GameTabFloatingControls({
    super.key,
    required this.scrollController,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onToggleLayout,
    this.searchFocusNode,
    this.searchHintText = 'Search',
    this.searchFieldKey,
    this.onFilter,
    this.filterActive = false,
    this.filterCount = 0,
    this.scrollToTopThreshold = 300,
    this.onSearchExpandedChanged,
  });

  final ScrollController scrollController;

  final TextEditingController searchController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final String searchHintText;
  final Key? searchFieldKey;

  /// Cycles the game-card view mode (list ↔ board grid ↔ single board).
  final VoidCallback onToggleLayout;

  /// Optional filter action; when null the filter button is omitted.
  final VoidCallback? onFilter;
  final bool filterActive;
  final int filterCount;

  final double scrollToTopThreshold;

  /// Fired when the search circle expands/collapses, so a parent screen can
  /// react (e.g. hide a floating bottom pill while searching).
  final ValueChanged<bool>? onSearchExpandedChanged;

  @override
  State<GameTabFloatingControls> createState() =>
      _GameTabFloatingControlsState();
}

class _GameTabFloatingControlsState extends State<GameTabFloatingControls> {
  bool _searchExpanded = false;
  bool _showScrollTop = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    // Best-effort: clear any parent "search active" flag on teardown.
    if (_searchExpanded) widget.onSearchExpandedChanged?.call(false);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final shouldShow =
        widget.scrollController.offset > widget.scrollToTopThreshold;
    if (shouldShow != _showScrollTop) {
      setState(() => _showScrollTop = shouldShow);
    }
  }

  void _scrollToTop() {
    HapticFeedback.mediumImpact();
    if (!widget.scrollController.hasClients) return;
    widget.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _setSearchExpanded(bool expanded) {
    if (_searchExpanded == expanded) return;
    setState(() => _searchExpanded = expanded);
    widget.onSearchExpandedChanged?.call(expanded);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    // Richer glass so the buttons read as a premium floating surface, matching
    // the home bottom-nav search button rather than the flat page chrome.
    const glass = LiquidGlassSettings(
      glassColor: Color(0xA62A2A2E),
      thickness: 20,
      blur: 14,
      lightIntensity: 0,
      ambientStrength: 0,
      glowIntensity: 0,
      ambientRim: 0,
      chromaticAberration: 0,
    );

    return Positioned(
      left: 16.w,
      right: 16.w,
      bottom: 16.h + bottomInset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scroll-to-top sits ABOVE the search button, only once scrolled.
          AnimatedOpacity(
            opacity: (_showScrollTop && !_searchExpanded) ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !(_showScrollTop && !_searchExpanded),
              child: Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child:
                    GlassIconButton(
                          icon: Icon(
                            CupertinoIcons.chevron_up,
                            color: colors.iconPrimary,
                          ),
                          onPressed: _scrollToTop,
                          size: 48,
                          iconSize: 22,
                          useOwnLayer: true,
                          settings: glass,
                        )
                        .animate(target: _showScrollTop ? 1 : 0)
                        .scale(
                          begin: const Offset(0.8, 0.8),
                          end: const Offset(1, 1),
                        ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!_searchExpanded) ...[
                if (widget.onFilter != null) ...[
                  _FilterButton(
                    active: widget.filterActive,
                    count: widget.filterCount,
                    glass: glass,
                    onTap: () {
                      HapticFeedbackService.buttonPress();
                      widget.onFilter!.call();
                    },
                  ),
                  SizedBox(width: 10.w),
                ],
                GlassIconButton(
                  icon: SvgPicture.asset(
                    SvgAsset.chase_grid,
                    width: 22,
                    height: 22,
                    colorFilter: ColorFilter.mode(
                      colors.iconPrimary,
                      BlendMode.srcIn,
                    ),
                  ),
                  onPressed: widget.onToggleLayout,
                  size: 48,
                  iconSize: 22,
                  useOwnLayer: true,
                  settings: glass,
                ),
                SizedBox(width: 10.w),
              ],
              // Search grows to fill the row when expanded; otherwise a circle.
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GlassIslandSearch(
                    controller: widget.searchController,
                    focusNode: widget.searchFocusNode,
                    textFieldKey: widget.searchFieldKey,
                    expanded: _searchExpanded,
                    onExpandedChanged: _setSearchExpanded,
                    hintText: widget.searchHintText,
                    onChanged: widget.onSearchChanged,
                    onClear: widget.onSearchCleared,
                    collapsedSize: 48,
                    expandedHeight: 48,
                    collapsedIconSize: 22,
                    collapsedSettings: glass,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.active,
    required this.count,
    required this.glass,
    required this.onTap,
  });

  final bool active;
  final int count;
  final LiquidGlassSettings glass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GlassIconButton(
          icon: Icon(
            CupertinoIcons.slider_horizontal_3,
            color: active ? const Color(0xFFEF4444) : colors.iconPrimary,
          ),
          onPressed: onTap,
          size: 48,
          iconSize: 22,
          useOwnLayer: true,
          settings: glass,
        ),
        if (active && count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 18.w,
              height: 18.w,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFEF4444),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

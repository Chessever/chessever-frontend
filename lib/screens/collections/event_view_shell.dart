import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/destination_title.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// A pushed collection uses the event detail header; the bottom navigation
/// destination uses the shared home header so its avatar and tabs stay aligned
/// with Home and Events. Pages beneath the tabs swipe in either layout.
class EventViewShell extends StatefulWidget {
  const EventViewShell({
    super.key,
    required this.title,
    required this.tabs,
    required this.pageBuilder,
    this.initialTab = 0,
    this.controller,
    this.showBackButton = true,
    this.homeTab = false,
    this.onOpenSidebar,
    this.scrollToTopSequence,
    this.header,
    this.embedded = false,
    this.tabStripOverride,
    this.tabStripPadding,
    this.actions,
    this.titleIcon,
    this.onTitleTap,
    this.beforeTabsBuilder,
    this.scrollableTabs = false,
    this.contentOverride,
    this.secondaryTabs = false,
    this.onTabChanged,
    this.tabLongPressFor,
    this.tabLongPressHint,
    this.dotScope,
  });

  /// Names the segmented tabs as discovery-dot anchors; see
  /// [SegmentedSwitcher.dotScope].
  final String? dotScope;

  /// Reports the tab the shell moved to (a tap, a swipe, or a controller
  /// request), so a parent can remember it.
  final ValueChanged<int>? onTabChanged;

  /// What holding tab `index` does, or null to leave it press-only.
  final VoidCallback? Function(int index)? tabLongPressFor;

  /// What assistive technology announces for a tab's long press.
  final String Function(int index)? tabLongPressHint;

  /// Renders only tabs and pages inside a parent screen. The parent owns the
  /// header and horizontal swipe; these secondary tabs remain tappable.
  final bool embedded;

  /// A quiet text row beneath a parent destination's segmented tabs.
  final bool secondaryTabs;

  /// Replaces the segmented tab strip (a search row on single-page screens).
  /// Pages still swipe; with one tab there is nothing to switch between.
  final Widget? tabStripOverride;

  /// Allows scrollable overrides to own their padding inside the viewport.
  final EdgeInsetsGeometry? tabStripPadding;
  final bool scrollableTabs;

  /// Search results replacing the pages while preserving tab/scroll state.
  final Widget? contentOverride;

  /// Trailing header buttons on the default (back + title) header, in place
  /// of the spacer that balances the back button.
  final List<Widget>? actions;
  final Widget? header;
  final Widget? titleIcon;

  /// Optional title action, used by an author name to select their About tab.
  final VoidCallback? onTitleTap;

  /// Pinned content between the detail header and tab switcher.
  final Widget Function(BuildContext context, int selectedTab)?
  beforeTabsBuilder;
  final String title;
  final List<String> tabs;
  final Widget Function(BuildContext context, int index) pageBuilder;
  final int initialTab;
  final bool showBackButton;

  /// Uses the home scaffold's header geometry for a bottom navigation page.
  final bool homeTab;
  final VoidCallback? onOpenSidebar;
  final int? scrollToTopSequence;

  /// Lets a page switch tabs (a player picked on Players opens their games).
  final EventViewController? controller;

  @override
  State<EventViewShell> createState() => _EventViewShellState();
}

/// Moves an [EventViewShell] to a tab.
class EventViewController extends ChangeNotifier {
  int? _request;
  bool _resetScroll = false;

  void showTab(int index, {bool scrollToTop = false}) {
    _request = index;
    _resetScroll = scrollToTop;
    notifyListeners();
  }
}

class _EventViewShellState extends State<EventViewShell> {
  late final PageController _pages = PageController(
    initialPage: widget.initialTab,
  );
  late int _selected = widget.initialTab;
  final Map<int, ScrollController> _scrolls = {};

  /// Settles tab moves on a spring rather than a stock easing curve.
  static final Curve _pageCurve = const CupertinoMotion.smooth().toCurve;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onRequest);
  }

  @override
  void didUpdateWidget(EventViewShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollToTopSequence != null &&
        oldWidget.scrollToTopSequence != widget.scrollToTopSequence) {
      final scroll = _scrolls[_selected];
      if (scroll != null && scroll.hasClients) {
        for (final position in scroll.positions) {
          if (MediaQuery.disableAnimationsOf(context)) {
            position.jumpTo(0);
          } else {
            position.animateTo(
              0,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
            );
          }
        }
      }
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onRequest);
      widget.controller?.addListener(_onRequest);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onRequest);
    _pages.dispose();
    for (final scroll in _scrolls.values) {
      scroll.dispose();
    }
    super.dispose();
  }

  void _onRequest() {
    final index = widget.controller?._request;
    if (index == null) return;
    _select(index);
    if (widget.controller?._resetScroll ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scroll = _scrolls[index];
        if (scroll != null && scroll.hasClients) {
          for (final position in scroll.positions) {
            position.jumpTo(0);
          }
        }
      });
    }
  }

  void _select(int index) {
    if (index < 0 || index >= widget.tabs.length) return;
    FocusScope.of(context).unfocus();
    if (index != _selected) widget.onTabChanged?.call(index);
    setState(() => _selected = index);
    if (!_pages.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
      return;
    }
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 240),
      curve: _pageCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final side = HomeTopBarMetrics.horizontalPadding;
    final content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.isTablet
              ? ResponsiveHelper.contentMaxWidth
              : double.infinity,
        ),
        child: Column(
          children: [
            if (widget.embedded)
              const SizedBox.shrink()
            else if (widget.header != null)
              widget.header!
            else if (widget.homeTab)
              HomeTopBar(
                onOpenSidebar: widget.onOpenSidebar,
                content: Semantics(
                  header: true,
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textMdMedium.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            else ...[
              SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4.h),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.adaptive(
                    phone: 16.w,
                    tablet: 24.w,
                  ),
                ),
                child: Row(
                  children: [
                    if (widget.showBackButton)
                      IconButton(
                        tooltip: 'Back',
                        iconSize: 24.ic,
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          HapticFeedbackService.navigation();
                          Navigator.of(context).maybePop();
                        },
                        icon: Icon(
                          Icons.arrow_back_ios_new_outlined,
                          size: 24.ic,
                          color: colors.textPrimary,
                        ),
                      ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: widget.titleIcon != null
                            ? Center(
                                child: DestinationTitle(
                                  title: widget.title,
                                  icon: widget.titleIcon!,
                                ),
                              )
                            : widget.onTitleTap != null
                            ? TextButton(
                                key: const ValueKey('event_view_title_action'),
                                onPressed: widget.onTitleTap,
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.textPrimary,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.w,
                                  ),
                                  minimumSize: const Size(44, 44),
                                ),
                                child: Text(
                                  widget.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.textMdMedium.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : Text(
                                widget.title,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.textMdMedium.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    if (widget.actions != null)
                      ...widget.actions!
                    else if (widget.showBackButton)
                      const SizedBox(width: 48),
                  ],
                ),
              ),
            ],
            SizedBox(height: widget.homeTab ? 16.h : 8.h),
            if (widget.beforeTabsBuilder != null)
              widget.beforeTabsBuilder!(context, _selected),
            Padding(
              padding:
                  widget.tabStripPadding ??
                  EdgeInsets.symmetric(horizontal: side),
              child:
                  widget.tabStripOverride ??
                  (widget.secondaryTabs
                      ? Row(
                          children: [
                            for (
                              var index = 0;
                              index < widget.tabs.length;
                              index++
                            )
                              Expanded(
                                child: Semantics(
                                  selected: index == _selected,
                                  child: TextButton(
                                    onPressed: () => _select(index),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(0, 44),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8.w,
                                        vertical: 12.h,
                                      ),
                                      foregroundColor: index == _selected
                                          ? colors.textPrimary
                                          : colors.textSecondary,
                                      textStyle: AppTypography.textSmMedium
                                          .copyWith(
                                            height: 1.2,
                                            fontWeight: index == _selected
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                          ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        widget.tabs[index],
                                        maxLines: 1,
                                        softWrap: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : SegmentedSwitcher(
                          dotScope: widget.dotScope,
                          key: ValueKey(
                            'event_view_tabs_${widget.tabs.join('_')}',
                          ),
                          backgroundColor: colors.popup,
                          selectedBackgroundColor: colors.popup,
                          // Keep the labels inside the fixed-height strip when the
                          // system text size grows.
                          textStyle: AppTypography.textSmMedium.copyWith(
                            color: colors.tabInactive,
                            height: 1.2,
                          ),
                          selectedTextStyle: AppTypography.textSmMedium
                              .copyWith(color: colors.textPrimary, height: 1.2),
                          options: widget.tabs,
                          optionLabels: [
                            for (final tab in widget.tabs)
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4.w),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    tab,
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                              ),
                          ],
                          isScrollable: widget.scrollableTabs,
                          initialSelection: widget.initialTab,
                          currentSelection: _selected,
                          onSelectionChanged: _select,
                          longPressFor: widget.tabLongPressFor,
                          longPressHint: widget.tabLongPressHint,
                        )),
            ),
            if (widget.homeTab) SizedBox(height: 12.h),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Offstage(
                    offstage: widget.contentOverride != null,
                    child: PageView.builder(
                      controller: _pages,
                      physics: widget.embedded
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      itemCount: widget.tabs.length,
                      onPageChanged: (index) {
                        if (index == _selected) return;
                        FocusScope.of(context).unfocus();
                        widget.onTabChanged?.call(index);
                        setState(() => _selected = index);
                      },
                      itemBuilder: (context, index) => PrimaryScrollController(
                        controller: _scrolls.putIfAbsent(
                          index,
                          ScrollController.new,
                        ),
                        child: Builder(
                          builder: (context) =>
                              widget.pageBuilder(context, index),
                        ),
                      ),
                    ),
                  ),
                  if (widget.contentOverride != null) widget.contentOverride!,
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.embedded) return content;
    return ScreenWrapper(
      child: Scaffold(backgroundColor: colors.background, body: content),
    );
  }
}

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/destination_title.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search_page_header.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// A pushed collection uses the event detail header; the bottom navigation
/// destination uses the shared home header so its avatar and tabs stay aligned
/// with Home and Events. Pages beneath the tabs swipe in either layout.
///
/// The header and the tabs step out of the way while the reader reads (X
/// style): scrolling a page down pushes them up under the status bar with
/// the finger, scrolling back up brings them back. Every page of every
/// screen built on the shell gets it; [embedded] tabs leave it to the
/// parent that owns the header.
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
    this.search,
  });

  /// The page's full-page search, when it has one: a floating search button
  /// over the tabs it searches, opening the field in the header's place.
  /// Not offered while [embedded].
  final EventViewSearch? search;

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
  /// With a [search], only while it is open: closing it brings the tabs
  /// back, narrowed by the filters left on and counted on its button,
  /// rather than leaving the results over every tab with no field to say
  /// why.
  final Widget? contentOverride;

  /// Trailing header buttons on the default (back + title) header, in place
  /// of the spacer that balances the back button.
  final List<Widget>? actions;

  /// Replaces the default header. It is laid out under the status bar's
  /// inset, which the shell keeps outside the part that scrolls away, so a
  /// header leaves that inset out (`HomeTopBarFrame(statusBar: false)`).
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

/// A page's search in an [EventViewShell]: the reader opens it from the
/// floating search button, the header and the tabs give way to [field], and
/// the tab they searched from stays under it, filtered as they type (or
/// replaced by the shell's `contentOverride`, for a page whose results are
/// a list of their own). Back closes it and clears what was searched.
class EventViewSearch {
  const EventViewSearch({
    required this.field,
    required this.focusNode,
    required this.onClose,
    this.label = 'Search',
    this.tabs,
    this.badgeCount = 0,
  });

  /// The page's own search field, filter glyph included when it has one.
  /// It takes [focusNode]; the shell puts the cursor in it as it opens.
  final Widget field;
  final FocusNode focusNode;

  /// Clears what was searched. Called as the search closes.
  final VoidCallback onClose;

  /// What the floating button announces.
  final String label;

  /// The tabs the button floats over; null for every tab.
  final Set<int>? tabs;

  /// Applied filters, counted on the button's shoulder so a list that is
  /// still narrowed says so while the search is closed.
  final int badgeCount;
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

class _EventViewShellState extends State<EventViewShell>
    with SingleTickerProviderStateMixin {
  late final PageController _pages = PageController(
    initialPage: widget.initialTab,
  );
  late int _selected = widget.initialTab;
  final Map<int, ScrollController> _scrolls = {};

  /// The header and the tabs, pushed away by the pages' scrolls.
  late final ScrollChromeController _chrome = ScrollChromeController(
    vsync: this,
  );

  /// The page's full-page search is open: its field in the header's place,
  /// the tab it searched under it, nothing else around it.
  bool _searching = false;

  bool get _searchable => widget.search != null && !widget.embedded;

  bool _searchesTab(int index) => widget.search?.tabs?.contains(index) ?? true;

  /// What replaces the pages now; see [EventViewShell.contentOverride].
  Widget? get _override =>
      _searchable && !_searching ? null : widget.contentOverride;

  void _openSearch() {
    if (_searching || !_searchable) return;
    setState(() => _searching = true);
    _chrome.show();
    // The field is built in this frame; the cursor goes in once it is.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searching) widget.search?.focusNode.requestFocus();
    });
  }

  void _closeSearch() {
    if (!_searching) return;
    widget.search?.focusNode.unfocus();
    widget.search?.onClose();
    setState(() => _searching = false);
    _chrome.show();
  }

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
      _scrollToTop();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onRequest);
      widget.controller?.addListener(_onRequest);
    }
    // A page that stops searching takes its open search with it.
    if (_searching && !_searchable) _searching = false;
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onRequest);
    _pages.dispose();
    for (final scroll in _scrolls.values) {
      scroll.dispose();
    }
    _chrome.dispose();
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

  /// Takes the open tab's list back to its top; the chrome comes back with
  /// it.
  void _scrollToTop() {
    final scroll = _scrolls[_selected];
    if (scroll == null || !scroll.hasClients) return;
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

  /// A tab tapped in the strip. The one already open goes back to its top,
  /// as a reselected tab does across the app: the lists' own up arrows gave
  /// their corner to the floating search, and a screen pushed from Profile
  /// has no bottom-bar tab to tap again.
  void _tapTab(int index) {
    if (index == _selected) {
      _scrollToTop();
      return;
    }
    _select(index);
  }

  void _select(int index) {
    if (index < 0 || index >= widget.tabs.length) return;
    FocusScope.of(context).unfocus();
    if (index != _selected) {
      widget.onTabChanged?.call(index);
      // Another tab opens with its header in place.
      _chrome.show();
    }
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

  /// The title row: the home bar's on a bottom-navigation page, the page's
  /// own header, or back and a centred title. Never the status bar's inset.
  Widget _header(BuildContext context) {
    final colors = context.colors;
    final header = widget.header;
    if (header != null) return header;
    final titleStyle = AppTypography.textMdMedium.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    );
    if (widget.homeTab) {
      return HomeTopBarFrame(
        statusBar: false,
        child: HomeTopBarRow(
          showAvatar: widget.onOpenSidebar != null,
          onAvatarTap: widget.onOpenSidebar,
          content: Semantics(
            header: true,
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w),
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
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        minimumSize: const Size(44, 44),
                      ),
                      child: Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    )
                  : Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
            ),
          ),
          if (widget.actions != null)
            ...widget.actions!
          else if (widget.showBackButton)
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _tabStrip(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding:
          widget.tabStripPadding ??
          EdgeInsets.symmetric(horizontal: HomeTopBarMetrics.horizontalPadding),
      child:
          widget.tabStripOverride ??
          (widget.secondaryTabs
              ? Row(
                  children: [
                    for (var index = 0; index < widget.tabs.length; index++)
                      Expanded(
                        child: Semantics(
                          selected: index == _selected,
                          child: TextButton(
                            onPressed: () => _tapTab(index),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: EdgeInsets.symmetric(
                                horizontal: 8.w,
                                vertical: 12.h,
                              ),
                              foregroundColor: index == _selected
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                              textStyle: AppTypography.textSmMedium.copyWith(
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
                  key: ValueKey('event_view_tabs_${widget.tabs.join('_')}'),
                  backgroundColor: colors.popup,
                  selectedBackgroundColor: colors.popup,
                  // Keep the labels inside the fixed-height strip when the
                  // system text size grows.
                  textStyle: AppTypography.textSmMedium.copyWith(
                    color: colors.tabInactive,
                    height: 1.2,
                  ),
                  selectedTextStyle: AppTypography.textSmMedium.copyWith(
                    color: colors.textPrimary,
                    height: 1.2,
                  ),
                  options: widget.tabs,
                  optionLabels: [
                    for (final tab in widget.tabs)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(tab, maxLines: 1, softWrap: false),
                        ),
                      ),
                  ],
                  isScrollable: widget.scrollableTabs,
                  initialSelection: widget.initialTab,
                  currentSelection: _selected,
                  onSelectionChanged: _tapTab,
                  notifyOnReselect: true,
                  longPressFor: widget.tabLongPressFor,
                  longPressHint: widget.tabLongPressHint,
                )),
    );
  }

  Widget _pageStack(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(
        offstage: _override != null,
        child: PageView.builder(
          controller: _pages,
          // Searching holds the tab: the search belongs to it.
          physics: widget.embedded || _searching
              ? const NeverScrollableScrollPhysics()
              : null,
          itemCount: widget.tabs.length,
          onPageChanged: (index) {
            if (index == _selected) return;
            FocusScope.of(context).unfocus();
            widget.onTabChanged?.call(index);
            _chrome.show();
            setState(() => _selected = index);
          },
          itemBuilder: (context, index) => PrimaryScrollController(
            controller: _scrolls.putIfAbsent(index, ScrollController.new),
            child: Builder(
              builder: (context) => widget.pageBuilder(context, index),
            ),
          ),
        ),
      ),
      ?_override,
    ],
  );

  /// The search button over the tabs it searches; nothing while searching.
  Widget _searchFab() {
    final search = widget.search;
    if (search == null || _searching || !_searchesTab(_selected)) {
      return const SizedBox.shrink();
    }
    return SearchInkFab(
      key: const ValueKey('event_view_search_fab'),
      label: search.label,
      badgeCount: search.badgeCount,
      onTap: _openSearch,
    );
  }

  Widget _frame(Widget column) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: ResponsiveHelper.isTablet
            ? ResponsiveHelper.contentMaxWidth
            : double.infinity,
      ),
      child: column,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (widget.embedded) {
      // The parent owns the header, the swipe and the chrome; these tabs sit
      // in its scrolling content.
      return _frame(
        Column(
          children: [
            SizedBox(height: widget.homeTab ? 16.h : 8.h),
            if (widget.beforeTabsBuilder != null)
              widget.beforeTabsBuilder!(context, _selected),
            _tabStrip(context),
            if (widget.homeTab) SizedBox(height: 12.h),
            Expanded(child: _pageStack(context)),
          ],
        ),
      );
    }

    final search = widget.search;
    final bars = _searching && search != null
        ? SearchPageHeader(
            closeKey: const ValueKey('event_view_search_close'),
            field: search.field,
            onClose: _closeSearch,
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context),
              SizedBox(height: widget.homeTab ? 16.h : 8.h),
              if (widget.beforeTabsBuilder != null)
                widget.beforeTabsBuilder!(context, _selected),
              _tabStrip(context),
              if (widget.homeTab) SizedBox(height: 12.h),
            ],
          );
    // The default header's breathing room under the status bar stays with
    // the inset, so the bars fold up to the same line in every state.
    final inset =
        MediaQuery.viewPaddingOf(context).top +
        (widget.header == null && !widget.homeTab ? 4.h : 0);

    final content = _frame(
      Column(
        children: [
          // The status bar's inset stays put: the bars fold up to it, never
          // into it.
          SizedBox(height: inset),
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            // A field on the bars with the keyboard up holds them: scrolling
            // what it searches must not push away the line being typed.
            onFocusChange: (focused) => _chrome.held = focused,
            child: CollapsingChrome(
              controller: _chrome,
              child: SizedBox(width: double.infinity, child: bars),
            ),
          ),
          Expanded(
            child: ScrollChromeRegion(
              controller: _chrome,
              child: _pageStack(context),
            ),
          ),
        ],
      ),
    );

    return PopScope(
      // Back from the search closes it, back to the tab it searched.
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: ScreenWrapper(
        child: Scaffold(
          backgroundColor: colors.background,
          floatingActionButton: _searchable
              ? SlidingFabs(controller: _chrome, child: _searchFab())
              : null,
          body: content,
        ),
      ),
    );
  }
}

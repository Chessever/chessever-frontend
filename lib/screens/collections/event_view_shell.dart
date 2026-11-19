import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/favorites/widgets/games_list_refetch_line.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart'
    show AppBarIconSurface;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/page_spring.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/page_back_float.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';

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
    this.secondaryTabs = false,
    this.onTabChanged,
    this.tabLongPressFor,
    this.tabLongPressHint,
    this.dotScope,
    this.search,
  });

  /// The page's full-page search, when it has one: a floating search button
  /// over the tabs it searches, whose glass morphs into the field in the
  /// header's place (the app's one search mode, [SearchModeHost]) and back.
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

  /// The space between two bare glyphs in the header's [actions], as the
  /// event screen's Games header spaces its view toggle and menu: their
  /// 44pt targets reach past the 32pt tiles they replaced, and the gap
  /// gives that back.
  static double get headerGlyphGap =>
      math.max(0.0, 18.w - 2 * AppBarIconSurface.bareReach);
}

/// What the shell tells one of its pages: whether its floating search
/// button floats over it.
class _EventViewPageScope extends InheritedWidget {
  const _EventViewPageScope({
    required this.underSearchButton,
    required super.child,
  });

  final bool underSearchButton;

  @override
  bool updateShouldNotify(_EventViewPageScope oldWidget) =>
      oldWidget.underSearchButton != underSearchButton;
}

/// The room a list in an [EventViewShell] page leaves after its last row so
/// the floating search button never covers it: put it last in the list.
///
/// It gives way with the button as the search opens, on the search mode's
/// own timeline, and grows back as it closes: a list read to its very end
/// settles down with the morph rather than jumping by the button's height
/// at the tap. Nothing on a tab the button does not float over, or under a
/// shell with no search.
class EventViewSearchButtonGap extends StatelessWidget {
  const EventViewSearchButtonGap({super.key});

  /// Its height while the button floats over the list.
  static double get extent => InkFabStack.extent();

  @override
  Widget build(BuildContext context) {
    final page = context
        .dependOnInheritedWidgetOfExactType<_EventViewPageScope>();
    final scope = SearchModeScope.maybeOf(context);
    if (page == null || !page.underSearchButton || scope == null) {
      return const SizedBox.shrink();
    }
    return SearchModeListEnd(buttons: extent);
  }
}

/// A page's search in an [EventViewShell], run by the app's one search
/// mode: the floating search button's glass morphs into the field in the
/// header's place, the tab it opened on stays under it (the same list, its
/// cards, grouping and layout), filtered as the reader types, and the
/// chevron or system back morphs it home again, clearing what was searched.
///
/// The field is the canonical [SearchModeHeader], typed into
/// [controller]'s words: the page hears them through [onChanged] (every
/// keystroke) and [onQuery] (once typing settles for [debounce]), and both
/// hear '' as the search closes.
class EventViewSearch {
  const EventViewSearch({
    this.controller,
    this.hintText = 'Search',
    this.rotatingHints,
    this.textFieldKey,
    this.onChanged,
    this.onQuery,
    this.onOpen,
    this.onClose,
    this.debounce = const Duration(milliseconds: 300),
    this.onFilters,
    this.filterKey,
    this.keepsTabStrip = false,
    this.label = 'Search',
    this.tabs,
    this.badgeCount = 0,
  });

  /// The search's state, created and disposed by the page. Null lets the
  /// shell hold one of its own (the page then reads the query only through
  /// [onChanged] and [onQuery]).
  final SearchModeController? controller;

  /// The field's hint, and [rotatingHints] cycled after it.
  final String hintText;
  final List<String>? rotatingHints;
  final Key? textFieldKey;

  /// Every keystroke, as typed; '' as the search closes when the field held
  /// anything.
  final ValueChanged<String>? onChanged;

  /// The trimmed query once typing settles for [debounce], an emptied field
  /// at once, and '' as the search closes when anything was searched.
  final ValueChanged<String>? onQuery;

  /// After the search opens.
  final VoidCallback? onOpen;

  /// After the search closes, once its query is cleared: a page clearing
  /// more than the words (a picked player) does it here.
  final VoidCallback? onClose;

  final Duration debounce;

  /// Opens the page's filter sheet. Given, the filters stand beside the
  /// field and in the page's header (on the tabs the search covers), one
  /// glyph ([SearchModeFilterButton]) carrying [badgeCount], so they are
  /// in reach with the search closed too.
  final VoidCallback? onFilters;

  /// On the Filters glyph beside the field.
  final Key? filterKey;

  /// The tab strip (or its override) stays under the field while searching,
  /// for a single page whose strip narrows what is searched (the report
  /// types on Reports). Otherwise the strip gives way with the header.
  final bool keepsTabStrip;

  /// What the floating button announces.
  final String label;

  /// The tabs the button floats over; null for every tab.
  final Set<int>? tabs;

  /// Applied filters: counted on the Filters glyph with [onFilters], else
  /// on the search button's shoulder, so a list still narrowed says so
  /// while the search is closed.
  final int badgeCount;
}

/// [list], a list searched in place, with the Games lists' quiet "still
/// looking" ([GamesListRefetchLine]) along its top while [busy]: the next
/// results load over the last ones rather than wiping them for a spinner
/// or a skeleton.
class EventViewSearchList extends StatelessWidget {
  const EventViewSearchList({
    super.key,
    required this.busy,
    required this.child,
  });

  /// Results are on their way.
  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      PositionedDirectional(
        top: 0,
        start: 0,
        end: 0,
        child: GamesListRefetchLine(active: busy),
      ),
    ],
  );
}

/// Keeps the place of a list searched in place: the hits start at its top,
/// and once the words are gone (emptied, or the search closed) the list is
/// back where the reader left it, rather than at the top of a list they
/// had scrolled through.
///
/// Read through the page's [PrimaryScrollController], so it works on any
/// list a shell tab holds.
class EventViewSearchPlace {
  double? _saved;
  String _words = '';
  bool _pending = false;
  bool _restore = false;

  /// The list is about to show what [words] (and its filters) find. Call
  /// while the list still shows what it showed, from inside the page.
  void queryChanged(BuildContext context, String words) {
    final next = words.trim();
    if (_words.isEmpty && next.isNotEmpty) _saved = _position(context)?.pixels;
    _restore = _words.isNotEmpty && next.isEmpty;
    _words = next;
    _pending = true;
  }

  /// The list now shows what it was asked for: its top for new results, or
  /// the place it was left at once the words are gone. Call from the build
  /// that hands the list its new rows: they are laid out there from their
  /// first frame, never a frame at the old place first.
  void settle(BuildContext context) {
    if (!_pending) return;
    _pending = false;
    final target = _restore ? (_saved ?? 0.0) : 0.0;
    if (_restore) _saved = null;
    _restore = false;
    final now = _position(context);
    // At rest, moved silently before this frame's layout (which reads it
    // with the new rows). A list still coasting is moved after the frame
    // instead: stopping it would report the scroll's end mid-build.
    if (now != null && now.hasPixels && !now.isScrollingNotifier.value) {
      now.correctPixels(math.max(0.0, target));
    }
    // Then held to what the new rows reach.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final position = _position(context);
      if (position == null) return;
      final double to = target.clamp(
        position.minScrollExtent,
        math.max(position.minScrollExtent, position.maxScrollExtent),
      );
      if (position.pixels != to) position.jumpTo(to);
    });
  }

  /// Forgets the place kept: the list under the search changed.
  void forget() => _saved = null;

  static ScrollPosition? _position(BuildContext context) {
    final scroll = PrimaryScrollController.maybeOf(context);
    if (scroll == null || !scroll.hasClients) return null;
    return scroll.positions.first;
  }
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

  bool get _searchable => widget.search != null && !widget.embedded;

  /// The search's state: the page's, or the shell's own for a page that
  /// hands it none.
  SearchModeController get _search =>
      widget.search?.controller ?? (_ownSearch ??= SearchModeController());
  SearchModeController? _ownSearch;

  /// The controller this shell listens to for the search opening and
  /// closing.
  SearchModeController? _boundSearch;

  bool _searchesTab(int index) => widget.search?.tabs?.contains(index) ?? true;

  void _bindSearch() {
    final next = _searchable ? _search : null;
    if (identical(next, _boundSearch)) return;
    _boundSearch?.removeListener(_onSearchToggled);
    next?.addListener(_onSearchToggled);
    _boundSearch = next;
  }

  void _onSearchToggled() {
    if (mounted) setState(() {});
  }

  void _onSearchOpened() => widget.search?.onOpen?.call();

  void _onSearchClosed() => widget.search?.onClose?.call();

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onRequest);
    _bindSearch();
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
    _bindSearch();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onRequest);
    _boundSearch?.removeListener(_onSearchToggled);
    _pages.dispose();
    for (final scroll in _scrolls.values) {
      scroll.dispose();
    }
    _chrome.dispose();
    _ownSearch?.dispose();
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
    if (scroll == null) return;
    unawaited(scroll.springToOffset(0, context: context));
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
    // On a real spring, as the header's other motion: a tab tapped while
    // the pages still move turns them toward it, carrying their speed.
    unawaited(_pages.springTo(index, context: context));
  }

  /// The title row: the home bar's on a bottom-navigation page, the page's
  /// own header, or back and a centred title. Never the status bar's inset.
  ///
  /// The title is named in the one title voice every root and pushed page
  /// shares ([PageTitle], [HomeTopBarTitle.style]).
  Widget _header(BuildContext context) {
    final colors = context.colors;
    final header = widget.header;
    if (header != null) return header;
    if (widget.homeTab) {
      return HomeTopBarFrame(
        statusBar: false,
        child: HomeTopBarRow(
          showAvatar: widget.onOpenSidebar != null,
          onAvatarTap: widget.onOpenSidebar,
          content: MediaQuery.withClampedTextScaling(
            maxScaleFactor: HomeTopBarMetrics.maxTextScale,
            child: Semantics(
              header: true,
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HomeTopBarTitle.style(context),
              ),
            ),
          ),
        ),
      );
    }
    final filters = _headerFilters();
    final actions = widget.actions;
    final start = SearchHeaderMetrics.leadingInset;
    // With Filters, the row ends where the search header's does and they
    // come last, as beside the field: their glyph sits on the gutter in
    // both headers, holding still as the search opens and closes.
    final end = filters == null
        ? start
        : math.max(
            0.0,
            SearchHeaderMetrics.gutter - SearchHeaderMetrics.trailingReach,
          );
    final List<Widget> trailing;
    if (actions != null) {
      trailing = [
        ...actions,
        if (filters != null) ...[
          if (actions.isNotEmpty)
            SizedBox(width: EventViewShell.headerGlyphGap),
          filters,
        ],
      ];
    } else if (filters != null) {
      // Alone, in the slot that balances the back button: the title keeps
      // the centre of the screen.
      final balance =
          start +
          (widget.showBackButton ? SearchHeaderMetrics.backTarget : 0) -
          end;
      trailing = [
        SizedBox(
          width: math.max(SearchModeFilterButton.target, balance),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: filters,
          ),
        ),
      ];
    } else {
      trailing = [
        if (widget.showBackButton)
          const SizedBox(width: SearchHeaderMetrics.backTarget),
      ];
    }
    // The back row the search header's sits on: the same chevron, size, x
    // and y, so only what is around it changes as the search opens.
    return Padding(
      padding: EdgeInsetsDirectional.only(start: start, end: end),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SearchHeaderMetrics.rowHeight,
        ),
        child: Row(
          children: [
            if (widget.showBackButton) const PageBackButton(),
            Expanded(
              child: Center(
                child: widget.onTitleTap != null
                    ? TextButton(
                        key: const ValueKey('event_view_title_action'),
                        onPressed: widget.onTitleTap,
                        style: TextButton.styleFrom(
                          foregroundColor: colors.textPrimary,
                          padding: EdgeInsets.symmetric(horizontal: 8.w),
                          minimumSize: const Size(44, 44),
                        ),
                        child: PageTitle(widget.title, mark: widget.titleIcon),
                      )
                    : PageTitle(widget.title, mark: widget.titleIcon),
              ),
            ),
            ...trailing,
          ],
        ),
      ),
    );
  }

  /// The page's Filters in its own header, on the tabs its search covers,
  /// so they are in reach with the search closed. Elsewhere the glyph keeps
  /// its place, unseen and untouchable, so neither the title nor the glyphs
  /// beside it shift as the tabs change.
  Widget? _headerFilters() {
    final search = _searchable ? widget.search : null;
    final open = search?.onFilters;
    if (search == null || open == null) return null;
    return Visibility(
      visible: _searchesTab(_selected),
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      // The search header's Filters at the same spot: one glyph, still.
      child: SearchModeShared(
        id: SearchModeFilterButton,
        child: SearchModeFilterButton(
          key: const ValueKey('event_view_filters'),
          count: search.badgeCount,
          onTap: open,
        ),
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

  /// The tabs' pages. A search narrows the page it opened on in place, so
  /// it reads as the same list: nothing ever stands in for the pages.
  Widget _pageStack(BuildContext context) => PageView.builder(
    controller: _pages,
    // Searching holds the tab: the search belongs to it.
    physics: widget.embedded
        ? const NeverScrollableScrollPhysics()
        : _searchable
        ? _search.pagePhysics()
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
      child: _EventViewPageScope(
        // Its list ends clear of the button ([EventViewSearchButtonGap]).
        underSearchButton: _searchable && _searchesTab(index),
        child: Builder(
          builder: (context) => widget.pageBuilder(context, index),
        ),
      ),
    ),
  );

  /// The search button over the tabs it searches. It stays while the
  /// search is open: the search mode hides it, its glass having become the
  /// field, and flies the glass back into it as the search closes.
  Widget _searchFab(EventViewSearch search) {
    if (!_searchesTab(_selected)) return const SizedBox.shrink();
    return InkFabStack(
      children: [
        SearchInkFab(
          key: const ValueKey('event_view_search_fab'),
          label: search.label,
          // With Filters in the header, the count is on them.
          badgeCount: search.onFilters == null ? search.badgeCount : 0,
        ),
      ],
    );
  }

  /// The search's header in the header's place, the canonical one.
  /// [matchGap] pads it to the page header's gap under its title row, so a
  /// strip kept under both ([EventViewSearch.keepsTabStrip]) holds still as
  /// they trade places.
  Widget _searchHeader(EventViewSearch search, {double? matchGap}) {
    const closeKey = ValueKey('event_view_search_close');
    final onFilters = search.onFilters;
    final trailing = [
      if (onFilters != null)
        SearchModeShared(
          id: SearchModeFilterButton,
          child: SearchModeFilterButton(
            key: search.filterKey,
            count: search.badgeCount,
            onTap: onFilters,
          ),
        ),
    ];
    Widget header = SearchModeHeader(
      hintText: search.hintText,
      rotatingHints: search.rotatingHints,
      textFieldKey: search.textFieldKey,
      trailing: trailing,
      closeKey: closeKey,
    );
    if (matchGap != null) {
      header = Padding(
        padding: EdgeInsets.only(
          bottom: math.max(0.0, matchGap - SearchHeaderMetrics.bottomGap),
        ),
        child: header,
      );
    }
    return header;
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

    final search = _searchable ? widget.search : null;
    final keepStrip = search?.keepsTabStrip ?? false;
    final gap = widget.homeTab ? 16.h : 8.h;
    Widget strip() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tabStrip(context),
        if (widget.homeTab) SizedBox(height: 12.h),
      ],
    );
    final header = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context),
        SizedBox(height: gap),
        if (widget.beforeTabsBuilder != null)
          widget.beforeTabsBuilder!(context, _selected),
        if (!keepStrip) strip(),
      ],
    );
    Widget bars = header;
    if (search != null) {
      // The header and the search trade places on the search mode's one
      // timeline: the header stays mounted (and exactly as it was left)
      // while the field stands in its place.
      bars = SearchModeHeaderSlot(
        header: header,
        search: _searchHeader(search, matchGap: keepStrip ? gap : null),
      );
      if (keepStrip) {
        bars = Column(
          mainAxisSize: MainAxisSize.min,
          children: [bars, strip()],
        );
      }
    }
    // The default header's breathing room under the status bar stays with
    // the inset, so the bars fold up to the same line in every state.
    final inset =
        MediaQuery.viewPaddingOf(context).top +
        (widget.header == null && !widget.homeTab ? 4.h : 0);

    final column = Column(
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
    );
    // The default header's way back, kept in reach while the bars are
    // folded away (a page's own header places its own).
    final floatsBack =
        widget.header == null && !widget.homeTab && widget.showBackButton;
    final content = _frame(
      floatsBack
          ? Stack(
              fit: StackFit.passthrough,
              children: [
                column,
                PageBackFloat(controller: _chrome),
              ],
            )
          : column,
    );

    final page = ScreenWrapper(
      child: Scaffold(
        backgroundColor: colors.background,
        floatingActionButton: search != null
            ? SlidingFabs(controller: _chrome, child: _searchFab(search))
            : null,
        body: content,
      ),
    );
    if (search == null) return page;
    // The search mode owns the rest: the morph both ways, system back
    // (closing the search first), focus and keyboard, holding the bars
    // while typing, and the query.
    return SearchModeHost(
      controller: _search,
      chrome: _chrome,
      debounce: search.debounce,
      onChanged: search.onChanged,
      onQuery: search.onQuery,
      onOpen: _onSearchOpened,
      onClose: _onSearchClosed,
      child: page,
    );
  }
}

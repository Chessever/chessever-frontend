import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
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
    this.actions = const [],
    this.tabStripOverride,
  });

  final Widget? header;
  final Widget? tabStripOverride;
  final List<Widget> actions;
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
    return ScreenWrapper(
      child: Scaffold(
        backgroundColor: colors.background,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.isTablet
                  ? ResponsiveHelper.contentMaxWidth
                  : double.infinity,
            ),
            child: Column(
              children: [
                if (widget.header != null)
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
                          ),
                        ),
                        if (widget.actions.isNotEmpty)
                          ...widget.actions
                        else if (widget.showBackButton)
                          const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: widget.homeTab ? 16.h : 8.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  child:
                      widget.tabStripOverride ??
                      SegmentedSwitcher(
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
                        initialSelection: widget.initialTab,
                        currentSelection: _selected,
                        onSelectionChanged: _select,
                      ),
                ),
                if (widget.homeTab) SizedBox(height: 12.h),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: widget.tabs.length,
                    onPageChanged: (index) {
                      if (index == _selected) return;
                      FocusScope.of(context).unfocus();
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

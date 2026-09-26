import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// The event view's frame, as the tournament screen draws it: back, a
/// centred title, the segmented tabs and the pages under them, which swipe.
/// Collections use it so a collection reads exactly like an event.
class EventViewShell extends StatefulWidget {
  const EventViewShell({
    super.key,
    required this.title,
    required this.tabs,
    required this.pageBuilder,
    this.initialTab = 0,
    this.controller,
  });

  final String title;
  final List<String> tabs;
  final Widget Function(BuildContext context, int index) pageBuilder;
  final int initialTab;

  /// Lets a page switch tabs (a player picked on Players opens their games).
  final EventViewController? controller;

  @override
  State<EventViewShell> createState() => _EventViewShellState();
}

/// Moves an [EventViewShell] to a tab.
class EventViewController extends ChangeNotifier {
  int? _request;

  void showTab(int index) {
    _request = index;
    notifyListeners();
  }
}

class _EventViewShellState extends State<EventViewShell> {
  late final PageController _pages = PageController(
    initialPage: widget.initialTab,
  );
  late int _selected = widget.initialTab;

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
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onRequest);
      widget.controller?.addListener(_onRequest);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onRequest);
    _pages.dispose();
    super.dispose();
  }

  void _onRequest() {
    final index = widget.controller?._request;
    if (index != null) _select(index);
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
      duration: const Duration(milliseconds: 360),
      curve: _pageCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final side = ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);
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
                      // Balances the back button so the title sits centred.
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                SizedBox(height: 8.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  child: SegmentedSwitcher(
                    key: ValueKey('event_view_tabs_${widget.tabs.join('_')}'),
                    backgroundColor: colors.popup,
                    selectedBackgroundColor: colors.popup,
                    // The strip is a fixed height: the body line height
                    // (22/14) would outgrow it at larger text sizes and cut
                    // a label's descenders ("Players"). A tight line keeps
                    // every label whole and still centred.
                    textStyle: AppTypography.textSmMedium.copyWith(
                      color: colors.tabInactive,
                      height: 1.2,
                    ),
                    selectedTextStyle: AppTypography.textSmMedium.copyWith(
                      color: colors.textPrimary,
                      height: 1.2,
                    ),
                    options: widget.tabs,
                    initialSelection: widget.initialTab,
                    currentSelection: _selected,
                    onSelectionChanged: _select,
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: widget.tabs.length,
                    onPageChanged: (index) {
                      if (index == _selected) return;
                      FocusScope.of(context).unfocus();
                      setState(() => _selected = index);
                    },
                    itemBuilder: widget.pageBuilder,
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

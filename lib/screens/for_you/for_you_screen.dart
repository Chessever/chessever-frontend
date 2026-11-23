import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/for_you/discovery/discovery_view.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart';
import 'package:chessever2/screens/group_event/widget/for_you_games_widget.dart';
import 'package:chessever2/screens/home/start_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/my_space/my_space_view.dart';
import 'package:chessever2/screens/search/search_tab_screen.dart';
import 'package:chessever2/services/discovery_dots/discovery_dot.dart'
    show discoveryDotId;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Builds the body of one For You page around the scroll controller the shell
/// owns for it (re-tapping the nav item scrolls that controller to the top).
typedef ForYouPageBuilder =
    Widget Function(
      BuildContext context,
      ForYouTab tab,
      ScrollController scrollController,
    );

/// The real pages. Today is the personalised feed that used to open the
/// Events screen, unchanged.
Widget buildForYouPage(
  BuildContext context,
  ForYouTab tab,
  ScrollController scrollController,
) {
  return switch (tab) {
    ForYouTab.mySpace => MySpaceView(scrollController: scrollController),
    ForYouTab.today => ForYouGamesWidget(scrollController: scrollController),
    ForYouTab.discovery => DiscoveryView(scrollController: scrollController),
  };
}

/// Scroll-to-top on re-tap settles on a spring, with no overshoot past the
/// top edge.
const CupertinoMotion _scrollTopMotion = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 360),
);
final Curve _scrollTopCurve = _scrollTopMotion.toCurve;

/// The For You section (Home): My Space | Today | Discovery.
///
/// Its only chrome is the page tabs, set in the bar every root wears
/// ([HomeTopBarFrame]): the same inset, height, gutter and centre line as
/// Feed's, Botvinnik's, Collections' and Profile's, with the pages starting
/// at the same line under it. The band scrolls away with the page and back.
/// The reader's profile has a tab of its own; Today's Search and Live first
/// float over it ([ForYouTodayFabs]). The picked tab holds for the session;
/// a launch opens on Today.
class ForYouScreen extends HookConsumerWidget {
  const ForYouScreen({super.key, this.pageBuilder});

  /// Replaces the page bodies, so widget tests can drive the shell without
  /// the network-backed pages. Null in the app.
  @visibleForTesting
  final ForYouPageBuilder? pageBuilder;

  static const int _tabCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTab = ref.watch(selectedForYouTabProvider);
    const pageCount = _tabCount;
    final selectedIndex = selectedTab.index;

    final pageController = usePageController(initialPage: selectedIndex);
    final mySpaceScrollController = useScrollController();
    final todayScrollController = useScrollController();
    final discoveryScrollController = useScrollController();
    // Set while the shell moves the PageView itself, so the resulting
    // onPageChanged is not mistaken for a swipe.
    final isJumping = useRef(false);
    // The page a swipe just selected. PageView reports a page as soon as the
    // offset rounds over to it, mid-drag or mid-fling, while the gesture is
    // still carrying the view there: the shell must not jump it.
    final swipedTo = useRef<int?>(null);
    final lastPageCount = useRef(pageCount);
    // The page the current build's PageView should rest on, read by syncs
    // that run after the build that set it.
    final restingIndex = useRef(selectedIndex);
    restingIndex.value = selectedIndex;
    // The pages the PageView shows, first to last: one at rest, two while a
    // swipe or its settle carries the view between them. Null until the
    // view first moves, which means the selected page alone.
    final shownPages = useState<(int, int)?>(null);
    // Watched so it lives exactly as long as this screen; written below.
    ref.watch(forYouTodayInViewProvider);

    ScrollController controllerForIndex(int index) {
      return switch (ForYouTab.values[index]) {
        ForYouTab.mySpace => mySpaceScrollController,
        ForYouTab.today => todayScrollController,
        ForYouTab.discovery => discoveryScrollController,
      };
    }

    void scrollToTop(ScrollController controller) {
      if (!controller.hasClients) return;
      controller.animateTo(
        0,
        duration: _scrollTopMotion.duration,
        curve: _scrollTopCurve,
      );
    }

    // Moves the PageView onto the selected page when the shell changed the
    // selection (a segment tap, Search appearing or going). Compared on raw
    // pixels, not `page`: when Search goes, the offset sits past the new last
    // page and `page` already reads clamped, which would skip the jump and
    // leave the viewport's own settle to report a page change nobody asked
    // for. Unless [force]d, a scroll in flight is left alone: that is the
    // user's drag or fling, and the scroll-end listener below re-syncs once
    // it lets go.
    void syncPage({required bool force}) {
      if (!context.mounted || !pageController.hasClients) return;
      final position = pageController.position;
      if (!position.hasPixels || !position.hasViewportDimension) return;
      final index = restingIndex.value;
      final target = index * position.viewportDimension;
      if ((position.pixels - target).abs() < 0.5) return;
      if (!force && position.isScrollingNotifier.value) return;
      isJumping.value = true;
      pageController.jumpToPage(index);
      isJumping.value = false;
    }

    // Keep the PageView on the selected page. Deferred to after layout so
    // the page count change has reached the viewport and the jump never runs
    // mid-build. A selection the user swiped to is skipped outright. Search
    // going away is forced: the shrink itself starts a settle toward the old
    // last page, which is not a gesture to wait for.
    useEffect(() {
      final shrank = pageCount < lastPageCount.value;
      lastPageCount.value = pageCount;
      final fromSwipe = swipedTo.value == selectedIndex;
      swipedTo.value = null;
      if (fromSwipe) return null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => syncPage(force: shrank),
      );
      return null;
    }, [selectedIndex, pageCount]);

    // Tracks which pages are in view as the PageView moves. The selection
    // flips at a swipe's halfway mark, so without this the page the swipe is
    // carrying in (before it) or leaving (after it) would render empty while
    // still half on screen. A page counts once more than a pixel of it shows,
    // so a settle that stops a hair off the edge leaves its neighbour unbuilt.
    useEffect(() {
      void track() {
        if (!pageController.hasClients) return;
        final position = pageController.position;
        if (!position.hasPixels || !position.hasViewportDimension) return;
        final viewport = position.viewportDimension;
        if (viewport <= 0) return;
        final page = position.pixels / viewport;
        final slack = 1 / viewport;
        final first = math.max(0, (page - 1 + slack).ceil());
        final last = math.max(first, (page + 1 - slack).floor());
        final next = (first, last);
        if (shownPages.value == next) return;
        final todayIndex = ForYouTab.today.index;
        final todayInView = first <= todayIndex && todayIndex <= last;
        void apply() {
          if (!context.mounted) return;
          shownPages.value = next;
          final inView = ref.read(forYouTodayInViewProvider.notifier);
          if (inView.state != todayInView) inView.state = todayInView;
        }

        // Scroll notifications can land inside layout (a viewport resize);
        // the tree cannot be dirtied there.
        if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => apply());
        } else {
          apply();
        }
      }

      pageController.addListener(track);
      return () => pageController.removeListener(track);
    }, [pageController]);

    void selectTab(ForYouTab tab) {
      ref.read(selectedForYouTabProvider.notifier).select(tab);
      FocusScope.of(context).unfocus();
      // A new page (tapped or swiped to) opens with its bars in view.
      ScrollChromeScope.maybeOf(context)?.show();
    }

    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item != BottomNavBarItem.forYou) return;
      if (previous != null && previous.sequence == next.sequence) return;
      // Home tapped again away from Today slides back to Today (the default
      // page, PM 2026-11-20); on Today it goes to the top.
      if (selectedIndex != ForYouTab.today.index) {
        selectTab(ForYouTab.today);
        return;
      }
      scrollToTop(controllerForIndex(selectedIndex));
    });

    final buildPage = pageBuilder ?? buildForYouPage;

    return Material(
      key: e2eKey(E2eIds.forYouRoot),
      color: context.colors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The header: the pages as tabs with an indicator that rides
              // the swipe, in the bar every root wears. The status bar's
              // inset stays; the band under it scrolls away with the page and
              // back (X-style). No avatar and no search field: Profile has a
              // tab of its own, and Search floats over Today.
              HomeTopBarFrame(
                child: _ForYouHeader(
                  pageController: pageController,
                  selectedIndex: selectedIndex,
                  onHold: (index) => unawaited(
                    makeStartScreenDefault(
                      context,
                      ref,
                      section: BottomNavBarItem.forYou,
                      page: forYouStartPage(ForYouTab.values[index]),
                    ),
                  ),
                  onSelected: (index) {
                    if (index == selectedIndex) {
                      scrollToTop(controllerForIndex(index));
                      return;
                    }
                    selectTab(ForYouTab.values[index]);
                  },
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollEndNotification>(
                  // A selection made while a gesture owned the PageView (a
                  // segment tapped mid-fling) was left for the gesture to
                  // finish; put the view on it now. Deferred: the
                  // notification fires from inside the position's own
                  // activity change.
                  onNotification: (notification) {
                    if (notification.depth == 0 && !isJumping.value) {
                      Future<void>.microtask(() => syncPage(force: false));
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: pageController,
                    itemCount: pageCount,
                    onPageChanged: (index) {
                      if (isJumping.value || index >= _tabCount) return;
                      final tab = ForYouTab.values[index];
                      // Already there: nothing to select.
                      if (ref.read(selectedForYouTabProvider) == tab) {
                        return;
                      }
                      // The gesture is already carrying the view there, so
                      // the sync effect skips it.
                      swipedTo.value = index;
                      selectTab(tab);
                    },
                    itemBuilder: (context, index) {
                      // Built: the selected page and any page a swipe shows
                      // beside it. At rest that is the selected page alone;
                      // the others keep their provider caches, not their
                      // widget trees.
                      final shown = shownPages.value;
                      final inView =
                          shown != null &&
                          index >= shown.$1 &&
                          index <= shown.$2;
                      if (index >= pageCount ||
                          (index != selectedIndex && !inView)) {
                        return const SizedBox.shrink();
                      }
                      return buildPage(
                        context,
                        ForYouTab.values[index],
                        controllerForIndex(index),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The key of Today's Live first button.
const String kForYouLiveFirstButtonKey = 'for_you_live_first_button';

/// The key of Today's Search button.
const String kForYouSearchButtonKey = E2eIds.forYouSearchButton;

/// The keys of My Space's and Discovery's Search buttons.
const String kMySpaceSearchButtonKey = 'my_space_search_button';
const String kDiscoverySearchButtonKey = 'discovery_search_button';

/// Home's Search button, the same on My Space, Today and Discovery and in
/// the same corner on each, as the 38.17 search field stood over all three:
/// it opens Search over Home ([SearchTabScreen.open]). [key] tells the
/// three apart.
SearchInkFab homeSearchFab(BuildContext context, {required String key}) =>
    SearchInkFab(
      key: ValueKey(key),
      onTap: () => unawaited(SearchTabScreen.open(context)),
    );

/// Today's floating buttons, in the thumb's reach where the search field and
/// Botvinnik used to be (Trello #1420), stacked as every page's are
/// ([InkFabStack]: the main button at the bottom, the smaller one above it,
/// rims flush on one trailing edge):
///
/// * Search, always, at the bottom: the page's main, regular button, the
///   magnifier every list's search button wears ([SearchInkFab]). It opens
///   Search over Home ([SearchTabScreen.open]), the app-wide search that had
///   the dock's slot Collections holds now. It never moves.
/// * Live first above it, the live mark ([LiveFirstCapsule]). Its tooltip
///   and accessibility label count the events a press lifts
///   ([todayLiveEventCountProvider]). It stays available while events are
///   live, while the count is unknown, or while the toggle is on. Turning
///   it on puts live events first and scrolls Today to the top.
///
/// Today has no filter of its own: the event filter belongs to the Events
/// page (Profile), which keeps it.
class ForYouTodayFabs extends HookConsumerWidget {
  const ForYouTodayFabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A press can wait on the feed for live events below its pages; taps
    // until it is answered are ignored.
    final pressing = useRef(false);
    final liveFirst = ref.watch(homeEventsLiveFirstProvider);
    final liveCount = ref.watch(todayLiveEventCountProvider);
    return InkFabStack(
      children: [
        if (showsHomeLiveFirst(liveCount: liveCount, on: liveFirst))
          LiveFirstCapsule(
            key: const ValueKey(kForYouLiveFirstButtonKey),
            subject: 'events',
            on: liveFirst,
            liveCount: liveCount,
            onTap: () async {
              if (pressing.value) return;
              pressing.value = true;
              try {
                if (await pressForYouLiveFirst(context: context, ref: ref)) {
                  // The live events now lead Today: show its top.
                  ref
                      .read(bottomNavBarReTapRequestProvider.notifier)
                      .request(BottomNavBarItem.forYou);
                }
              } finally {
                pressing.value = false;
              }
            },
          ),
        homeSearchFab(context, key: kForYouSearchButtonKey),
      ],
    );
  }
}

/// Home's header: My Space | Today | Discovery as text tabs, nothing else,
/// filling the bar's row ([HomeTopBarFrame] holds the gutters).
///
/// The selected tab is set as every root's title is ([HomeTopBarTitle]),
/// with a short rounded bar under it in the brand's tonal blue. The bar
/// rides the pages' own position, so it travels with a swipe under the
/// finger rather than jumping when the swipe lands. Tapping the selected tab
/// takes its page back to the top.
class _ForYouHeader extends StatelessWidget {
  const _ForYouHeader({
    required this.pageController,
    required this.selectedIndex,
    required this.onSelected,
    required this.onHold,
  });

  final PageController pageController;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// A held tab title.
  final ValueChanged<int> onHold;

  @override
  Widget build(BuildContext context) {
    return ForYouPageTabs(
      // The ids Home's tabs wore before 38.18 (`home.tab.my_space`, ...):
      // Nudges published for them, and trails through them, light here.
      dotScope: 'home.tab',
      pageController: pageController,
      selectedIndex: selectedIndex,
      labels: [for (final tab in ForYouTab.values) tab.label],
      onSelected: onSelected,
      onHold: onHold,
    );
  }
}

/// Equal-width text tabs with an indicator that follows [pageController],
/// as tall as the bar's row ([HomeTopBarMetrics.rowExtent]) so each label
/// sits on the centre line every root's title sits on, and the indicator
/// rests on the row's foot. A root whose pages are its header wears them:
/// Home, and Collections on its tab.
///
/// With a [dotScope] each tab is a Nudge surface (a [DiscoveryDotAnchor])
/// named `<dotScope>.<label>`, as the segmented tabs these replaced were:
/// the dot sits off the word's top-right shoulder, and the tab is reached
/// by a tap or by being the page on screen.
class ForYouPageTabs extends StatelessWidget {
  const ForYouPageTabs({
    super.key,
    required this.pageController,
    required this.selectedIndex,
    required this.labels,
    required this.onSelected,
    required this.onHold,
    this.holdHint,
    this.dotScope,
  });

  final PageController pageController;
  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onHold;

  /// What assistive technology announces for holding tab `index`; null for
  /// Home's ("Make Home → Today the start screen").
  final String Function(int index)? holdHint;

  /// The Nudge surfaces' scope (`home.tab`); null for tabs that carry
  /// none.
  final String? dotScope;

  static const double _barHeight = 3;

  /// Where a tab's dot sits from its slot's centre: just right of the word
  /// as it is drawn ([word], after the label's scale-down), level with the
  /// top of its letters.
  static Offset _dotShoulder(Size word) => Offset(
    word.width / 2 + 2 + DiscoveryDotMark.size / 2,
    -word.height / 2 + 5,
  );

  /// Where the pages are, as a tab index: fractional mid-swipe.
  double _position() {
    if (pageController.hasClients) {
      final position = pageController.position;
      if (position.hasPixels &&
          position.hasViewportDimension &&
          position.viewportDimension > 0) {
        return (position.pixels / position.viewportDimension).clamp(
          0.0,
          labels.length - 1.0,
        );
      }
    }
    return selectedIndex.toDouble();
  }

  /// [label] in [style] as the tab draws it: one line, scaled down to
  /// [room] when wider.
  static Size _drawnWord(
    BuildContext context,
    String label,
    TextStyle style,
    double room,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    final scale = room > 0 && size.width > room ? room / size.width : 1.0;
    return size * scale;
  }

  /// Tab [index]'s slot, as a Nudge surface when the tabs have a [scope].
  Widget _dot(String? scope, int index, List<Size> words, Widget slot) {
    if (scope == null) return slot;
    return DiscoveryDotAnchor(
      id: discoveryDotId(scope, labels[index]),
      selected: index == selectedIndex,
      alignment: Alignment.center,
      offset: _dotShoulder(words[index]),
      child: slot,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // One line at any text size: scaled down rather than wrapped, so a long
    // label at a large text scale never breaks the row. The selected label
    // is a root title ([HomeTopBarTitle]); the others step back in weight
    // only, all in the same bright ink.
    final style = HomeTopBarTitle.style(context);
    final height = HomeTopBarMetrics.rowExtent(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: HomeTopBarMetrics.maxTextScale,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / labels.length;
            final painters = [
              for (final label in labels)
                TextPainter(
                  text: TextSpan(
                    text: label,
                    style: style.copyWith(fontWeight: FontWeight.w700),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout(),
            ];
            final widths = [
              for (final painter in painters)
                math.min(painter.width, slot - 16) + 8,
            ];
            for (final painter in painters) {
              painter.dispose();
            }
            // Each word as drawn (its own weight, scaled down to its slot),
            // for the dot on its shoulder.
            final scope = dotScope;
            final words = scope == null
                ? const <Size>[]
                : [
                    for (var i = 0; i < labels.length; i++)
                      _drawnWord(
                        context,
                        labels[i],
                        style.copyWith(
                          fontWeight: i == selectedIndex
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        slot - 8,
                      ),
                  ];
            return Stack(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == selectedIndex,
                          label: labels[i],
                          onLongPressHint:
                              holdHint?.call(i) ??
                              startScreenHint(
                                BottomNavBarItem.forYou,
                                forYouStartPage(ForYouTab.values[i]),
                              ),
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticFeedbackService.selection();
                              onSelected(i);
                            },
                            onLongPress: () => onHold(i),
                            child: _dot(
                              scope,
                              i,
                              words,
                              PressSpring(
                                pressedScale: 0.92,
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        labels[i],
                                        maxLines: 1,
                                        softWrap: false,
                                        style: style.copyWith(
                                          // Every title stays bright: the
                                          // underline alone says which page
                                          // shows (PM, 2026-11-20).
                                          color: colors.textPrimary,
                                          fontWeight: i == selectedIndex
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // The indicator: a short rounded bar under the selected
                // title, as wide as its word, moving with the pages.
                AnimatedBuilder(
                  animation: pageController,
                  builder: (context, _) {
                    final at = _position();
                    final from = at.floor().clamp(0, labels.length - 1);
                    final to = at.ceil().clamp(0, labels.length - 1);
                    final t = at - from;
                    final width =
                        widths[from] + (widths[to] - widths[from]) * t;
                    final centre = slot * (at + 0.5);
                    return Positioned(
                      left: centre - width / 2,
                      width: width,
                      bottom: 0,
                      height: _barHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.accentText,
                          borderRadius: BorderRadius.circular(_barHeight),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Title-cases the query for the Search segment and trims it at a word
/// boundary so it fits beside the three tabs: "magnus carlsen" reads
/// "Magnus…", "HIKARU" reads "Hikaru".
@visibleForTesting
String forYouSearchTabTitle(String query, {int maxLength = 12}) {
  final words = [
    for (final word in query.trim().split(RegExp(r'\s+')))
      if (word.isNotEmpty)
        word[0].toUpperCase() + word.substring(1).toLowerCase(),
  ];
  if (words.isEmpty) return 'Search';
  final full = words.join(' ');
  if (full.length <= maxLength) return full;

  final buffer = StringBuffer();
  for (final word in words) {
    final separator = buffer.isEmpty ? '' : ' ';
    if (buffer.length + separator.length + word.length > maxLength - 1) break;
    buffer
      ..write(separator)
      ..write(word);
  }
  if (buffer.isNotEmpty) return '$buffer…';
  return '${words.first.substring(0, maxLength - 1)}…';
}

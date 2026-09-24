import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_stream.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_clip.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_states.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Feed: two streams under one bar, switched by the titles at its top.
///
/// * **Feed**: finished games that replay themselves on a playable board,
///   one per page, picked by [FeedRanker] with a ChessEver News article now
///   and then ([feedEntriesProvider]).
/// * **Puzzle**: puzzles as posts on the same page geometry
///   ([PuzzleStream]).
///
/// Swipe for the next page, pull down on the first one for a fresh draw;
/// everything else happens on the board (see [FeedClip] for the gesture
/// set).
///
/// Part of the app like any other tab: it follows the app theme (light or
/// dark surfaces, status bar icons to match), wears the same top bar as the
/// other main tabs, and keeps the bottom nav. The board stays the focus.
/// Playback runs only while Feed is actually seen: the Feed tab is selected,
/// the app is in the foreground, and no route, menu or the home sidebar sits
/// on top.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

/// The Feed page the viewer was last on, by [FeedEntry.key]. Home mounts only
/// the selected tab, so [FeedScreen] is rebuilt on every return to Feed; this
/// puts the viewer back on that page rather than on the first game again.
/// Held by identity, not position: if the entries were rebuilt (a refresh)
/// and the page is gone, Feed starts from the top.
final feedCurrentEntryKeyProvider = StateProvider<String?>((ref) => null);

/// The two streams the Feed page switches between.
enum FeedTab { feed, puzzle }

/// The stream on screen; kept across returns to the Feed tab.
final feedTabProvider = StateProvider<FeedTab>((ref) => FeedTab.feed);

class _FeedScreenState extends ConsumerState<FeedScreen>
    with WidgetsBindingObserver, RouteAware {
  late final PageController _pages;
  int _index = 0;
  bool _appResumed = true;
  bool _routeCurrent = true;
  bool _scrollLocked = false;
  bool _announcedFirst = false;
  ModalRoute<void>? _route;

  /// The Puzzle tab is built the first time it is opened, then kept (paused
  /// while hidden) so switching back is instant and keeps its place.
  bool _puzzleMounted = false;

  /// Bottom-nav re-taps meant for the Puzzle tab.
  final ValueNotifier<int> _puzzleNext = ValueNotifier(0);

  /// Settles page moves on a spring rather than a stock easing curve.
  static final Curve _pageCurve = const CupertinoMotion.smooth().toCurve;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _appResumed = state == null || state == AppLifecycleState.resumed;
    _index = _restoredIndex();
    _pages = PageController(initialPage: _index);
    _puzzleMounted = ref.read(feedTabProvider) == FeedTab.puzzle;
    // Warms up when the board's Sound setting is (or turns) on; see
    // [_warmUpSoundsIfAudible].
    ref.listenManual<bool>(
      boardSettingsProviderNew.select(
        (settings) => settings.valueOrNull?.soundEnabled == true,
      ),
      (_, soundOn) {
        if (soundOn) _warmUpSoundsIfAudible();
      },
      fireImmediately: true,
    );
  }

  /// The page to open on: the one the viewer left, when it is still there.
  int _restoredIndex() {
    final key = ref.read(feedCurrentEntryKeyProvider);
    if (key == null) return 0;
    final index = ref.read(feedEntriesProvider).indexWhere((e) => e.key == key);
    return index < 0 ? 0 : index;
  }

  /// Loads the classification and swipe sounds, only for a viewer who will
  /// hear them. Warming up also makes the audio service reload those clips on
  /// every re-init (each return to the foreground), which a silent Feed must
  /// not pay for. Mirrors the board's own warm-up gate.
  void _warmUpSoundsIfAudible() {
    final soundOn =
        ref.read(boardSettingsProviderNew).valueOrNull?.soundEnabled == true;
    if (!soundOn || ref.read(feedSfxProvider).muted) return;
    unawaited(_warmUpSounds());
  }

  Future<void> _warmUpSounds() async {
    try {
      await ref.read(feedSfxProvider).warmUp();
    } catch (error) {
      // Feed plays silently rather than not at all.
      debugPrint('[Feed] sound warm-up failed: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      if (_route != null) routeObserver.unsubscribe(this);
      _route = route;
      if (route != null) routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) routeObserver.unsubscribe(this);
    _pages.dispose();
    _puzzleNext.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ visibility

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed != _appResumed && mounted) {
      setState(() => _appResumed = resumed);
    }
  }

  /// Any route on top (a pushed page, the share overlay, a dialog or the
  /// long-press menu) pauses the clip; it resumes where it was on return.
  @override
  void didPushNext() {
    if (mounted) setState(() => _routeCurrent = false);
  }

  @override
  void didPopNext() {
    if (mounted) setState(() => _routeCurrent = true);
  }

  // ---------------------------------------------------------------- paging

  void _setScrollLock(bool locked) {
    if (_scrollLocked == locked) return;
    void apply() {
      if (mounted && _scrollLocked != locked) {
        setState(() => _scrollLocked = locked);
      }
    }

    // Clips release the lock while they are being updated or disposed, which
    // happens mid-build; defer to after the frame in that case.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  void _onPageChanged(int index, List<FeedEntry> entries) {
    if (index == _index) return;
    setState(() {
      _index = index;
      _scrollLocked = false;
    });
    if (index < entries.length) {
      ref.read(feedCurrentEntryKeyProvider.notifier).state = entries[index].key;
    }
    feedSfxSafely(ref.read(feedSfxProvider).playSwipe);
    _reportVisible(index, entries);
  }

  /// Freezes the pages the viewer has reached and keeps games coming: the
  /// games notifier pages by game, so the page index is translated.
  void _reportVisible(int index, List<FeedEntry> entries) {
    ref.read(feedEntriesProvider.notifier).markSeen(index);
    final notifier = ref.read(feedProvider.notifier);
    notifier.onVisible(math.max(0, feedGameIndexAt(entries, index)));
    if (index >= entries.length - 3) unawaited(notifier.loadMore());
  }

  void _goNext() {
    if (!mounted || !_pages.hasClients) return;
    final entries = ref.read(feedEntriesProvider);
    if (_index >= entries.length - 1) {
      unawaited(ref.read(feedProvider.notifier).loadMore());
      return;
    }
    // Reduced motion: cut straight to the next game, no full-screen slide.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(_index + 1);
      return;
    }
    unawaited(
      _pages.animateToPage(
        _index + 1,
        duration: const Duration(milliseconds: 420),
        curve: _pageCurve,
      ),
    );
  }

  // ------------------------------------------------------ pull to refresh

  /// A new draw: fresh sources, a new seed, the games already seen held
  /// back. The page on screen stays until the new first page is ready; a
  /// failed refresh says so and keeps it.
  Future<void> _refreshFeed() async {
    unawaited(HapticFeedbackService.selection());
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(feedProvider.notifier)
          .refresh()
          .timeout(const Duration(seconds: 20));
    } catch (error) {
      debugPrint('[Feed] refresh failed: $error');
      if (messenger != null) {
        showAppSnackOn(
          messenger,
          "Couldn't refresh the feed",
          tone: AppSnackTone.danger,
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _index = 0;
      _scrollLocked = false;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    final entries = ref.read(feedEntriesProvider);
    ref.read(feedCurrentEntryKeyProvider.notifier).state = entries.isEmpty
        ? null
        : entries.first.key;
    _reportVisible(0, entries);
  }

  void _selectTab(FeedTab tab) {
    if (ref.read(feedTabProvider) == tab) return;
    HapticFeedbackService.toggle();
    setState(() {
      if (tab == FeedTab.puzzle) _puzzleMounted = true;
    });
    ref.read(feedTabProvider.notifier).state = tab;
  }

  /// The speaker. With the board's Sound setting off every Feed sound is
  /// silent whatever the speaker says, so the tap offers to turn that setting
  /// on instead of flipping a mute nobody would hear.
  void _toggleSound({required bool boardSoundOn}) {
    HapticFeedbackService.toggle();
    if (!boardSoundOn) {
      showAppSnack(
        context,
        _boardSoundOffHint,
        actionLabel: 'Turn on',
        onAction: _turnOnBoardSound,
      );
      return;
    }
    final sfx = ref.read(feedSfxProvider);
    setState(() => sfx.muted = !sfx.muted);
    _warmUpSoundsIfAudible();
  }

  static const String _boardSoundOffHint = 'Sound is off in board settings';

  Future<void> _turnOnBoardSound() async {
    if (!mounted) return;
    setState(() => ref.read(feedSfxProvider).muted = false);
    // The settings listener in initState warms the sounds up once it lands.
    await ref.read(boardSettingsProviderNew.notifier).toggleSound(true);
  }

  /// The avatar gives its own haptic, the same on every tab.
  void _openSidebar(BuildContext context) {
    Scaffold.maybeOf(context)?.openDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final onFeedTab = ref.watch(
      selectedBottomNavBarItemProvider.select(
        (item) => item == BottomNavBarItem.feed,
      ),
    );
    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item != BottomNavBarItem.feed) return;
      if (previous != null && previous.sequence == next.sequence) return;
      HapticFeedbackService.navigation();
      if (ref.read(feedTabProvider) == FeedTab.puzzle) {
        _puzzleNext.value++;
      } else {
        _goNext();
      }
    });

    final tab = ref.watch(feedTabProvider);
    final feed = ref.watch(feedProvider);
    final entries = ref.watch(feedEntriesProvider);
    // The sidebar is a Scaffold drawer, not a route, so RouteAware never sees
    // it; Home reports it instead.
    final sidebarOpen = ref.watch(homeDrawerOpenProvider);
    final seen = onFeedTab && _appResumed && _routeCurrent && !sidebarOpen;
    final visible = seen && tab == FeedTab.feed;

    // What the speaker shows is what the viewer will hear: the board's Sound
    // setting silences Feed too. Until the setting loads, the last value Feed
    // was told about stands in.
    final sfx = ref.read(feedSfxProvider);
    final boardSoundOn =
        ref.watch(
          boardSettingsProviderNew.select(
            (settings) => settings.valueOrNull?.soundEnabled,
          ),
        ) ??
        sfx.boardSoundEnabled;

    if (entries.isNotEmpty && !_announcedFirst) {
      _announcedFirst = true;
      final games = entries.whereType<FeedGameEntry>().length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _reportVisible(_index, ref.read(feedEntriesProvider));
        if (games <= 3) unawaited(ref.read(feedProvider.notifier).loadMore());
      });
    }

    final Widget body;
    if (entries.isNotEmpty) {
      body = RefreshIndicator(
        key: const ValueKey('feed_refresh'),
        onRefresh: _refreshFeed,
        color: context.colors.textPrimary,
        backgroundColor: context.colors.surface,
        // Tone, not a cast shadow, lifts the spinner off the page.
        elevation: 0,
        // Only the page view's own drags, and never while a clip holds the
        // pages (a piece or the scrub bar under the finger).
        notificationPredicate: (notification) =>
            notification.depth == 0 && !_scrollLocked,
        child: PageView.builder(
          key: const ValueKey('feed_pages'),
          controller: _pages,
          scrollDirection: Axis.vertical,
          // Keeps the neighbours built (current ± 1) so the next board is
          // already painted when the swipe lands.
          allowImplicitScrolling: true,
          physics: _scrollLocked ? const NeverScrollableScrollPhysics() : null,
          onPageChanged: (i) => _onPageChanged(i, entries),
          itemCount: entries.length,
          // Pages keep their state by identity, not position, so an entry that
          // is recaptioned (or a list that grows) never restarts a clip.
          findChildIndexCallback: (key) {
            if (key is! ValueKey<String>) return null;
            final index = entries.indexWhere((e) => e.key == key.value);
            return index < 0 ? null : index;
          },
          itemBuilder: (context, i) {
            final entry = entries[i];
            final isCurrent = i == _index;
            return switch (entry) {
              FeedGameEntry(:final item) => FeedClip(
                key: ValueKey(entry.key),
                item: item,
                isCurrent: isCurrent,
                isVisible: visible,
                onRequestNext: _goNext,
                onScrollLock: _setScrollLock,
              ),
              FeedPuzzleEntry(:final puzzle) => FeedPuzzlePage(
                key: ValueKey(entry.key),
                puzzle: puzzle,
                isCurrent: isCurrent,
                isVisible: visible,
                onRequestNext: _goNext,
              ),
              FeedNewsEntry(:final news) => FeedNewsPage(
                key: ValueKey(entry.key),
                news: news,
                isCurrent: isCurrent,
                isVisible: visible,
                onRequestNext: _goNext,
              ),
            };
          },
        ),
      );
    } else if (feed.hasError && !feed.isLoading) {
      body = FeedMessage(
        title: "Feed didn't load",
        body: userFacingError(
          feed.error,
          fallback: 'Something went wrong. Please try again.',
        ),
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(feedProvider),
      );
    } else if (feed.isLoading || !feed.hasValue) {
      body = const FeedSkeleton();
    } else {
      body = FeedMessage(
        title: 'Nothing to play yet',
        body: 'New games land here as they finish.',
        actionLabel: 'Refresh',
        onAction: () => ref.invalidate(feedProvider),
      );
    }

    final colors = context.colors;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.isLightTheme
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: ColoredBox(
        key: e2eKey(E2eIds.feedRoot),
        color: colors.background,
        // The top inset belongs to the home bar's frame, the same one every
        // main tab uses; only the side insets are applied here.
        child: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              // Outside the page's text cap: the home bar grows with the
              // system text size exactly as it does on the other tabs, and
              // caps its own chrome (the title included) at the same scale.
              _FeedHeader(
                soundOn: boardSoundOn && !sfx.muted,
                soundHint: boardSoundOn ? null : _boardSoundOffHint,
                onToggleSound: () => _toggleSound(boardSoundOn: boardSoundOn),
                tab: tab,
                onSelectTab: _selectTab,
                // The sidebar (and its calendar) opens from every main tab.
                // Outside the home shell there is no drawer, so no avatar
                // rather than a dead control.
                onOpenSidebar: (Scaffold.maybeOf(context)?.hasDrawer ?? false)
                    ? () => _openSidebar(context)
                    : null,
              ),
              Expanded(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: HomeTopBarMetrics.maxTextScale,
                  // Both streams stay built once opened; only the one shown
                  // plays.
                  child: IndexedStack(
                    index: tab.index,
                    sizing: StackFit.expand,
                    children: [
                      body,
                      if (_puzzleMounted)
                        PuzzleStream(
                          isVisible: seen && tab == FeedTab.puzzle,
                          nextRequests: _puzzleNext,
                        )
                      else
                        const SizedBox.shrink(),
                    ],
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

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.soundOn,
    required this.onToggleSound,
    required this.tab,
    required this.onSelectTab,
    this.soundHint,
    this.onOpenSidebar,
  });

  /// Whether Feed will actually make a sound: its own speaker is on AND the
  /// board's Sound setting is on.
  final bool soundOn;
  final VoidCallback onToggleSound;

  /// The stream on screen, and how to switch it.
  final FeedTab tab;
  final ValueChanged<FeedTab> onSelectTab;

  /// Why the speaker reads off when Feed's own mute is not the reason.
  final String? soundHint;

  /// Opens the home sidebar; null hides the avatar.
  final VoidCallback? onOpenSidebar;

  /// A 22pt glyph centred in a 44pt-wide target sits 11pt inside it; the
  /// bar's right gutter is pulled in by that much so the glyph's own edge
  /// lands on the gutter.
  static const double _glyphInset = 11;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // The home bar every main tab wears: the avatar in the same place at the
    // same size as on Events, and the titles where the other tabs' search
    // field starts. Feed owns only its two titles and the speaker.
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: HomeTopBar(
        onOpenSidebar: onOpenSidebar,
        avatarKey: const ValueKey('feed_sidebar_avatar'),
        trailingOpticalInset: _glyphInset,
        // Chrome, like the page under it: the titles stop growing where the
        // page does, while the bar itself follows the system text size.
        content: MediaQuery.withClampedTextScaling(
          maxScaleFactor: HomeTopBarMetrics.maxTextScale,
          child: _FeedTabTitles(tab: tab, onSelect: onSelectTab),
        ),
        trailing: [
          Semantics(
            toggled: soundOn,
            hint: soundHint,
            child: FeedPressable(
              key: const ValueKey('feed_sound_toggle'),
              semanticsLabel: 'Move sounds',
              onTap: onToggleSound,
              // No taller than the avatar, so the shared row keeps its
              // height and the avatar sits exactly where it does on every
              // tab. On a phone that draws it shorter than 44pt the bar's
              // tap target still takes a full 44pt (see HomeTopBarTapTarget).
              child: SizedBox(
                width: 44,
                height: HomeTopBarMetrics.controlExtent,
                child: Center(
                  child: FeedGlyph(
                    soundOn ? FeedGlyphs.soundOn : FeedGlyphs.soundOff,
                    width: 22,
                    height: 22,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Feed  Puzzle": two page titles in the bar, the one on screen in ink and
/// the other a step back in the secondary tone. The state is carried by
/// the type alone (no pill, no underline, no dot), and the tone moves on
/// a snappy spring when the pick changes.
class _FeedTabTitles extends StatelessWidget {
  const _FeedTabTitles({required this.tab, required this.onSelect});

  final FeedTab tab;
  final ValueChanged<FeedTab> onSelect;

  static const Map<FeedTab, String> _labels = {
    FeedTab.feed: 'Feed',
    FeedTab.puzzle: 'Puzzle',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final base = AppTypography.textXlBold.copyWith(
      fontSize: 22,
      height: 28 / 22,
    );

    Widget title(FeedTab value) {
      final selected = value == tab;
      final label = _labels[value]!;
      Widget text(double t) => Text(
        label,
        maxLines: 1,
        style: base.copyWith(
          color: Color.lerp(colors.textSecondary, colors.textPrimary, t),
        ),
      );
      // A full 44pt reach inside the bar, like every other control in it.
      return HomeTopBarTapTarget(
        child: FeedPressable(
          key: ValueKey('feed_tab_${value.name}'),
          semanticsLabel: label,
          selected: selected,
          inMutuallyExclusiveGroup: true,
          onTap: () => onSelect(value),
          child: SizedBox(
            height: HomeTopBarMetrics.controlExtent,
            child: Center(
              widthFactor: 1,
              child: reduceMotion
                  ? text(selected ? 1 : 0)
                  : SingleMotionBuilder(
                      value: selected ? 1.0 : 0.0,
                      motion: const CupertinoMotion.snappy(),
                      builder: (context, t, _) => text(t.clamp(0.0, 1.0)),
                    ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      header: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            title(FeedTab.feed),
            const SizedBox(width: 18),
            title(FeedTab.puzzle),
          ],
        ),
      ),
    );
  }
}

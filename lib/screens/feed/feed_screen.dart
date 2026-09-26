import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/feed_visibility.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_clip.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/screens/feed/widgets/feed_pull_refresh.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_states.dart';
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

/// Feed: finished games that replay themselves on a playable board, one per
/// page, picked by [FeedRanker], with a ChessEver News article now and then
/// ([feedEntriesProvider]).
///
/// Swipe for the next page, pull down on the first one for a fresh draw;
/// everything else happens on the board (see [FeedClip] for the gesture
/// set). The title answers a tap: back to the first post from anywhere down
/// the feed, and a fresh draw (the pull, run for you) when already there.
///
/// A page pushed from For You › Discovery: it follows the app theme (light
/// or dark surfaces, status bar icons to match) and wears the home bar's
/// geometry with a back button where the tabs keep the avatar. The board
/// stays the focus. Playback runs only while Feed is actually seen: the app
/// is in the foreground, no route or menu sits on top, and the viewer is
/// not on their way out (Back, a back swipe). Leaving stops every Feed sound
/// at once ([FeedSeen]), not when the page has finished animating away.
///
/// Every page is the whole screen: one post to a page, composed as its own
/// frame ([FeedLayout]), with nothing of the next post showing under it.
/// After the last post stands one more page ([FeedTail]): the next post's
/// skeleton while more can load, the end of the feed once nothing is left.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  /// Opens Feed over whatever is showing.
  static Future<void> open(BuildContext context) {
    HapticFeedbackService.navigation();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const FeedScreen()));
  }

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

/// The Feed page the viewer was last on, by [FeedEntry.key]. [FeedScreen] is
/// built anew on every visit; this puts the viewer back on that page rather
/// than on the first game again.
/// Held by identity, not position: if the entries were rebuilt (a refresh)
/// and the page is gone, Feed starts from the top.
final feedCurrentEntryKeyProvider = StateProvider<String?>((ref) => null);

class _FeedScreenState extends ConsumerState<FeedScreen>
    with WidgetsBindingObserver, RouteAware {
  late final PageController _pages;
  int _index = 0;

  /// The pull to refresh, so the title can run it.
  final GlobalKey<FeedPullRefreshState> _refresh =
      GlobalKey<FeedPullRefreshState>();

  /// The title is taking the viewer back to the first post: the pages it
  /// passes on the way are not visits (no swipe sound, nothing marked seen,
  /// nothing loaded for them).
  bool _homing = false;

  /// The title's ride made the first post current but was taken over by a
  /// touch before it got there: the first post is reported as reached when
  /// the page comes to rest on it (or a swipe reports another).
  bool _homeUnreported = false;
  bool _appResumed = true;
  bool _routeCurrent = true;
  bool _scrollLocked = false;
  bool _announcedFirst = false;
  ModalRoute<void>? _route;
  late final StateController<bool> _open;
  late final FeedSfx _sfx;

  /// Whether Feed is seen this instant; see [FeedSeen]. Every page that can
  /// sound listens to it, so it is written the moment Feed is left.
  final ValueNotifier<bool> _seen = ValueNotifier<bool>(true);

  /// Feed's route is being popped: it is on its way out.
  bool _leaving = false;

  /// A back swipe is under way on Feed's own route.
  bool _backSwipe = false;
  NavigatorState? _navigator;

  /// The post the feed was last found to end under (the tail said stalled
  /// or exhausted while it was the last). It counts down to no next game
  /// until a post actually lands after it: a load asked for meanwhile (Try
  /// again, or reaching it again) must not start a countdown that carries
  /// the viewer onto a skeleton and, when the load fails, back again.
  String? _endedUnder;

  /// The tail's key: its own, so it keeps its place (and never becomes a
  /// post's page) when posts arrive in front of it.
  static const ValueKey<String> _tailKey = ValueKey<String>('feed:tail');

  bool get _isSeen => _appResumed && _routeCurrent && !_leaving && !_backSwipe;

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
    // Written after the frame: a provider must not change while the tree
    // that mounts this screen is still building.
    _open = ref.read(feedScreenOpenProvider.notifier);
    _sfx = ref.read(feedSfxProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open.state = true;
    });
    // Warms up when the board's Sound setting is (or turns) on; see
    // [_warmUpSoundsIfAudible].
    ref.listenManual<List<FeedEntry>>(feedEntriesProvider, _onEntriesChanged);
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
    // A back swipe is a user gesture on the navigator: Feed holds while the
    // finger is down and plays on if the swipe is let go of.
    final navigator = Navigator.maybeOf(context);
    if (navigator != _navigator) {
      _navigator?.userGestureInProgressNotifier.removeListener(
        _onNavigatorGesture,
      );
      _navigator = navigator
        ?..userGestureInProgressNotifier.addListener(_onNavigatorGesture);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) routeObserver.unsubscribe(this);
    _navigator?.userGestureInProgressNotifier.removeListener(
      _onNavigatorGesture,
    );
    // The pages have unmounted (children first) and stopped their own
    // timers; the draw chime is the one sound that could still be waiting.
    feedSfxSafely(_sfx.hush);
    _seen.dispose();
    _pages.dispose();
    // After this frame, and only while the provider still lives: closing
    // the app disposes the provider together with this screen.
    final open = _open;
    Future.microtask(() {
      if (open.mounted) open.state = false;
    });
    super.dispose();
  }

  // ------------------------------------------------------------ visibility

  /// In the background no frame is drawn, so the pages are told at once
  /// rather than at a rebuild that would not come.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _appResumed || !mounted) return;
    _appResumed = resumed;
    _syncSeen();
    _rebuildSoon();
  }

  /// Any route on top (a pushed page, the share overlay, a dialog or the
  /// long-press menu) pauses the clip; it resumes where it was on return.
  @override
  void didPushNext() {
    _routeCurrent = false;
    _syncSeen();
    _rebuildSoon();
  }

  @override
  void didPopNext() {
    _routeCurrent = true;
    _syncSeen();
    _rebuildSoon();
  }

  /// Back (the button, the system back, a finished back swipe): Feed goes
  /// silent now, not when its page has finished animating away.
  @override
  void didPop() {
    _leaving = true;
    _syncSeen();
    _rebuildSoon();
  }

  void _onNavigatorGesture() {
    final swiping =
        (_navigator?.userGestureInProgress ?? false) &&
        (_route?.isCurrent ?? false);
    if (swiping == _backSwipe) return;
    _backSwipe = swiping;
    _syncSeen();
    _rebuildSoon();
  }

  /// Tells every page at once whether Feed is seen ([FeedSeen]); a page that
  /// stops hearing it stops its timers before they fire.
  void _syncSeen() {
    final seen = _isSeen;
    if (_seen.value == seen) return;
    _seen.value = seen;
    if (!seen) feedSfxSafely(_sfx.hush);
  }

  /// setState, or right after the frame when a route change lands mid-build.
  void _rebuildSoon() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
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
    if (_homing) return;
    if (index == _index) {
      _reportHomeIfPending(index, entries);
      return;
    }
    _homeUnreported = false;
    setState(() {
      _index = index;
      _scrollLocked = false;
    });
    // Only posts are remembered: the tail has no key of its own to return
    // to, and the last post stays the place to come back to.
    if (index < entries.length) {
      ref.read(feedCurrentEntryKeyProvider.notifier).state = entries[index].key;
    }
    if (_seen.value) feedSfxSafely(ref.read(feedSfxProvider).playSwipe);
    _reportVisible(index, entries);
  }

  /// Freezes the pages the viewer has reached and keeps games coming: the
  /// games notifier pages by game, so the page index is translated. On the
  /// tail, that is the last post's game, and the next page is asked for.
  void _reportVisible(int index, List<FeedEntry> entries) {
    ref.read(feedEntriesProvider.notifier).markSeen(index);
    final notifier = ref.read(feedProvider.notifier);
    notifier.onVisible(math.max(0, feedGameIndexAt(entries, index)));
    if (index >= entries.length - 3) unawaited(_loadMore());
  }

  /// Asks for the next page and, once the load it joined has finished,
  /// rebuilds if the tail has something new to say ([FeedMore]).
  Future<void> _loadMore() async {
    final notifier = ref.read(feedProvider.notifier);
    final load = notifier.loadMore();
    // A retry turns a stalled note back into the skeleton at once.
    if (notifier.more != _builtMore) _rebuildSoon();
    await load;
    if (!mounted) return;
    if (notifier.more != _builtMore) _rebuildSoon();
  }

  /// The [FeedMore] the tail was last built with.
  FeedMore _builtMore = FeedMore.open;

  /// A scroll came to rest: the page it rests on is the current one. Page
  /// changes are normally reported mid-swipe; this catches the one a swipe
  /// that interrupted the title's ride home could leave unreported.
  bool _onScrollEnd(ScrollEndNotification end, List<FeedEntry> entries) {
    if (end.depth != 0 || _homing || !_pages.hasClients) return false;
    final page = _pages.page;
    if (page == null) return false;
    final settled = page.round();
    if ((page - settled).abs() >= 0.01) return false;
    if (settled != _index) {
      _onPageChanged(settled, entries);
    } else {
      _reportHomeIfPending(settled, entries);
    }
    return false;
  }

  /// The first post, reached at last after the title's ride was held up
  /// ([_homeUnreported]).
  void _reportHomeIfPending(int index, List<FeedEntry> entries) {
    if (!_homeUnreported || index != 0) return;
    _homeUnreported = false;
    _reportVisible(0, entries);
  }

  /// Posts arrived while the viewer sat on the tail: the skeleton they were
  /// looking at is now a post, in place. It becomes the current page (its
  /// key remembered, the pages after it asked for) as if swiped onto.
  void _onEntriesChanged(List<FeedEntry>? previous, List<FeedEntry> next) {
    final before = previous?.length ?? 0;
    if (_index < before || _index >= next.length) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final entries = ref.read(feedEntriesProvider);
      if (_index >= entries.length) return;
      ref.read(feedCurrentEntryKeyProvider.notifier).state =
          entries[_index].key;
      _reportVisible(_index, entries);
    });
  }

  void _goNext() {
    if (!mounted || !_pages.hasClients) return;
    final entries = ref.read(feedEntriesProvider);
    // On the tail already: nothing to move on to until more arrives.
    if (_index >= entries.length) {
      unawaited(_loadMore());
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

  // ----------------------------------------------------------------- title

  /// The title: back to the first post from anywhere down the feed; on the
  /// first post already, the pull to refresh, run for the viewer (its rank
  /// shown, a real fresh draw).
  void _onTitleTap() {
    if (!mounted || !_pages.hasClients || _homing) return;
    final entries = ref.read(feedEntriesProvider);
    if (entries.isEmpty) return;
    final page = _pages.page ?? _index.toDouble();
    final onFirst = _index == 0 && page.abs() < 0.01;
    if (onFirst) {
      final pull = _refresh.currentState;
      if (pull == null || pull.isRefreshing || _scrollLocked) return;
      HapticFeedbackService.selection();
      unawaited(pull.show());
      return;
    }
    HapticFeedbackService.navigation();
    unawaited(_rideHome(entries, from: page));
  }

  /// Back to the first post on a spring. The first post is the current page
  /// from the first frame (the one being left stops at once, and nothing in
  /// between is visited); from further down than two pages the ride starts
  /// one page away, so it is always short and nothing in between is built.
  Future<void> _rideHome(
    List<FeedEntry> entries, {
    required double from,
  }) async {
    _homing = true;
    _homeUnreported = false;
    setState(() {
      _index = 0;
      _scrollLocked = false;
    });
    ref.read(feedCurrentEntryKeyProvider.notifier).state = entries.first.key;
    if (_seen.value) feedSfxSafely(ref.read(feedSfxProvider).playSwipe);
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        _pages.jumpToPage(0);
      } else {
        if (from > 2) _pages.jumpToPage(1);
        await _pages.animateToPage(
          0,
          duration: const Duration(milliseconds: 520),
          curve: _pageCurve,
        );
      }
    } finally {
      _homing = false;
    }
    if (!mounted || !_pages.hasClients) return;
    if ((_pages.page ?? 0).abs() < 0.01) {
      _reportVisible(0, ref.read(feedEntriesProvider));
    } else {
      // A touch took over on the way: the page it comes to rest on is
      // reported then, the first post included.
      _homeUnreported = true;
    }
  }

  // ------------------------------------------------------ pull to refresh

  /// A new draw: usually the notifier's ready reserve, landing in the same
  /// frame; otherwise fresh sources, the page on screen staying until the
  /// new first page is ready. A failed refresh says so and keeps it.
  Future<void> _refreshFeed() async {
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
    // The fresh page has landed: one light tap to say so.
    unawaited(HapticFeedbackService.light());
    _homeUnreported = false;
    setState(() {
      _index = 0;
      _scrollLocked = false;
      _endedUnder = null;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    final entries = ref.read(feedEntriesProvider);
    ref.read(feedCurrentEntryKeyProvider.notifier).state = entries.isEmpty
        ? null
        : entries.first.key;
    _reportVisible(0, entries);
  }

  /// The end note's action: a fresh draw, exactly what the pull does, then
  /// the first page.
  void _freshDraw() {
    HapticFeedbackService.buttonPress();
    unawaited(_refreshFeed());
  }

  void _retryMore() {
    HapticFeedbackService.buttonPress();
    unawaited(_loadMore());
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

  /// Page [i]: a post, then the tail ([FeedTail]).
  Widget _page(
    int i, {
    required List<FeedEntry> entries,
    required FeedMore more,
    required bool visible,
  }) {
    if (i >= entries.length) {
      return FeedTail(
        key: _tailKey,
        more: more,
        onFreshDraw: _freshDraw,
        onRetry: _retryMore,
      );
    }
    final entry = entries[i];
    final isCurrent = i == _index;
    return switch (entry) {
      FeedGameEntry(:final item) => FeedClip(
        key: ValueKey(entry.key),
        item: item,
        isCurrent: isCurrent,
        isVisible: visible,
        // The last post of a feed that has ended has no next
        // game to count down to, nor has one the feed was found
        // to end under, until a post lands after it.
        hasNext:
            i < entries.length - 1 ||
            (more == FeedMore.open && entry.key != _endedUnder),
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
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final entries = ref.watch(feedEntriesProvider);
    final visible = _isSeen;
    final more = ref.read(feedProvider.notifier).more;
    _builtMore = more;
    if (more != FeedMore.open && entries.isNotEmpty) {
      _endedUnder = entries.last.key;
    }

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
        if (games <= 3) unawaited(_loadMore());
      });
    }

    final Widget body;
    if (entries.isNotEmpty) {
      body = FeedPullRefresh(
        key: _refresh,
        onRefresh: _refreshFeed,
        // Never while a clip holds the pages (a piece or the scrub bar
        // under the finger).
        enabled: !_scrollLocked,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (end) => _onScrollEnd(end, entries),
          child: PageView.builder(
            key: const ValueKey('feed_pages'),
            controller: _pages,
            scrollDirection: Axis.vertical,
            // Keeps the neighbours built (current ± 1) so the next board is
            // already painted when the swipe lands.
            allowImplicitScrolling: true,
            physics: _scrollLocked
                ? const NeverScrollableScrollPhysics(parent: feedPagePhysics)
                : feedPagePhysics,
            onPageChanged: (i) => _onPageChanged(i, entries),
            // One page more than there are posts: the tail.
            itemCount: entries.length + 1,
            // Pages keep their state by identity, not position, so an entry
            // that is recaptioned (or a list that grows) never restarts a
            // clip.
            findChildIndexCallback: (key) {
              if (key == _tailKey) return entries.length;
              if (key is! ValueKey<String>) return null;
              final index = entries.indexWhere((e) => e.key == key.value);
              return index < 0 ? null : index;
            },
            itemBuilder: (context, i) =>
                _page(i, entries: entries, more: more, visible: visible),
          ),
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
      child: Scaffold(
        key: e2eKey(E2eIds.feedRoot),
        backgroundColor: colors.background,
        resizeToAvoidBottomInset: false,
        // The top inset belongs to the home bar's frame, the same one every
        // main tab uses. With no bottom nav under it, the page clears the
        // home indicator itself.
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              // Outside the page's text cap: the home bar grows with the
              // system text size exactly as it does on the other tabs, and
              // caps its own chrome (the title included) at the same scale.
              _FeedHeader(
                soundOn: boardSoundOn && !sfx.muted,
                soundHint: boardSoundOn ? null : _boardSoundOffHint,
                onToggleSound: () => _toggleSound(boardSoundOn: boardSoundOn),
                onTitleTap: _onTitleTap,
              ),
              Expanded(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: HomeTopBarMetrics.maxTextScale,
                  child: FeedSeen(seen: _seen, child: body),
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
    required this.onTitleTap,
    this.soundHint,
  });

  /// Whether Feed will actually make a sound: its own speaker is on AND the
  /// board's Sound setting is on.
  final bool soundOn;
  final VoidCallback onToggleSound;

  /// Back to the first post, or a fresh draw when already there.
  final VoidCallback onTitleTap;

  /// Why the speaker reads off when Feed's own mute is not the reason.
  final String? soundHint;

  /// A 22pt glyph centred in a 44pt-wide target sits 11pt inside it; the
  /// bar's right gutter is pulled in by that much so the glyph's own edge
  /// lands on the gutter.
  static const double _glyphInset = 11;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // The home bar's frame and row, so the title and the speaker sit exactly
    // where they did as a tab; the back button takes the avatar's place.
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: HomeTopBarFrame(
        trailingOpticalInset: _glyphInset,
        child: HomeTopBarRow(
          showAvatar: false,
          leading: const HomeTopBarBackButton(key: ValueKey('feed_back')),
          content: MediaQuery.withClampedTextScaling(
            maxScaleFactor: HomeTopBarMetrics.maxTextScale,
            child: _FeedTitle(onTap: onTitleTap),
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
                // height. On a phone that draws it shorter than 44pt the
                // bar's tap target still takes a full 44pt (see
                // HomeTopBarTapTarget).
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
      ),
    );
  }
}

/// The page title, set as the tabs set theirs. A tap takes the viewer back
/// to the first post, or refreshes when they are already on it, as a tap
/// on an app's status bar does: so it is a button as wide as its word and
/// the full height of the bar, which gives a little under the finger.
class _FeedTitle extends StatelessWidget {
  const _FeedTitle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        header: true,
        // Drawn no taller than the avatar, so the shared row keeps its
        // height; the bar's tap target still answers across a full 44pt.
        child: HomeTopBarTapTarget(
          child: FeedPressable(
            key: const ValueKey('feed_title'),
            semanticsLabel: 'Feed',
            semanticsHint: 'Back to the first post, or refresh',
            onTap: onTap,
            child: SizedBox(
              height: HomeTopBarMetrics.controlExtent,
              child: Center(
                widthFactor: 1,
                child: Text(
                  'Feed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textXlBold.copyWith(
                    fontSize: 22,
                    height: 28 / 22,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

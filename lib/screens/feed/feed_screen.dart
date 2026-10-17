import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/feed_visibility.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_ad_page.dart';
import 'package:chessever2/screens/feed/widgets/feed_clip.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/screens/feed/widgets/feed_pull_refresh.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_states.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/destination_title.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Feed: finished games that replay themselves on a playable board, one per
/// page, picked by [FeedRanker], with a ChessEver News article now and then
/// ([feedEntriesProvider]) and, for viewers who see ads, an ad between posts
/// ([feedPagesProvider]).
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
///
/// Feed is open to everyone. A viewer without a paid subscription gets an ad page
/// at positions 3, 8, 13… ([feedPagesProvider], [FeedAdPage]) and swipes past
/// it like any post: no prompt ever stands between them and the next one.
///
/// Watch ([watch], the board's menu) opens Feed on a game of the viewer's
/// choosing: [lead] is the first post and the feed carries on after it as it
/// is, without its own copy of that game. A refresh is a fresh draw, without
/// the lead.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key, this.lead});

  /// The game Watch opened Feed on, above the feed's own posts.
  final FeedItem? lead;

  /// Opens Feed over whatever is showing.
  static Future<void> open(BuildContext context) {
    HapticFeedbackService.navigation();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const FeedScreen()));
  }

  /// Opens Feed on [lead]: its first post, then the feed.
  static Future<void> watch(BuildContext context, FeedItem lead) {
    HapticFeedbackService.navigation();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => FeedScreen(lead: lead)));
  }

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

/// The Feed page the viewer was last on, by [FeedEntry.key]. [FeedScreen] is
/// built anew on every visit; this puts the viewer back on that page rather
/// than on the first game again.
/// Held by identity, not position: if the entries were rebuilt (a refresh)
/// and the page is gone, Feed starts from the top. Only posts are held: an
/// ad page is never the place to come back to.
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
  late final FeedScreenCount _screens;
  late final FeedClipResumeStore _resume;

  /// This screen is in [_screens]' count (from its first frame).
  bool _counted = false;
  late final FeedSfx _sfx;

  /// The page of the post Watch opened Feed on ([FeedScreen.lead]), until a
  /// refresh draws a new first page. Told apart from Feed's own pages by
  /// identity: its [FeedEntry.key] is the one Feed's copy of that game has.
  FeedGameEntry? _lead;

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
    final lead = widget.lead;
    if (lead != null) {
      _lead = FeedGameEntry(lead);
      _watched = lead;
    }
    _index = _restoredIndex();
    _pages = PageController(initialPage: _index);
    // Written after the frame: a provider must not change while the tree
    // that mounts this screen is still building.
    _open = ref.read(feedScreenOpenProvider.notifier);
    _screens = ref.read(feedScreenCountProvider);
    _resume = ref.read(feedClipResumeProvider);
    _sfx = ref.read(feedSfxProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _counted = true;
      _screens.value++;
      _open.state = true;
    });
    // Warms up when the board's Sound setting is (or turns) on; see
    // [_warmUpSoundsIfAudible].
    ref.listenManual<List<FeedEntry>>(feedPagesProvider, _onPagesChanged);
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
  /// Watch always opens on its lead.
  int _restoredIndex() {
    if (_lead != null) return 0;
    final key = ref.read(feedCurrentEntryKeyProvider);
    if (key == null) return 0;
    final index = ref.read(feedPagesProvider).indexWhere((e) => e.key == key);
    return index < 0 ? 0 : index;
  }

  /// Feed's pages as this screen shows them: the lead first, then the feed
  /// without its own copy of that game. Without a lead, Feed's own.
  List<FeedEntry> _pagesOf(List<FeedEntry> feed) {
    final lead = _lead;
    if (lead == null) return feed;
    final pages = <FeedEntry>[
      lead,
      for (final page in feed)
        if (page is! FeedGameEntry || !_isWatchedGame(page.item)) page,
    ];
    // An ad stands only between two posts ([withFeedAds]); one left last by
    // the hidden copy waits for the post that comes after it.
    if (pages.last is FeedAdEntry) pages.removeLast();
    return List.unmodifiable(pages);
  }

  List<FeedEntry> _currentPages() => _pagesOf(ref.read(feedPagesProvider));

  /// The game Watch opened on, kept after a refresh drops its page: Feed's
  /// own copy of it is the game the board under this screen holds.
  FeedItem? _watched;

  /// Whether [item] is Feed's copy of the game Watch opened on: the same id,
  /// or the same moves (an archive copy of a broadcast game has its own id).
  bool _isWatchedGame(FeedItem item) {
    final watched = _watched;
    if (watched == null) return false;
    if (item.game.gameId == watched.game.gameId ||
        item.game.likeId == watched.game.likeId) {
      return true;
    }
    if (item.plies.length != watched.plies.length ||
        _movesOf(item) != _movesOf(watched)) {
      return false;
    }
    // The same moves by other players is another game.
    final white = item.game.whitePlayer.fideId;
    final watchedWhite = watched.game.whitePlayer.fideId;
    return white == null || watchedWhite == null || white == watchedWhite;
  }

  static final Expando<String> _moves = Expando<String>('feedMoves');

  /// [item]'s moves as one string, worked out once per item.
  static String _movesOf(FeedItem item) =>
      _moves[item] ??= [for (final ply in item.plies) ply.uci ?? ''].join(' ');

  /// The key a page is built under. The lead's is its own: after a refresh
  /// Feed's copy of the game may stand where the lead stood, and it must be
  /// a new page with its own clip, not the lead's carried over.
  String _pageKeyOf(FeedEntry page) =>
      identical(page, _lead) ? 'watch:${page.key}' : page.key;

  /// Page [index] of [pages] as a page of Feed's own [feed], found by key:
  /// -1 for the lead (above Feed's first page), past the last page for the
  /// tail, null for a page Feed no longer has.
  int? _feedIndexOf(int index, List<FeedEntry> pages, List<FeedEntry> feed) {
    if (index >= pages.length) return feed.length + index - pages.length;
    final page = pages[index];
    if (identical(page, _lead)) return -1;
    final found = feed.indexWhere((other) => other.key == page.key);
    return found < 0 ? null : found;
  }

  /// The game of Feed's own the viewer has last reached at page [index] of
  /// [pages], as an index into [feed]'s games: the nearest game at or before
  /// it on screen. -1 when that is the lead, or there is none. Feed's own
  /// copy of the lead's game is not on screen, so it is never the one.
  int _visitIndexOf(int index, List<FeedEntry> pages, List<FeedEntry> feed) {
    for (var i = math.min(index, pages.length - 1); i >= 0; i--) {
      final page = pages[i];
      if (page is! FeedGameEntry) continue;
      if (identical(page, _lead)) return -1;
      final found = feed.indexWhere((other) => other.key == page.key);
      return found < 0 ? -1 : feedGameIndexAt(feed, found);
    }
    return -1;
  }

  /// Feed's state as far as the lead's screen goes: ready once its first
  /// page has loaded and no load is running.
  bool _feedReady(AsyncValue<List<FeedItem>> feed) =>
      feed.hasValue && !feed.isLoading;

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
    // the app disposes the provider together with this screen. A Feed still
    // on the stack under this one keeps it open.
    final open = _open;
    final screens = _screens;
    if (_counted) screens.value--;
    // A Feed still on the stack under this one (Watch, closed) keeps its own
    // clip mounted: the playback this one's clips just saved (children
    // dispose first) is no place it returns to, and must not resurface on
    // the next post it builds as current.
    if (screens.value > 0) _resume.clear();
    Future.microtask(() {
      if (open.mounted && screens.value <= 0) open.state = false;
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
    _reclaim();
  }

  /// Back on top. When what was on top held another Feed (Watch, from a
  /// board opened here), that Feed moved the visit to its own pages and may
  /// have drawn a new arrangement under this one: the page here is the
  /// viewer's again, remembered and visited.
  void _reclaim() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_routeCurrent || _homing) return;
      final pages = _currentPages();
      if (pages.isEmpty) return;
      _remember(_index, pages);
      _reportVisible(_index, pages);
    });
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

  void _onPageChanged(int index, List<FeedEntry> pages) {
    if (_homing) return;
    if (index == _index) {
      _reportHomeIfPending(index, pages);
      return;
    }
    _homeUnreported = false;
    setState(() {
      _index = index;
      _scrollLocked = false;
    });
    _remember(index, pages);
    if (_seen.value) feedSfxSafely(ref.read(feedSfxProvider).playSwipe);
    _reportVisible(index, pages);
  }

  /// Only posts are remembered: the tail has no key of its own to return to
  /// (the last post stays the place to come back to), and an ad page is no
  /// place to return to (the post it follows stands for it). Nor is Watch's
  /// lead, which is not in the feed: Feed keeps the place the viewer had.
  void _remember(int index, List<FeedEntry> pages) {
    if (index >= pages.length) return;
    var page = pages[index];
    if (page is FeedAdEntry && _lead != null && index > 0) {
      // Under a lead the post an ad follows on screen may not be the one it
      // follows in Feed (that one may be the lead's hidden copy): the post
      // before it here stands for it.
      page = pages[index - 1];
    }
    if (identical(page, _lead)) return;
    ref.read(feedCurrentEntryKeyProvider.notifier).state = page is FeedAdEntry
        ? page.after
        : page.key;
  }

  /// Freezes the pages the viewer has reached and keeps games coming: the
  /// arrangement freezes by post and the games notifier pages by game, so
  /// the page index is translated for each. On the tail, that is the last
  /// post's game, and the next page is asked for.
  ///
  /// Under a lead the pages are not Feed's own: the page is found among
  /// Feed's by key ([_feedIndexOf]) to hold its place, and the game reached
  /// is the nearest one on screen ([_visitIndexOf]). The lead is the page
  /// above Feed's first: the page after it holds its place, and no visit is
  /// counted for it.
  void _reportVisible(int index, List<FeedEntry> pages) {
    final notifier = ref.read(feedProvider.notifier);
    final entries = ref.read(feedEntriesProvider.notifier);
    if (_lead == null) {
      entries.markSeen(feedPostIndexAt(pages, index));
      notifier.onVisible(math.max(0, feedGameIndexAt(pages, index)));
    } else {
      final feed = ref.read(feedPagesProvider);
      final at = _feedIndexOf(index, pages, feed);
      if (at != null) {
        // The page after this one here (built, and seen mid-swipe) holds its
        // place too, though Feed's hidden copy of the lead may stand between
        // them in Feed's own order.
        final after = index + 1 < pages.length
            ? _feedIndexOf(index + 1, pages, feed)
            : null;
        entries.markSeen(
          math.max(
            feedPostIndexAt(feed, at),
            after == null || after < 0 ? -1 : feedPostIndexAt(feed, after) - 1,
          ),
        );
        notifier.onVisible(_visitIndexOf(index, pages, feed));
      }
    }
    if (index >= pages.length - 3) unawaited(_loadMore());
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

  /// The pages changed under the viewer. The page they are on stays theirs:
  ///
  /// * Posts arrived while they sat on the tail: the skeleton they were
  ///   looking at is now a page, in place, and becomes the current one (its
  ///   key remembered, the pages after it asked for) as if swiped onto.
  /// * An ad page joined or left before them (a subscription began or
  ///   ended, an ad found no fill): Feed moves with their page, so it
  ///   neither slides away nor is visited anew.
  /// * The ad page they were on was withdrawn: the post after it takes its
  ///   place, as the current page.
  ///
  /// A post that left is a new arrangement (a refresh): the viewer starts it
  /// at its first page. A refresh run here lands there anyway; one run by a
  /// Feed stacked over this one (Watch) would otherwise leave this one on
  /// whatever now stands where the viewer was. A page that is not seen
  /// (another route on top) is visited on the return ([_reclaim]).
  ///
  /// Under a lead, both lists are taken as this screen shows them.
  void _onPagesChanged(List<FeedEntry>? previous, List<FeedEntry> feed) {
    if (_homing) return;
    final before = _pagesOf(previous ?? const <FeedEntry>[]);
    final next = _pagesOf(feed);
    // Under a lead, a load that brought only Feed's copy of the lead's game
    // adds nothing here: a viewer on the tail would wait on a skeleton no
    // load is coming for. The next page is asked for.
    if (_lead != null &&
        _index >= before.length &&
        next.length == before.length &&
        feed.length > (previous?.length ?? 0)) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadMore());
      });
    }
    int? target;
    if (_index >= before.length) {
      if (_index < next.length) target = _index;
    } else {
      var postLeft = false;
      for (var i = _index; i < before.length; i++) {
        final found = next.indexWhere((page) => page.key == before[i].key);
        if (found >= 0) {
          target = found;
          break;
        }
        if (before[i] is! FeedAdEntry) {
          postLeft = true;
          break;
        }
      }
      if (target == null && postLeft && next.isNotEmpty) target = 0;
    }
    if (target == null) return;
    final index = target;
    final was = _index < before.length ? before[_index].key : null;
    final arrived = next[index].key != was;
    if (index != _index) _settleOn(index);
    if (!arrived) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _index != index || !_routeCurrent) return;
      final pages = _currentPages();
      if (index >= pages.length) return;
      _remember(index, pages);
      _reportVisible(index, pages);
    });
  }

  /// Puts the viewer on page [index] at once, without the page change
  /// counting as a visit (it is the same page, moved).
  void _settleOn(int index) {
    void apply() {
      if (!mounted || !_pages.hasClients) return;
      setState(() {
        _index = index;
        _scrollLocked = false;
      });
      _pages.jumpToPage(index);
    }

    _index = index;
    // A jump during build would report a page change mid-build.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  void _goNext() {
    if (!mounted || !_pages.hasClients) return;
    final entries = _currentPages();
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
    final entries = _currentPages();
    if (entries.isEmpty) return;
    final page = _pages.page ?? _index.toDouble();
    final onFirst = _index == 0 && page.abs() < 0.01;
    if (onFirst) {
      final pull = _refresh.currentState;
      if (pull == null || pull.isRefreshing || _scrollLocked) return;
      // On Watch's lead, Feed's own first page has to be in first.
      if (_lead != null && !_feedReady(ref.read(feedProvider))) return;
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
    _remember(0, entries);
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
      _reportVisible(0, _currentPages());
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
      // A fresh draw: Watch's lead gives way to it.
      _lead = null;
      _index = 0;
      _scrollLocked = false;
      _endedUnder = null;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    final entries = ref.read(feedPagesProvider);
    ref.read(feedCurrentEntryKeyProvider.notifier).state = entries.isEmpty
        ? null
        : entries.first.key;
    _reportVisible(0, entries);
  }

  /// Analyze on Watch's lead: back to the board Watch was opened from,
  /// which holds that game with the viewer's own analysis, rather than a
  /// second board for it on top of the first.
  void _backToBoard() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    unawaited(Navigator.of(context).maybePop());
  }

  /// The end note's action: a fresh draw, exactly what the pull does, then
  /// the first page.
  void _freshDraw() {
    HapticFeedbackService.buttonPress();
    unawaited(_refreshFeed());
  }

  void _retryMore() {
    HapticFeedbackService.buttonPress();
    // Under Watch's lead the tail stands for a first page that did not
    // load: that load runs again.
    final feed = ref.read(feedProvider);
    if (_lead != null &&
        ref.read(feedPagesProvider).isEmpty &&
        feed.hasError &&
        !feed.isLoading) {
      ref.invalidate(feedProvider);
      return;
    }
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

  /// Page [i]: a post or an ad, then the tail ([FeedTail]).
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
        key: ValueKey(_pageKeyOf(entry)),
        item: item,
        isCurrent: isCurrent,
        isVisible: visible,
        // The last post of a feed that has ended has no next
        // game to count down to, nor has one the feed was found
        // to end under, until a post lands after it.
        hasNext:
            i < entries.length - 1 ||
            (more == FeedMore.open && _pageKeyOf(entry) != _endedUnder),
        onRequestNext: _goNext,
        onScrollLock: _setScrollLock,
        // The lead is not a place in Feed: it neither takes nor leaves the
        // playback Feed keeps for its return.
        keepsPlace: !identical(entry, _lead),
        // The board under Watch holds this game: Analyze goes back to it,
        // from the lead and, after a refresh, from Feed's own copy.
        onOpenGame: identical(entry, _lead) || _isWatchedGame(item)
            ? _backToBoard
            : null,
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
      FeedAdEntry() => FeedAdPage(key: ValueKey(entry.key), entry: entry),
    };
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final feedPages = ref.watch(feedPagesProvider);
    final entries = _pagesOf(feedPages);
    final visible = _isSeen;
    var more = ref.read(feedProvider.notifier).more;
    // Under Watch's lead there is always a page, so the tail stands in for
    // Feed's own first-page states: its skeleton while the first page loads,
    // a retry when it failed.
    if (_lead != null && feedPages.isEmpty) {
      if (feed.isLoading || !feed.hasValue) {
        more = feed.hasError && !feed.isLoading
            ? FeedMore.stalled
            : FeedMore.open;
      }
    }
    _builtMore = more;
    if (more != FeedMore.open && entries.isNotEmpty) {
      _endedUnder = _pageKeyOf(entries.last);
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

    // Feed's first page is in. Under Watch's lead there is a page before
    // that, so it is the load that is waited for, empty or not.
    final firstPageIn = _lead == null ? entries.isNotEmpty : _feedReady(feed);
    if (firstPageIn && !_announcedFirst) {
      _announcedFirst = true;
      final games = entries.whereType<FeedGameEntry>().length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _reportVisible(_index, _currentPages());
        if (games <= 3) unawaited(_loadMore());
      });
    }

    final Widget body;
    if (entries.isNotEmpty) {
      body = FeedPullRefresh(
        key: _refresh,
        onRefresh: _refreshFeed,
        // Never while a clip holds the pages (a piece or the scrub bar
        // under the finger), nor on Watch's lead before Feed's own first
        // page is in: a fresh draw needs the draw it replaces.
        enabled: !_scrollLocked && (_lead == null || _feedReady(feed)),
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
            // One page more than there are posts and ads: the tail.
            itemCount: entries.length + 1,
            // Pages keep their state by identity, not position, so an entry
            // that is recaptioned (or a list that grows) never restarts a
            // clip.
            findChildIndexCallback: (key) {
              if (key == _tailKey) return entries.length;
              if (key is! ValueKey<String>) return null;
              final index = entries.indexWhere(
                (e) => _pageKeyOf(e) == key.value,
              );
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Keep the home bar's vertical geometry, with the title centered between
    // equal side gutters independently of the back and sound controls.
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: HomeTopBarFrame(
        child: Stack(
          alignment: Alignment.center,
          children: [
            HomeTopBarRow(
              showAvatar: false,
              leading: const HomeTopBarBackButton(key: ValueKey('feed_back')),
              content: MediaQuery.withClampedTextScaling(
                maxScaleFactor: HomeTopBarMetrics.maxTextScale,
                child: const SizedBox.shrink(),
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
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 56.w),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: HomeTopBarMetrics.maxTextScale,
                child: _FeedTitle(onTap: onTitleTap),
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
      alignment: Alignment.center,
      heightFactor: 1,
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
                child: const DestinationTitle(
                  title: 'Feed',
                  icon: Icon(Icons.smart_display_rounded),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

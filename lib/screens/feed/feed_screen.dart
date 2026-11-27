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
import 'package:chessever2/screens/feed/widgets/feed_ad_page.dart';
import 'package:chessever2/screens/feed/widgets/feed_bars_on_tap.dart';
import 'package:chessever2/screens/feed/widgets/feed_centred_between_bars.dart';
import 'package:chessever2/screens/feed/widgets/feed_clip.dart';
import 'package:chessever2/screens/feed/widgets/feed_collection_page.dart';
import 'package:chessever2/screens/feed/widgets/feed_deck.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/screens/feed/widgets/feed_page_viewport.dart';
import 'package:chessever2/screens/feed/widgets/feed_pull_refresh.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_short_page.dart';
import 'package:chessever2/screens/feed/widgets/feed_states.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/home/widget/home_nav_dock.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart'
    show PageBackButton;
import 'package:chessever2/widgets/scroll_chrome.dart';
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
/// set). Paging is silent: no sound marks a page turn. As the Feed tab,
/// re-tapping the tab takes the viewer back to the first post with the bars
/// in view, as every root's re-tap takes its page back to the top, but never
/// draws afresh.
///
/// As the Feed tab it has no top bar of its own: no title and no controls,
/// so each post starts right under the status bar's strip, its own header
/// line first, and uses the height a bar would have taken. The dock leaves
/// as the reader pages on and comes back the moment they page back
/// ([ScrollChromeRegion.paged]), when a post is tapped ([FeedBarsOnTap]),
/// and when the reader returns from a page opened here. Each page is the
/// whole screen with one framed post laid out clear of the bars as they
/// stand when shown, keeping [FeedLayout.footGap] over the dock, so a post
/// never changes size and is never under a bar at rest. As the dock moves, the post is moved, never laid out
/// again, so it stays centred in the room it leaves, on the bars' own
/// spring value ([FeedCentredBetweenBars]).
///
/// Under the pages one still deck ([FeedBottomDeck]) rises from the board
/// block's foot to the screen's edge, under the dock: the posts page over
/// it, and each post's chart is drawn straight on it.
///
/// A page pushed from For You › Discovery: it follows the app theme (light
/// or dark surfaces, status bar icons to match) and wears the home bar's
/// geometry holding only a back button where the tabs keep the avatar. The
/// board stays the focus. Playback runs only while Feed is actually seen: the app
/// is in the foreground, no route or menu sits on top, and the viewer is
/// not on their way out (Back, a back swipe). Leaving stops every Feed sound
/// at once ([FeedSeen]), not when the page has finished animating away.
///
/// Every page is the whole screen: one post to a page, composed as its own
/// frame ([FeedLayout]), with nothing of the next post showing under it.
/// After the last post stands one more page ([FeedTail]): the next post's
/// skeleton while more can load, the end of the feed once nothing is left.
///
/// Viewers without a paid subscription swipe past [FeedAdPage] like any
/// post. Slot placement comes from [feedPagesProvider].
///
/// Watch ([watch], the board's menu) opens Feed on a game of the viewer's
/// choosing: [lead] is the first post and the feed carries on after it as it
/// is, without its own copy of that game. A refresh is a fresh draw, without
/// the lead.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key, this.lead, this.embedded = false});

  /// The game Watch opened Feed on, above the feed's own posts.
  final FeedItem? lead;

  /// Feed as the home bar's Feed tab: no back chevron (there is nothing to
  /// go back to), and the bar under it clears the home indicator.
  final bool embedded;

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

  /// A re-tap of the Feed tab is taking the viewer back to the first post:
  /// the pages it passes on the way are not visits (nothing marked seen,
  /// nothing loaded for them).
  bool _homing = false;

  /// The ride home made the first post current but was taken over by a
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
    // The Feed tab re-tapped in the bottom bar does what every root's
    // re-tap does: back to the top (the first post), bars in view. Never a
    // fresh draw: one stray re-tap must not replace the post being watched
    // (the bar's contract, see selectBottomNavBarItem).
    ref.listenManual<BottomNavBarReTapRequest>(
      bottomNavBarReTapRequestProvider,
      (previous, next) {
        if (!widget.embedded || next.item != BottomNavBarItem.feed) return;
        if (previous != null && previous.sequence == next.sequence) return;
        _onNavReTap();
      },
    );
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

  /// Loads the classification sounds, only for a viewer who will hear
  /// them. Warming up also makes the audio service reload those clips on
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
    // Back from a page opened here (Analyze, the news reader): the bars are
    // in view, so the way on to another tab is too.
    ScrollChromeScope.maybeOf(context)?.show();
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
    // No sound for a page turn: the move sounds of the post landed on are
    // Feed's only voice. What the last post still had waiting is dropped.
    feedSfxSafely(_sfx.pageTurned);
    _remember(index, pages);
    _reportVisible(index, pages);
  }

  /// Only posts are remembered: the tail has no key of its own to return to
  /// (the last post stays the place to come back to), and an ad page is no
  /// place to return to (the post it follows stands for it). Nor is Watch's
  /// lead, which is not in the feed: Feed keeps the place the viewer had.
  void _remember(int index, List<FeedEntry> pages) {
    if (index >= pages.length) return;
    var page = pages[index];
    // Restore to the preceding post even if the ad is withdrawn or the
    // same feed is opened with ads disabled.
    if (page is FeedAdEntry && index > 0) page = pages[index - 1];
    if (identical(page, _lead)) return;
    ref.read(feedCurrentEntryKeyProvider.notifier).state = page.key;
  }

  /// Record the visible card and prefetch as the viewer approaches the tail.
  void _reportVisible(int index, List<FeedEntry> pages) {
    final notifier = ref.read(feedProvider.notifier);
    final entry = index >= 0 && index < pages.length ? pages[index] : null;
    if (entry case FeedNewsEntry(:final news)) {
      notifier.noteNewsVisible(news.id);
    } else if (entry case FeedShortEntry(:final short)) {
      notifier.noteShortVisible(short.id);
    }
    if (entry is! FeedGameEntry || identical(entry, _lead)) {
      notifier.onVisible(-1);
    } else if (_lead == null) {
      notifier.onVisible(feedGameIndexAt(pages, index));
    } else {
      notifier.onVisible(
        _visitIndexOf(index, pages, ref.read(feedPagesProvider)),
      );
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
  /// that interrupted the ride home could leave unreported.
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

  /// The first post, reached at last after the ride home was held up
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

  // -------------------------------------------------------------- re-tap

  /// The Feed tab re-tapped in the bottom bar: the bars come back and, from
  /// further down, the first post with them. On the first post already
  /// there is nothing more to do; the refresh stays the pull's. The bar
  /// already gave the tap its haptic.
  void _onNavReTap() {
    if (!mounted) return;
    ScrollChromeScope.maybeOf(context)?.show();
    if (!_pages.hasClients || _homing) return;
    final entries = _currentPages();
    if (entries.isEmpty) return;
    final page = _pages.page ?? _index.toDouble();
    if (_index == 0 && page.abs() < 0.01) return;
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
    feedSfxSafely(_sfx.pageTurned);
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
        onRead: () => ref.read(feedProvider.notifier).noteNewsOpened(news.id),
        isCurrent: isCurrent,
        isVisible: visible,
        onRequestNext: _goNext,
      ),
      FeedCollectionEntry(:final card) => FeedCollectionPage(
        key: ValueKey(entry.key),
        card: card,
        active: isCurrent && visible,
        onGameVisible: (gameId) => ref
            .read(feedProvider.notifier)
            .noteCollectionGameVisible(card, gameId),
        onGameOpened: (gameId) => ref
            .read(feedProvider.notifier)
            .noteCollectionGameOpened(card, gameId),
      ),
      FeedShortEntry(:final short) => FeedShortPage(
        key: ValueKey(entry.key),
        short: short,
        active: isCurrent && visible,
        preload: visible && i == _index + 1,
        onOpened: () =>
            ref.read(feedProvider.notifier).noteShortOpened(short.id),
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

    // In the home shell Feed has no top bar: the pages run under the status
    // bar's strip and the dock, every page the whole screen, laid out clear
    // of the strip and the dock as it stands when shown, so nothing of a
    // post is ever under them at rest, and moved to the middle of what they
    // leave as the dock goes. Pages flow edge to edge as they turn.
    // Elsewhere (Feed pushed over another page) the bar with its back
    // button stands above the pages, as on any page.
    final chrome = ScrollChromeScope.maybeOf(context);
    final dock = HomeNavScope.maybeOf(context);
    final EdgeInsets clear = chrome == null
        ? EdgeInsets.zero
        : EdgeInsets.only(
            top: MediaQuery.viewPaddingOf(context).top,
            // The shell's dock keeps one slot in the layout and the page
            // runs under it: the post is laid out clear of the dock as it
            // stands shown, its capsule's top at the slot's top, whatever
            // the dock is doing now (the post keeps [FeedLayout.footGap]
            // over it). Read from the dock's own metrics so a dock moving
            // away never lays the page out again.
            bottom: math.max(
              dock?.extent ?? 0,
              MediaQuery.paddingOf(context).bottom,
            ),
          );
    // The system's own insets, read from the window: the shell spends the
    // home indicator's on its dock before the page sees it.
    final system = chrome == null
        ? EdgeInsets.zero
        : MediaQueryData.fromView(View.of(context)).viewPadding;
    final centring = FeedCentredBetweenBars.travelFor(
      shown: clear,
      away: EdgeInsets.only(
        // The status bar's strip is all there is at the top, bars shown or
        // not. Reading on, the dock leaves whole: only the system's own
        // strip (the home indicator, the gesture bar, the three buttons)
        // still covers the foot, as with no dock (a tablet's rail).
        top: math.min(system.top, clear.top),
        bottom: math.min(dock?.awayExtent ?? system.bottom, clear.bottom),
      ),
    );
    Widget clearOfBars(Widget page) {
      if (chrome == null) return page;
      // Keyed as the page it holds: the pager finds a page by its key.
      return KeyedSubtree(
        key: page.key,
        child: Padding(
          padding: clear,
          child: FeedCentredBetweenBars(
            chrome: chrome,
            travel: centring,
            child: page,
          ),
        ),
      );
    }

    final Widget body;
    if (entries.isNotEmpty) {
      body = FeedPullRefresh(
        onRefresh: _refreshFeed,
        // Never while a clip holds the pages (a piece or the scrub bar
        // under the finger), nor on Watch's lead before Feed's own first
        // page is in: a fresh draw needs the draw it replaces.
        enabled: !_scrollLocked && (_lead == null || _feedReady(feed)),
        // The pull opens a gap under the status bar's strip.
        indicatorInset: clear.top,
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
            itemBuilder: (context, i) => clearOfBars(
              _page(i, entries: entries, more: more, visible: visible),
            ),
          ),
        ),
      );
    } else if (feed.error is BoardFeedSignInRequired && !feed.isLoading) {
      body = clearOfBars(
        FeedMessage(
          title: 'Sign in to open Feed',
          body: 'See boards, news, Shorts, and collections.',
          actionLabel: 'Sign in',
          onAction: () async {
            final signedIn = await showAuthUpgradeSheet(context: context);
            if (mounted && signedIn) ref.invalidate(feedProvider);
          },
        ),
      );
    } else if (feed.hasError && !feed.isLoading) {
      body = clearOfBars(
        FeedMessage(
          title: "Feed didn't load",
          body: userFacingError(
            feed.error,
            fallback: 'Something went wrong. Please try again.',
          ),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(feedProvider),
        ),
      );
    } else if (feed.isLoading || !feed.hasValue) {
      body = clearOfBars(const FeedSkeleton());
    } else {
      body = clearOfBars(
        FeedMessage(
          title: 'Nothing to play yet',
          body: 'New games land here as they finish.',
          actionLabel: 'Refresh',
          onAction: () => ref.invalidate(feedProvider),
        ),
      );
    }

    final colors = context.colors;
    final pages = MediaQuery.withClampedTextScaling(
      maxScaleFactor: HomeTopBarMetrics.maxTextScale,
      child: FeedSeen(
        seen: _seen,
        child: _FeedDeckUnder(
          clear: clear,
          chrome: chrome,
          travel: centring,
          // Below the screen's edge by as far as the post rises, so its foot
          // never shows above the edge as the bars leave.
          overhang: math.max(0, -centring),
          child: FeedBarsOnTap(chrome: chrome, child: body),
        ),
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.isLightTheme
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        key: e2eKey(E2eIds.feedRoot),
        backgroundColor: colors.background,
        resizeToAvoidBottomInset: false,
        body: chrome == null
            // The top inset belongs to the home bar's frame, the same one
            // every pushed page uses, holding the back button. With no
            // bottom nav under it, the page clears the home indicator
            // itself.
            ? SafeArea(
                top: false,
                bottom: !widget.embedded,
                child: Column(
                  children: [
                    _FeedBackBar(showBack: !widget.embedded),
                    Expanded(child: pages),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  // The pages place themselves clear of the bars ([clear]);
                  // the insets they were handed are spent.
                  MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    removeBottom: true,
                    child: pages,
                  ),
                  // The status bar's strip, in the page's own ground, so
                  // pages turning under it pass behind it and the clock and
                  // battery never sit on a post.
                  Positioned(
                    key: const ValueKey('feed_status_strip'),
                    top: 0,
                    left: 0,
                    right: 0,
                    height: clear.top,
                    child: ColoredBox(color: colors.background),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The pages over the deck that rises under every post's foot
/// ([FeedBottomDeck]): one still layer, laid where each post's board block
/// ends ([FeedLayout.deckTop]) in a page [clear] of the bars, and moved
/// with the posts as the bars come and go ([FeedCentredBetweenBars]), so
/// the board always flows into it at the same line. A short window, whose
/// posts scroll inside their page, has none.
class _FeedDeckUnder extends StatelessWidget {
  const _FeedDeckUnder({
    required this.clear,
    required this.chrome,
    required this.travel,
    required this.overhang,
    required this.child,
  });

  final EdgeInsets clear;
  final ScrollChromeController? chrome;
  final double travel;
  final double overhang;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageHeight = constraints.maxHeight - clear.vertical;
        final hasDeck =
            pageHeight.isFinite && pageHeight >= FeedPageViewport.shortWindow;
        final shown = chrome;
        const deck = FeedBottomDeck();
        // One tree with or without the deck: a window folding across the
        // short line never rebuilds the pages (a clip keeps its state).
        final Widget under;
        if (!hasDeck) {
          under = const Positioned(
            left: 0,
            top: 0,
            width: 0,
            height: 0,
            child: SizedBox.shrink(),
          );
        } else {
          final l = FeedLayout.resolve(
            BoxConstraints(
              maxWidth: constraints.maxWidth,
              maxHeight: pageHeight,
            ),
            MediaQuery.textScalerOf(context),
            evalWidth: 20.w,
          );
          under = Positioned(
            left: 0,
            right: 0,
            top: clear.top + l.deckTop,
            bottom: -overhang,
            child: shown == null
                ? deck
                : FeedCentredBetweenBars(
                    chrome: shown,
                    travel: travel,
                    child: deck,
                  ),
          );
        }
        return Stack(fit: StackFit.expand, children: [under, child]);
      },
    );
  }
}

/// A pushed Feed's bar: the home bar's frame, holding only the back
/// chevron where the tabs keep the avatar. No title and no controls: the
/// post's own header says what it is.
class _FeedBackBar extends StatelessWidget {
  const _FeedBackBar({required this.showBack});

  /// A pushed Feed has a back chevron; an embedded one outside the shell
  /// (a test host) has nowhere to go back to.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return HomeTopBarFrame(
      child: HomeTopBarTitleRow(
        leading: showBack
            ? const PageBackButton(key: ValueKey('feed_back'))
            : null,
        title: const SizedBox.shrink(),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/board_settings_provider_new.dart';
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
import 'package:chessever2/utils/responsive_helper.dart';
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
/// set).
///
/// A page pushed from For You › Discovery: it follows the app theme (light
/// or dark surfaces, status bar icons to match) and wears the home bar's
/// geometry with a back button where the tabs keep the avatar. The board
/// stays the focus. Playback runs only while Feed is actually seen: the app
/// is in the foreground and no route or menu sits on top.
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
  late PageController _pages;

  /// Each page's share of the viewport: one post tall, so a screen taller
  /// than a post shows the next one under it rather than an empty band.
  double _pageFraction = 1;
  int _index = 0;
  bool _appResumed = true;
  bool _routeCurrent = true;
  bool _scrollLocked = false;
  bool _announcedFirst = false;
  ModalRoute<void>? _route;
  late final StateController<bool> _open;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open.state = true;
    });
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
    // After this frame, and only while the provider still lives: closing
    // the app disposes the provider together with this screen.
    final open = _open;
    Future.microtask(() {
      if (open.mounted) open.state = false;
    });
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

  /// Sizes the pages to one post for [constraints], swapping in a controller
  /// with the new fraction (on the same page) when it changes.
  void _fitPages(BoxConstraints constraints, TextScaler scaler) {
    final height = constraints.maxHeight;
    if (!height.isFinite || height <= 0) return;
    final post = FeedLayout.naturalHeight(
      constraints.maxWidth,
      scaler,
      evalWidth: 20.w,
    );
    final fraction = (post / height).clamp(0.5, 1.0).toDouble();
    if ((fraction - _pageFraction).abs() < 0.002) return;
    _pageFraction = fraction;
    final old = _pages;
    _pages = PageController(initialPage: _index, viewportFraction: fraction);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final entries = ref.watch(feedEntriesProvider);
    final visible = _appResumed && _routeCurrent;

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
      body = FeedPullRefresh(
        key: const ValueKey('feed_refresh'),
        onRefresh: _refreshFeed,
        // Never while a clip holds the pages (a piece or the scrub bar
        // under the finger).
        enabled: !_scrollLocked,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _fitPages(constraints, MediaQuery.textScalerOf(context));
            return PageView.builder(
              key: const ValueKey('feed_pages'),
              controller: _pages,
              // Pages start at the top, one post tall; the next post shows
              // under the current one on a screen taller than a post.
              padEnds: false,
              scrollDirection: Axis.vertical,
              // Keeps the neighbours built (current ± 1) so the next board is
              // already painted when the swipe lands.
              allowImplicitScrolling: true,
              physics: _scrollLocked
                  ? const NeverScrollableScrollPhysics()
                  : feedPagePhysics,
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
            );
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
              ),
              Expanded(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: HomeTopBarMetrics.maxTextScale,
                  child: body,
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
    this.soundHint,
  });

  /// Whether Feed will actually make a sound: its own speaker is on AND the
  /// board's Sound setting is on.
  final bool soundOn;
  final VoidCallback onToggleSound;

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
            child: const _FeedTitle(),
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

/// The page title, set as the tabs set theirs.
class _FeedTitle extends StatelessWidget {
  const _FeedTitle();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
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
    );
  }
}

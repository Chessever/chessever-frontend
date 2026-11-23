import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart'
    show CollectionScreen;
import 'package:chessever2/screens/collections/open_collection_game.dart'
    show resolvePlayableCollectionGames;
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart'
    show reportsGameTypeProvider;
import 'package:chessever2/screens/for_you/discovery/reports_screen.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart'
    show openDiscoveryGame;
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_pages.dart';
import 'package:chessever2/screens/stories/story_row.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/paywall/game_report_access.dart';
import 'package:chessever2/widgets/paywall/past_game_access.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Opens [collections]' stories on the root navigator, at
/// [initialIndex]'s, growing out of [origin] (its circle on screen, cut by
/// an edge or not) and shrinking back into the circle [anchors] knows when
/// it closes.
Future<void> openCollectionStories(
  BuildContext context, {
  required List<Collection> collections,
  required int initialIndex,
  Rect? origin,
  StoryAnchors? anchors,
}) {
  if (collections.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push(
    StoryRoute(
      builder: (route) => CollectionStoryViewer(
        collections: collections,
        initialIndex: initialIndex.clamp(0, collections.length - 1),
        origin: origin,
        anchors: anchors,
        route: route,
      ),
    ),
  );
}

/// The page a story's collection opens on: the collection's own screen, as
/// its card opens it; for Missed chances, Reports on its Missed Chance
/// topic. Tests hand in a page of their own.
final storyCollectionPageProvider =
    Provider<Widget Function(Collection collection)>(
      (ref) =>
          (collection) => isMissedChances(collection)
          ? ProviderScope(
              overrides: [
                reportsGameTypeProvider.overrideWith(
                  (ref) => ReportGameType.missedChance,
                ),
              ],
              child: const ReportsScreen(),
            )
          : CollectionScreen(collection: collection),
    );

/// Opens a story's game on the board at a move ([moveIndex], the board's
/// own count: -1 is the start), through the gate its source asks: a
/// collection's access, as its page opens a game; a report's, as Reports
/// opens one. Tests hand in their own.
typedef StoryGameOpener =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref, {
      required Collection collection,
      required StoryBatch batch,
      required StoryGame story,
      required int moveIndex,
    });

final storyGameOpenerProvider = Provider<StoryGameOpener>(
  (ref) => openStoryGame,
);

/// Opens a story game's event over the stories (Missed chances' second
/// action) through the app's own links; true once it is on its way. Tests
/// hand in their own.
typedef StoryEventOpener =
    Future<bool> Function({String? tourId, String? roundId});

final storyEventOpenerProvider = Provider<StoryEventOpener>(
  (ref) => DeepLinkService.instance.openEventForShortcut,
);

/// The Premium chooser (Upgrade / Watch ad) for [collection], as a
/// collection's own game opens with it: true once the reader may go on (a
/// purchase, or a watched ad's rewarded access). A guest meets the same
/// chooser; Upgrade asks them to sign in before the paywall. Tests hand in
/// their own.
typedef StoryPremiumChooser =
    Future<bool> Function(BuildContext context, Collection collection);

final storyPremiumChooserProvider = Provider<StoryPremiumChooser>(
  (ref) =>
      (context, collection) => ensurePremiumGameAccess(
        context,
        featureId: collectionPaywallFeatureId(collection.kind),
        returnTo: kCollectionPaywallReturnTo,
      ),
);

/// Whether the reader may open [collection]'s page from one of its stories
/// (View collection, a book's header, an event's Go to event). The stories
/// themselves are the same for every reader; opening a Premium collection
/// is what asks a reader without Premium for it, with the same chooser its
/// games open with. Missed chances opens Reports, which anyone may browse.
Future<bool> ensureStoryCollectionAccess(
  BuildContext context,
  WidgetRef ref,
  Collection collection,
) async {
  if (isMissedChances(collection) || !collection.isPremium) return true;
  if (ref.read(premiumAccessProvider)) return true;
  return ref.read(storyPremiumChooserProvider)(context, collection);
}

/// Puts a story's game on the board, past every gate: [games] to step
/// through, at [index], each opened at its move in [moves] (the board's own
/// count). Tests hand in their own.
typedef StoryBoardOpener =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref, {
      required List<GamesTourModel> games,
      required int index,
      required Map<String, int> moves,
    });

final storyBoardOpenerProvider = Provider<StoryBoardOpener>(
  (ref) => _openStoryBoard,
);

Future<void> _openStoryBoard(
  BuildContext context,
  WidgetRef ref, {
  required List<GamesTourModel> games,
  required int index,
  required Map<String, int> moves,
}) async {
  ref.read(chessboardViewFromProviderNew.notifier).state = ChessboardView.tour;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChessBoardScreenNew(
        currentIndex: index,
        games: games,
        viewSource: ChessboardView.tour,
        showGamebaseButton: false,
        disableGamebaseOverlayByDefault: true,
        allowGameExport: false,
        initialMoveIndexByGameId: moves,
      ),
    ),
  );
}

/// The app's [StoryGameOpener].
Future<void> openStoryGame(
  BuildContext context,
  WidgetRef ref, {
  required Collection collection,
  required StoryBatch batch,
  required StoryGame story,
  required int moveIndex,
}) async {
  final moves = {story.id: moveIndex};
  if (isMissedChances(collection)) {
    // As Reports: the stories are for everyone, the game behind the gate.
    if (!await ensureGameReportAccess(context) || !context.mounted) return;
    final index = batch.orderedIndexOf(story.id);
    if (index < 0) return;
    openDiscoveryGame(
      context,
      ref,
      batch.ordered,
      index,
      initialMoveIndexByGameId: moves,
    );
    return;
  }
  final previews = batch.ordered;
  final index = batch.orderedIndexOf(story.id);
  if (index < 0) return;
  final owner = ref.read(currentUserProvider)?.id;
  bool current() =>
      context.mounted && ref.read(currentUserProvider)?.id == owner;
  try {
    final games = await resolvePlayableCollectionGames(
      repository: ref.read(collectionsRepositoryProvider),
      slug: collection.slug,
      visibleIds: [for (final game in previews) game.gameId],
      requestAccess: (detail) =>
          ref.read(storyPremiumChooserProvider)(context, detail),
      stillCurrent: current,
    );
    if (games == null || !context.mounted || !current()) return;
    if (!await ensurePastGameAccess(
          context,
          game: games[index],
          publishedEventGame: true,
        ) ||
        !context.mounted ||
        !current()) {
      return;
    }
    final navigation = gameNavigationForAccess(
      games: games,
      index: index,
      premium: ref.read(premiumAccessProvider),
      publishedEventGame: true,
    );
    await ref.read(storyBoardOpenerProvider)(
      context,
      ref,
      games: navigation.games,
      index: navigation.index,
      moves: moves,
    );
  } catch (error) {
    if (!context.mounted || !current()) return;
    showAppSnack(
      context,
      error is CollectionsRequestException && error.isPremiumGate
          ? "Couldn't confirm access to this game. Please try again."
          : "Couldn't open this game. Please try again.",
      tone: AppSnackTone.danger,
    );
  }
}

/// The viewer's route. It has no transition of its own: the viewer grows
/// out of its circle and shrinks back into it on its own springs, over the
/// page it was opened from. Once it fills the screen it turns opaque, so the
/// page under it stops painting (and its tickers stop) while the reader
/// watches; it turns see-through again before any motion that shows that
/// page (a drag down, the way out).
///
/// Not a page route on purpose: Today takes itself out of the tree when a
/// page covers it ([pageRouteObserver]), and the viewer has to grow out of,
/// and land back in, a row that is still there. Today hears of the viewer
/// through [storyViewerOpenProvider] and [storyViewerCoversProvider]
/// instead, and stops its live streams while it is hidden.
class StoryRoute extends ModalRoute<void> {
  StoryRoute({required this.builder})
    : super(settings: const RouteSettings(name: 'collection_stories'));

  final Widget Function(StoryRoute route) builder;

  /// Called when a page opened over the viewer is popped (an event opened
  /// from a story through the app's links, which hands back no future).
  VoidCallback? onUncovered;

  @override
  void didPopNext(Route<dynamic> nextRoute) {
    super.didPopNext(nextRoute);
    onUncovered?.call();
  }

  bool _opaque = false;

  @override
  bool get opaque => _opaque;

  /// Whether the page under the viewer is hidden.
  void setOpaque(bool value) {
    if (_opaque == value) return;
    _opaque = value;
    if (isActive && overlayEntries.isNotEmpty) {
      overlayEntries.first.opaque = value;
    }
  }

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  // The page under never slides or fades for this route: the viewer's own
  // way in is the only motion.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => false;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(this);
}

/// The full-screen stories of [collections]: one face per collection on a
/// cube the reader turns with a swipe, one story per game on each face.
class CollectionStoryViewer extends ConsumerStatefulWidget {
  const CollectionStoryViewer({
    super.key,
    required this.collections,
    required this.initialIndex,
    this.origin,
    this.anchors,
    this.route,
  });

  final List<Collection> collections;
  final int initialIndex;

  /// The circle the viewer grows out of, on screen (it may be cut by the
  /// screen's edge). Null grows it from the bottom of the screen, fading in.
  final Rect? origin;

  /// Where the row's circles are when the viewer closes.
  final StoryAnchors? anchors;

  /// The route the viewer is the page of, when it has one.
  final StoryRoute? route;

  @override
  ConsumerState<CollectionStoryViewer> createState() =>
      _CollectionStoryViewerState();
}

class _CollectionStoryViewerState extends ConsumerState<CollectionStoryViewer>
    with TickerProviderStateMixin, WidgetsBindingObserver
    implements StoryPuzzleHost {
  /// Out of the circle: smooth, no overshoot, so the surface never swings
  /// past the screen's edges.
  static const Motion _openMotion = _StoryMotion(
    duration: Duration(milliseconds: 440),
    tolerance: _StoryMotion.unit,
  );

  /// Back into it.
  static const Motion _closeMotion = _StoryMotion(
    duration: Duration(milliseconds: 380),
    tolerance: _StoryMotion.unit,
  );

  /// A drag let go short of closing: back into place, in pixels.
  static const Motion _settleMotion = _StoryMotion(
    duration: Duration(milliseconds: 420),
    bounce: 0.15,
    tolerance: _StoryMotion.pixels,
  );

  /// The surface counts as in place, and the first story starts, this close
  /// to the full screen: the spring's last fraction of a pixel is not worth
  /// a wait.
  static const double _playsFrom = 0.97;

  /// The header, bars and actions fading while the reader holds a story.
  static const Motion _chromeMotion = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 240),
  );

  /// The cube's turn to the next collection when a collection's last story
  /// ends. A curve runs its spring in seconds, so it gets a whole second:
  /// the turn itself lands in about half of it.
  static final Curve _turnCurve = const CupertinoMotion.smooth(
    duration: Duration(milliseconds: 480),
  ).toCurve;
  static const Duration _turnDuration = Duration(seconds: 1);

  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: kStoryEmptyDuration)
        ..addStatusListener(_onProgressStatus)
        ..addListener(_onProgressTick);
  late final SingleMotionController _presence = SingleMotionController(
    motion: _openMotion,
    vsync: this,
  )..addListener(_onPresence);
  late final SingleMotionController _drag = SingleMotionController(
    motion: _settleMotion,
    vsync: this,
  );
  late final SingleMotionController _chrome = SingleMotionController(
    motion: _chromeMotion,
    vsync: this,
    initialValue: 1,
  );

  late int _active = widget.initialIndex;

  /// The page each collection is on, once the reader has been there: its
  /// place in the collection's pages as they are now ([_story]), and which
  /// page it is ([_storyId], [StoryFrame.id]). A re-read of the stories
  /// (new games ahead of it, a Premium unlock) moves the place with the
  /// page, never the page under the reader.
  final Map<String, int> _story = {};
  final Map<String, String?> _storyId = {};

  /// The story each collection's bar was last run for, and how long it ran:
  /// when either changes under the reader, the bar starts again.
  final Map<String, (String?, Duration)> _placed = {};

  /// The frame a face holds after it has turned away mid-turn, by slug: its
  /// board and bar stay exactly as they were while it is still on screen.
  /// Let go once the cube is at rest on one face.
  final Map<String, double> _held = {};

  /// Set while the bar is moved by hand (a held frame given back), so the
  /// move is not taken for the story running out.
  bool _quietProgress = false;

  /// The reader turned back to a face whose story had run out: it starts
  /// again once the cube rests on that face.
  bool _restartAtRest = false;

  /// The story already counted as seen: each counts once.
  Object? _countedFor;

  /// A game story counts as seen once its last position has been on screen
  /// this long (or half of it has played, whichever comes first), as a
  /// stories app counts a story once it has been shown.
  static const Duration _seenBeat = Duration(milliseconds: 1200);
  static const double _watchedAt = 0.5;

  Size _size = Size.zero;

  /// The surface's two ends: [_closedRect] at presence 0 (the circle),
  /// [_openRect] at 1 (the screen, until a close starts from elsewhere).
  Rect? _closedRect;
  double _closedRadius = 0;
  Rect? _openRect;
  double _openRadius = 0;

  /// Scales the scrim from a close that started mid-drag.
  double _scrimScale = 1;

  /// No circle to land in: the surface fades as it shrinks away.
  bool _fade = false;

  /// The collection whose circle the viewer grew out of, when it had one.
  String? _originSlug;

  /// The row was brought round to the active circle (behind the full
  /// screen), so that circle is whole in view or nowhere.
  bool _revealed = false;

  /// The surface fills the screen at rest and the page under it is hidden.
  bool _covering = false;

  /// True while the collection's cover flies between its circle in the row
  /// and the header's circle (on the way in and out); the header's own
  /// circle hides meanwhile, so only one is ever drawn.
  final ValueNotifier<bool> _flightOn = ValueNotifier<bool>(true);

  EdgeInsets _padding = EdgeInsets.zero;
  TextDirection _direction = TextDirection.ltr;

  bool _opened = false;
  bool _closing = false;
  bool _pressing = false;
  bool _holding = false;
  bool _dragging = false;
  bool _paging = false;
  bool _userPaging = false;
  bool _away = false;
  bool _background = false;
  bool _settled = true;

  /// Screen points per point of the surface's own space, as it stood when
  /// the finger last touched it: under 1 while the surface is still
  /// growing (or springing back), where the gesture recognizers measure in
  /// that smaller space.
  double _touchScale = 1;

  /// Where a drag down began on the screen, and the surface's drag then.
  double _dragFromGlobal = 0;
  double _dragFromValue = 0;

  /// How far the reader has pulled on past the last collection's face.
  double _endPull = 0;

  StoryBatch? _activeBatch;
  Object? _bound;

  /// Read once: [dispose] may not read providers.
  late final StateController<bool> _openFlag;
  late final StateController<bool> _coverFlag;

  Collection get _activeCollection => widget.collections[_active];
  String get _activeSlug => _activeCollection.slug;
  StorySeenNotifier get _seen => ref.read(storySeenProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pages.addListener(_onPageScroll);
    final origin = widget.origin;
    _fade = origin == null;
    _closedRect = origin;
    _closedRadius = origin == null ? 0 : origin.shortestSide / 2;
    _originSlug = origin == null ? null : _activeSlug;
    _openFlag = ref.read(storyViewerOpenProvider.notifier);
    _coverFlag = ref.read(storyViewerCoversProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closing) return;
      _openFlag.state = true;
      // The row is not brought round to the circle here: it is still on
      // show around the growing surface. That waits until it is hidden.
      _presence.animateTo(1).then((_) => _onSettled());
    });
  }

  @override
  void dispose() {
    // Providers may not change while the tree is being torn down.
    final openFlag = _openFlag;
    final coverFlag = _coverFlag;
    unawaited(
      Future<void>.microtask(() {
        if (coverFlag.mounted) coverFlag.state = false;
        if (openFlag.mounted) openFlag.state = false;
      }),
    );
    _opaqueTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pages.removeListener(_onPageScroll);
    _pages.dispose();
    _progress.dispose();
    _presence.dispose();
    _drag.dispose();
    _chrome.dispose();
    _caughtUpHold.dispose();
    _flightOn.dispose();
    zone.dispose();
    widget.route?.onUncovered = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = state != AppLifecycleState.resumed;
    _sync();
  }

  // --------------------------------------------------------------- playback

  bool get _canPlay =>
      _opened &&
      !_closing &&
      !_pressing &&
      !_holding &&
      !_dragging &&
      !_paging &&
      !_away &&
      !_background &&
      _settled &&
      !_prompting &&
      !_caughtUp &&
      _activeBatch != null;

  /// Runs the active story's bar when nothing holds it, stops it otherwise.
  void _sync() {
    if (!mounted) return;
    if (_canPlay) {
      if (!_progress.isAnimating && !_progress.isCompleted) {
        _progress.forward();
      }
    } else if (_progress.isAnimating) {
      _progress.stop();
    }
  }

  void _onProgressStatus(AnimationStatus status) {
    if (_quietProgress) return;
    if (status == AnimationStatus.completed) _next(auto: true);
  }

  /// Moves the bar to [value] without it counting as a story's run.
  void _setProgress(double value) {
    _quietProgress = true;
    try {
      _progress.value = value;
    } finally {
      _quietProgress = false;
    }
  }

  /// A game story whose last position has been on screen for a beat
  /// ([_seenBeat]) is seen: its collection opens on the next story the
  /// reader has not seen, and its ring goes quiet once every story is. A
  /// story the reader taps on past from its last position is seen too
  /// ([_next]), however briefly it showed. A reader who leaves mid-story
  /// keeps what they saw.
  void _onProgressTick() {
    if (_quietProgress) return;
    final batch = _activeBatch;
    final index = _story[_activeSlug];
    final frame = index == null ? null : batch?.frameAt(index);
    if (frame == null || !frame.endsStory) return;
    if (_countedFor == _bound) return;
    final run = _progress.duration ?? kStoryEmptyDuration;
    final beat = run.inMicroseconds <= 0
        ? 0.0
        : _seenBeat.inMicroseconds / run.inMicroseconds;
    if (_progress.value < math.min(beat, _watchedAt)) return;
    _countActive();
  }

  /// Counts the game story on screen as seen, once, when it is on its last
  /// position.
  void _countActive() {
    final batch = _activeBatch;
    final bound = _bound;
    final index = _story[_activeSlug];
    if (batch == null || bound == null || index == null) return;
    final frame = batch.frameAt(index);
    if (frame == null || !frame.endsStory || _countedFor == bound) return;
    _countedFor = bound;
    _seen.markSeen(_activeCollection, batch, frame.game.id);
  }

  /// How long page [index] runs: the time to read its words.
  Duration _durationOf(StoryBatch batch, int index) => batch.durationOf(index);

  /// The page [collection] is on in [batch]: the one the reader left it on,
  /// wherever it stands now; else (never visited, or that game gone) the
  /// first page of the first story they have not seen.
  int _placeIn(Collection collection, StoryBatch batch) {
    final id = _storyId[collection.slug];
    final placed = id == null ? null : storyIndexOf(batch, id);
    return clampStoryIndex(
      placed ?? _seen.resumeIndex(collection, batch),
      batch.storyCount,
    );
  }

  /// Ties the bar to the active collection's stories once they are known.
  /// Called from build; anything that notifies runs after the frame.
  void _bind(StoryBatch? batch) {
    _activeBatch = batch;
    if (batch == null) {
      _bound = null;
      _afterFrame(_sync);
      return;
    }
    final collection = _activeCollection;
    final slug = collection.slug;
    final index = _placeIn(collection, batch);
    final id = storyIdAt(batch, index);
    _story[slug] = index;
    _storyId[slug] = id;
    final bound = (slug, index, batch);
    if (_bound == bound) return;
    _bound = bound;
    final duration = _durationOf(batch, index);
    final before = _placed[slug];
    _placed[slug] = (id, duration);
    _progress.duration = duration;
    if (before != null && (before.$1 != id || before.$2 != duration)) {
      // Another page under the reader (its game gone from a re-read), or
      // the same page read again with other words: it starts from its
      // beginning, never part way through a page they did not watch. The
      // descendants it notifies build next.
      _progress.stop();
      _setProgress(0);
      _releasePrompt();
    }
    final counted = !identical(_reconciled[slug], batch);
    _reconciled[slug] = batch;
    _afterFrame(() {
      // The collection's record keeps to the stories it shows now.
      if (counted) _seen.reconcile(collection, batch);
      if (id != null) _seen.markAt(collection, id);
      _sync();
    });
  }

  /// The stories each collection's seen record was last counted against.
  final Map<String, StoryBatch> _reconciled = {};

  void _afterFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  /// Shows story [index] of the active collection, from its start.
  void _go(int index) {
    final batch = _activeBatch;
    if (batch == null) return;
    final slug = _activeSlug;
    final id = storyIdAt(batch, index);
    final duration = _durationOf(batch, index);
    setState(() {
      _story[slug] = index;
      _storyId[slug] = id;
    });
    _placed[slug] = (id, duration);
    if (id != null) _seen.markAt(_activeCollection, id);
    _releasePrompt();
    _progress
      ..stop()
      ..duration = duration
      ..value = 0;
    _bound = (slug, index, batch);
    _sync();
  }

  // ---------------------------------------------------------------- puzzles

  /// How the reader answered each position that asked for a move, by
  /// [StoryFrame.id]: going back to one shows its answer, not the question.
  final Map<String, StoryPuzzleOutcome> _outcomes = {};

  /// The page on screen waits for the reader's move: its bar holds.
  bool _prompting = false;
  String? _promptFor;

  @override
  final ValueNotifier<Rect?> zone = ValueNotifier<Rect?>(null);

  /// The page on screen, as [StoryFrame.id].
  String? get _activeFrameId {
    final index = _story[_activeSlug];
    final batch = _activeBatch;
    return index == null || batch == null ? null : storyIdAt(batch, index);
  }

  @override
  StoryPuzzleOutcome? outcomeOf(String frameId) => _outcomes[frameId];

  @override
  void prompting(String frameId, bool waiting) {
    if (frameId != _activeFrameId) return;
    if (_prompting == waiting && _promptFor == frameId) return;
    _prompting = waiting;
    _promptFor = waiting ? frameId : null;
    if (waiting) _setProgress(0);
    _sync();
  }

  @override
  void settle(String frameId, StoryPuzzleOutcome outcome, {Duration? hold}) {
    _outcomes[frameId] = outcome;
    if (frameId != _activeFrameId) return;
    _prompting = false;
    _promptFor = null;
    // The answer is enjoyed before the story moves on: its bar runs from
    // the start over the longer of the position's reading time and the
    // answer's hold. Never a page the reader did not see: the bar held at
    // its start while they thought.
    final run = _progress.duration ?? kStoryEmptyDuration;
    if (hold != null && hold > run) _progress.duration = hold;
    _setProgress(0);
    _sync();
  }

  /// Another page: nothing waits until it says so.
  void _releasePrompt() {
    _prompting = false;
    _promptFor = null;
    zone.value = null;
  }

  /// The last finger came down on the board taking the reader's move and
  /// the board took it (a piece picked up, played or put down): its tap or
  /// hold is the reader's, never the story's, even once the move it made
  /// has answered the question. A finger on an empty square (or an
  /// opponent's piece) with nothing picked up is the story's: it moves on
  /// like a tap anywhere else ([storyBoardTap]).
  bool _downOnBoard = false;

  /// What the board said of the finger now coming down ([boardTouch]): it
  /// hears every touch before the viewer does. Read once, by that touch.
  bool? _boardTook;

  @override
  void boardTouch(String frameId, {required bool takes}) {
    _boardTook = frameId == _activeFrameId && takes;
  }

  // ------------------------------------------------------------- caught up

  /// Every circle watched, the last story done: one quiet line, then out.
  bool _caughtUp = false;

  late final AnimationController _caughtUpHold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..addStatusListener(_onCaughtUpStatus);

  void _onCaughtUpStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) unawaited(_close());
  }

  /// Whether every circle the reader came from reads as watched.
  bool get _allWatched => widget.collections.every(_seen.isSeen);

  void _showCaughtUp() {
    if (_caughtUp || _closing) return;
    _progress.stop();
    _releasePrompt();
    setState(() => _caughtUp = true);
    unawaited(_chrome.animateTo(0));
    _caughtUpHold.forward(from: 0);
  }

  /// The next story; after a collection's last, the next collection; after
  /// the last collection's, the way out.
  void _next({bool auto = false}) {
    // A game being opened holds the story where it is.
    if (_closing || _away || !mounted) return;
    if (!auto) unawaited(HapticFeedbackService.selection());
    // Moved on from: seen, as it showed (a tap past it included).
    _countActive();
    final batch = _activeBatch;
    if (batch == null) {
      _toCollection(_active + 1);
      return;
    }
    final index = _story[_activeSlug] ?? 0;
    if (index + 1 < batch.storyCount) {
      _go(index + 1);
    } else {
      _toCollection(_active + 1);
    }
  }

  void _previous() {
    if (_closing || _away) return;
    unawaited(HapticFeedbackService.selection());
    final batch = _activeBatch;
    final index = _story[_activeSlug] ?? 0;
    if (batch != null && index > 0) {
      _go(index - 1);
    } else if (_active > 0) {
      _toCollection(_active - 1);
    } else if (batch != null) {
      _go(index);
    }
  }

  /// Turns the cube to collection [index], or past the last one ends the
  /// stories: with every circle watched on one quiet line ("You're all
  /// caught up"), otherwise straight out.
  void _toCollection(int index) {
    if (index >= widget.collections.length) {
      if (_allWatched) {
        _showCaughtUp();
      } else {
        unawaited(_close());
      }
      return;
    }
    if (index < 0 || !_pages.hasClients) return;
    _progress.stop();
    _settled = false;
    unawaited(
      _pages.animateToPage(index, duration: _turnDuration, curve: _turnCurve),
    );
  }

  /// Past the turn's half way the face coming in becomes the active one.
  /// The face turning away holds the frame it was on (its board, its bars)
  /// while it is still on screen, and a face turned back to mid-turn picks
  /// up the frame it held: no face ever jumps during a turn.
  ///
  /// Once the way out has begun the active collection is fixed: its cover
  /// is the one flying home.
  void _onPageChanged(int index) {
    if (_closing || index == _active) return;
    if (_userPaging) unawaited(HapticFeedbackService.selection());
    final leaving = _activeSlug;
    _held[leaving] = _progress.value;
    setState(() => _active = index);
    _progress.stop();
    _releasePrompt();
    final frame = _held.remove(_activeSlug) ?? 0;
    _restartAtRest = frame >= 1;
    _setProgress(frame);
    _bound = null;
    _revealActive();
  }

  void _onPageScroll() {
    final page = _pages.hasClients && _pages.position.haveDimensions
        ? _pages.page
        : null;
    final settled = page == null || (page - page.round()).abs() < 0.002;
    if (settled == _settled) return;
    _settled = settled;
    _sync();
  }

  /// The turn is over (the pager's scroll has ended) and the cube rests on
  /// the active face. The faces that turned away are off screen now and
  /// let go of the frames they held; a story the reader turned back to
  /// after it had run out starts again, at rest.
  void _onTurnEnded() {
    final page = _pages.hasClients && _pages.position.haveDimensions
        ? _pages.page
        : null;
    if (page != null && (page - _active).abs() > 0.01) return;
    if (_held.isNotEmpty) _setStateSafely(_held.clear);
    if (_restartAtRest) {
      _restartAtRest = false;
      if (_progress.value >= 1) _setProgress(0);
    }
  }

  /// [setState], or after the frame when the tree is being laid out.
  void _setStateSafely(VoidCallback change) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _afterFrame(() => setState(change));
    } else {
      setState(change);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _paging = true;
      _userPaging = true;
      _endPull = 0;
      _sync();
    } else if (notification is OverscrollNotification) {
      // Past the last face there is no collection to turn to.
      if (notification.dragDetails != null && notification.overscroll > 0) {
        _endPull += notification.overscroll;
      }
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _endPull = 0;
    } else if (notification is ScrollEndNotification) {
      final pull = _endPull;
      _endPull = 0;
      _paging = false;
      _userPaging = false;
      _onTurnEnded();
      if (_pulledPastEnd(pull, notification.dragDetails)) {
        // As after the last collection's last story: the way out. Once the
        // pager has finished changing its own scroll activity, which is
        // what sent this notification: the way out stops the pager too.
        scheduleMicrotask(() {
          if (mounted) unawaited(_close());
        });
        return false;
      }
      _sync();
    }
    return false;
  }

  /// A swipe on past the last collection, let go far enough along or with
  /// a flick, closes the stories, as Instagram's does.
  bool _pulledPastEnd(double pull, DragEndDetails? end) {
    if (pull <= 0 || _closing) return false;
    if (pull >= _size.width * 0.12) return true;
    final velocity = end?.primaryVelocity ?? 0;
    // The next face lies to the right in a left-to-right layout: a pull on
    // towards it moves the finger left.
    final onward = _direction == TextDirection.rtl ? velocity : -velocity;
    return pull >= 8 && onward > 600;
  }

  // --------------------------------------------------------------- gestures

  /// Stories take touches only once the surface is in place: a second tap
  /// on the circle that lands on the growing surface is not a story tap.
  /// Nor while a game opened from the story is on its way: the reader comes
  /// back to the story they opened it from.
  bool get _takesTouches => _opened && !_closing && !_away;

  /// Records how the surface's own space stands to the screen's under a
  /// new finger ([_touchScale]).
  void _onPointerDown(PointerDownEvent event) {
    final took = _boardTook ?? false;
    _boardTook = null;
    _downOnBoard = took && (zone.value?.contains(event.position) ?? false);
    final toLocal = event.transform;
    if (toLocal == null) {
      _touchScale = 1;
      return;
    }
    final a = MatrixUtils.transformPoint(toLocal, Offset.zero);
    final b = MatrixUtils.transformPoint(toLocal, const Offset(0, 100));
    final local = (b - a).dy;
    _touchScale = local.abs() < 1e-3 ? 1 : (100 / local).abs();
  }

  void _onTapDown(TapDownDetails details) {
    if (!_takesTouches || _downOnBoard) return;
    _pressing = true;
    _sync();
  }

  /// The third of the story nearest where reading starts goes back; the
  /// rest goes on.
  void _onTapUp(TapUpDetails details) {
    if (!_takesTouches) {
      _pressing = false;
      return;
    }
    _pressing = false;
    if (_caughtUp) {
      unawaited(_close());
      return;
    }
    if (_downOnBoard) return;
    final x = details.localPosition.dx;
    final back = Directionality.of(context) == TextDirection.rtl
        ? x > _size.width * 2 / 3
        : x < _size.width / 3;
    back ? _previous() : _next();
    _sync();
  }

  void _onTapCancel() {
    _pressing = false;
    _sync();
  }

  void _setHolding(bool value) {
    if (_holding == value) return;
    _holding = value;
    unawaited(_chrome.animateTo(value ? 0 : 1));
    _sync();
  }

  void _togglePause() => _setHolding(!_holding);

  /// How far the finger had moved down from where it held when the hold
  /// turned into a drag; null while it holds still.
  double? _holdDragFrom;

  /// A finger that rests on the story holds it, even one that came down
  /// while the surface was still growing: the story waits under it.
  void _onHoldStart(LongPressStartDetails details) {
    if (_closing || _away || _downOnBoard) return;
    _setHolding(true);
  }

  /// A held story dragged down follows the finger as a drag from rest
  /// does: the long press has the gesture by then, so it hands its moves on.
  void _onHoldMove(LongPressMoveUpdateDetails details) {
    if (!_holding || _closing) return;
    final dy = details.offsetFromOrigin.dy;
    var from = _holdDragFrom;
    if (from == null) {
      if (dy < kTouchSlop) return;
      from = _holdDragFrom = dy;
      _beginDrag();
    }
    if (_dragging) _drag.value = math.max(0.0, dy - from);
  }

  void _onHoldEnd(LongPressEndDetails details) {
    final dragged = _holdDragFrom != null;
    _holdDragFrom = null;
    if (dragged && _dragging) {
      _endDrag(details.velocity.pixelsPerSecond.dy * _touchScale);
    }
    _setHolding(false);
  }

  void _onHoldCancel() {
    final dragged = _holdDragFrom != null;
    _holdDragFrom = null;
    if (dragged) _onDragCancel();
    _setHolding(false);
  }

  double get _displayDrag {
    final raw = _drag.value;
    return raw >= 0 ? raw : math.max(-64.sp, raw * 0.3);
  }

  /// A drag down is read on the screen, never in the surface's own space:
  /// a drag that starts while the surface is still growing (drawn smaller
  /// than the screen) moves it exactly as far as the finger, no further.
  void _onDragStart(DragStartDetails details) {
    _beginDrag();
    _dragFromGlobal = details.globalPosition.dy;
    _dragFromValue = _drag.value;
  }

  void _beginDrag() {
    if (_closing) return;
    // The surface still hides the row: bring the circle round now, unseen,
    // before the drag shows the page under.
    _revealActive();
    _dragging = true;
    _pressing = false;
    _opaqueTimer?.cancel();
    _setOpaque(false);
    _drag.stop(canceled: true);
    _sync();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_closing || !_dragging) return;
    _drag.value = _dragFromValue + details.globalPosition.dy - _dragFromGlobal;
  }

  /// The recognizer measures the fling in the surface's space as it stood
  /// at touch-down; on the screen it is [_touchScale] of that.
  void _onDragEnd(DragEndDetails details) =>
      _endDrag(details.velocity.pixelsPerSecond.dy * _touchScale);

  void _endDrag(double velocity) {
    if (_closing || !_dragging) return;
    _dragging = false;
    final raw = _drag.value;
    if (raw > 0 && (raw > _size.height * 0.16 || velocity > 800)) {
      unawaited(_close(velocity: velocity));
      return;
    }
    if (raw < 0 && (raw < -80.sp || velocity < -800)) {
      // A swipe up is the story's action: the game, at this position.
      if (!_caughtUp) unawaited(_openGame());
    }
    _drag.animateTo(0, withVelocity: velocity).then((_) => _onSettled());
    _sync();
  }

  void _onDragCancel() {
    if (_closing || !_dragging) return;
    _dragging = false;
    _drag.animateTo(0).then((_) => _onSettled());
    _sync();
  }

  /// The first story starts as the surface arrives, not after the spring's
  /// last sub-pixel. The flying cover lands on the header's circle exactly
  /// as the surface does, and hands over to it there.
  void _onPresence() {
    final p = _presence.value;
    final flying = _closing || p < 1;
    if (_flightOn.value != flying) _flightOn.value = flying;
    if (_opened || _closing || p < _playsFrom) return;
    setState(() => _opened = true);
    _sync();
  }

  /// Whether the page under is hidden ([_covering]); told to Today, which
  /// stops its live streams while it is, as under any page.
  void _setOpaque(bool value) {
    widget.route?.setOpaque(value);
    _covering = value;
    _publishCover();
  }

  void _publishCover() {
    final covers = _covering || _away;
    if (_coverFlag.mounted && _coverFlag.state != covers) {
      _coverFlag.state = covers;
    }
  }

  /// The surface fills the whole screen, untouched: nothing of the page
  /// under it shows.
  bool get _surfaceHidesPage =>
      !_closing &&
      _openRect == null &&
      _presence.value >= 1 &&
      _drag.value.abs() < 0.5;

  /// Scrolls the row so the active collection's circle is in view for the
  /// way out, only while the surface hides the row entirely: the row is
  /// never seen to jump.
  void _revealActive() {
    if (!_surfaceHidesPage) return;
    _revealed = true;
    widget.anchors?.reveal(_activeSlug);
  }

  /// The surface fills the screen at rest: the page under can stop painting.
  ///
  /// It waits a beat first: the page under is set aside mid-motion
  /// otherwise (the tapped circle still springing back from its press), and
  /// would finish that motion only when the viewer closes into it.
  void _onSettled() {
    _opaqueTimer?.cancel();
    _opaqueTimer = Timer(_opaqueAfter, () {
      if (!mounted || _closing || _dragging || !_opened) return;
      if (_presence.value < 1) return;
      if (_drag.value.abs() > 0.5) return;
      _revealActive();
      _setOpaque(true);
    });
  }

  /// How long the page under keeps painting after the surface settles.
  static const Duration _opaqueAfter = Duration(milliseconds: 900);
  Timer? _opaqueTimer;

  // --------------------------------------------------------------- open/close

  Rect get _screen => Offset.zero & _size;

  /// Where the surface goes with no circle to land in: small, low and
  /// centred, fading as it goes.
  Rect get _fallbackRect => Rect.fromCenter(
    center: Offset(_size.width / 2, _size.height * 0.86),
    width: StoryRowMetrics.cover,
    height: StoryRowMetrics.cover,
  );

  double _interval(double value, double begin, double end) =>
      ((value - begin) / (end - begin)).clamp(0.0, 1.0);

  /// How far down the surface has been dragged, 0 to 1 of the screen.
  double get _dragShare =>
      _size.height <= 0 ? 0 : (_displayDrag / _size.height).clamp(0.0, 1.0);

  /// The surface's rect and corner radius at presence [p] and the current
  /// drag.
  (Rect, double) _surface(double p) {
    final closed = _closedRect ?? _fallbackRect;
    final open = _openRect ?? _screen;
    var rect = Rect.lerp(closed, open, p)!;
    var radius = lerpDouble(_closedRadius, _openRadius, p)!;
    final drag = _displayDrag;
    if (drag > 0) {
      final t = _dragShare;
      final scale = 1 - 0.32 * t;
      rect = Rect.fromCenter(
        center: rect.center + Offset(0, drag),
        width: rect.width * scale,
        height: rect.height * scale,
      );
      radius += 28.sp * math.min(1.0, t * 5);
    } else if (drag < 0) {
      rect = rect.shift(Offset(0, drag));
    }
    return (rect, math.min(radius, rect.shortestSide / 2));
  }

  double _scrim(double p) =>
      (p.clamp(0.0, 1.0) * _scrimScale * (1 - math.min(1.0, _dragShare * 2)))
          .clamp(0.0, 1.0);

  /// Shrinks the surface back into the active collection's circle (looked
  /// up now: the row may have scrolled), or away at the bottom when the
  /// circle is out of view, then leaves.
  Future<void> _close({double velocity = 0}) async {
    if (_closing || !mounted) return;
    // While the surface still fills the screen, the row comes round to the
    // circle unseen.
    _revealActive();
    _closing = true;
    // A turn under way stops and the cube swings back onto the face being
    // closed, whose cover is the one flying home: never on to the next
    // collection, which is neither made the active one nor marked seen.
    if (_pages.hasClients && _pages.position.haveDimensions) {
      _pages.jumpTo(_pages.position.pixels);
    }
    _flightOn.value = true;
    _dragging = false;
    _holdDragFrom = null;
    _setHolding(false);
    _progress.stop();
    _opaqueTimer?.cancel();
    _setOpaque(false);
    setState(() {});
    // The page under lays itself out again before its circle is measured.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final p = _presence.value.clamp(0.0, 1.0);
    final (rect, radius) = _surface(p);
    final scrim = _scrim(p);
    final anchors = widget.anchors;
    // A circle wholly in view; or, when the row was never brought round
    // (closed before the surface filled the screen), the circle it grew
    // out of, where it still stands.
    final anchor =
        anchors?.rectOf(_activeSlug) ??
        (!_revealed && _activeSlug == _originSlug
            ? anchors?.rectOf(_activeSlug, whole: false)
            : null);
    final closed = anchor ?? _fallbackRect;
    final closedRadius = closed.shortestSide / 2;
    _drag
      ..stop(canceled: true)
      ..value = 0;
    setState(() {
      _fade = anchor == null;
      _closedRect = closed;
      _closedRadius = closedRadius;
      if (p > 0.05) {
        // Rebased so the surface as it stands is where presence p puts it:
        // the way back starts exactly here, with no jump.
        double far(double from, double at) => from + (at - from) / p;
        _openRect = Rect.fromLTRB(
          far(closed.left, rect.left),
          far(closed.top, rect.top),
          far(closed.right, rect.right),
          far(closed.bottom, rect.bottom),
        );
        _openRadius = far(closedRadius, radius);
        _scrimScale = p <= 0 ? 0 : (scrim / p).clamp(0.0, 1.0);
      }
    });
    final distance = (rect.center - closed.center).distance;
    final speed = distance < 1 ? 0.0 : (velocity.abs() / distance);
    _presence.motion = _closeMotion;
    await _presence.animateTo(0, withVelocity: -speed.clamp(0.0, 6.0));
    if (!mounted) return;
    // One frame exactly on the circle before the row's own circle takes
    // over: the hand-off has no last-pixel jump.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final route = widget.route;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    } else {
      Navigator.maybeOf(context)?.pop();
    }
  }

  // ---------------------------------------------------------------- actions

  /// Pauses, opens the story's game on the board at the position on screen
  /// (the one before it while a move is asked for), through its source's
  /// gate, and resumes once the reader is back.
  Future<void> _openGame() async {
    final batch = _activeBatch;
    final index = _story[_activeSlug] ?? 0;
    final frame = batch?.frameAt(index);
    if (batch == null || frame == null || _away || _closing) return;
    final segment = frame.position;
    final asking = segment.puzzle != null && _outcomes[frame.id] == null;
    unawaited(HapticFeedbackService.buttonPress());
    setState(() => _away = true);
    _publishCover();
    _sync();
    try {
      await ref.read(storyGameOpenerProvider)(
        context,
        ref,
        collection: _activeCollection,
        batch: batch,
        story: frame.game,
        moveIndex: segment.isStill
            ? -1
            : segment.boardMoveIndex(before: asking),
      );
    } finally {
      if (mounted) {
        setState(() => _away = false);
        _publishCover();
        _sync();
      }
    }
  }

  /// The game's event, from a Missed chances story: the event page over the
  /// stories, which wait until it is popped.
  Future<void> _openEvent() async {
    final batch = _activeBatch;
    final index = _story[_activeSlug] ?? 0;
    final frame = batch?.frameAt(index);
    if (frame == null || _away || _closing || !_opened) return;
    final game = frame.game.game;
    unawaited(HapticFeedbackService.buttonPress());
    setState(() => _away = true);
    _publishCover();
    _sync();
    final route = widget.route;
    void back() {
      route?.onUncovered = null;
      if (!mounted) return;
      setState(() => _away = false);
      _publishCover();
      _sync();
    }

    route?.onUncovered = back;
    final opened = await ref.read(storyEventOpenerProvider)(
      tourId: game.tourId,
      roundId: game.roundId,
    );
    if (!opened) {
      back();
      if (mounted) {
        showAppSnack(
          context,
          "Couldn't open this event",
          tone: AppSnackTone.danger,
        );
      }
    }
  }

  /// The collection's own page (its header, View collection) over the
  /// stories, which wait where they are and play on once the reader is
  /// back. A Premium collection asks a reader without Premium first
  /// ([ensureStoryCollectionAccess]); turned down, the stories play on.
  Future<void> _openCollection() async {
    if (_away || _closing || !_opened) return;
    unawaited(HapticFeedbackService.buttonPress());
    setState(() => _away = true);
    _publishCover();
    _sync();
    final page = ref.read(storyCollectionPageProvider);
    final collection = _activeCollection;
    try {
      if (!await ensureStoryCollectionAccess(context, ref, collection) ||
          !mounted) {
        return;
      }
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page(collection)));
    } finally {
      if (mounted) {
        setState(() => _away = false);
        _publishCover();
        _sync();
      }
    }
  }

  void _retry(String slug) {
    ref.invalidate(collectionContentsProvider(slug));
    ref.invalidate(collectionDetailProvider(slug));
    ref.invalidate(storyBatchProvider(slug));
  }

  // ------------------------------------------------------------------ build

  /// The cover's flight at presence [p], in the coordinates of a surface
  /// standing at [rect]: from the circle the viewer grew out of (or lands
  /// in), where at presence 0 it fills the surface, to the header's circle
  /// as the surface draws it (the page drawn into the surface scaled to
  /// cover it, centred). Always a circle: its centre and its diameter move,
  /// never a stretched picture.
  Rect _flightRect(double p, Rect rect) {
    final from = _closedRect ?? _fallbackRect;
    if (_size.isEmpty) return from.shift(-rect.topLeft);
    final avatar = StoryPageMetrics.avatarRect(_size, _padding, _direction);
    final scale = math.max(
      rect.width / _size.width,
      rect.height / _size.height,
    );
    final drawn = Offset(
      rect.left + (rect.width - _size.width * scale) / 2,
      rect.top + (rect.height - _size.height * scale) / 2,
    );
    final to = Rect.fromLTWH(
      drawn.dx + avatar.left * scale,
      drawn.dy + avatar.top * scale,
      avatar.width * scale,
      avatar.height * scale,
    );
    final t = p.clamp(0.0, 1.0);
    final center = Offset.lerp(from.center, to.center, t)!;
    final diameter = lerpDouble(from.shortestSide, to.shortestSide, t)!;
    return Rect.fromCenter(
      center: center - rect.topLeft,
      width: diameter,
      height: diameter,
    );
  }

  @override
  Widget build(BuildContext context) {
    _size = MediaQuery.sizeOf(context);
    _padding = MediaQuery.paddingOf(context);
    _direction = Directionality.of(context);
    final collections = widget.collections;
    // The active collection's stories, and the next one's read ahead, so
    // the cube's next face is ready before the reader turns to it. The
    // face before is kept warm from the visit (or read when turned to).
    if (_active + 1 < collections.length) {
      ref.watch(storyBatchProvider(collections[_active + 1].slug));
    }
    _bind(ref.watch(storyBatchProvider(_activeSlug)).valueOrNull);

    final colors = context.colors;
    final light = context.isLightTheme;
    final backdrop = colors.background;
    // What the page under falls into as the stories come up: the night's
    // own dark on the dark theme; on paper the app's recessed tint of the
    // page, never a grey wash of ink over it.
    final scrimColor = light ? colors.surfaceRecessed : colors.scrim;
    final scrimDepth = light ? 0.9 : colors.scrim.a;
    final story = _story[_activeSlug];
    final batch = _activeBatch;

    final pager = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageView.builder(
        key: const ValueKey('story_pages'),
        controller: _pages,
        // Still while Open game is on its way: the reader comes back to the
        // collection the game was opened from.
        physics: _away
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(parent: ClampingScrollPhysics()),
        onPageChanged: _onPageChanged,
        itemCount: collections.length,
        itemBuilder: (context, index) {
          final active = index == _active;
          final collection = collections[index];
          return _CubeFace(
            controller: _pages,
            index: index,
            restingPage: _active,
            child: TickerMode(
              enabled: active,
              child: StoryCollectionPage(
                key: ValueKey('story_page_${collection.slug}'),
                collection: collection,
                storyIndex: _story[collection.slug],
                storyId: _storyId[collection.slug],
                // A face turning away keeps the frame it was on.
                progress: active
                    ? _progress
                    : AlwaysStoppedAnimation<double>(
                        _held[collection.slug] ?? 0,
                      ),
                avatarHidden: active ? _flightOn : null,
                chrome: _chrome,
                backdrop: backdrop,
                onClose: () => unawaited(_close()),
                onOpenGame: () => unawaited(_openGame()),
                onOpenCollection: () => unawaited(_openCollection()),
                onOpenEvent: isMissedChances(collection)
                    ? () => unawaited(_openEvent())
                    : null,
                onRetry: () => _retry(collection.slug),
                active: active && !_away,
                puzzles: this,
              ),
            ),
          );
        },
      ),
    );

    final content = RepaintBoundary(
      child: Listener(
        onPointerDown: _onPointerDown,
        child: RawGestureDetector(
          key: const ValueKey('story_gestures'),
          behavior: HitTestBehavior.opaque,
          gestures: {
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (r) => r
                    ..onTapDown = _onTapDown
                    ..onTapUp = _onTapUp
                    ..onTapCancel = _onTapCancel,
                ),
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(
                    duration: const Duration(milliseconds: 220),
                  ),
                  (r) => r
                    ..onLongPressStart = _onHoldStart
                    ..onLongPressMoveUpdate = _onHoldMove
                    ..onLongPressEnd = _onHoldEnd
                    ..onLongPressCancel = _onHoldCancel,
                ),
            VerticalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  VerticalDragGestureRecognizer
                >(
                  VerticalDragGestureRecognizer.new,
                  (r) => r
                    ..onStart = _onDragStart
                    ..onUpdate = _onDragUpdate
                    ..onEnd = _onDragEnd
                    ..onCancel = _onDragCancel,
                ),
          },
          // Nothing inside takes a touch until the surface is in place, nor
          // on the way out.
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                ignoring: !_opened || _closing || _caughtUp,
                child: pager,
              ),
              // The end: the last story done with every circle watched.
              if (_caughtUp)
                Positioned.fill(
                  child: ColoredBox(
                    color: backdrop,
                    child: const StoryCaughtUp(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final count = batch?.storyCount ?? 0;
    final semanticsLabel = _caughtUp
        ? "You're all caught up"
        : [
            'Stories of ${_activeCollection.title}',
            if (batch != null && count > 0 && story != null)
              'story ${story + 1} of $count',
            if (_prompting) 'your move',
            if (_holding) 'paused',
          ].join(', ');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        // A see-through scaffold of its own, so a snack raised from a story
        // (an open that failed) shows over the stories, not under them.
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: Semantics(
            key: const ValueKey('story_viewer'),
            container: true,
            explicitChildNodes: true,
            label: semanticsLabel,
            customSemanticsActions: {
              const CustomSemanticsAction(label: 'Next story'): _next,
              const CustomSemanticsAction(label: 'Previous story'): _previous,
              CustomSemanticsAction(
                label: _holding ? 'Resume stories' : 'Pause stories',
              ): _togglePause,
              const CustomSemanticsAction(label: 'View collection'): () =>
                  unawaited(_openCollection()),
              const CustomSemanticsAction(label: 'Close stories'): () =>
                  unawaited(_close()),
            },
            child: AnimatedBuilder(
              animation: Listenable.merge([_presence, _drag]),
              child: content,
              builder: (context, content) {
                final p = _presence.value;
                final (rect, radius) = _surface(p);
                // The page fades in over its own backdrop (never over a
                // picture), so it may start early: no frame is a blank slab.
                final contentOpacity = _interval(p, 0.25, 0.85);
                final surfaceOpacity = _fade ? _interval(p, 0, 0.6) : 1.0;
                final flying = _flightOn.value;
                return Stack(
                  children: [
                    // Takes every touch outside the surface while it moves:
                    // the page under is shown, never pressed.
                    Positioned.fill(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        child: ColoredBox(
                          color: scrimColor.withValues(
                            alpha: scrimDepth * _scrim(p),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fromRect(
                      rect: rect,
                      child: Opacity(
                        opacity: surfaceOpacity,
                        child: ClipRRect(
                          key: const ValueKey('story_surface'),
                          borderRadius: BorderRadius.circular(radius),
                          child: ColoredBox(
                            color: backdrop,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Opacity(
                                  opacity: contentOpacity,
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox.fromSize(
                                      size: _size,
                                      child: content,
                                    ),
                                  ),
                                ),
                                // The collection's cover, a circle the whole
                                // way: at the start it is the tapped circle
                                // itself, then it travels into the header's
                                // circle while the page grows around it, and
                                // back on the way out. It never fades over
                                // the page.
                                if (flying)
                                  Positioned.fromRect(
                                    rect: _flightRect(p, rect),
                                    child: IgnorePointer(
                                      child: ClipOval(
                                        key: const ValueKey('story_flight'),
                                        child: StoryCoverImage(
                                          collection: _activeCollection,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// One collection's face of the cube: as the pager turns, the face rotates
/// about the edge it shares with its neighbour and darkens as it turns
/// away. At rest it is drawn flat and untouched.
class _CubeFace extends StatelessWidget {
  const _CubeFace({
    required this.controller,
    required this.index,
    required this.restingPage,
    required this.child,
  });

  final PageController controller;
  final int index;
  final int restingPage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final light = context.isLightTheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final shade = light ? context.colors.textPrimary : Colors.black;
    final shadeDepth = light ? 0.22 : 0.5;
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? restingPage.toDouble()
            : restingPage.toDouble();
        // Which side a face sits on follows the reading direction: in a
        // right-to-left layout the next face comes in from the left.
        final offset = (index - page).clamp(-1.0, 1.0);
        final delta = rtl ? -offset : offset;
        final turning = delta.abs() > 1e-4;
        final transform = Matrix4.identity();
        if (turning) {
          transform
            ..setEntry(3, 2, 0.0011)
            ..rotateY(-delta * math.pi / 2);
        }
        return Transform(
          alignment: delta > 0 ? Alignment.centerLeft : Alignment.centerRight,
          transform: transform,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            // The face turning away falls into shade: deep on the dark
            // surface, a light tint of the page's own ink on paper, never a
            // grey wash over it.
            decoration: BoxDecoration(
              color: shade.withValues(
                alpha: turning ? shadeDepth * delta.abs() : 0,
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// The viewer's springs: smooth (or a touch snappy) Cupertino springs that
/// call themselves done within [tolerance] of their target, in the units
/// they move (a share of the way, or pixels), so a settled surface never
/// waits on the spring's last thousandth.
class _StoryMotion extends CupertinoMotion {
  const _StoryMotion({
    required super.duration,
    super.bounce,
    required Tolerance tolerance,
  }) : _tolerance = tolerance, // ignore: prefer_initializing_formals
       super(snapToEnd: true);

  /// For a value that runs from 0 to 1: under a pixel on any screen.
  static const Tolerance unit = Tolerance(distance: 0.001, velocity: 0.02);

  /// For a value in pixels.
  static const Tolerance pixels = Tolerance(distance: 0.5, velocity: 10);

  final Tolerance _tolerance;

  @override
  Tolerance get tolerance => _tolerance;
}

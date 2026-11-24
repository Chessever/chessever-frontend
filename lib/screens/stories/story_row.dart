import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/game_review/classification_style.dart'
    show moveAnnotationColor;
import 'package:chessever2/screens/collections/collections_screen.dart'
    show CollectionCoverPlate, collectionMenuActions;
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart'
    show LichessMoveAnnotationType;
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_row_access.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/screens/stories/story_viewer.dart';
import 'package:chessever2/screens/stories/story_visit.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/text_scale.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:skeletonizer/skeletonizer.dart' show Bone;

/// The row's geometry, one set of numbers for the row, its skeleton and the
/// viewer's way in and out.
abstract final class StoryRowMetrics {
  /// The cover's circle.
  static double get cover => 64.sp;

  /// The air between the cover and its ring.
  static double get ringGap => 3.sp;

  /// The ring of a collection with stories the reader has not seen.
  static double get ringUnseen => 2.5.sp;

  /// The ring of one they have.
  static double get ringSeen => 1.sp;

  /// The ring's outer diameter: the item's width.
  static double get item => cover + 2 * (ringGap + ringUnseen);

  /// Between two items.
  static double get spacing => 12.sp;

  /// From one item's start to the next one's.
  static double get pitch => item + spacing;

  /// Between the ring and the name under it.
  static double get labelGap => 6.sp;

  /// The name's line, room for it at its largest text scale
  /// ([kDenseTextScale]), so a larger text setting never spills it into the
  /// tiles below.
  static double get labelHeight => 18.sp;

  /// The row's height, the name included.
  static double get height => item + labelGap + labelHeight;

  /// Under the row, above the tiles that follow it.
  static double get bottom => 16.sp;

  /// How much of a circle cut by an edge has to show (of its width and of
  /// its height) for the viewer to grow out of it.
  static const double partShown = 0.3;

  /// A pull past either end of the row, read through its resistance
  /// ([pullCeiling]), turns the row Off (Settings › Customization ›
  /// Collection stories): well past a scroll's overshoot, as News turns a
  /// page.
  static const double pullArm = 56;

  /// What a pull past an end can reach, however far the finger goes.
  static const double pullCeiling = 100;

  /// The pull mark's circle: News's pull ring's size.
  static const double pullMark = 20;

  /// The ring of a collection with stories the reader has not seen: the
  /// brand's blue a deep tonal step down from its bright cyan, on paper the
  /// app's deep teal ink, on the dark page the cyan sunk toward the page.
  /// Never the poster-bright brand fill.
  static Color unseenRing(BuildContext context) {
    final colors = context.colors;
    if (context.isLightTheme) return colors.accentText;
    return Color.lerp(colors.brand, colors.background, 0.38)!;
  }

  /// The name's type: one size, whatever its length.
  static TextStyle labelType() =>
      AppTypography.textXsMedium.copyWith(fontSize: 12.f, height: 1.25);

  /// The pixel width a cover is decoded at for a circle of [diameter]
  /// (twice its side, so a landscape cover still fills the circle crisply).
  static int cacheWidth(BuildContext context, double diameter) =>
      (diameter * MediaQuery.devicePixelRatioOf(context) * 2).round();
}

/// A collection's cover in a circle of [diameter], whole ([StoryCoverImage]),
/// as the row and the viewer's header draw it.
class StoryCover extends ConsumerWidget {
  const StoryCover({
    super.key,
    required this.collection,
    required this.diameter,
  });

  final Collection collection;
  final double diameter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox.square(
      dimension: diameter,
      child: ClipOval(child: StoryCoverImage(collection: collection)),
    );
  }
}

/// The share of a story circle's diameter a cover stands in, whole and
/// centred. A 2:3 cover this tall reaches 0.47 of the diameter from the
/// centre at its corners, so the circle's rim never cuts it: a book's title
/// and author read in the circle instead of being cropped off its top and
/// bottom. Missed chances' mark draws its picture at the same share.
const double kStoryCoverShare = 0.78;

/// How soft the bed around a cover is: the blur's sigma as a share of the
/// circle's diameter, enough that the bed reads as one field of the cover's
/// colours, never as a second copy of it.
const double kStoryCoverBedBlur = 0.2;

/// The bed is drawn this much larger than the circle, so the blur reads the
/// picture right up to the rim: drawn at the circle's size, it would pull
/// in the page around it and darken (or lighten) the rim into a halo.
const double kStoryCoverBedBleed = 1.6;

/// A collection's cover as its story circle draws it, filling its (square)
/// box: the whole cover centred at [kStoryCoverShare] of the box, on a bed
/// of its own colours (the same picture, past the box and blurred), so
/// nothing of the cover is cut by the circle and the circle is still one
/// picture. A collection with no cover, or one still loading, shows its
/// pixel plate; Missed chances its own mark.
///
/// Decoded at the row circle's size, so the row, the viewer's header and
/// its way in and out all share one decoded picture.
class StoryCoverImage extends ConsumerWidget {
  const StoryCoverImage({super.key, required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isMissedChances(collection)) return const MissedChancesMark();
    final plate = CollectionCoverPlate(collection: collection);
    final local = ref.watch(storyCoverOverrideProvider)?.call(collection);
    final url = collection.coverUrl;
    final ImageProvider? picture =
        local ??
        (url == null
            ? null
            : ResizeImage.resizeIfNeeded(
                StoryRowMetrics.cacheWidth(context, StoryRowMetrics.cover),
                null,
                CachedNetworkImageProvider(url),
              ));
    if (picture == null) return plate;
    return _StoryCoverPicture(image: picture, placeholder: plate);
  }
}

/// [image] laid out as a story circle draws a cover: whole, centred at
/// [kStoryCoverShare] of its box, over a blurred bed of itself bleeding past
/// the box. [placeholder] stands in until the picture is decoded, and if it
/// cannot be.
class _StoryCoverPicture extends StatelessWidget {
  const _StoryCoverPicture({required this.image, required this.placeholder});

  final ImageProvider image;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        if (!side.isFinite || side <= 0) return const SizedBox.shrink();
        final sigma = side * kStoryCoverBedBlur;
        return Image(
          image: image,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => placeholder,
          frameBuilder: (context, cover, frame, synchronous) {
            if (frame == null && !synchronous) return placeholder;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Decoded already: the bed draws in the same frame.
                ImageFiltered(
                  key: const ValueKey('story_cover_bed'),
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: sigma,
                    sigmaY: sigma,
                    tileMode: TileMode.clamp,
                  ),
                  child: Transform.scale(
                    scale: kStoryCoverBedBleed,
                    child: Image(
                      image: image,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                Center(
                  child: SizedBox.square(
                    key: const ValueKey('story_cover_whole'),
                    dimension: side * kStoryCoverShare,
                    child: cover,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A picture to draw in place of a collection's network cover. Null (the
/// app) draws the cover itself; previews and tests hand in local pictures.
@visibleForTesting
final storyCoverOverrideProvider =
    Provider<ImageProvider? Function(Collection collection)?>((ref) => null);

/// Where the circles of the Today row are, for the viewer: the circle it
/// grows out of and shrinks back into, and a circle to bring into view as
/// the reader moves on to another collection.
abstract class StoryAnchors {
  /// [slug]'s cover circle on screen, as painted, or null when it is not in
  /// view (scrolled off the row, or the row is gone).
  ///
  /// [whole] asks for a circle that is entirely in view, as a circle to land
  /// in must be. Without it a circle cut by the row's or the screen's edge
  /// counts while a real share of it shows: the circle the reader just
  /// tapped, which the viewer grows out of as it stands.
  Rect? rectOf(String slug, {bool whole = true});

  /// Scrolls the row, unseen behind the viewer, so [slug]'s circle is in
  /// view when the viewer closes.
  void reveal(String slug);
}

/// What the row says once a pull past its end has turned it Off: what
/// happened, and where it comes back from.
const String kStoryRowHiddenMessage =
    'Collection stories hidden. Turn them on again in Settings › '
    'Customization.';

/// A catalog read this long ago is read again when the app comes back to
/// Today ([TodayStoryRow]).
const Duration kStoryCatalogStale = Duration(minutes: 10);

/// Reads the stories' catalog again: Today's pull to refresh, and a return
/// to a Today left in the background. The row keeps its circles meanwhile;
/// what the new read holds (a new collection, a book's new games) lights
/// its ring. Off reads nothing.
void refreshStoryCatalog(WidgetRef ref) {
  if (ref.read(storyRowPrefsProvider).mode == StoryRowMode.off) return;
  ref.invalidate(collectionsProvider);
}

/// The stories at the top of Today: Missed Chances, recent collections and
/// rotating archive picks. Watched circles quieten in place. A skeleton of
/// the same geometry while the catalog loads.
///
/// The row stays while it is On, everything seen or not: watched circles
/// go grey, and the row is never empty of what the reader can come back to.
/// Pulled past its first or last circle it turns Off: the same choice as
/// Settings › Customization › Collection stories, which shows it at once,
/// with an Undo. Today's first frame already knows whether it is there
/// ([storyRowExpected]), so the list never jumps on launch.
///
/// [gutter] is the page's: the row scrolls edge to edge and starts and ends
/// on it.
class TodayStoryRow extends ConsumerStatefulWidget {
  const TodayStoryRow({super.key, required this.gutter});

  final double gutter;

  @override
  ConsumerState<TodayStoryRow> createState() => _TodayStoryRowState();
}

/// Which end of the row a pull is past.
enum _RowEdge { start, end }

class _TodayStoryRowState extends ConsumerState<TodayStoryRow>
    with TickerProviderStateMixin
    implements StoryAnchors {
  final ScrollController _scroll = ScrollController();
  final Map<String, BuildContext> _anchors = {};
  final GlobalKey _viewport = GlobalKey(debugLabel: 'story_row_viewport');

  /// The row's order, fixed while the row is on screen: a circle the reader
  /// just watched turns quiet where it is and moves behind the unseen ones
  /// the next time the row is built, never under the reader's eyes.
  List<Collection> _order = const [];
  List<String>? _orderedFrom;

  /// A failed catalog read is asked again on its own (an offline cold
  /// start), waiting longer each time, so the row comes back once the
  /// network does instead of staying gone for the session.
  Timer? _retry;
  Duration _retryDelay = const Duration(seconds: 8);

  // ------------------------------------------------------------ presence

  /// The row coming onto Today and leaving it: its height and its ink, 0
  /// gone to 1 there. Smooth, never past 1: the list under it moves up and
  /// down with it, and never overshoots.
  static const Motion _presenceMotion = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 460),
    snapToEnd: true,
  );

  late final SingleMotionController _presence = SingleMotionController(
    motion: _presenceMotion,
    vsync: this,
  )..addStatusListener(_onPresenceStatus);

  /// Whether the row is meant to be on Today; null before the first frame.
  bool? _shown;

  /// The row as last drawn, kept while it springs away.
  Widget? _lastContent;

  // ---------------------------------------------------------------- pull

  /// How far the pull past an end has gone toward [StoryRowMetrics.pullArm],
  /// 0 to 1: the indicator's fill.
  late final SingleMotionController _pull = SingleMotionController(
    motion: const CupertinoMotion.smooth(
      duration: Duration(milliseconds: 280),
      snapToEnd: true,
    ),
    vsync: this,
  );

  /// 1 while a release would put the row away: the indicator's disc.
  late final SingleMotionController _armedFill = SingleMotionController(
    motion: const CupertinoMotion.snappy(
      duration: Duration(milliseconds: 260),
      snapToEnd: true,
    ),
    vsync: this,
  );

  int? _pointer;
  double? _origin;
  _RowEdge? _edge;
  bool _armed = false;

  /// The end the indicator shows at, kept while it springs back.
  _RowEdge _shownEdge = _RowEdge.start;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    // The server holds the signed-in reader's choice, perhaps changed on
    // another device since this one last read it.
    scheduleMicrotask(() {
      if (mounted) unawaited(ref.read(storyRowPrefsProvider.notifier).pull());
    });
    // On again by any way (Settings, the server, Undo): the "hidden" snack
    // would now say the opposite of what Today shows, so it goes.
    ref.listenManual<StoryRowMode>(
      storyRowPrefsProvider.select((prefs) => prefs.mode),
      (_, mode) {
        if (mode == StoryRowMode.on) _retireHiddenSnack();
      },
    );
    ref.listenManual(storyVisitProvider, (_, __) {
      _refreshCatalogIfStale();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients || _pointer != null) return;
        _scroll.jumpTo(_scroll.position.minScrollExtent);
      });
    });
  }

  void _scheduleRetry() {
    if (_retry?.isActive ?? false) return;
    _retry = Timer(_retryDelay, () {
      if (!mounted) return;
      final next = _retryDelay * 2;
      _retryDelay = next > const Duration(minutes: 2)
          ? const Duration(minutes: 2)
          : next;
      ref.invalidate(collectionsProvider);
      ref.invalidate(storyCollectionsProvider);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _retry?.cancel();
    _missedWait?.cancel();
    _scroll.dispose();
    _presence.dispose();
    _pull.dispose();
    _armedFill.dispose();
    super.dispose();
  }

  List<Collection> _ordered(
    ({List<Collection> recent, List<Collection> archive}) lineup,
    StorySeenNotifier seen, {
    required Collection? missed,
    required StoryVisit visit,
    required bool viewerOpen,
  }) {
    if (viewerOpen && _order.isNotEmpty) return _order;
    // The order is fixed while the row is on screen; a circle watched just
    // now goes quiet where it stands. A circle that gets something new (a
    // game, an update: its signature changes) orders the row again, so it
    // lands leftmost the moment the catalog says so.
    final all = [?missed, ...lineup.recent, ...lineup.archive];
    final slugs = [
      '${visit.rotation}|${lineup.recent.length}',
      for (final c in all) '${c.slug}|${storySignature(c)}',
    ];
    if (!listEquals(slugs, _orderedFrom)) {
      _orderedFrom = slugs;
      _order = [
        ?missed,
        ...orderStoryCollections(lineup.recent, seen.isSeen),
        ...lineup.archive,
      ];
    } else {
      // Same collections: keep the order, take the fresh rows.
      final bySlug = {for (final c in all) c.slug: c};
      _order = [for (final c in _order) bySlug[c.slug] ?? c];
    }
    return _order;
  }

  @override
  Rect? rectOf(String slug, {bool whole = true}) {
    if (!mounted) return null;
    final anchor = _anchors[slug];
    final viewport = _viewport.currentContext?.findRenderObject();
    if (anchor == null || !anchor.mounted || viewport is! RenderBox) {
      return null;
    }
    final box = anchor.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (!viewport.attached || !viewport.hasSize) return null;
    // At rest: the anchor is the item outside its press, and the cover sits
    // centred in the ring's square at its top. A circle still springing back
    // from a tap is where it settles, so the viewer lands where the circle
    // will be, not where it was mid-press.
    final inset = (StoryRowMetrics.item - StoryRowMetrics.cover) / 2;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Rect.fromLTWH(inset, inset, StoryRowMetrics.cover, StoryRowMetrics.cover),
    );
    final row = viewport.localToGlobal(Offset.zero) & viewport.size;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final inRow = rect.left >= row.left - 0.5 && rect.right <= row.right + 0.5;
    final onScreen =
        rect.top >= top - 0.5 &&
        rect.bottom <= screen.bottom + 0.5 &&
        rect.left >= -0.5 &&
        rect.right <= screen.right + 0.5;
    if (inRow && onScreen) return rect;
    if (whole) return null;
    final shown = rect
        .intersect(row)
        .intersect(Rect.fromLTRB(0, top, screen.right, screen.bottom));
    final share = StoryRowMetrics.partShown;
    return shown.width >= rect.width * share &&
            shown.height >= rect.height * share
        ? rect
        : null;
  }

  @override
  void reveal(String slug) {
    if (!mounted || !_scroll.hasClients) return;
    final index = _order.indexWhere((c) => c.slug == slug);
    if (index < 0) return;
    final position = _scroll.position;
    final start = widget.gutter + index * StoryRowMetrics.pitch;
    final end = start + StoryRowMetrics.item;
    final view = position.viewportDimension;
    double? target;
    if (start - widget.gutter < position.pixels) {
      target = start - widget.gutter;
    } else if (end + widget.gutter > position.pixels + view) {
      target = end + widget.gutter - view;
    }
    if (target == null) return;
    _scroll.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void _open(Collection collection) {
    final index = _order.indexOf(collection);
    if (index < 0) return;
    HapticFeedbackService.cardTap();
    openCollectionStories(
      context,
      collections: List.unmodifiable(_order),
      initialIndex: index,
      // Out of the circle where it stands, cut by an edge or not: the row
      // is brought round to it only once the viewer hides it.
      origin: rectOf(collection.slug, whole: false),
      anchors: this,
    );
  }

  void _openPage(Collection collection) {
    final page = ref.read(storyCollectionPageProvider);
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page(collection)));
  }

  // ------------------------------------------------------------ presence

  /// Sets where the row is going: at once on the first frame (it is laid
  /// out where it belongs), on its spring after.
  void _setShown(bool shown) {
    if (_shown == shown) return;
    final first = _shown == null;
    _shown = shown;
    if (first) {
      _presence.value = shown ? 1 : 0;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shown != shown) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _presence.value = shown ? 1 : 0;
        if (!shown) setState(() => _lastContent = null);
        return;
      }
      unawaited(_presence.animateTo(shown ? 1 : 0));
    });
  }

  /// Gone: its drawing is let go.
  void _onPresenceStatus(AnimationStatus status) {
    if (!mounted || _shown != false || _presence.value > 0.001) return;
    if (_lastContent != null) setState(() => _lastContent = null);
  }

  // ------------------------------------------------------------ freshness

  /// When the row last had the catalog read, by the row's clock.
  DateTime? _catalogReadAt;

  /// The catalog the row last saw arrive, to tell a new read from a rebuild.
  List<Collection>? _arrived;

  /// Back from the background: the day may have turned (a new day of
  /// Missed chances), and a catalog read long ago is read again, so what
  /// arrived meanwhile shows (new circles, lit rings) without a cold
  /// start.
  void _onResume() {
    if (!mounted) return;
    _refreshCatalogIfStale();
    setState(() {});
  }

  void _refreshCatalogIfStale() {
    final readAt = _catalogReadAt;
    final now = ref.read(storyClockProvider)();
    if (readAt != null && now.difference(readAt) >= kStoryCatalogStale) {
      _catalogReadAt = now;
      refreshStoryCatalog(ref);
    }
  }

  /// A catalog read where a collection changed since its stories were read
  /// (a new game, an update): those stories are read again (they are kept
  /// warm for a few minutes), so opening its lit ring shows what is new.
  void _onCatalogArrived(List<Collection> list) {
    _catalogReadAt = ref.read(storyClockProvider)();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final c in list) {
        final batch = storyBatchProvider(c.slug);
        if (!ref.exists(batch)) continue;
        final read = ref.read(batch).valueOrNull;
        if (read == null) continue;
        final grew = (read.gameCount ?? c.gameCount) < c.gameCount;
        final changed =
            read.signature != null && read.signature != storySignature(c);
        if (!grew && !changed) continue;
        ref.invalidate(collectionDetailProvider(c.slug));
        ref.invalidate(collectionGamesProvider(c.slug));
      }
    });
  }

  // ---------------------------------------------------------------- pull

  /// Which way a finger moves to pull past [edge]: +1 to the right.
  double _outward(_RowEdge edge, AxisDirection direction) {
    final ltr = direction == AxisDirection.right;
    return edge == _RowEdge.start ? (ltr ? 1 : -1) : (ltr ? -1 : 1);
  }

  /// Only the finger's own travel past an end counts, never a fling that
  /// carries the row there.
  bool _onRowScroll(ScrollNotification notification) {
    if (_pointer == null ||
        _shown != true ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    final DragUpdateDetails? drag = switch (notification) {
      ScrollUpdateNotification(:final dragDetails) => dragDetails,
      OverscrollNotification(:final dragDetails) => dragDetails,
      _ => null,
    };
    if (drag == null) return false;
    final metrics = notification.metrics;
    final before = metrics.minScrollExtent - metrics.pixels;
    final after = metrics.pixels - metrics.maxScrollExtent;
    _RowEdge? edge;
    if (notification is OverscrollNotification) {
      edge = notification.overscroll < 0 ? _RowEdge.start : _RowEdge.end;
    } else if (before > 0) {
      edge = _RowEdge.start;
    } else if (after > 0) {
      edge = _RowEdge.end;
    }
    if (edge == null) {
      // Back inside the row: the pull is over.
      if (_origin != null) _releasePull();
      return false;
    }
    final outward = _outward(edge, metrics.axisDirection);
    final x = drag.globalPosition.dx;
    if (_origin == null || _edge != edge) {
      _edge = edge;
      _shownEdge = edge;
      final past = edge == _RowEdge.start ? before : after;
      _origin = x - outward * (past > 0 ? past : 0);
    }
    _track(((x - _origin!) * outward).clamp(0.0, double.infinity));
    return false;
  }

  void _track(double travel) {
    final ceiling = StoryRowMetrics.pullCeiling;
    final shown = ceiling * (1 - 1 / (travel * 0.85 / ceiling + 1));
    final armed = shown >= StoryRowMetrics.pullArm;
    if (armed != _armed) {
      _armed = armed;
      if (armed) unawaited(HapticFeedbackService.selection());
      unawaited(_armedFill.animateTo(armed ? 1 : 0));
    }
    _pull.stop(canceled: true);
    _pull.value = (shown / StoryRowMetrics.pullArm).clamp(0.0, 1.0);
  }

  /// The pull let go short, or taken back inside: the indicator empties.
  void _releasePull() {
    _origin = null;
    _edge = null;
    if (_armed) {
      _armed = false;
      unawaited(_armedFill.animateTo(0));
    }
    if (_pull.value > 0) unawaited(_pull.animateTo(0));
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final hide = _armed;
    _releasePull();
    if (hide) unawaited(_hide());
  }

  void _onPointerCancel(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _releasePull();
  }

  /// Turns the row Off: the one choice Settings › Customization ›
  /// Collection stories shows, changed here, with Undo turning it On again.
  /// Off is Premium, as in Settings: a reader without it goes through the
  /// subscription flow first, and backing out leaves the row On. Undo (On)
  /// is free.
  Future<void> _hide() async {
    if (!mounted) return;
    final allowed = await mayChooseStoryRowMode(
      context,
      ref,
      StoryRowMode.off,
      returnTo: 'home',
    );
    if (!mounted || !allowed) return;
    unawaited(HapticFeedbackService.success());
    final notifier = ref.read(storyRowPrefsProvider.notifier);
    unawaited(notifier.setMode(StoryRowMode.off));
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final snack = showAppSnackOn(
      messenger,
      kStoryRowHiddenMessage,
      actionLabel: 'Undo',
      onAction: () => notifier.setMode(StoryRowMode.on),
    );
    _hiddenSnack = (snack: snack, messenger: messenger);
    unawaited(
      snack.closed.then((_) {
        if (identical(_hiddenSnack?.snack, snack)) _hiddenSnack = null;
      }),
    );
  }

  /// The "hidden" snack while it is still up.
  ({
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> snack,
    ScaffoldMessengerState messenger,
  })?
  _hiddenSnack;

  /// Takes the "hidden" snack down, if it is still up. Every snack raised
  /// retires the one before it ([showAppSnackOn]), so while this one has not
  /// closed it is the one showing, or the one leaving for a newer message:
  /// hiding the current snack hides it and never touches that newer one.
  void _retireHiddenSnack() {
    final hidden = _hiddenSnack;
    _hiddenSnack = null;
    if (hidden == null || !hidden.messenger.mounted) return;
    hidden.messenger.hideCurrentSnackBar();
  }

  // --------------------------------------------------------------- build

  /// The day the Missed chances circle was last read for: a new day reads
  /// a new set.
  String? _missedDay;

  /// The catalog has been here this long without the Missed chances read:
  /// the row shows without that circle rather than wait on it.
  bool _missedWaitOver = false;
  Timer? _missedWait;

  /// How long the row waits for Missed chances once the catalog is in, so
  /// the circle does not arrive after the rest and move them.
  static const Duration _missedPatience = Duration(milliseconds: 2500);

  /// The Missed chances circle for today, when the day's read holds a game;
  /// null while it is still worth waiting for ([_missedWaitOver]).
  ({bool waiting, Collection? circle}) _missedCircle(DateTime now) {
    final day = storyDayKey(now);
    if (_missedDay != day) {
      if (_missedDay != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.invalidate(missedChancesBatchProvider);
        });
      }
      _missedDay = day;
    }
    final read = ref.watch(storyBatchProvider(kMissedChancesSlug));
    final batch = read.valueOrNull;
    if (batch != null) {
      return (
        waiting: false,
        circle: batch.games.isEmpty ? null : missedChancesCollection(now),
      );
    }
    if (read.hasError) return (waiting: false, circle: null);
    _missedWait ??= Timer(_missedPatience, () {
      if (mounted) setState(() => _missedWaitOver = true);
    });
    return (waiting: !_missedWaitOver, circle: null);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(storyRowPrefsProvider);
    final now = ref.watch(storyClockProvider)();
    final Widget? content;
    final bool shown;
    if (prefs.mode == StoryRowMode.off) {
      // Off: the catalog is not even read.
      shown = false;
      content = null;
    } else {
      final collections = ref.watch(storyCollectionsProvider);
      final seenRecord = ref.watch(storySeenProvider);
      final visit = ref.watch(storyVisitProvider);
      final viewerOpen = ref.watch(storyViewerOpenProvider);
      final catalog = collections.valueOrNull;
      final missed = catalog == null && !collections.hasError
          ? (waiting: false, circle: null)
          : _missedCircle(now);
      if (catalog == null && collections.hasError) {
        _scheduleRetry();
      }
      final list =
          catalog ?? (collections.hasError ? const <Collection>[] : null);
      if (list == null ||
          seenRecord == null ||
          (missed.waiting && _order.isEmpty)) {
        // Loading: the device's copy says whether the row will be there, so
        // a row that stays away never shows its skeleton.
        if (list == null) _retryDelay = const Duration(seconds: 8);
        shown = storyRowExpected(prefs);
        content = shown ? _StoryRowSkeleton(gutter: widget.gutter) : null;
      } else {
        if (catalog != null) {
          _retryDelay = const Duration(seconds: 8);
          if (!identical(catalog, _arrived)) {
            _arrived = catalog;
            _onCatalogArrived(catalog);
          }
        }
        final seen = ref.read(storySeenProvider.notifier);
        final lineup = selectStoryCollections(
          list,
          visit: visit,
          hasMissedChances: missed.circle != null,
        );
        if (_shown == false) _orderedFrom = null;
        final circles = _ordered(
          lineup,
          seen,
          missed: missed.circle,
          visit: visit,
          viewerOpen: viewerOpen,
        );
        shown = circles.isNotEmpty;
        // Drawn while it is there or still springing away.
        content = shown ? _row(circles, seen) : null;
      }
    }
    _setShown(shown);
    if (content != null) _lastContent = content;
    return _StoryRowPresence(
      presence: _presence,
      child: shown ? content : (content ?? _lastContent),
    );
  }

  Widget _row(List<Collection> order, StorySeenNotifier seen) {
    return Semantics(
      container: true,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Hide collection stories'): () =>
            unawaited(_hide()),
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: StoryRowMetrics.bottom),
        child: SizedBox(
          key: _viewport,
          height: StoryRowMetrics.height,
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _onRowScroll,
                child: Listener(
                  onPointerDown: (event) => _pointer ??= event.pointer,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: ListView.builder(
                    key: const PageStorageKey<String>('today_story_row'),
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    // Today's own bounce, on every platform: the room a
                    // pull opens past an end is where its indicator fills.
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: EdgeInsetsDirectional.only(
                      start: widget.gutter,
                      end: widget.gutter - StoryRowMetrics.spacing,
                    ),
                    itemExtent: StoryRowMetrics.pitch,
                    itemCount: order.length,
                    itemBuilder: (context, index) {
                      final c = order[index];
                      final isSeen = seen.isSeen(c);
                      return Align(
                        alignment: AlignmentDirectional.topStart,
                        child: _StoryCircle(
                          key: ValueKey('story_circle_${c.slug}'),
                          collection: c,
                          seen: isSeen,
                          onAnchor: (anchor, {required bool mounted}) {
                            if (mounted) {
                              _anchors[c.slug] = anchor;
                            } else if (identical(_anchors[c.slug], anchor)) {
                              _anchors.remove(c.slug);
                            }
                          },
                          onOpen: () => _open(c),
                          onOpenPage: () => _openPage(c),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: _StoryRowPullMark(
                    scroll: _scroll,
                    pull: _pull,
                    armed: _armedFill,
                    edge: () => _shownEdge,
                    gutter: widget.gutter,
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

/// The row on Today at [presence]: its height and its ink together, so the
/// list under it moves with it and nothing jumps. Its tree stays the same
/// shape at every value, so a row springing in or out keeps its scroll.
class _StoryRowPresence extends StatelessWidget {
  const _StoryRowPresence({required this.presence, required this.child});

  final Animation<double> presence;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    return AnimatedBuilder(
      animation: presence,
      child: child,
      builder: (context, child) {
        final v = presence.value.clamp(0.0, 1.0);
        if (v <= 0.001 || child == null) {
          return const SizedBox(
            key: ValueKey('story_row_gone'),
            width: double.infinity,
          );
        }
        return ClipRect(
          clipBehavior: v < 1 ? Clip.hardEdge : Clip.none,
          child: Align(
            key: const ValueKey('story_row_presence'),
            alignment: AlignmentDirectional.topStart,
            heightFactor: v,
            child: Opacity(opacity: (v * 1.6).clamp(0.0, 1.0), child: child),
          ),
        );
      },
    );
  }
}

/// The mark a pull past either end of the row opens room for: a small
/// circle whose ring fills with the pull and, once letting go would put the
/// row away, closes into a disc with a bar across it. It sits in the room
/// the row's bounce opens, centred on the circles, and grows with that room
/// from the pull's first points, so the pull answers at once.
class _StoryRowPullMark extends StatelessWidget {
  const _StoryRowPullMark({
    required this.scroll,
    required this.pull,
    required this.armed,
    required this.edge,
    required this.gutter,
  });

  final ScrollController scroll;
  final Animation<double> pull;
  final Animation<double> armed;
  final _RowEdge Function() edge;
  final double gutter;

  /// The air the mark keeps from the gutter and from the circle.
  static const double clear = 3;

  /// The mark is drawn from this size on: smaller, it is a speck.
  static const double minSize = 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: Listenable.merge([scroll, pull, armed]),
      builder: (context, _) {
        final progress = pull.value.clamp(0.0, 1.0);
        if (progress <= 0.001 || !scroll.hasClients) {
          return const SizedBox.shrink();
        }
        final position = scroll.position;
        if (!position.hasPixels || !position.hasContentDimensions) {
          return const SizedBox.shrink();
        }
        final atStart = edge() == _RowEdge.start;
        // The room the pull opened between the page's gutter and the
        // first (or last) circle.
        final gap =
            (atStart
                    ? position.minScrollExtent - position.pixels
                    : position.pixels - position.maxScrollExtent)
                .clamp(0.0, double.infinity);
        // From the pull's first points: the mark grows with the room the
        // pull opens, centred in it and clear of the gutter and the circle
        // by [_StoryRowPullMark.clear] on each side, to its full size once
        // the room holds it, then stays centred as the room widens.
        final full = StoryRowMetrics.pullMark;
        final size = (gap - 2 * clear).clamp(0.0, full);
        if (size < minSize) return const SizedBox.shrink();
        // Ink comes in over its first few points of size, never a pop.
        final ink = ((size - minSize) / 4).clamp(0.0, 1.0);
        final onLeft = atStart != rtl;
        final offset = gutter + (gap - size) / 2;
        return Stack(
          children: [
            Positioned(
              key: const ValueKey('story_row_pull_mark'),
              left: onLeft ? offset : null,
              right: onLeft ? null : offset,
              top: StoryRowMetrics.item / 2 - size / 2,
              width: size,
              height: size,
              child: Semantics(
                liveRegion: armed.value > 0.5,
                label: armed.value > 0.5
                    ? 'Release to hide collection stories'
                    : 'Pull further to hide collection stories',
                child: Opacity(
                  opacity: ink,
                  child: CustomPaint(
                    painter: StoryPullMarkPainter(
                      progress: progress,
                      armed: armed.value.clamp(0.0, 1.0),
                      ink: colors.textPrimary,
                      page: colors.background,
                      track: colors.textPrimary.withValues(
                        alpha: context.isLightTheme ? 0.16 : 0.22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Draws the row's pull mark: a track ring, the pull's arc over it from the
/// top with round caps, and once armed a disc that grows from the centre
/// with a bar across it, centred on the disc.
@visibleForTesting
class StoryPullMarkPainter extends CustomPainter {
  const StoryPullMarkPainter({
    required this.progress,
    required this.armed,
    required this.ink,
    required this.page,
    required this.track,
  });

  /// The arc's share of the ring, 0 to 1.
  final double progress;

  /// The disc's share of its full size, 0 to 1.
  final double armed;
  final Color ink;
  final Color page;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = size.shortestSide * 0.09;
    final radius = size.shortestSide / 2 - stroke / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, ring);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = ink,
      );
    }
    if (armed > 0) {
      final disc = (radius + stroke / 2) * armed;
      canvas.drawCircle(center, disc, Paint()..color = ink);
      final half = disc * 0.42;
      canvas.drawLine(
        center - Offset(half, 0),
        center + Offset(half, 0),
        Paint()
          ..strokeWidth = stroke * 1.1
          ..strokeCap = StrokeCap.round
          ..color = page.withValues(alpha: armed),
      );
    }
  }

  @override
  bool shouldRepaint(StoryPullMarkPainter old) =>
      old.progress != progress ||
      old.armed != armed ||
      old.ink != ink ||
      old.page != page ||
      old.track != track;
}

/// One collection of the row: its cover in its ring, its name under it.
/// Tapped, its stories open out of the circle; held, it lifts into the
/// collection's own focus menu.
class _StoryCircle extends ConsumerWidget {
  const _StoryCircle({
    super.key,
    required this.collection,
    required this.seen,
    required this.onAnchor,
    required this.onOpen,
    required this.onOpenPage,
  });

  final Collection collection;
  final bool seen;
  final StoryAnchorReport onAnchor;
  final VoidCallback onOpen;
  final VoidCallback onOpenPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final face = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      // Outside the press: the circle is measured where it rests.
      child: _AnchorReporter(
        onAnchor: onAnchor,
        child: PressSpring(
          delay: const Duration(milliseconds: 70),
          child: ExcludeSemantics(
            child: StoryCircleFace(collection: collection, seen: seen),
          ),
        ),
      ),
    );
    if (isMissedChances(collection)) {
      // Not a collection: no collection menu to hold it into.
      return Semantics(
        container: true,
        button: true,
        label: '${collection.title}, ${seen ? 'stories seen' : 'new stories'}',
        child: face,
      );
    }
    // One button for the screen reader: its tap opens the stories, its
    // long-press the collection's menu (both from the detectors below).
    return Semantics(
      container: true,
      button: true,
      label: '${collection.title}, ${seen ? 'stories seen' : 'new stories'}',
      child: CardContextMenu(
        actions: (menuContext) => collectionMenuActions(
          context,
          menuContext,
          ref,
          collection,
          onOpen: onOpenPage,
        ),
        previewBuilder: (_) =>
            StoryCircleFace(collection: collection, seen: seen),
        onPreviewTap: onOpenPage,
        child: face,
      ),
    );
  }
}

/// The drawing of one row item: the ring, the cover, the name.
class StoryCircleFace extends StatelessWidget {
  const StoryCircleFace({
    super.key,
    required this.collection,
    required this.seen,
  });

  final Collection collection;
  final bool seen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ring = seen ? StoryRowMetrics.ringSeen : StoryRowMetrics.ringUnseen;
    final cover = StoryCover(
      collection: collection,
      diameter: StoryRowMetrics.cover,
    );
    return SizedBox(
      width: StoryRowMetrics.item,
      height: StoryRowMetrics.height,
      child: Column(
        children: [
          SizedBox.square(
            dimension: StoryRowMetrics.item,
            child: DecoratedBox(
              key: const ValueKey('story_ring'),
              // A solid ring, inside the item's edge: the brand's tonal blue
              // while there is something new, a quiet hairline once seen.
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: seen
                      ? colors.dividerStrong
                      : StoryRowMetrics.unseenRing(context),
                  width: ring,
                ),
              ),
              child: Center(child: cover),
            ),
          ),
          SizedBox(height: StoryRowMetrics.labelGap),
          SizedBox(
            width: StoryRowMetrics.item,
            height: StoryRowMetrics.labelHeight,
            child: CappedTextScale(
              child: Text(
                collection.title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                textAlign: TextAlign.center,
                style: StoryRowMetrics.labelType().copyWith(
                  color: seen ? colors.textSecondary : colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a row item is (its context, the cover centred in the top of it),
/// while it is [mounted].
typedef StoryAnchorReport =
    void Function(BuildContext anchor, {required bool mounted});

/// Hands its context to [onAnchor] while it is mounted.
class _AnchorReporter extends StatefulWidget {
  const _AnchorReporter({required this.onAnchor, required this.child});

  final StoryAnchorReport onAnchor;
  final Widget child;

  @override
  State<_AnchorReporter> createState() => _AnchorReporterState();
}

class _AnchorReporterState extends State<_AnchorReporter> {
  @override
  void initState() {
    super.initState();
    widget.onAnchor(context, mounted: true);
  }

  @override
  void didUpdateWidget(covariant _AnchorReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.onAnchor(context, mounted: true);
  }

  @override
  void dispose() {
    widget.onAnchor(context, mounted: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The row while the collections load: the same circles and names, as
/// bones, so nothing moves when they land.
class _StoryRowSkeleton extends StatelessWidget {
  const _StoryRowSkeleton({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: StoryRowMetrics.bottom),
      child: SizedBox(
        key: const ValueKey('story_row_skeleton'),
        height: StoryRowMetrics.height,
        child: ClipRect(
          child: OverflowBox(
            alignment: AlignmentDirectional.centerStart,
            maxWidth: double.infinity,
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: gutter),
              child: SkeletonWidget(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < kStoryLineupSize; i++)
                      Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: StoryRowMetrics.spacing,
                        ),
                        child: SizedBox(
                          width: StoryRowMetrics.item,
                          child: Column(
                            children: [
                              Bone.circle(size: StoryRowMetrics.item),
                              // Centred on the name's line as it sits at
                              // its usual size.
                              SizedBox(
                                height:
                                    StoryRowMetrics.labelGap +
                                    (15.sp - 10.sp) / 2,
                              ),
                              Bone(
                                width: StoryRowMetrics.item * 0.72,
                                height: 10.sp,
                                borderRadius: BorderRadius.circular(5.sp),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Missed chances circle's own mark, drawn instead of a cover: a crop
/// of the reader's board, one square ringed in the missed win's coral, and
/// an arrow that stops one square short of it. The win was there; the move
/// played did not reach it. The drawing stands at [kStoryCoverShare] of the
/// circle, as a cover does, with the board running on to the rim.
class MissedChancesMark extends ConsumerWidget {
  const MissedChancesMark({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme =
        (ref.watch(boardSettingsProviderNew).valueOrNull ??
                const BoardSettingsNew())
            .colorScheme;
    return ExcludeSemantics(
      child: CustomPaint(
        key: const ValueKey('missed_chances_mark'),
        painter: MissedChancesMarkPainter(
          light: scheme.lightSquare,
          dark: scheme.darkSquare,
          ring: moveAnnotationColor(LichessMoveAnnotationType.missedWin),
          share: kStoryCoverShare,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Paints [MissedChancesMark] into any square: a 5 by 5 crop of the board
/// whose middle three squares each way hold the drawing, so the circle's
/// edge never cuts it. The crop spans [share] of the square, centred; the
/// board's squares run on past it to the edges.
@visibleForTesting
class MissedChancesMarkPainter extends CustomPainter {
  const MissedChancesMarkPainter({
    required this.light,
    required this.dark,
    required this.ring,
    this.share = 1,
  });

  final Color light;
  final Color dark;
  final Color ring;

  /// The share of the square the 5 by 5 crop spans.
  final double share;

  /// The arrow's ink: near-black, a touch see-through, as the board's own
  /// arrows lie on the squares.
  static const Color ink = Color(0xD9101314);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final side = size.shortestSide;
    final cell = side * share / 5;
    // The crop's corner, the crop centred in the square.
    final origin = Offset(
      (size.width - 5 * cell) / 2,
      (size.height - 5 * cell) / 2,
    );
    // Whole squares beyond the crop on each side, enough to reach the edges.
    final beyondX = (origin.dx / cell).ceil();
    final beyondY = (origin.dy / cell).ceil();
    final squares = Paint();
    for (var row = -beyondY; row < 5 + beyondY; row++) {
      for (var col = -beyondX; col < 5 + beyondX; col++) {
        squares.color = (row + col).isEven ? light : dark;
        canvas.drawRect(
          Rect.fromLTWH(
            origin.dx + col * cell,
            origin.dy + row * cell,
            cell + 0.5,
            cell + 0.5,
          ),
          squares,
        );
      }
    }
    Offset centre(int col, int row) =>
        origin + Offset((col + 0.5) * cell, (row + 0.5) * cell);
    // The win: a ring inside its square.
    canvas.drawCircle(
      centre(3, 1),
      cell * 0.36,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.13
        ..color = ring,
    );
    // The move played: from b2 toward the ring, landing a square short.
    final from = centre(1, 3);
    final to = centre(2, 2);
    final direction = (to - from) / (to - from).distance;
    final normal = Offset(-direction.dy, direction.dx);
    final head = cell * 0.42;
    final tip = to + direction * cell * 0.18;
    final base = tip - direction * head;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.2
      ..strokeCap = StrokeCap.round
      ..color = ink;
    canvas.drawLine(from, base + direction * cell * 0.02, stroke);
    final arrowHead = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        base.dx + normal.dx * head * 0.62,
        base.dy + normal.dy * head * 0.62,
      )
      ..lineTo(
        base.dx - normal.dx * head * 0.62,
        base.dy - normal.dy * head * 0.62,
      )
      ..close();
    canvas.drawPath(
      arrowHead,
      Paint()
        ..color = ink
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(MissedChancesMarkPainter old) =>
      old.light != light ||
      old.dark != dark ||
      old.ring != ring ||
      old.share != share;
}

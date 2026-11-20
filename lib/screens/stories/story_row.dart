import 'dart:async';

import 'package:chessever2/screens/collections/collections_screen.dart'
    show CollectionCover, CollectionScreen, collectionMenuActions;
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/screens/stories/story_viewer.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/text_scale.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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

/// A collection's cover cropped into a circle of [diameter], as the row and
/// the viewer's header draw it.
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

/// A collection's cover filling its box (cropped to it), decoded at the
/// row circle's size so the row, the viewer's header and its way in and out
/// all share one decoded picture.
///
/// [full] decodes the whole cover instead, for a picture drawn large (the
/// See all story).
class StoryCoverImage extends ConsumerWidget {
  const StoryCoverImage({
    super.key,
    required this.collection,
    this.full = false,
  });

  final Collection collection;
  final bool full;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(storyCoverOverrideProvider)?.call(collection);
    if (local != null) {
      return Image(image: local, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return CollectionCover(
      collection: collection,
      cacheWidth: full
          ? null
          : StoryRowMetrics.cacheWidth(context, StoryRowMetrics.cover),
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

/// The collections' story row at the top of Today: one circle per
/// collection, the ones with stories the reader has not seen first. Hidden
/// when there are none; a skeleton of the same geometry while they load.
///
/// [gutter] is the page's: the row scrolls edge to edge and starts and ends
/// on it.
class TodayStoryRow extends ConsumerStatefulWidget {
  const TodayStoryRow({super.key, required this.gutter});

  final double gutter;

  @override
  ConsumerState<TodayStoryRow> createState() => _TodayStoryRowState();
}

class _TodayStoryRowState extends ConsumerState<TodayStoryRow>
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
    _retry?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  List<Collection> _ordered(
    List<Collection> collections,
    StorySeenNotifier seen,
  ) {
    final slugs = [for (final c in collections) c.slug];
    if (!listEquals(slugs, _orderedFrom)) {
      _orderedFrom = slugs;
      _order = orderStoryCollections(
        collections,
        (c) => seen.isSeen(c.slug, storySignature(c)),
      );
    } else {
      // Same collections: keep the order, take the fresh rows.
      final bySlug = {for (final c in collections) c.slug: c};
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CollectionScreen(collection: collection),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(storyCollectionsProvider);
    final seenRecord = ref.watch(storySeenProvider);
    final list = collections.valueOrNull;
    if (list == null && collections.hasError) {
      _scheduleRetry();
      return const SizedBox.shrink();
    }
    _retryDelay = const Duration(seconds: 8);
    if (list != null && list.isEmpty) return const SizedBox.shrink();
    if (list == null || seenRecord == null) {
      return _StoryRowSkeleton(gutter: widget.gutter);
    }
    final seen = ref.read(storySeenProvider.notifier);
    final order = _ordered(list, seen);
    return Padding(
      padding: EdgeInsets.only(bottom: StoryRowMetrics.bottom),
      child: SizedBox(
        key: _viewport,
        height: StoryRowMetrics.height,
        child: ListView.builder(
          key: const PageStorageKey<String>('today_story_row'),
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          // The platform's own physics: a bounce on iOS, a clamp on Android.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsetsDirectional.only(
            start: widget.gutter,
            end: widget.gutter - StoryRowMetrics.spacing,
          ),
          itemExtent: StoryRowMetrics.pitch,
          itemCount: order.length,
          itemBuilder: (context, index) {
            final c = order[index];
            return Align(
              alignment: AlignmentDirectional.topStart,
              child: _StoryCircle(
                key: ValueKey('story_circle_${c.slug}'),
                collection: c,
                seen: seen.isSeen(c.slug, storySignature(c)),
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
    );
  }
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
        child: GestureDetector(
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
        ),
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
                    for (var i = 0; i < 6; i++)
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

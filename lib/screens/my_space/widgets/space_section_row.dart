import 'dart:async';

import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_sheet_session_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_auto_tile.dart';
import 'package:chessever2/screens/my_space/widgets/space_door.dart';
import 'package:chessever2/screens/my_space/widgets/space_door_actions.dart';
import 'package:chessever2/screens/my_space/widgets/space_metrics.dart';
import 'package:chessever2/screens/my_space/widgets/space_reorder.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_screen.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

const _doorKey = ValueKey<String>('__space_door__');

/// One My Space row: a header (title, count, "See all") over a single
/// horizontal rail whose first tile is always the row's door. After the door
/// come the row's live mirror (the Library tab, My Likes), then its pins, then
/// its suggestions. An empty row is still shown, its door stretched across
/// the full width.
class SpaceSectionRow extends ConsumerStatefulWidget {
  const SpaceSectionRow({
    super.key,
    required this.section,
    required this.items,
    required this.availableWidth,
    required this.topGap,
    this.ready = true,
  });

  final SpaceSection section;
  final List<SpaceShortcut> items;

  /// Width of the page the rail spans, gutters included.
  final double availableWidth;

  /// Space above the header. The "See all" hit area grows into it, so the
  /// 28pt header still gets a full-size touch target.
  final double topGap;

  /// False while the stored list is still being read. Nothing counts as
  /// "arrived" until the first real list lands, so a cold start never pops
  /// every tile in.
  final bool ready;

  @override
  ConsumerState<SpaceSectionRow> createState() => _SpaceSectionRowState();
}

class _SpaceSectionRowState extends ConsumerState<SpaceSectionRow> {
  Set<String>? _known;

  /// Mirror and suggestion keys the row already showed, once its sources
  /// settled; anything new after that springs in.
  Set<String>? _knownAuto;

  /// The pins as the row shows them: the store's, less any a mirrored tile
  /// stands for and any an open add sheet is still holding back.
  List<SpaceShortcut> _pins = const [];

  /// The rail's own scroll, so a sheet that added to the front can bring the
  /// row back to where the new tiles land.
  final ScrollController _rail = ScrollController();

  /// The row as a drag in progress shows it; null when nothing is lifted.
  /// Owned here, never written to the store until the drop.
  List<String>? _order;
  String? _dragKey;

  /// When the shortcut open in flight started, shared by every row: most
  /// kinds await the network before they push, and a second tap in that
  /// window would push the destination twice. Null when nothing is opening.
  static DateTime? _openingSince;

  /// A hung request must not leave every tile dead: past this the guard
  /// lets the next tap through.
  static const _openGuardCap = Duration(seconds: 10);

  /// The last reorder spoken to a screen reader where the platform only
  /// speaks live regions (Android). Empty until the first move.
  String _announcement = '';

  // ---------------------------------------------------------------- actions

  SpaceShortcut? _current(SpaceShortcut s) {
    final list = ref.read(spaceShortcutsProvider).valueOrNull ?? const [];
    for (final item in list) {
      if (item.key == s.key) return item;
    }
    return null;
  }

  void _open(SpaceShortcut s) {
    _guardedOpen(() {
      HapticFeedbackService.cardTap();
      return openSpaceShortcut(context, ref, _current(s) ?? s);
    });
  }

  /// Runs [open] unless another open is still in flight.
  void _guardedOpen(Future<void> Function() open) {
    final pending = _openingSince;
    if (pending != null && DateTime.now().difference(pending) < _openGuardCap) {
      return;
    }
    final since = _openingSince = DateTime.now();
    unawaited(
      open()
          .catchError((Object e) {
            debugPrint('[MySpace] open failed: $e');
          })
          .whenComplete(() {
            if (identical(_openingSince, since)) _openingSince = null;
          }),
    );
  }

  @override
  void dispose() {
    _rail.dispose();
    super.dispose();
  }

  Future<void> _moveToFront(SpaceShortcut s) async {
    final current = _current(s);
    if (current == null) return;
    HapticFeedbackService.light();
    final write = ref
        .read(spaceShortcutsProvider.notifier)
        .moveToFront(current.id);
    _announceMove(current, 0);
    await write;
  }

  /// Tells a screen reader where a moved tile landed (WCAG 4.1.3): an
  /// announcement where the platform speaks one, a live region elsewhere.
  void _announceMove(SpaceShortcut s, int to) {
    if (!mounted) return;
    final message = 'Moved ${s.title} to position ${to + 1} of ${_pins.length}';
    if (MediaQuery.maybeSupportsAnnounceOf(context) ?? false) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          Directionality.of(context),
        ).catchError((Object _) {}),
      );
    } else {
      setState(() => _announcement = message);
    }
  }

  /// Commits a removal the tile has already animated. The store updates
  /// synchronously, so the Undo snack lands the moment the tile is gone; the
  /// network delete finishes behind it.
  Future<bool> _remove(SpaceShortcut s) async {
    final current = _current(s);
    if (current == null) return false;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final notifier = ref.read(spaceShortcutsProvider.notifier);
    unawaited(notifier.removeTarget(current.kind, current.targetId));
    if (messenger != null) {
      showAppSnackOn(
        messenger,
        'Removed from ${widget.section.title}',
        actionLabel: 'Undo',
        onAction: () => notifier.restore(current),
      );
    }
    return true;
  }

  // ---------------------------------------------------------------- reorder

  /// Left edge of the first pin's slot: past the gutter, the door, and the
  /// mirrored tiles in front of the pins.
  double _firstSlot = 0;

  List<SpaceShortcut> get _shown => spacePreviewOrder(_pins, _order);

  /// The store index a pin moving into [visible] (the row as shown) lands
  /// on. Pins the row holds back keep their places, so the move is placed
  /// against the shown neighbour before it (or after it, at the front).
  int _storeIndex(String key, List<String> visible) {
    final store = [
      for (final s in widget.items)
        if (s.key != key) s.key,
    ];
    final at = visible.indexOf(key);
    if (at > 0) {
      final before = store.indexOf(visible[at - 1]);
      if (before >= 0) return before + 1;
    }
    if (at + 1 < visible.length) {
      final after = store.indexOf(visible[at + 1]);
      if (after >= 0) return after;
    }
    return at <= 0 ? 0 : store.length;
  }

  void _reorderStart(SpaceShortcut s) {
    _dragKey = s.key;
    _order = [for (final item in _shown) item.key];
  }

  /// Re-slots the lifted tile under the finger. The row rebuilds only when
  /// the tile crosses into a new slot, never on every pointer move.
  void _reorderMove(SpaceShortcut s, Offset center) {
    if (_dragKey != s.key || _order == null) return;
    final order = [for (final item in _shown) item.key];
    final from = order.indexOf(s.key);
    if (from < 0) return;
    final width = s.kind.tileWidth;
    final pitch = width + SpaceMetrics.gap;
    final centers = [
      for (var i = 0; i < order.length; i++)
        Offset(_firstSlot + i * pitch + width / 2, 0),
    ];
    final to = spaceNearestSlot(
      centers,
      Offset(center.dx, 0),
      from,
      hysteresis: SpaceMetrics.gap,
    );
    if (to == from) return;
    order
      ..removeAt(from)
      ..insert(to, s.key);
    setState(() => _order = order);
    HapticFeedbackService.selection();
  }

  /// The drop: one write, and only if the tile really moved.
  void _reorderEnd(SpaceShortcut s) {
    final order = _order == null ? null : [for (final i in _shown) i.key];
    setState(() {
      _order = null;
      _dragKey = null;
    });
    if (order == null) return;
    final to = order.indexOf(s.key);
    final from = _pins.indexWhere((item) => item.key == s.key);
    if (to < 0 || from < 0 || to == from) return;
    unawaited(
      ref
          .read(spaceShortcutsProvider.notifier)
          .moveWithinSection(s.key, _storeIndex(s.key, order)),
    );
  }

  void _reorderCancel() {
    if (_order == null) return;
    setState(() {
      _order = null;
      _dragKey = null;
    });
  }

  /// "Move left" / "Move right" for screen readers: the same write as a drop.
  void _moveBy(SpaceShortcut s, int delta) {
    final from = _pins.indexWhere((item) => item.key == s.key);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _pins.length) return;
    HapticFeedbackService.selection();
    final order = [for (final p in _pins) p.key]
      ..removeAt(from)
      ..insert(to, s.key);
    unawaited(
      ref
          .read(spaceShortcutsProvider.notifier)
          .moveWithinSection(s.key, _storeIndex(s.key, order)),
    );
    _announceMove(s, to);
  }

  void _seeAll() {
    HapticFeedbackService.navigation();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // My Likes has its own full list, with its filters and dates.
        builder: (_) => widget.section == SpaceSection.likes
            ? const MyLikesScreen()
            : SpaceSectionScreen(section: widget.section),
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final auto = ref.watch(spaceAutoRowProvider(section));
    final held = ref.watch(
      spaceSheetSessionProvider.select(
        (s) => s?.section == section ? s!.added : const <String>{},
      ),
    );
    // A sheet that added to this row closes: the new tiles land at the front
    // of the rail, so bring the rail back there to watch them arrive.
    ref.listen<SpaceSheetSession?>(spaceSheetSessionProvider, (prev, next) {
      if (prev?.section != section || next != null) return;
      if (prev!.added.isEmpty || !_rail.hasClients) return;
      if (_rail.offset > 0) _rail.jumpTo(0);
    });

    _pins = [
      for (final s in widget.items)
        if (!auto.hiddenPinKeys.contains(s.key) && !held.contains(s.key)) s,
    ];
    // A lifted tile that disappeared from the store (removed on another
    // device) takes its drag with it.
    if (_dragKey != null && !_pins.any((s) => s.key == _dragKey)) {
      _dragKey = null;
      _order = null;
    }
    final pins = _shown;
    final leading = auto.leading;
    final trailing = auto.trailing;
    final canReorder = pins.length >= 2;

    final keys = {for (final s in pins) s.key};
    final arrived = widget.ready && _known != null
        ? keys.difference(_known!)
        : const <String>{};
    if (widget.ready) _known = keys;

    final autoKeys = {
      for (final a in leading) a.key,
      for (final a in trailing) a.key,
    };
    final autoArrived = widget.ready && auto.settled && _knownAuto != null
        ? autoKeys.difference(_knownAuto!)
        : const <String>{};
    if (widget.ready && auto.settled) _knownAuto = autoKeys;

    final gutter = SpaceMetrics.gutter;
    final gap = SpaceMetrics.gap;
    final door = SpaceMetrics.narrow;
    final fullDoor = (widget.availableWidth - 2 * gutter)
        .clamp(door, 10000.0)
        .toDouble();
    final empty = leading.isEmpty && pins.isEmpty && trailing.isEmpty;
    final doorWidth = empty && widget.ready && auto.settled ? fullDoor : door;

    // Slot of every tile along the rail, for the neighbours' FLIP: the
    // mirror, then the pins, then the suggestions.
    final leadSlots = <double>[];
    final pinSlots = <double>[];
    final trailSlots = <double>[];
    var x = gutter + door;
    for (final a in leading) {
      x += gap;
      leadSlots.add(x);
      x += a.shortcut.kind.tileWidth;
    }
    _firstSlot = x + gap;
    for (final s in pins) {
      x += gap;
      pinSlots.add(x);
      x += s.kind.tileWidth;
    }
    for (final a in trailing) {
      x += gap;
      trailSlots.add(x);
      x += a.shortcut.kind.tileWidth;
    }

    final liked = [
      for (final a in leading)
        if (a.analysis case final SavedAnalysis analysis) analysis,
    ];
    final count = auto.total ?? leading.length + pins.length + trailing.length;
    final itemCount = 1 + leading.length + pins.length + trailing.length;
    final pinStart = 1 + leading.length;
    final trailStart = pinStart + pins.length;

    // Where announcements are not spoken, the header carries the last move as
    // a live region. Always in the tree, so the header never remounts; inert
    // until a move happens, and never itself a focus stop.
    final live = _announcement.isNotEmpty;

    Widget autoTile(SpaceAutoItem item, double slot) => Padding(
      key: ValueKey<String>('auto:${item.key}'),
      padding: EdgeInsets.only(left: gap),
      child: SpaceAutoTile(
        item: item,
        section: section,
        liked: liked,
        slotX: slot,
        entering: autoArrived.contains(item.key),
        onOpen: _guardedOpen,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: live,
          explicitChildNodes: live,
          liveRegion: live,
          label: live ? _announcement : null,
          accessibilityFocusBlockType: live
              ? AccessibilityFocusBlockType.blockNode
              : AccessibilityFocusBlockType.none,
          child: _Header(
            section: section,
            count: count,
            topGap: widget.topGap,
            onSeeAll: empty ? null : _seeAll,
          ),
        ),
        SizedBox(
          height: SpaceMetrics.railHeight,
          // Sideways the rail clips at the page edge like any list; upward it
          // does not, so a tile being thrown out can travel over the header
          // and the row above.
          child: ClipRect(
            clipper: const _HorizontalClipper(),
            child: ListView.builder(
              controller: _rail,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: gutter),
              itemCount: itemCount,
              findChildIndexCallback: (key) {
                if (key == _doorKey) return 0;
                if (key is! ValueKey<String>) return null;
                final value = key.value;
                if (value.startsWith('auto:')) {
                  final k = value.substring(5);
                  final lead = leading.indexWhere((a) => a.key == k);
                  if (lead >= 0) return 1 + lead;
                  final trail = trailing.indexWhere((a) => a.key == k);
                  return trail < 0 ? null : trailStart + trail;
                }
                final i = pins.indexWhere((s) => s.key == value);
                return i < 0 ? null : pinStart + i;
              },
              itemBuilder: (context, index) {
                if (index == 0) {
                  return SingleMotionBuilder(
                    key: _doorKey,
                    motion: const CupertinoMotion.snappy(snapToEnd: true),
                    value: doorWidth,
                    builder: (context, width, _) => SpaceDoor(
                      section: section,
                      width: width,
                      height: SpaceMetrics.railHeight,
                      glyph: section == SpaceSection.likes
                          ? SpaceDoorGlyph.open
                          : SpaceDoorGlyph.plus,
                      onTap: () => openSpaceDoor(context, ref, section),
                    ),
                  );
                }
                if (index < pinStart) {
                  return autoTile(leading[index - 1], leadSlots[index - 1]);
                }
                if (index >= trailStart) {
                  final at = index - trailStart;
                  return autoTile(trailing[at], trailSlots[at]);
                }
                final at = index - pinStart;
                final s = pins[at];
                return Padding(
                  key: ValueKey<String>(s.key),
                  padding: EdgeInsets.only(left: gap),
                  child: SpaceTile(
                    shortcut: s,
                    slotX: pinSlots[at],
                    entering: arrived.contains(s.key),
                    canMoveToFront: at > 0,
                    onOpen: () => _open(s),
                    onMoveToFront: () => _moveToFront(s),
                    onRemove: () => _remove(s),
                    reorder: canReorder
                        ? SpaceTileReorder(
                            axis: SpaceReorderAxis.horizontal,
                            onStart: () => _reorderStart(s),
                            onMove: (center) => _reorderMove(s, center),
                            onEnd: () => _reorderEnd(s),
                            onCancel: _reorderCancel,
                            semanticMoves: {
                              if (at > 0) 'Move left': () => _moveBy(s, -1),
                              if (at < pins.length - 1)
                                'Move right': () => _moveBy(s, 1),
                            },
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _HorizontalClipper extends CustomClipper<Rect> {
  const _HorizontalClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -size.height * 4, size.width, size.height * 2);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.section,
    required this.count,
    required this.topGap,
    required this.onSeeAll,
  });

  final SpaceSection section;
  final int count;
  final double topGap;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final gutter = SpaceMetrics.gutter;
    final rowHeight = 28.w;
    final below = 10.w;
    final grey = context.colors.textSecondary;
    final titleStyle = spaceText(
      context,
      size: 16,
      line: 24,
      weight: FontWeight.w700,
    );

    return SizedBox(
      height: topGap + rowHeight + below,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: gutter, bottom: below),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  height: rowHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: section.title),
                          if (count > 0)
                            TextSpan(
                              text: '  $count',
                              style: titleStyle.copyWith(
                                fontWeight: FontWeight.w500,
                                color: grey,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                      style: titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onSeeAll != null)
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSeeAll,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 0, gutter, below),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: SizedBox(
                      height: rowHeight,
                      child: Center(
                        child: Text(
                          'See all',
                          style: spaceText(
                            context,
                            size: 12,
                            line: 16,
                            color: grey,
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
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_auto_tile.dart';
import 'package:chessever2/screens/my_space/widgets/space_metrics.dart';
import 'package:chessever2/screens/my_space/widgets/space_reorder.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// "See all" for one My Space row: everything the row shows (its mirror, its
/// pins, its suggestions), laid out as a grid in the rail's order. The same
/// tiles and the same hold menu as the rail; swipe-to-remove stays on the
/// rail, where a tile has one clear direction to leave in. Here a grabbed pin
/// moves freely and the grid reflows around it.
class SpaceSectionScreen extends ConsumerStatefulWidget {
  const SpaceSectionScreen({super.key, required this.section});

  final SpaceSection section;

  @override
  ConsumerState<SpaceSectionScreen> createState() => _SpaceSectionScreenState();
}

class _SpaceSectionScreenState extends ConsumerState<SpaceSectionScreen> {
  /// The grid as a drag in progress shows it; null when nothing is lifted.
  List<String>? _order;
  String? _dragKey;

  SpaceSection get section => widget.section;

  /// The pins the grid shows, as of its last build.
  List<SpaceShortcut> _pins = const [];

  /// Tiles before the pins (the mirror); pin slots start after them.
  int _lead = 0;

  List<SpaceShortcut> get _stored => _pins;

  /// Store index for a pin that lands where [visible] shows it; pins the
  /// grid holds back keep their places. See the rail's twin.
  int _storeIndex(String key, List<String> visible) {
    final store = [
      for (final s
          in ref.read(spaceShortcutsBySectionProvider)[section] ??
              const <SpaceShortcut>[])
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

  DateTime? _openingSince;

  void _guardedOpen(Future<void> Function() open) {
    final pending = _openingSince;
    if (pending != null &&
        DateTime.now().difference(pending) < const Duration(seconds: 10)) {
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

  SpaceShortcut? _current(SpaceShortcut s) {
    final list = ref.read(spaceShortcutsProvider).valueOrNull ?? const [];
    for (final item in list) {
      if (item.key == s.key) return item;
    }
    return null;
  }

  Future<bool> _remove(SpaceShortcut s) async {
    final current = _current(s);
    if (current == null) return false;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final notifier = ref.read(spaceShortcutsProvider.notifier);
    unawaited(notifier.removeTarget(current.kind, current.targetId));
    if (messenger != null) {
      showAppSnackOn(
        messenger,
        'Removed from ${section.title}',
        actionLabel: 'Undo',
        onAction: () => notifier.restore(current),
      );
    }
    return true;
  }

  void _open(SpaceShortcut s) {
    HapticFeedbackService.cardTap();
    unawaited(openSpaceShortcut(context, ref, _current(s) ?? s));
  }

  Future<void> _moveToFront(SpaceShortcut s) async {
    final current = _current(s);
    if (current == null) return;
    HapticFeedbackService.light();
    await ref.read(spaceShortcutsProvider.notifier).moveToFront(current.id);
  }

  // ---------------------------------------------------------------- reorder

  void _reorderStart(SpaceShortcut s, List<SpaceShortcut> shown) {
    _dragKey = s.key;
    _order = [for (final item in shown) item.key];
  }

  void _reorderMove(SpaceShortcut s, Offset center, SpaceGridGeometry grid) {
    if (_dragKey != s.key || _order == null) return;
    final order = [
      for (final item in spacePreviewOrder(_stored, _order)) item.key,
    ];
    final from = order.indexOf(s.key);
    if (from < 0) return;
    final to = spaceNearestSlot(
      [for (var i = 0; i < order.length; i++) grid.center(_lead + i)],
      center,
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

  void _reorderEnd(SpaceShortcut s) {
    final stored = _stored;
    final order = _order == null
        ? null
        : [for (final i in spacePreviewOrder(stored, _order)) i.key];
    setState(() {
      _order = null;
      _dragKey = null;
    });
    if (order == null) return;
    final to = order.indexOf(s.key);
    final from = stored.indexWhere((item) => item.key == s.key);
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

  /// Screen-reader moves: a step sideways, or a whole row up or down.
  void _moveBy(SpaceShortcut s, int delta) {
    final stored = _stored;
    final from = stored.indexWhere((item) => item.key == s.key);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= stored.length) return;
    HapticFeedbackService.selection();
    final order = [for (final p in stored) p.key]
      ..removeAt(from)
      ..insert(to, s.key);
    unawaited(
      ref
          .read(spaceShortcutsProvider.notifier)
          .moveWithinSection(s.key, _storeIndex(s.key, order)),
    );
  }

  /// Moves for the pin at [index] of [count]. Pins sit after the mirror's
  /// [_lead] tiles, so the column comes from the grid slot, and a sideways
  /// move is offered only onto a neighbouring pin in the same row.
  Map<String, VoidCallback> _semanticMoves(
    SpaceShortcut s,
    int index,
    int count,
    int columns,
  ) {
    final column = (_lead + index) % columns;
    return {
      if (column > 0 && index > 0) 'Move left': () => _moveBy(s, -1),
      if (column < columns - 1 && index < count - 1)
        'Move right': () => _moveBy(s, 1),
      if (index - columns >= 0) 'Move up': () => _moveBy(s, -columns),
      if (index + columns < count) 'Move down': () => _moveBy(s, columns),
    };
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(
      spaceShortcutsBySectionProvider.select(
        (map) => map[section] ?? const <SpaceShortcut>[],
      ),
    );
    final auto = ref.watch(spaceAutoRowProvider(section));
    final stored = _pins = [
      for (final s in all)
        if (!auto.hiddenPinKeys.contains(s.key)) s,
    ];
    _lead = auto.leading.length;
    if (_dragKey != null && !stored.any((s) => s.key == _dragKey)) {
      _dragKey = null;
      _order = null;
    }
    final items = spacePreviewOrder(stored, _order);
    final shown = auto.leading.length + items.length + auto.trailing.length;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8.w, 8.w, 16.w, 4.w),
              child: Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: context.colors.textPrimary,
                      size: 20.sp,
                    ),
                  ),
                  Text(
                    section.title,
                    style: AppTypography.textLgBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    '${auto.total ?? shown}',
                    style: AppTypography.textLgMedium.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: shown == 0
                  ? Center(
                      child: Text(
                        'Nothing in ${section.title} yet',
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) =>
                          _grid(auto, items, constraints.maxWidth),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(SpaceAutoRow auto, List<SpaceShortcut> items, double maxWidth) {
    final gutter = SpaceMetrics.gutter;
    final widths = [
      for (final a in auto.leading) a.shortcut.kind.tileWidth,
      for (final s in items) s.kind.tileWidth,
      for (final a in auto.trailing) a.shortcut.kind.tileWidth,
    ];
    final grid = SpaceGridGeometry(
      width: (maxWidth - 2 * gutter).clamp(0.0, double.infinity),
      // One width per row today; the widest keeps a mixed row from
      // overlapping should that ever change.
      tileWidth: widths.reduce(math.max),
      tileHeight: SpaceMetrics.railHeight,
      gap: SpaceMetrics.gap,
      runSpacing: 20.w,
    );
    // Centre the columns: two narrow tiles on a phone leave a third of the
    // width empty. Slots stay relative to the grid, so the offset rides on
    // the padding and the reorder maths never sees it.
    final columns = grid.columns;
    final used = columns * grid.tileWidth + (columns - 1) * grid.gap;
    final inset = math.max(0.0, (grid.width - used) / 2);
    final canReorder = items.length >= 2;
    final lead = auto.leading.length;
    final trailFrom = lead + items.length;
    final liked = [
      for (final a in auto.leading)
        if (a.analysis case final SavedAnalysis analysis) analysis,
    ];

    Widget autoTile(SpaceAutoItem item, int at) {
      final slot = grid.slot(at);
      return Positioned(
        key: ValueKey<String>('auto:${item.key}'),
        left: slot.dx,
        top: slot.dy,
        child: SpaceAutoTile(
          item: item,
          section: section,
          liked: liked,
          slotX: slot.dx,
          slotY: slot.dy,
          onOpen: _guardedOpen,
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(gutter + inset, 12.w, gutter + inset, 32.w),
      child: SizedBox(
        width: grid.width - 2 * inset,
        height: grid.height(widths.length),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < lead; i++) autoTile(auto.leading[i], i),
            for (var i = 0; i < items.length; i++)
              _positioned(items, i, grid, canReorder),
            for (var i = 0; i < auto.trailing.length; i++)
              autoTile(auto.trailing[i], trailFrom + i),
          ],
        ),
      ),
    );
  }

  Widget _positioned(
    List<SpaceShortcut> items,
    int i,
    SpaceGridGeometry grid,
    bool canReorder,
  ) {
    final s = items[i];
    final slot = grid.slot(_lead + i);
    return Positioned(
      key: ValueKey<String>(s.key),
      left: slot.dx,
      top: slot.dy,
      child: SpaceTile(
        shortcut: s,
        slotX: slot.dx,
        slotY: slot.dy,
        swipeToRemove: false,
        canMoveToFront: i > 0,
        onOpen: () => _open(s),
        onMoveToFront: () => _moveToFront(s),
        onRemove: () => _remove(s),
        reorder: canReorder
            ? SpaceTileReorder(
                axis: SpaceReorderAxis.free,
                onStart: () => _reorderStart(s, items),
                onMove: (center) => _reorderMove(s, center, grid),
                onEnd: () => _reorderEnd(s),
                onCancel: _reorderCancel,
                semanticMoves: _semanticMoves(s, i, items.length, grid.columns),
              )
            : null,
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/config/feature_flags.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction, DiscoveryActionLead;
import 'package:chessever2/screens/my_space/actions/space_edit_actions.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_auto_tile.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart'
    show SpaceGroupEdit, SpaceGroupPage, spaceDatabaseGroupsProvider;
import 'package:chessever2/screens/my_space/widgets/space_door_actions.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_grid.dart'
    show SpaceStartController;
import 'package:chessever2/screens/my_space/widgets/space_metrics.dart';
import 'package:chessever2/screens/my_space/widgets/space_reorder.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_header.dart';
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
///
/// With [pinsOnly] (My Database's See all) it lists what the user saved and
/// nothing else: no mirror, no suggestions. Then it is the group itself at
/// full length ([SpaceGroupPage]): the same cards My Database draws for the
/// group's first few, in the viewer's games view, never the rail's tiles.
/// Its Edit keeps those cards, in the page's order, and circles each one
/// ([SpaceGroupEdit]): tap to select, hold to move (Players order
/// themselves, so they only select), Remove takes the selected out with one
/// Undo, Done (or back) ends it, the circles going the way they came.
class SpaceSectionScreen extends ConsumerStatefulWidget {
  const SpaceSectionScreen({
    super.key,
    required this.section,
    this.pinsOnly = false,
  });

  final SpaceSection section;

  /// Only the saved things, as My Database groups them.
  final bool pinsOnly;

  @override
  ConsumerState<SpaceSectionScreen> createState() => _SpaceSectionScreenState();
}

class _SpaceSectionScreenState extends ConsumerState<SpaceSectionScreen> {
  /// The grid as a drag in progress shows it; null when nothing is lifted.
  List<String>? _order;

  /// See all is in Edit: every card circled, selectable and movable.
  bool _editing = false;

  /// Edit has ended and its circles are on their way out; the page takes
  /// their place once they have gone.
  bool _closing = false;

  /// What Edit has selected, by [spaceEditKeys].
  final Set<String> _selected = {};
  String? _dragKey;

  /// The page's list and Edit's: Edit opens where the reader is on the
  /// page, and Done brings the page back where the reader left it, or where
  /// they left Edit when the two lay the group out alike.
  final _pageScroll = SpaceStartController();
  final _editScroll = SpaceStartController();

  /// Whether Edit lays the group out as the page does, so a place in one is
  /// the same place in the other: every group but the events (Edit leaves
  /// out a live event's boards) and the players (and their games).
  bool get _editMirrorsPage =>
      section != SpaceSection.events && section != SpaceSection.players;

  @override
  void dispose() {
    _pageScroll.dispose();
    _editScroll.dispose();
    super.dispose();
  }

  SpaceSection get section => widget.section;

  /// The pins the grid shows, as of its last build.
  List<SpaceShortcut> _pins = const [];

  /// Tiles before the pins (the mirror); pin slots start after them.
  int _lead = 0;

  List<SpaceShortcut> get _stored => _pins;

  /// Store index for a pin that lands where [visible] shows it; pins the
  /// grid holds back keep their places ([spaceStoreIndexFor]).
  int _storeIndex(String key, List<String> visible) => spaceStoreIndexFor(
    ref.read(spaceShortcutsBySectionProvider)[section] ??
        const <SpaceShortcut>[],
    key,
    visible,
  );

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
        'Removed from My Space',
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

  void _setEditing(bool value) {
    HapticFeedbackService.selection();
    if (value) {
      _pageScroll.start = _pageScroll.at ?? _pageScroll.start;
      _editScroll.start = _pageScroll.start;
    } else if (_editing && _editMirrorsPage) {
      _pageScroll.start = _editScroll.at ?? _pageScroll.start;
    }
    setState(() {
      _closing = !value && (_editing || _closing);
      _editing = value;
      _selected.clear();
    });
  }

  void _closed() {
    if (mounted && _closing) setState(() => _closing = false);
  }

  void _toggleSelected(String key) {
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
    });
  }

  /// Takes the selected things out of My Space (Undo on the snack); Edit
  /// ends once nothing is left to edit.
  Future<void> _removeSelected(Set<String> all) async {
    final keys = {..._selected};
    if (keys.isEmpty) return;
    final emptied = keys.containsAll(all);
    setState(() {
      _selected.clear();
      // Nothing left to edit: the empty page at once, no circles to see off.
      if (emptied) _editing = _closing = false;
    });
    await spaceRemoveSelected(
      context: context,
      ref: ref,
      section: section,
      keys: keys,
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
    final all = [
      for (final s in ref.watch(
        spaceShortcutsBySectionProvider.select(
          (map) => map[section] ?? const <SpaceShortcut>[],
        ),
      ))
        // Streak cards stay out while streaks are hidden.
        if (FeatureFlags.streaks || s.kind != SpaceShortcutKind.streak) s,
    ];
    final auto = widget.pinsOnly
        ? SpaceAutoRow.empty
        : ref.watch(spaceAutoRowProvider(section));
    final title = widget.pinsOnly ? spaceGroupTitle(section) : section.title;
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
    // My Space's own group counts what the group shows (the Players group
    // holds the followed players too).
    final group = widget.pinsOnly
        ? ref.watch(
            spaceDatabaseGroupsProvider.select(
              (groups) => groups
                  ?.where((g) => g.section == section)
                  .fold<int>(0, (n, g) => n + g.items.length),
            ),
          )
        : null;
    final shown =
        group ?? auto.leading.length + items.length + auto.trailing.length;
    // What Edit can select: the pins, or for Players every face (a follow
    // needs no pin). A selection whose thing has left is dropped.
    final editKeys = widget.pinsOnly
        ? spaceEditKeys(ref, section, stored)
        : const <String>{};
    _selected.retainAll(editKeys);
    final editing = _editing && widget.pinsOnly;
    final closing = _closing && widget.pinsOnly && !editing;
    final picked = _selected.length;

    // Back in Edit ends Edit, as a selection's back does, before it leaves.
    return PopScope(
      canPop: !editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _editing) _setEditing(false);
      },
      // The page's list is the one a tap on the status bar takes to the top.
      child: PrimaryScrollController(
        controller: _pageScroll,
        child: _scaffold(
          context,
          title: title,
          count: auto.total ?? shown,
          editing: editing,
          closing: closing,
          picked: picked,
          editKeys: editKeys,
          stored: stored,
          auto: auto,
          items: items,
          shown: shown,
        ),
      ),
    );
  }

  Widget _scaffold(
    BuildContext context, {
    required String title,
    required int count,
    required bool editing,
    required bool closing,
    required int picked,
    required Set<String> editKeys,
    required List<SpaceShortcut> stored,
    required SpaceAutoRow auto,
    required List<SpaceShortcut> items,
    required int shown,
  }) {
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
                  // The title and its count take the room the action leaves,
                  // so the action sits on the gutter.
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textLgBold.copyWith(
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          '$count',
                          style: AppTypography.textLgMedium.copyWith(
                            color: context.colors.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // The count never runs into the actions on a narrow screen.
                  SizedBox(width: 12.w),
                  // Edit keeps the cards and circles them; Remove takes
                  // Edit's side and Done Add's.
                  if (editing) ...[
                    DiscoveryAction(
                      key: const ValueKey<String>('space_edit_remove'),
                      label: picked == 0 ? 'Remove' : 'Remove $picked',
                      onTap: picked == 0
                          ? null
                          : () => unawaited(_removeSelected(editKeys)),
                      semanticsLabel: picked == 0
                          ? 'Remove, select something first'
                          : 'Remove $picked from My Space',
                    ),
                    SizedBox(width: 16.w),
                    DiscoveryAction(
                      key: const ValueKey<String>('space_edit_done'),
                      label: 'Done',
                      onTap: () => _setEditing(false),
                      semanticsLabel: 'Done editing',
                    ),
                  ] else if (widget.pinsOnly && editKeys.isNotEmpty) ...[
                    DiscoveryAction(
                      key: const ValueKey<String>('space_edit'),
                      label: 'Edit',
                      onTap: () => _setEditing(true),
                      semanticsLabel: 'Edit $title',
                    ),
                    SizedBox(width: 16.w),
                  ],
                  if (!editing &&
                      section != SpaceSection.links &&
                      section != SpaceSection.likes)
                    DiscoveryAction(
                      label: 'Add',
                      lead: DiscoveryActionLead.plus,
                      onTap: () => openSpaceAdd(context, ref, section),
                      semanticsLabel: 'Add to $title',
                    ),
                ],
              ),
            ),
            Expanded(
              child: widget.pinsOnly
                  // The page's list and Edit's hold their own controllers,
                  // and no list inside a card takes the page's.
                  ? PrimaryScrollController.none(
                      child: editing || closing
                          ? SpaceGroupEdit(
                              section: section,
                              pins: stored,
                              selected: {..._selected},
                              onToggle: _toggleSelected,
                              closing: closing,
                              onClosed: _closed,
                              // The Players order themselves (the latest
                              // visited first): nothing to move by hand.
                              onReorder: section == SpaceSection.players
                                  ? null
                                  : (key, order) => unawaited(
                                      spaceReorderPin(ref, section, key, order),
                                    ),
                              controller: _editScroll,
                            )
                          : SpaceGroupPage(
                              section: section,
                              controller: _pageScroll,
                            ),
                    )
                  : shown == 0
                  ? Center(
                      child: Text(
                        'Nothing in $title yet',
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

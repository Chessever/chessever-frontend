import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction, DiscoveryActionLead;
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/my_space/actions/space_edit_actions.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart'
    show SpaceGroupEdit;
import 'package:chessever2/screens/my_space/widgets/space_door_actions.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_grid.dart'
    show SpaceStartController;
import 'package:chessever2/screens/my_space/widgets/space_opening_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart'
    show GameCardChessboard;
import 'package:dartchess/dartchess.dart' show Side, kInitialFEN;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// My Prep, in the event view's frame (back, a centred title, segments that
/// swipe), as Favorites and Countrymen open from Today: the user's
/// databases (the Library's own list, with its Add) and the openings and
/// positions they saved, each on its board.
class MyPrepScreen extends StatelessWidget {
  const MyPrepScreen({super.key, this.initialTab = 0});

  final int initialTab;

  static const List<String> tabs = ['Databases', 'Openings'];

  /// The Openings tab: where My Space's Openings group leads.
  static int get openingsTab => tabs.indexOf('Openings');

  static Future<void> open(BuildContext context, {int initialTab = 0}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyPrepScreen(initialTab: initialTab),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return EventViewShell(
      title: 'My Prep',
      tabs: tabs,
      initialTab: initialTab,
      pageBuilder: (context, index) => switch (index) {
        0 => const LibraryScreen(
          key: PageStorageKey<String>('my_prep_databases'),
          embedded: true,
        ),
        _ => const MyPrepOpeningsPage(
          key: PageStorageKey<String>('my_prep_openings'),
        ),
      },
    );
  }
}

/// The openings, positions and player lines the user saved, on their
/// boards, as the games view setting lays out game cards. The Openings
/// group's See all: its Edit circles every line (tap to select, hold to
/// move), Remove takes the selected out with one Undo, Done (or back) ends
/// it, the circles going the way they came. The count and its actions stay
/// put over the lines, so Remove and Done are always at hand, however far
/// down the reader has selected.
class MyPrepOpeningsPage extends ConsumerStatefulWidget {
  const MyPrepOpeningsPage({super.key});

  static bool isOpening(SpaceShortcut s) => switch (s.kind) {
    SpaceShortcutKind.opening ||
    SpaceShortcutKind.position ||
    SpaceShortcutKind.playerOpenings => true,
    _ => false,
  };

  @override
  ConsumerState<MyPrepOpeningsPage> createState() => _MyPrepOpeningsPageState();
}

class _MyPrepOpeningsPageState extends ConsumerState<MyPrepOpeningsPage> {
  bool _editing = false;

  /// Edit has ended and its circles are on their way out.
  bool _closing = false;
  final Set<String> _selected = {};

  /// The lines' list and Edit's, which lay the lines out alike: Edit opens
  /// where the reader is, and Done leaves the list where the reader left
  /// Edit. Where the reader stands is kept across a swipe to Databases and
  /// back.
  final _listScroll = SpaceStartController();
  final _editScroll = SpaceStartController();
  PageStorageBucket? _bucket;
  bool _restored = false;
  static const _offsetId = 'my_prep_openings_offset';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bucket = PageStorage.maybeOf(context);
    if (_restored) return;
    _restored = true;
    final kept = _bucket?.readState(context, identifier: _offsetId);
    if (kept is double) _listScroll.start = kept;
  }

  @override
  void deactivate() {
    // Before the lists below let go of their places.
    final at = _listScroll.at ?? _editScroll.at;
    if (at != null) _bucket?.writeState(context, at, identifier: _offsetId);
    super.deactivate();
  }

  @override
  void dispose() {
    _listScroll.dispose();
    _editScroll.dispose();
    super.dispose();
  }

  void _setEditing(bool value) {
    HapticFeedbackService.selection();
    if (value) {
      _listScroll.start = _listScroll.at ?? _listScroll.start;
      _editScroll.start = _listScroll.start;
    } else if (_editing) {
      _listScroll.start = _editScroll.at ?? _listScroll.start;
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

  Future<void> _removeSelected(Set<String> all) async {
    final keys = {..._selected};
    if (keys.isEmpty) return;
    final emptied = keys.containsAll(all);
    setState(() {
      _selected.clear();
      if (emptied) _editing = _closing = false;
    });
    await spaceRemoveSelected(
      context: context,
      ref: ref,
      section: SpaceSection.openings,
      keys: keys,
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(spaceShortcutsProvider).valueOrNull;
    final openings = [
      for (final s in saved ?? const <SpaceShortcut>[])
        if (MyPrepOpeningsPage.isOpening(s)) s,
    ];
    final keys = {for (final s in openings) s.key};
    _selected.retainAll(keys);
    final editing = _editing && openings.isNotEmpty;
    final closing = _closing && openings.isNotEmpty && !editing;
    final picked = _selected.length;
    final mode = ref.watch(gamesListViewModeProvider);
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    final gap = 12.sp;
    // Two to a row on every device, as every other grid of games and
    // positions (My Database, See all, the Discovery lists).
    final columns = mode == GamesListViewMode.chessBoardGrid ? 2 : 1;

    final rows = <Widget>[];
    for (var i = 0; i < openings.length; i += columns) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) SizedBox(width: gap),
              Expanded(
                child: i + c < openings.length
                    ? SpaceOpeningCard(
                        key: ValueKey<String>('prep_${openings[i + c].key}'),
                        shortcut: openings[i + c],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    final header = Padding(
      padding: EdgeInsets.fromLTRB(gutter, 8.h, gutter, 4.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              openings.isEmpty
                  ? 'Openings and positions you save'
                  : openings.length == 1
                  ? '1 saved line'
                  : '${openings.length} saved lines',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(width: 12.w),
          // Remove takes Edit's side and Done Add's.
          if (editing) ...[
            DiscoveryAction(
              key: const ValueKey<String>('space_edit_remove'),
              label: picked == 0 ? 'Remove' : 'Remove $picked',
              onTap: picked == 0 ? null : () => _removeSelected(keys),
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
          ] else ...[
            if (openings.isNotEmpty) ...[
              DiscoveryAction(
                key: const ValueKey<String>('space_edit'),
                label: 'Edit',
                onTap: () => _setEditing(true),
                semanticsLabel: 'Edit openings',
              ),
              SizedBox(width: 16.w),
            ],
            DiscoveryAction(
              label: 'Add',
              lead: DiscoveryActionLead.plus,
              semanticsLabel: 'Add an opening',
              onTap: () => openSpaceAdd(context, ref, SpaceSection.openings),
            ),
          ],
        ],
      ),
    );

    // Back in Edit ends Edit, as a selection's back does, before it leaves.
    return PopScope(
      canPop: !editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _editing) _setEditing(false);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: editing || closing
                ? _edit(openings, gutter: gutter, closing: closing)
                : _list(context, saved, openings, rows, gutter, gap),
          ),
        ],
      ),
    );
  }

  Widget _edit(
    List<SpaceShortcut> openings, {
    required double gutter,
    required bool closing,
  }) {
    return SpaceGroupEdit(
      section: SpaceSection.openings,
      pins: openings,
      closing: closing,
      onClosed: _closed,
      selected: {..._selected},
      onToggle: (key) => setState(() {
        if (!_selected.remove(key)) _selected.add(key);
      }),
      onReorder: (key, order) =>
          spaceReorderPin(ref, SpaceSection.openings, key, order),
      gutter: gutter,
      // The list's own air over its first row and under its last.
      top: 8.h,
      bottom: 32.h,
      controller: _editScroll,
    );
  }

  Widget _list(
    BuildContext context,
    List<SpaceShortcut>? saved,
    List<SpaceShortcut> openings,
    List<Widget> rows,
    double gutter,
    double gap,
  ) {
    return ListView(
      controller: _listScroll,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(bottom: 32.h),
      children: [
        if (saved != null && openings.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 24.h, gutter, 0),
            child: Column(
              children: [
                // A real board at the start, where the saved lines will
                // stand on theirs.
                SizedBox.square(
                  dimension: 96.w,
                  child: GameCardChessboard(
                    fen: kInitialFEN,
                    lastMove: null,
                    boardSize: 96.w,
                    orientation: Side.white,
                    showCoordinates: false,
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  'Hold a position in the explorer or on a board and choose '
                  'Add to My Space, or add an opening here.',
                  textAlign: TextAlign.center,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textSecondary,
                    height: 20 / 14,
                  ),
                ),
              ],
            ),
          ),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, i == 0 ? 8.h : gap, gutter, 0),
            child: rows[i],
          ),
      ],
    );
  }
}

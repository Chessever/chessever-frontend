import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction, DiscoveryActionLead;
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_door_actions.dart';
import 'package:chessever2/screens/my_space/widgets/space_opening_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
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
/// boards, as the games view setting lays out game cards.
class MyPrepOpeningsPage extends ConsumerWidget {
  const MyPrepOpeningsPage({super.key});

  static bool isOpening(SpaceShortcut s) => switch (s.kind) {
    SpaceShortcutKind.opening ||
    SpaceShortcutKind.position ||
    SpaceShortcutKind.playerOpenings => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(spaceShortcutsProvider).valueOrNull;
    final openings = [
      for (final s in saved ?? const <SpaceShortcut>[])
        if (isOpening(s)) s,
    ];
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
          DiscoveryAction(
            label: 'Add',
            lead: DiscoveryActionLead.plus,
            semanticsLabel: 'Add an opening',
            onTap: () => openSpaceAdd(context, ref, SpaceSection.openings),
          ),
        ],
      ),
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(bottom: 32.h),
      children: [
        header,
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

import 'dart:async';

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_move_line.dart';
import 'package:chessever2/screens/gamebase/utils/space_position_draft.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/library/widgets/menu_preview_surface.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/utils/player_menu_actions.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/round_space_shortcut.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/string_utils.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show buildEventShareUrl;
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// My Space targets reachable from the board screen: the event, round and
/// opening rows of its info sheet, and a position picked from the notation.
///
/// Every builder returns null when the app could not reopen the target later
/// (a gamebase virtual event, an archive round, a non-ECO opening), so a menu
/// never offers a pin that would open to "This shortcut can no longer open".

/// The event a board game belongs to. The target is the group broadcast when
/// known, so a pin made here dedupes with the one made from the event card.
SpaceShortcut? boardEventSpaceDraft({
  required String eventName,
  String? groupBroadcastId,
  String? tourId,
  String? dates,
}) {
  final groupId = _clean(groupBroadcastId);
  final tour = _clean(tourId);
  final target = groupId ?? tour;
  final name = eventName.trim();
  if (target == null || name.isEmpty) return null;
  if (isVirtualGamebaseId(target) || isVirtualGamebaseId(tour)) return null;
  final when = _clean(dates);
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.event,
    targetId: target,
    title: name,
    subtitle: when,
    params: {
      if (tour != null) 'tourId': tour,
      if (groupId != null) 'groupBroadcastId': groupId,
      if (when != null) 'dates': when,
    },
  );
}

/// One round of a live broadcast, built by the shared [roundSpaceDraft] so a
/// round pinned from a game's info sheet is the same shortcut the Games tab
/// round header makes. Archive games (gamebase, TWIC, saved) carry a sentinel
/// in `roundId`, so only broadcast games offer it.
SpaceShortcut? boardRoundSpaceDraft({
  required GamesTourModel game,
  String? groupBroadcastId,
  String? eventName,
}) {
  if (game.source != GameSource.supabase) return null;
  final slug = game.roundSlug?.trim() ?? '';
  final label =
      slug.isNotEmpty
          ? StringUtils.formatRoundLabel(slug)
          : game.roundDisplayName.trim();
  return roundSpaceDraft(
    round: GamesAppBarModel(
      id: game.roundId,
      name: label.isEmpty ? 'Round' : label,
      startsAt: null,
      roundStatus: RoundStatus.completed,
    ),
    tourId: game.tourId,
    groupBroadcastId: groupBroadcastId,
    eventName: eventName,
  );
}

final RegExp _ecoCode = RegExp(r'^[A-E][0-9]{2}$');

/// The opening a game was played in, keyed by its ECO code exactly like the
/// search result and the profile repertoire row, so all three dedupe.
SpaceShortcut? boardOpeningSpaceDraft({String? eco, String? openingName}) {
  final code = eco?.trim().toUpperCase() ?? '';
  if (!_ecoCode.hasMatch(code)) return null;
  final name =
      _clean(openingName) ?? EcoOpenings.getOpeningName(code) ?? code;
  return spaceOpeningDraft(
    targetId: code,
    name: name,
    extraParams: {'ecoCode': code},
  );
}

/// The position after the move at [pointer] in [game]'s notation tree, with
/// the line that reaches it when that line replays from the standard start.
SpaceShortcut? boardNotationPositionDraft({
  required ChessGame? game,
  required ChessMovePointer pointer,
}) {
  if (game == null || pointer.isEmpty) return null;
  final path = pathFromPointer(game, pointer);
  if (path.isEmpty) return null;
  // A null move leaves a position no explorer line can reach.
  if (path.any((move) => move.san == '--')) return null;
  final fen = path.last.fen;
  final line = resolveSpaceLine(fen: fen, moves: [for (final m in path) m.uci]);
  return spacePositionDraft(
    fen: fen,
    ucis: line?.ucis ?? const <String>[],
    startingFen: game.startingFen,
  );
}

/// "Share event" for a broadcast event row: the same chessever.com link the
/// event card shares. Null for anything that is not a real broadcast.
LibraryMenuAction? boardShareEventAction(
  BuildContext context, {
  required String eventName,
  String? groupBroadcastId,
  String? tourId,
  String? tourSlug,
}) {
  final groupId = _clean(groupBroadcastId);
  final tour = _clean(tourId);
  final id = groupId ?? tour;
  final name = eventName.trim();
  if (id == null || name.isEmpty) return null;
  if (isVirtualGamebaseId(id) || isVirtualGamebaseId(tour)) return null;
  final url = buildEventShareUrl(
    id: id,
    title: name,
    tourId: tour,
    tourSlug: _clean(tourSlug),
  );
  final origin = _rectOf(context);
  return LibraryMenuAction(
    icon: Icons.ios_share_rounded,
    label: 'Share event',
    onSelected: () async {
      HapticFeedbackService.buttonPress();
      await Share.share(
        url,
        subject: name,
        sharePositionOrigin: origin ?? const Rect.fromLTWH(0, 0, 1, 1),
      );
    },
  );
}

/// The player rows every game-scoped menu offers for one [player]: open the
/// profile, pin the player, pin their Games tab, share the profile link.
List<LibraryMenuAction> boardPlayerMenuActions(
  BuildContext context,
  WidgetRef ref,
  PlayerCard player,
) {
  final name = player.name.trim();
  final fed =
      player.countryCode.trim().isNotEmpty
          ? player.countryCode.trim()
          : player.federation.trim();
  return playerMenuActions(
    context,
    ref,
    playerName: name,
    fideId: player.fideId,
    title: _clean(player.title),
    federation: _clean(fed),
    rating: player.rating > 0 ? player.rating : null,
    gamebasePlayerId: player.gamebasePlayerId,
    onOpen: () => openBoardPlayerProfile(context, player),
  );
}

/// Pushes [player]'s profile from a board-scoped surface.
void openBoardPlayerProfile(BuildContext context, PlayerCard player) {
  if (!context.mounted) return;
  HapticFeedbackService.cardTap();
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => PlayerProfileScreen(
              fideId: player.fideId,
              playerName: player.name,
              title: _clean(player.title),
              federation: player.federation,
              rating: player.rating > 0 ? player.rating : null,
              gamebasePlayerId: player.gamebasePlayerId,
            ),
      ),
    ),
  );
}

/// A row of the board's info sheet that long-presses into the shared focus
/// menu. The row lifts on a plate of the sheet's own colour, which is
/// invisible in place, so the lifted row is the row itself.
///
/// An empty action list opens nothing and raises no haptic, so a row whose
/// target cannot be pinned simply stays a plain row.
class BoardInfoFocusRow extends ConsumerWidget {
  const BoardInfoFocusRow({
    super.key,
    required this.actions,
    required this.child,
    this.onOpen,
  });

  final List<LibraryMenuAction> Function(BuildContext context, WidgetRef ref)
  actions;
  final Widget child;

  /// Tapping the lifted row. The menu closes first.
  final FutureOr<void> Function()? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = onOpen;
    return CardContextMenu(
      actions: (rowContext) => actions(rowContext, ref),
      onPreviewTap: open == null ? null : () => unawaited(Future.sync(open)),
      child: MenuPreviewSurface(color: context.colors.surface, child: child),
    );
  }
}

Rect? _rectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

String? _clean(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

import 'dart:async';

import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/utils/player_profile_share_utils.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// The rows every player long-press menu shares, in one order: open the
/// player, pin the player, pin their Games tab, share their profile link.
///
/// Surfaces that already had a menu keep their own wording through
/// [playerAddLabel] / [playerRemoveLabel], so migrating a menu never renames
/// an action a user already knows. Anything surface-specific (open a
/// scorecard, remove a favourite) goes in [extra], after the shared rows.
List<LibraryMenuAction> playerMenuActions(
  BuildContext context,
  WidgetRef ref, {
  required String playerName,
  int? fideId,
  String? title,
  String? federation,
  int? rating,
  String? gamebasePlayerId,
  String? memorialSourceIdentity,
  String? memorialRouteId,
  FutureOr<void> Function()? onOpen,
  String openLabel = 'Open profile',
  IconData openIcon = Icons.person_outline_rounded,
  bool includeGamesTab = true,
  bool includeShare = true,
  String playerAddLabel = 'Add player to My Space',
  String playerRemoveLabel = 'Remove player from My Space',
  List<LibraryMenuAction> extra = const [],
}) {
  final name = playerName.trim();
  if (name.isEmpty && (fideId == null || fideId <= 0)) return const [];
  final share = includeShare
      ? sharePlayerProfileAction(
          context,
          playerName: name,
          fideId: fideId,
          memorialRouteId: memorialRouteId,
        )
      : null;
  return [
    if (onOpen != null)
      LibraryMenuAction(icon: openIcon, label: openLabel, onSelected: onOpen),
    labeledSpaceMenuAction(
      context: context,
      ref: ref,
      draft: spacePlayerDraft(
        playerName: name,
        fideId: fideId,
        title: title,
        federation: federation,
        rating: rating,
        gamebasePlayerId: gamebasePlayerId,
        memorialSourceIdentity: memorialSourceIdentity,
        memorialRouteId: memorialRouteId,
      ),
      addLabel: playerAddLabel,
      removeLabel: playerRemoveLabel,
    ),
    if (includeGamesTab)
      labeledSpaceMenuAction(
        context: context,
        ref: ref,
        draft: spacePlayerGamesDraft(
          playerName: name,
          fideId: fideId,
          title: title,
          federation: federation,
          rating: rating,
          gamebasePlayerId: gamebasePlayerId,
          memorialSourceIdentity: memorialSourceIdentity,
          memorialRouteId: memorialRouteId,
        ),
        addLabel: 'Add Games tab to My Space',
        removeLabel: 'Remove Games tab from My Space',
      ),
    if (share != null) share,
    ...extra,
  ];
}

/// [playerMenuActions] for the standings-shaped row model most player lists
/// render. `score` is the row's rating in every list that builds one.
List<LibraryMenuAction> playerStandingMenuActions(
  BuildContext context,
  WidgetRef ref,
  PlayerStandingModel player, {
  FutureOr<void> Function()? onOpen,
  String openLabel = 'Open profile',
  IconData openIcon = Icons.person_outline_rounded,
  bool includeGamesTab = true,
  bool includeShare = true,
  String playerAddLabel = 'Add player to My Space',
  String playerRemoveLabel = 'Remove player from My Space',
  List<LibraryMenuAction> extra = const [],
}) {
  return playerMenuActions(
    context,
    ref,
    playerName: player.name,
    fideId: player.fideId,
    title: player.title,
    federation: player.countryCode,
    rating: player.score > 0 ? player.score : null,
    gamebasePlayerId: player.gamebasePlayerId,
    memorialSourceIdentity: player.memorialSourceIdentity,
    memorialRouteId: player.memorialRouteId,
    onOpen: onOpen,
    openLabel: openLabel,
    openIcon: openIcon,
    includeGamesTab: includeGamesTab,
    includeShare: includeShare,
    playerAddLabel: playerAddLabel,
    playerRemoveLabel: playerRemoveLabel,
    extra: extra,
  );
}

/// "Share profile" for a player row: the same chessever.com link the profile's
/// own share preview carries. Null when the player has no public page (no FIDE
/// id and no memorial route), so a menu never offers a share that cannot work.
LibraryMenuAction? sharePlayerProfileAction(
  BuildContext context, {
  required String playerName,
  int? fideId,
  String? memorialRouteId,
  String label = 'Share profile',
}) {
  final url = buildPlayerProfileShareUrl(
    fideId,
    playerName: playerName,
    memorialRouteId: memorialRouteId,
  );
  if (url == null) return null;
  // Measured now, while the pressed row is certainly laid out: iPad anchors
  // the share sheet to it, and the row may have scrolled by the time the menu
  // closes.
  final origin = _originOf(context);
  return LibraryMenuAction(
    icon: Icons.ios_share_rounded,
    label: label,
    onSelected: () async {
      HapticFeedbackService.buttonPress();
      await Share.share(
        url,
        subject: playerName.trim().isEmpty ? null : playerName.trim(),
        sharePositionOrigin: origin,
      );
    },
  );
}

/// Pushes the player's profile. The one "Open profile" every row without a
/// richer destination uses.
void openPlayerProfileFor(
  BuildContext context,
  PlayerStandingModel player, {
  PlayerProfileTab? initialTab,
}) {
  if (!context.mounted) return;
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerProfileScreen(
          fideId: player.fideId,
          playerName: player.name,
          title: player.title,
          federation: player.countryCode,
          rating: player.score > 0 ? player.score : null,
          gamebasePlayerId: player.gamebasePlayerId,
          memorialSourceIdentity: player.memorialSourceIdentity,
          memorialRouteId: player.memorialRouteId,
          initialTab: initialTab,
        ),
      ),
    ),
  );
}

Rect _originOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize && box.attached) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return const Rect.fromLTWH(0, 0, 1, 1);
}

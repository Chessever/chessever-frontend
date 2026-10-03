import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A preview is never board input. Resolve protected content through the
/// collection endpoint, after the current server verdict / shared access gate.
/// Apply the visible ID sequence to the authorized response so board swiping
/// cannot escape a search, opening or player scope.
Future<List<GamesTourModel>?> resolvePlayableCollectionGames({
  required CollectionsRepository repository,
  required String slug,
  required List<String> visibleIds,
  required Future<bool> Function(Collection collection) requestAccess,
  required bool Function() stillCurrent,
}) async {
  final release = repository.holdFreshAccess(slug);
  try {
    final detail = await repository.fetchCollection(slug);
    if (!stillCurrent()) return null;
    if (detail.isPremium && detail.contentLocked != false) {
      if (!await requestAccess(detail) || !stillCurrent()) return null;
    }
    // The server authenticates this separately, including stale local Premium
    // and expired sessions. No unprotected /game or saved-copy fallback.
    final authorized = await repository.fetchPlayableGames(slug);
    if (!stillCurrent()) return null;
    final byId = {for (final game in authorized) game.id: game.game};
    if (visibleIds.any((id) => !byId.containsKey(id))) {
      throw const FormatException('Collection changed; refresh the game list.');
    }
    return [for (final id in visibleIds) byId[id]!];
  } finally {
    release();
  }
}

Future<void> openCollectionGame(
  BuildContext context,
  WidgetRef ref, {
  required String slug,
  required List<GamesTourModel> previews,
  required int index,
}) async {
  if (index < 0 || index >= previews.length) return;
  final owner = ref.read(currentUserProvider)?.id;
  bool current() =>
      context.mounted && ref.read(currentUserProvider)?.id == owner;
  try {
    final games = await resolvePlayableCollectionGames(
      repository: ref.read(collectionsRepositoryProvider),
      slug: slug,
      visibleIds: [for (final game in previews) game.gameId],
      requestAccess: (collection) => ensurePremiumGameAccess(
        context,
        featureId: collectionPaywallFeatureId(collection.kind),
        returnTo: kCollectionPaywallReturnTo,
      ),
      stillCurrent: current,
    );
    if (games == null || !context.mounted || !current()) return;
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChessBoardScreenNew(
          currentIndex: index,
          games: games,
          viewSource: ChessboardView.tour,
          showGamebaseButton: false,
          disableGamebaseOverlayByDefault: true,
          allowGameExport: false,
        ),
      ),
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

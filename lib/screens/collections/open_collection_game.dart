import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/feed/models/feed_collection.dart';
import 'package:chessever2/screens/feed/providers/board_feed_client.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:chessever2/widgets/paywall/past_game_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A preview is never board input. Resolve protected content through the
/// collection endpoint, after the current server verdict / shared access gate.
/// Apply the visible ID sequence to the authorized response so board swiping
/// cannot escape a search, opening or player scope.
Future<List<GamesTourModel>?> resolvePlayableCollectionGames({
  required CollectionsRepository repository,
  required String slug,
  required List<String>? visibleIds,
  ValueChanged<Collection>? onResolved,
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
    onResolved?.call(detail);
    if (visibleIds == null) return [for (final game in authorized) game.game];
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
  await _openCollection(
    context,
    ref,
    slug: slug,
    previews: previews,
    index: index,
  );
}

Future<CollectionCheckpoint?> openFeedCollectionGame(
  BuildContext context,
  WidgetRef ref, {
  required Collection collection,
  required String featuredGameId,
  required CollectionCheckpoint? checkpoint,
}) async {
  final client = BoardFeedClient.forCurrentUser();
  final userId = ref.read(currentUserProvider)?.id;
  // A checkpoint can resume the selected game without changing which game opens.
  if (checkpoint?.gameId != featuredGameId) checkpoint = null;
  if (client != null) {
    try {
      final latest = await client.loadCollectionProgress(collection.id);
      if (latest?.gameId == featuredGameId) checkpoint = latest;
    } catch (_) {
      // The feed card already supplies the last known position.
    }
  }
  if (!context.mounted || ref.read(currentUserProvider)?.id != userId) {
    return null;
  }
  return _openCollection(
    context,
    ref,
    slug: collection.slug,
    featuredGameId: featuredGameId,
    checkpoint: checkpoint,
  );
}

Future<CollectionCheckpoint?> _openCollection(
  BuildContext context,
  WidgetRef ref, {
  required String slug,
  List<GamesTourModel>? previews,
  int index = 0,
  String? featuredGameId,
  CollectionCheckpoint? checkpoint,
}) async {
  final owner = ref.read(currentUserProvider)?.id;
  bool current() =>
      context.mounted && ref.read(currentUserProvider)?.id == owner;
  try {
    Collection? detail;
    final games = await resolvePlayableCollectionGames(
      repository: ref.read(collectionsRepositoryProvider),
      slug: slug,
      visibleIds: previews == null
          ? null
          : [for (final game in previews) game.gameId],
      onResolved: (resolved) => detail = resolved,
      requestAccess: (collection) => ensurePremiumGameAccess(
        context,
        featureId: collectionPaywallFeatureId(collection.kind),
        returnTo: kCollectionPaywallReturnTo,
      ),
      stillCurrent: current,
    );
    if (games == null || !context.mounted || !current()) return null;
    if (games.isEmpty) {
      showAppSnack(
        context,
        'No playable games are available in this collection.',
      );
      return null;
    }
    if (featuredGameId != null) {
      final featuredIndex = games.indexWhere(
        (game) => game.gameId == featuredGameId,
      );
      if (featuredIndex < 0) {
        showAppSnack(context, 'This game is no longer in the collection.');
        return null;
      }
      index = featuredIndex;
    }
    if (checkpoint != null) {
      final resumeIndex = games.indexWhere(
        (game) => game.gameId == checkpoint!.gameId,
      );
      if (resumeIndex >= 0) {
        index = resumeIndex;
      } else {
        showAppSnack(
          context,
          'That game is no longer in this collection. Opening an available game.',
        );
        checkpoint = null;
      }
    }
    if (!await ensurePastGameAccess(
          context,
          game: games[index],
          publishedEventGame: true,
        ) ||
        !context.mounted ||
        !current()) {
      return null;
    }
    final navigation = gameNavigationForAccess(
      games: games,
      index: index,
      premium: ref.read(premiumAccessProvider),
      publishedEventGame: true,
    );
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;
    final client = BoardFeedClient.forCurrentUser();
    final id = detail?.id;
    final writer = client != null && id != null && id.isNotEmpty
        ? _CollectionProgressWriter(client, id, checkpoint)
        : null;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChessBoardScreenNew(
            currentIndex: navigation.index,
            games: navigation.games,
            viewSource: ChessboardView.tour,
            showGamebaseButton: false,
            disableGamebaseOverlayByDefault: true,
            allowGameExport: false,
            initialMoveIndexByGameId: checkpoint == null
                ? null
                : {checkpoint.gameId: checkpoint.moveIndex},
            onStudyPositionChanged: writer?.record,
          ),
        ),
      );
    } finally {
      await writer?.finish();
    }
    return writer?.saved;
  } catch (error) {
    if (!context.mounted || !current()) return null;
    showAppSnack(
      context,
      error is CollectionsRequestException && error.isPremiumGate
          ? "Couldn't confirm access to this game. Please try again."
          : "Couldn't open this game. Please try again.",
      tone: AppSnackTone.danger,
    );
    return null;
  }
}

class _CollectionProgressWriter {
  _CollectionProgressWriter(this.client, this.id, this._position);

  final BoardFeedClient client;
  final String id;
  CollectionCheckpoint? _position;
  CollectionCheckpoint? saved;
  ({CollectionCheckpoint position, DateTime observedAt})? _pending;
  Timer? _timer;
  Future<void>? _inFlight;

  void record(String gameId, int moveIndex) {
    final position = (gameId: gameId, moveIndex: moveIndex);
    if (_position == position) return;
    _position = position;
    _pending = (position: position, observedAt: DateTime.now());
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_flush()),
    );
  }

  Future<void> _flush() async {
    if (_inFlight case final running?) await running;
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    final write = _write(pending);
    _inFlight = write;
    await write;
    if (identical(_inFlight, write)) _inFlight = null;
  }

  Future<void> _write(
    ({CollectionCheckpoint position, DateTime observedAt}) pending,
  ) async {
    try {
      saved = await client.saveCollectionProgress(
        id,
        pending.position,
        pending.observedAt,
      );
    } catch (_) {
      _pending ??= pending;
    }
  }

  Future<void> finish() async {
    _timer?.cancel();
    await _flush();
  }
}

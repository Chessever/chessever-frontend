import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Loads a chess player from Supabase by FIDE ID.
final chessPlayerByFideIdProvider = FutureProvider.family
    .autoDispose<ChessPlayer?, int?>((ref, fideId) async {
      if (fideId == null || fideId <= 0) return null;
      return ref.read(chessPlayerRepositoryProvider).getPlayerByFideId(fideId);
    });

/// Backfills missing scorecard player fields (title/federation/rating)
/// using the canonical `chess_players` row for the player's FIDE ID.
final backfilledStandingPlayerProvider = FutureProvider.family
    .autoDispose<PlayerStandingModel, PlayerStandingModel>((ref, player) async {
      final fideId = player.fideId;
      if (fideId == null || fideId <= 0) return player;

      final needsBackfill =
          (player.title?.trim().isEmpty ?? true) ||
          player.countryCode.trim().isEmpty ||
          player.score <= 0;
      if (!needsBackfill) return player;

      final chessPlayer = await ref.watch(
        chessPlayerByFideIdProvider(fideId).future,
      );
      if (chessPlayer == null) return player;

      final normalizedTitle = ChessTitleUtils.normalize(chessPlayer.title);
      final mergedTitle =
          (player.title?.trim().isNotEmpty ?? false)
              ? player.title
              : (normalizedTitle.isNotEmpty ? normalizedTitle : player.title);
      final mergedCountry =
          player.countryCode.trim().isNotEmpty
              ? player.countryCode.trim()
              : (chessPlayer.country?.trim() ?? '');
      final mergedScore =
          player.score > 0
              ? player.score
              : (chessPlayer.rating ?? player.score);

      return player.copyWith(
        title: mergedTitle,
        countryCode: mergedCountry,
        score: mergedScore,
      );
    });

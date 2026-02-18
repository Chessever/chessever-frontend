import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
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
      final needsBackfill =
          player.fideId == null ||
          player.fideId! <= 0 ||
          (player.title?.trim().isEmpty ?? true) ||
          player.countryCode.trim().isEmpty ||
          player.score <= 0;
      if (!needsBackfill) return player;

      int? resolvedFideId =
          (player.fideId != null && player.fideId! > 0) ? player.fideId : null;
      var mergedPlayer = player;

      if (resolvedFideId == null) {
        final gamebasePlayerId = player.gamebasePlayerId?.trim();
        if (gamebasePlayerId != null && gamebasePlayerId.isNotEmpty) {
          try {
            final gamebasePlayer = await ref
                .read(gamebaseRepositoryProvider)
                .getPlayerById(gamebasePlayerId);
            if (gamebasePlayer != null) {
              final parsedFide = int.tryParse(gamebasePlayer.fideId);
              if (parsedFide != null && parsedFide > 0) {
                resolvedFideId = parsedFide;
              }
              final normalizedTitle = ChessTitleUtils.normalize(
                gamebasePlayer.title,
              );
              mergedPlayer = mergedPlayer.copyWith(
                fideId: resolvedFideId,
                title:
                    (mergedPlayer.title?.trim().isNotEmpty ?? false)
                        ? mergedPlayer.title
                        : (normalizedTitle.isNotEmpty ? normalizedTitle : null),
                countryCode:
                    mergedPlayer.countryCode.trim().isNotEmpty
                        ? mergedPlayer.countryCode
                        : gamebasePlayer.fed,
                score:
                    mergedPlayer.score > 0
                        ? mergedPlayer.score
                        : (gamebasePlayer.ratingClassical ??
                            gamebasePlayer.highestRating ??
                            mergedPlayer.score),
              );
            }
          } catch (_) {
            // Best effort only.
          }
        }
      }

      if (resolvedFideId == null) {
        final query = player.name.trim();
        if (query.isNotEmpty) {
          try {
            final candidates = await ref
                .read(chessPlayerRepositoryProvider)
                .searchAllPlayers(query: query, limit: 20);
            ChessPlayer? best;
            final target = _normalizePlayerName(query);
            for (final candidate in candidates) {
              final candidateNorm = _normalizePlayerName(candidate.name);
              if (candidateNorm == target) {
                best = candidate;
                break;
              }
              if (best == null && candidateNorm.contains(target)) {
                best = candidate;
              }
            }
            if (best != null && best.fideid > 0) {
              resolvedFideId = best.fideid;
              mergedPlayer = mergedPlayer.copyWith(
                fideId: resolvedFideId,
                title:
                    (mergedPlayer.title?.trim().isNotEmpty ?? false)
                        ? mergedPlayer.title
                        : best.title,
                countryCode:
                    mergedPlayer.countryCode.trim().isNotEmpty
                        ? mergedPlayer.countryCode
                        : (best.country ?? ''),
                score:
                    mergedPlayer.score > 0
                        ? mergedPlayer.score
                        : (best.rating ?? mergedPlayer.score),
              );
            }
          } catch (_) {
            // Best effort only.
          }
        }
      }

      if (resolvedFideId == null || resolvedFideId <= 0) {
        return mergedPlayer;
      }

      final chessPlayer = await ref.watch(
        chessPlayerByFideIdProvider(resolvedFideId).future,
      );
      if (chessPlayer == null) return mergedPlayer;

      final normalizedTitle = ChessTitleUtils.normalize(chessPlayer.title);
      final mergedTitle =
          (mergedPlayer.title?.trim().isNotEmpty ?? false)
              ? mergedPlayer.title
              : (normalizedTitle.isNotEmpty
                  ? normalizedTitle
                  : mergedPlayer.title);
      final mergedCountry =
          mergedPlayer.countryCode.trim().isNotEmpty
              ? mergedPlayer.countryCode.trim()
              : (chessPlayer.country?.trim() ?? '');
      final mergedScore =
          mergedPlayer.score > 0
              ? mergedPlayer.score
              : (chessPlayer.rating ?? mergedPlayer.score);

      return mergedPlayer.copyWith(
        fideId: resolvedFideId,
        title: mergedTitle,
        countryCode: mergedCountry,
        score: mergedScore,
      );
    });

String _normalizePlayerName(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(',', ' ')
      .replaceAll('.', ' ')
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ')
      .trim();
}

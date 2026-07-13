import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/bracket_game_result.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';

Future<void> showKnockoutMatchSheet({
  required BuildContext context,
  required KnockoutMatch match,
  required ValueChanged<Games> onGameTap,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder:
        (sheetContext) => _KnockoutMatchSheet(
          match: match,
          onGameTap: (game) {
            Navigator.of(sheetContext).pop();
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => onGameTap(game),
            );
          },
        ),
  );
}

class _KnockoutMatchSheet extends StatelessWidget {
  const _KnockoutMatchSheet({required this.match, required this.onGameTap});

  final KnockoutMatch match;
  final ValueChanged<Games> onGameTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.76;
    final liveGameId = _liveGameId(match);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        key: const ValueKey('knockout-match-sheet'),
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textPrimary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Match details',
                      style: TextStyle(
                        fontFamily: 'InterDisplay',
                        color: colors.textPrimary,
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: colors.iconSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _AggregateCard(match: match),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
              child: Row(
                children: [
                  Text(
                    'Games',
                    style: TextStyle(
                      fontFamily: 'InterDisplay',
                      color: colors.textPrimary,
                      fontSize: 13,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceRecessed,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${match.games.length}',
                      style: TextStyle(
                        fontFamily: 'InterDisplay',
                        color: colors.textSecondary,
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                itemCount: match.games.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final game = match.games[index];
                  return _LegTile(
                    game: game,
                    label: _legLabel(match.games, index),
                    isLive: game.id == liveGameId,
                    onTap: () {
                      HapticFeedbackService.navigation();
                      onGameTap(game);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AggregateCard extends StatelessWidget {
  const _AggregateCard({required this.match});

  final KnockoutMatch match;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.popup,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          _AggregateParticipantRow(
            participant: match.participant1,
            score: match.participant1Score,
            isWinner: match.winner?.id == match.participant1.id,
            isEliminated:
                match.winner != null &&
                match.winner?.id != match.participant1.id,
            isLive: match.isLive,
          ),
          Divider(height: 1, thickness: 1, color: colors.divider),
          _AggregateParticipantRow(
            participant: match.participant2,
            score: match.participant2Score,
            isWinner: match.winner?.id == match.participant2.id,
            isEliminated:
                match.winner != null &&
                match.winner?.id != match.participant2.id,
            isLive: false,
          ),
        ],
      ),
    );
  }
}

class _AggregateParticipantRow extends StatelessWidget {
  const _AggregateParticipantRow({
    required this.participant,
    required this.score,
    required this.isWinner,
    required this.isEliminated,
    required this.isLive,
  });

  final BracketParticipant participant;
  final double score;
  final bool isWinner;
  final bool isEliminated;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasFlag = FederationFlag.hasVisibleFlag(participant.federation);

    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (isLive) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.brand,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (hasFlag) ...[
              FederationFlag(
                federation: participant.federation,
                width: 20,
                height: 14,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Text(
                participant.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'InterDisplay',
                  color:
                      isEliminated ? colors.textTertiary : colors.textPrimary,
                  fontSize: 14,
                  height: 1,
                  fontWeight: isWinner ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            if (isWinner) ...[
              Icon(Icons.check_rounded, size: 17, color: colors.brand),
              const SizedBox(width: 5),
            ],
            Text(
              _scoreLabel(score),
              style: TextStyle(
                fontFamily: 'InterDisplay',
                color:
                    isWinner
                        ? colors.brand
                        : isEliminated
                        ? colors.textTertiary
                        : colors.textPrimary,
                fontSize: 19,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegTile extends StatelessWidget {
  const _LegTile({
    required this.game,
    required this.label,
    required this.isLive,
    required this.onTap,
  });

  final Games game;
  final String label;
  final bool isLive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final players = game.players ?? const <Player>[];
    final whiteName = players.isNotEmpty ? players.first.name : '';
    final blackName = players.length > 1 ? players[1].name : '';
    final parsedResult = bracketGameResult(game);
    final result =
        isLive
            ? 'LIVE'
            : parsedResult.displayText.isNotEmpty
            ? parsedResult.displayText
            : '—';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('bracket-leg-${game.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
          decoration: BoxDecoration(
            color: colors.surfaceRecessed.withValues(
              alpha: context.isLightTheme ? 0.72 : 0.62,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.divider.withValues(alpha: 0.72)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color:
                      isLive
                          ? colors.brand.withValues(alpha: 0.12)
                          : colors.surface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  isLive
                      ? Icons.radio_button_checked_rounded
                      : Icons.sports_esports_outlined,
                  size: 17,
                  color: isLive ? colors.brand : colors.iconSecondary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'InterDisplay',
                        color: colors.textPrimary,
                        fontSize: 12.5,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (whiteName.isNotEmpty || blackName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$whiteName${whiteName.isNotEmpty && blackName.isNotEmpty ? ' · ' : ''}$blackName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'InterDisplay',
                          color: colors.textSecondary,
                          fontSize: 10.5,
                          height: 1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                result,
                style: TextStyle(
                  fontFamily: 'InterDisplay',
                  color: isLive ? colors.brand : colors.textPrimary,
                  fontSize: isLive ? 10 : 13,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: isLive ? 0.3 : 0,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.iconSecondary,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _liveGameId(KnockoutMatch match) {
  if (!match.isLive) return null;
  final undecided = match.games
      .where((game) => bracketGameResult(game) == BracketGameResult.undecided)
      .toList(growable: false);
  if (undecided.isEmpty) return null;

  // Prefer the latest leg with actual move evidence. When a live round has
  // started but its first move has not arrived, the latest undecided leg is
  // still the only evidence-backed active candidate.
  for (final game in undecided.reversed) {
    if (game.lastMove?.trim().isNotEmpty ?? false) return game.id;
  }
  return undecided.last.id;
}

String _scoreLabel(double score) {
  if (score == score.roundToDouble()) return score.toInt().toString();
  return score.toStringAsFixed(1);
}

String _legLabel(List<Games> games, int index) {
  final game = games[index];
  final marker = '${game.roundSlug} ${game.name ?? ''}'.toLowerCase();
  final isRapid = marker.contains('rapid');
  final isBlitz = marker.contains('blitz');
  final isTiebreak =
      marker.contains('tiebreak') ||
      marker.contains('tie-break') ||
      marker.contains('playoff');

  if (isRapid || isBlitz || isTiebreak) {
    final sameKindBefore =
        games.take(index).where((candidate) {
          final candidateMarker =
              '${candidate.roundSlug} ${candidate.name ?? ''}'.toLowerCase();
          if (isRapid) return candidateMarker.contains('rapid');
          if (isBlitz) return candidateMarker.contains('blitz');
          return candidateMarker.contains('tiebreak') ||
              candidateMarker.contains('tie-break') ||
              candidateMarker.contains('playoff');
        }).length;
    final prefix =
        isRapid
            ? 'Rapid tiebreak'
            : isBlitz
            ? 'Blitz tiebreak'
            : 'Tiebreak';
    return '$prefix ${sameKindBefore + 1}';
  }

  final mainGameNumber =
      games.take(index).where((candidate) {
        final candidateMarker =
            '${candidate.roundSlug} ${candidate.name ?? ''}'.toLowerCase();
        return !candidateMarker.contains('rapid') &&
            !candidateMarker.contains('blitz') &&
            !candidateMarker.contains('tiebreak') &&
            !candidateMarker.contains('tie-break') &&
            !candidateMarker.contains('playoff');
      }).length +
      1;
  return 'Game $mainGameNumber';
}

import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';

class KnockoutMatchCard extends StatelessWidget {
  const KnockoutMatchCard({
    required this.match,
    required this.onTap,
    this.isFocused = false,
    super.key,
  });

  final KnockoutMatch match;
  final bool isFocused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final winnerId = match.winner?.id;
    final semantics =
        StringBuffer()
          ..write(match.isLive ? 'Live match. ' : 'Match. ')
          ..write(
            '${match.participant1.displayName} ${_scoreLabel(match.participant1Score)}, '
            '${match.participant2.displayName} ${_scoreLabel(match.participant2Score)}',
          );
    if (match.winner != null) {
      semantics.write('. ${match.winner!.displayName} advances');
    }

    return Semantics(
      button: true,
      label: semantics.toString(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('bracket-match-${match.key}'),
          onTap: () {
            HapticFeedbackService.cardTap();
            onTap();
          },
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: colors.popup,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    isFocused
                        ? colors.brand.withValues(alpha: 0.78)
                        : colors.divider,
                width: isFocused ? 1.4 : 0.8,
              ),
              boxShadow:
                  context.isLightTheme
                      ? [
                        BoxShadow(
                          color: colors.shadow,
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                      : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: _ParticipantRow(
                          participant: match.participant1,
                          score: match.participant1Score,
                          isWinner: winnerId == match.participant1.id,
                          isEliminated:
                              winnerId != null &&
                              winnerId != match.participant1.id,
                          isLeader: match.leader?.id == match.participant1.id,
                        ),
                      ),
                      Divider(
                        height: 0.8,
                        thickness: 0.8,
                        color: colors.divider,
                      ),
                      Expanded(
                        child: _ParticipantRow(
                          participant: match.participant2,
                          score: match.participant2Score,
                          isWinner: winnerId == match.participant2.id,
                          isEliminated:
                              winnerId != null &&
                              winnerId != match.participant2.id,
                          isLeader: match.leader?.id == match.participant2.id,
                        ),
                      ),
                    ],
                  ),
                  if (match.isLive)
                    Positioned(
                      left: 0,
                      top: 11,
                      bottom: 11,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: colors.brand,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  if (match.isLive)
                    Positioned(
                      top: 5,
                      right: 6,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: colors.brand,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: colors.brand.withValues(alpha: 0.42),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.score,
    required this.isWinner,
    required this.isEliminated,
    required this.isLeader,
  });

  final BracketParticipant participant;
  final double score;
  final bool isWinner;
  final bool isEliminated;
  final bool isLeader;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primaryColor =
        isEliminated ? colors.textTertiary : colors.textPrimary;
    final federation = participant.federation;
    final hasFlag = FederationFlag.hasVisibleFlag(federation);
    final metadata = <String>[
      if ((participant.title ?? '').trim().isNotEmpty)
        participant.title!.trim(),
      if (participant.rating != null && participant.rating! > 0)
        participant.rating.toString(),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 10, 5),
      child: Row(
        children: [
          if (hasFlag) ...[
            FederationFlag(
              federation: federation,
              width: 17,
              height: 12,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        participant.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'InterDisplay',
                          color: primaryColor,
                          fontSize: 12.5,
                          height: 1.1,
                          fontWeight:
                              isWinner ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isWinner) ...[
                      const SizedBox(width: 3),
                      Icon(Icons.check_rounded, size: 13, color: colors.brand),
                    ],
                  ],
                ),
                if (metadata.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    metadata,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'InterDisplay',
                      color:
                          isEliminated
                              ? colors.textTertiary.withValues(alpha: 0.72)
                              : colors.textSecondary,
                      fontSize: 10,
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
            _scoreLabel(score),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'InterDisplay',
              color:
                  isWinner
                      ? colors.brand
                      : isEliminated
                      ? colors.textTertiary
                      : isLeader
                      ? colors.brand
                      : colors.textPrimary,
              fontSize: 15,
              height: 1,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

String _scoreLabel(double score) {
  if (score == score.roundToDouble()) return score.toInt().toString();
  return score.toStringAsFixed(1);
}

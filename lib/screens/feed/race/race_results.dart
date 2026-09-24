import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/feed/race/race_chess.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_copy.dart';
import 'package:chessever2/screens/feed/race/race_flames.dart';
import 'package:chessever2/screens/feed/race/race_widgets.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// How the race went: the score and the flames it earned, the time, the
/// level reached, the best streak and the accuracy, the standings in
/// multiplayer, and every puzzle with its answer. The numbers are the room's.
class RaceResults extends ConsumerWidget {
  const RaceResults({
    required this.onBack,
    required this.backLabel,
    this.onSignIn,
    super.key,
  });

  /// Leaves Puzzle Race (back to where it was opened from).
  final VoidCallback onBack;

  /// Where [onBack] goes ("Feed"), named on the way out.
  final String backLabel;

  /// A guest's way to keep the flames they earn from now on; null when
  /// already signed in.
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(raceControllerProvider);
    final colors = context.colors;
    final records = state.records;
    final elapsed = state.finalElapsedMs ?? state.lastElapsedMs ?? 0;
    final accuracy = state.accuracy;
    final standings = _standings(state);
    final stillRacing =
        state.multiplayer && standings.any((row) => !row.finished);

    final title = AppTypography.textLgBold.copyWith(
      fontSize: 18,
      height: 24 / 18,
      color: colors.textPrimary,
    );

    return Column(
      children: [
        RaceHeader(
          back: RaceBackControl(
            key: const ValueKey('race_back'),
            glyph: RaceGlyphs.back,
            label: backLabel,
            semanticsLabel: 'Back to $backLabel',
            onTap: onBack,
          ),
          trailing: Builder(
            builder: (buttonContext) => RaceIconButton(
              key: const ValueKey('race_share_result'),
              glyph: FeedGlyphs.share,
              label: 'Share result',
              onTap: () => unawaited(_share(buttonContext, state)),
            ),
          ),
          // Title at the start and the mode at the end while both fit on one
          // line. At large text on a narrow phone the mode drops under the
          // title instead of either being cut.
          title: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Semantics(
                  header: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'Race over',
                      key: const ValueKey('race_results_title'),
                      maxLines: 1,
                      softWrap: false,
                      style: AppTypography.displayXsBold.copyWith(
                        fontSize: 28,
                        height: 34 / 28,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
                Text(
                  '${raceModeName(state.mode)} · '
                  '${state.multiplayer ? 'Multiplayer' : 'Solo'}',
                  key: const ValueKey('race_results_mode'),
                  maxLines: 1,
                  softWrap: false,
                  style: AppTypography.textSmMedium.copyWith(
                    fontSize: 14,
                    height: 20 / 14,
                    color: raceQuietInk(colors),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: CustomScrollView(
            key: const ValueKey('race_results'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Hero(state: state, onSignIn: onSignIn),
                      const SizedBox(height: 24),
                      _StatGrid(
                        cells: [
                          ('Time', formatRaceClock(elapsed)),
                          ('Level reached', '${state.displayLevel}'),
                          ('Best streak', '${state.bestStreak}'),
                          (
                            'Accuracy',
                            accuracy == null
                                ? '-'
                                : '${(accuracy * 100).round()}%',
                          ),
                        ],
                      ),
                      if (state.multiplayer && standings.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        Semantics(
                          header: true,
                          child: Text('Standings', style: title),
                        ),
                        if (stillRacing) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Others are still racing. This updates live.',
                            style: AppTypography.textSmRegular.copyWith(
                              fontSize: 14,
                              height: 19 / 14,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        _StandingsTable(rows: standings, you: state.you),
                      ],
                      const SizedBox(height: 32),
                      Semantics(
                        header: true,
                        child: Text(
                          records.isEmpty ? 'No puzzles finished' : 'Puzzles',
                          style: title,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.builder(
                  itemCount: records.length,
                  itemBuilder: (context, i) =>
                      _PuzzleRow(record: records[i], number: i + 1),
                ),
              ),
            ],
          ),
        ),
        _Actions(backLabel: backLabel, onBack: onBack),
      ],
    );
  }

  Future<void> _share(BuildContext context, RaceState state) async {
    unawaited(HapticFeedbackService.buttonPress());
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final my = state.myResult;
    final text = raceShareText(
      mode: state.mode,
      multiplayer: state.multiplayer,
      score: state.score,
      elapsedMs: state.finalElapsedMs ?? state.lastElapsedMs ?? 0,
      displayLevel: state.displayLevel,
      bestStreak: state.bestStreak,
      rank: my?.rank,
      players: state.results.length,
    );
    try {
      await Share.share(text, sharePositionOrigin: origin);
    } catch (error) {
      debugPrint('[Race] share failed: ${error.runtimeType}');
      if (messenger != null) {
        showAppSnackOn(
          messenger,
          "Couldn't open sharing.",
          tone: AppSnackTone.danger,
        );
      }
    }
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.state, required this.onSignIn});

  final RaceState state;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final quiet = raceQuietInk(colors);
    final earned = state.flamesEarned ?? 0;
    final previous = state.previousBest;
    final String? bestLine = state.newBest
        ? (previous != null && previous > 0
              ? 'New best, up from $previous'
              : 'New best')
        : previous != null && previous > 0
        ? 'Best $previous'
        : null;
    final summary = Semantics(
      label:
          '${state.score} solved. ${raceFinishLine(state.finishReason)}.'
          '${state.unconfirmed ? ' $kRaceUnconfirmedLine.' : ''}'
          '${bestLine == null ? '' : ' $bestLine.'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${state.score}',
                key: const ValueKey('race_final_score'),
                style: AppTypography.displayXlBold.copyWith(
                  fontSize: 76,
                  height: 84 / 76,
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'solved',
                  style: AppTypography.textLgMedium.copyWith(
                    fontSize: 18,
                    height: 24 / 18,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            raceFinishLine(state.finishReason),
            style: AppTypography.textMdMedium.copyWith(
              fontSize: 16,
              height: 22 / 16,
              color: colors.textSecondary,
            ),
          ),
          if (state.unconfirmed) ...[
            const SizedBox(height: 2),
            Text(
              kRaceUnconfirmedLine,
              key: const ValueKey('race_unconfirmed'),
              style: AppTypography.textSmRegular.copyWith(
                fontSize: 14,
                height: 19 / 14,
                color: quiet,
              ),
            ),
          ],
          if (bestLine != null) ...[
            const SizedBox(height: 6),
            Text(
              bestLine,
              key: const ValueKey('race_best_line'),
              style: AppTypography.textMdBold.copyWith(
                fontSize: 16,
                height: 22 / 16,
                color: state.newBest ? colors.titleAccent : quiet,
              ),
            ),
          ],
        ],
      ),
    );
    if (earned <= 0) return summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        summary,
        const SizedBox(height: 14),
        RaceFlameMark(
          key: const ValueKey('race_flames_earned'),
          flames: earned,
          earned: true,
          size: 20,
        ),
        if (onSignIn != null)
          RaceTextLink(
            key: const ValueKey('race_keep_flames'),
            label: 'Sign in to keep your flames',
            onTap: onSignIn,
          ),
      ],
    );
  }
}

/// Two by two figures, each column on one grid line.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.cells});

  final List<(String, String)> cells;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget cell((String, String) c) => Semantics(
      label: '${c.$1}: ${c.$2}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A long time at the largest text on a narrow phone scales down
          // a little rather than lose a digit.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              c.$2,
              maxLines: 1,
              style: AppTypography.displayXsBold.copyWith(
                fontSize: 26,
                height: 32 / 26,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            c.$1,
            style: AppTypography.textSmMedium.copyWith(
              fontSize: 13,
              height: 18 / 13,
              color: raceQuietInk(colors),
            ),
          ),
        ],
      ),
    );
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 18));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cell(cells[i])),
            const SizedBox(width: 16),
            Expanded(
              child: i + 1 < cells.length
                  ? cell(cells[i + 1])
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
    return Column(children: rows);
  }
}

typedef _Standing = ({
  String id,
  String name,
  int score,
  int mistakes,
  int elapsedMs,
  bool finished,

  /// Whether [elapsedMs] is the room's time for this run. Only a run the
  /// room's results already closed has one: `results` is frozen at this
  /// player's own finish, and a run that ends after it arrives as a snapshot
  /// without a time until the room's final results.
  bool timeKnown,

  /// Position in the room's results, the last tiebreak.
  int order,
});

/// The room's results, with live scores for anyone still racing.
List<_Standing> _standings(RaceState state) {
  final live = {for (final p in state.players) p.id: p};
  final results = state.results;
  final rows = <_Standing>[
    for (var i = 0; i < results.length; i++)
      if (!results[i].finished && live[results[i].id] != null)
        (
          id: results[i].id,
          name: results[i].name,
          score: live[results[i].id]!.score,
          mistakes: live[results[i].id]!.mistakes,
          elapsedMs: results[i].elapsedMs,
          finished: live[results[i].id]!.finished,
          timeKnown: false,
          order: i,
        )
      else
        (
          id: results[i].id,
          name: results[i].name,
          score: results[i].score,
          mistakes: results[i].mistakes,
          elapsedMs: results[i].elapsedMs,
          finished: results[i].finished,
          timeKnown: results[i].finished,
          order: i,
        ),
  ];
  rows.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byMistakes = a.mistakes.compareTo(b.mistakes);
    if (byMistakes != 0) return byMistakes;
    // A run with a known time ended before any run without one, so it leads;
    // an unknown time never takes part in the order.
    if (a.timeKnown != b.timeKnown) return a.timeKnown ? -1 : 1;
    if (a.timeKnown) {
      final byTime = a.elapsedMs.compareTo(b.elapsedMs);
      if (byTime != 0) return byTime;
    }
    return a.order.compareTo(b.order);
  });
  return rows;
}

/// Name, score and time, one row per player. The score and time columns are
/// as wide as their widest entry at the current text size (never narrower
/// than at 1x), so every row lines up and no figure is cut.
class _StandingsTable extends StatelessWidget {
  const _StandingsTable({required this.rows, required this.you});

  final List<_Standing> rows;
  final String? you;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    TableRow row(_Standing row) {
      final isMe = row.id == you;
      final base = AppTypography.textMdMedium.copyWith(
        fontSize: 15,
        height: 20 / 15,
        color: isMe ? colors.textPrimary : colors.textSecondary,
        fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      final time = !row.finished
          ? 'racing'
          : row.timeKnown
          ? formatRaceClock(row.elapsedMs)
          : 'done';
      return TableRow(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: RaceNameLine(name: row.name, isMe: isMe, style: base),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12),
            child: Text(
              '${row.score}',
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.end,
              style: base,
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12),
            child: Text(
              time,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.end,
              style: base.copyWith(
                fontWeight: FontWeight.w500,
                color: row.finished ? raceQuietInk(colors) : colors.titleAccent,
              ),
            ),
          ),
        ],
      );
    }

    return Table(
      key: const ValueKey('race_standings'),
      columnWidths: const {
        0: FlexColumnWidth(),
        1: MaxColumnWidth(FixedColumnWidth(52), IntrinsicColumnWidth()),
        2: MaxColumnWidth(FixedColumnWidth(84), IntrinsicColumnWidth()),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [for (final r in rows) row(r)],
    );
  }
}

/// One finished puzzle: its rating, how it went, the time it took, and its
/// solution in SAN.
class _PuzzleRow extends StatelessWidget {
  const _PuzzleRow({required this.record, required this.number});

  final RacePuzzleRecord record;
  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final puzzle = record.puzzle;
    final solution = raceSanLine(puzzle.fen, puzzle.setupMove, record.solution);
    final outcome = record.solved ? 'Solved' : 'Missed';
    final tint = raceVerdictInk(context, solved: record.solved);
    final figures = AppTypography.textMdMedium.copyWith(
      fontSize: 15,
      height: 20 / 15,
      color: colors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label:
          'Puzzle $number, rated ${puzzle.rating}, $outcome in '
          '${formatPuzzleTime(record.timeMs)}. Solution $solution',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '#$number',
                    style: figures.copyWith(color: raceQuietInk(colors)),
                  ),
                ),
                Text(
                  '${puzzle.rating}',
                  style: figures.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    outcome,
                    style: figures.copyWith(
                      color: tint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  formatPuzzleTime(record.timeMs),
                  style: figures.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Text(
                solution.isEmpty ? 'No solution sent' : solution,
                style: AppTypography.textSmRegular.copyWith(
                  fontSize: 14,
                  height: 20 / 14,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The two ways on: back where the race was opened from, or another race.
/// Sharing lives in the header, so each of these keeps its full label.
class _Actions extends ConsumerWidget {
  const _Actions({required this.backLabel, required this.onBack});

  final String backLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, math.max(12, bottom)),
      child: Row(
        children: [
          Expanded(
            child: RaceButton(
              key: const ValueKey('race_back_to_feed'),
              label: 'Back to $backLabel',
              onTap: onBack,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RaceButton(
              key: const ValueKey('race_play_again'),
              label: 'Play again',
              tone: RaceButtonTone.primary,
              onTap: () {
                unawaited(HapticFeedbackService.buttonPress());
                unawaited(
                  ref.read(raceControllerProvider.notifier).playAgain(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

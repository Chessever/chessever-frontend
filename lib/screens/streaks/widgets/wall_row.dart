import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Width that holds the widest rank on the list ("1,105" needs more than "9").
double wallRankWidth(int rows) {
  final digits = rows.toString().length;
  return (digits * 8.4 + 2).w.clamp(18.w, 48.w);
}

/// "beat avg 2654 · also 9 in rapid": the second line, when there is one.
String? wallRowNotes(StreakRow row, List<StreakRow> live) {
  final others = [
    for (final r in live)
      if (r.timeClass != row.timeClass && r.currentStreak > 0) r,
  ];
  final avg = row.runOppAvg;
  final notes = [
    if (avg != null && avg > 0) 'beat avg $avg',
    if (others.isNotEmpty)
      'also ${others.map((r) => '${r.currentStreak} in ${r.timeClass.label.toLowerCase()}').join(', ')}',
  ];
  return notes.isEmpty ? null : notes.join(' · ');
}

/// One player on the wall: rank, avatar, name and meta, and the run.
/// Tap opens the streak card; a long press offers the card, the profile and
/// My Space.
class WallRow extends ConsumerWidget {
  const WallRow({
    super.key,
    required this.row,
    required this.rank,
    required this.rankWidth,
  });

  final StreakRow row;
  final int rank;
  final double rankWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(playerLiveStreaksProvider(row.fideId));
    final notes = wallRowNotes(row, live);
    Widget content() => _WallRowContent(
      row: row,
      rank: rank,
      rankWidth: rankWidth,
      notes: notes,
    );

    return Builder(
      builder: (target) {
        return WallPressable(
          wash: context.colors.surface,
          semanticLabel:
              '$rank. ${row.title != null ? '${row.title} ' : ''}'
              '${row.displayName}, ${row.currentStreak} wins in a row'
              '${notes == null ? '' : ', $notes'}',
          onTap: () => openWallStreakCard(context, row),
          onLongPress: () => showWallRowMenu(
            target,
            ref,
            row,
            previewBuilder: (_) =>
                ColoredBox(color: context.colors.background, child: content()),
          ),
          child: ExcludeSemantics(child: content()),
        );
      },
    );
  }
}

class _WallRowContent extends StatelessWidget {
  const _WallRowContent({
    required this.row,
    required this.rank,
    required this.rankWidth,
    required this.notes,
  });

  final StreakRow row;
  final int rank;
  final double rankWidth;
  final String? notes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = colors.textPrimary;
    final muted = ink.withValues(alpha: 0.7);
    final meta = wallMeta(row);
    final metaStyle = wallText(12, 16, FontWeight.w500, muted, tabular: true);

    return DecoratedBox(
      // The design's 1px lower edge, in the card tone: felt, not drawn.
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.surface)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 60.w),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.w),
          child: Row(
            children: [
              SizedBox(
                width: rankWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$rank',
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: wallText(
                      13,
                      18,
                      FontWeight.w600,
                      colors.textSecondary,
                      tabular: true,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              WallAvatar(row: row, size: 40.w),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          if (row.title != null)
                            TextSpan(
                              text: '${row.title} ',
                              style: TextStyle(color: colors.titleAccent),
                            ),
                          TextSpan(text: row.displayName),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: wallText(14, 18, FontWeight.w600, ink),
                    ),
                    if (meta.isNotEmpty) ...[
                      SizedBox(height: 2.w),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metaStyle,
                      ),
                    ],
                    if (notes != null)
                      Text(
                        notes!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metaStyle,
                      ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              WallStillFlame(streak: row.currentStreak, size: 20.w),
              SizedBox(width: 5.w),
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: 22.w),
                child: Text(
                  '${row.currentStreak}',
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: wallText(18, 22, FontWeight.w700, ink, tabular: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder rows while the wall loads: the list's own shape, shimmering.
class WallSkeletonRows extends StatelessWidget {
  const WallSkeletonRows({super.key, this.count = 8});

  final int count;

  @override
  Widget build(BuildContext context) {
    final style = wallText(14, 18, FontWeight.w600, context.colors.textPrimary);
    final meta = wallText(12, 16, FontWeight.w500, context.colors.textPrimary);
    return ExcludeSemantics(
      child: SkeletonWidget(
        child: Column(
          children: [
            for (var i = 0; i < count; i++)
              // Same box as WallRow: a 60 floor that grows with the text
              // scale, so large type never overflows the placeholder.
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: 60.w),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 8.w,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18.w,
                        child: Text('${i + 1}', style: meta),
                      ),
                      SizedBox(width: 12.w),
                      Bone.circle(size: 40.w),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              i.isEven
                                  ? 'GM Firstname Surname'
                                  : 'IM Name Surname',
                              style: style,
                            ),
                            SizedBox(height: 2.w),
                            Text('FED · 2700 · 30 y', style: meta),
                          ],
                        ),
                      ),
                      Text('12', style: style),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

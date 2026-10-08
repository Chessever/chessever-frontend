import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/my_prep/library/prep_library.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_source_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_tree/build_tree_button.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PrepTreesTab extends ConsumerStatefulWidget {
  const PrepTreesTab({
    super.key,
    required this.profile,
    required this.onSources,
  });
  final PrepProfile profile;
  final VoidCallback onSources;
  @override
  ConsumerState<PrepTreesTab> createState() => _PrepTreesTabState();
}

class _PrepTreesTabState extends ConsumerState<PrepTreesTab> {
  int _side = 0;
  int _clock = 0;

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final repo = ref.watch(prepRepositoryProvider);
    final colors = context.colors;
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    final color = switch (_side) {
      1 => GamebasePlayerColor.white,
      2 => GamebasePlayerColor.black,
      _ => null,
    };
    final clock = switch (_clock) {
      1 => TimeControl.blitz,
      2 => TimeControl.rapid,
      3 => TimeControl.classical,
      _ => null,
    };
    final sides = profile.kind == PrepKind.mine
        ? const ['Both', 'As White', 'As Black']
        : const ['Both', 'Their White', 'Their Black'];
    const clocks = ['All clocks', 'Blitz', 'Rapid', 'Classical'];
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 12.h, gutter, 32.h),
      children: [
        Text(
          profile.kind == PrepKind.mine
              ? 'Study your games'
              : 'Prepare against this player',
          style: AppTypography.textMdBold.copyWith(color: colors.textPrimary),
        ),
        SizedBox(height: 6.h),
        Text(
          'Choose the player’s colour. Each tree opens with that side selected.',
          style: AppTypography.textSmRegular.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
        SizedBox(height: 16.h),
        SegmentedSwitcher(
          height: prepSegmentHeight(context, wrapLabels: true),
          options: sides,
          optionLabels: [
            for (final side in sides)
              Text(side, maxLines: 2, textAlign: TextAlign.center),
          ],
          initialSelection: _side,
          currentSelection: _side,
          onSelectionChanged: (side) => setState(() => _side = side),
        ),
        SizedBox(height: 20.h),
        SegmentedSwitcher(
          height: prepSegmentHeight(context, wrapLabels: true),
          options: clocks,
          optionLabels: [
            for (final clock in clocks)
              Text(clock, maxLines: 2, textAlign: TextAlign.center),
          ],
          initialSelection: _clock,
          currentSelection: _clock,
          onSelectionChanged: (clock) => setState(() => _clock = clock),
        ),
        SizedBox(height: 16.h),
        _TreeRow(
          title: 'Combined',
          subtitle:
              '${prepGamesLabel(profile.gameCount)} from all attached sources',
          marks: PrepSourceMarks(
            sources: profile.accounts.map((a) => a.source),
          ),
          target: PrepProfileTreeTarget(profile: profile, repository: repo),
          gameCount: profile.gameCount,
          color: color,
          clock: clock,
          onSources: widget.onSources,
        ),
        SizedBox(height: 16.h),
        for (final account in profile.accounts) ...[
          _TreeRow(
            title: account.source.label,
            subtitle: account.displayName ?? account.username,
            marks: PrepSourceMark(source: account.source),
            target: PrepAccountTreeTarget(
              profile: profile,
              account: account,
              repository: repo,
            ),
            gameCount: account.gameCount,
            color: color,
            clock: clock,
            onSources: () => prepDownloadSource(context, ref, profile, account),
          ),
          SizedBox(height: 12.h),
        ],
        if (profile.accounts.isEmpty)
          TextButton(
            onPressed: widget.onSources,
            child: const Text('Attach a source'),
          ),
      ],
    );
  }
}

class _TreeRow extends ConsumerWidget {
  const _TreeRow({
    required this.title,
    required this.subtitle,
    required this.marks,
    required this.target,
    required this.gameCount,
    required this.onSources,
    this.color,
    this.clock,
  });
  final String title;
  final String subtitle;
  final Widget marks;
  final GameTreeTarget target;
  final int gameCount;
  final GamebasePlayerColor? color;
  final TimeControl? clock;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      gameTreeStatusProvider.select((s) => s[target.scopeId]),
    );
    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.textMdBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              marks,
            ],
          ),
          SizedBox(height: 6.h),
          Text(
            subtitle,
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(
                child: Text(
                  status?.busy == true
                      ? status?.message ?? 'Building tree…'
                      : gameCount == 0
                      ? 'Download games first'
                      : '${prepGamesLabel(gameCount)} available',
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              if (gameCount > 0 || status?.busy == true)
                BuildTreeButton(
                  target: target,
                  color: color,
                  timeControl: clock,
                  compact: false,
                )
              else
                TextButton(onPressed: onSources, child: const Text('Download')),
            ],
          ),
        ],
      ),
    );
  }
}

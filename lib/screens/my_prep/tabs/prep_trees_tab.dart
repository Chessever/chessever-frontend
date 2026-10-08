import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/my_prep/library/prep_library.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_source_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filter_popup.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_tree/build_tree_button.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
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

  Future<void> _showFilters() async {
    final result = await showAlertModal<(int, int)>(
      context: context,
      child: _TreeFilterDialog(
        mine: widget.profile.kind == PrepKind.mine,
        side: _side,
        clock: _clock,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _side = result.$1;
      _clock = result.$2;
    });
  }

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
    final sides = _sideLabels(profile.kind == PrepKind.mine);
    final activeFilters = [
      if (_side > 0) sides[_side],
      if (_clock > 0) _clockLabels[_clock],
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 12.h, gutter, 32.h),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Opening trees', style: AppTypography.textSmBold),
                  if (activeFilters.isNotEmpty) ...[
                    SizedBox(height: 4.h),
                    Text(
                      activeFilters.join(' · '),
                      style: AppTypography.textXsRegular.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PrepFilterButton(
              active: activeFilters.isNotEmpty,
              tooltip: 'Filter opening trees',
              onPressed: _showFilters,
            ),
          ],
        ),
        SizedBox(height: 12.h),
        _TreeRow(
          title: 'Combined',
          subtitle: 'All attached sources',
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
            subtitle: account.source.online
                ? account.username
                : account.displayName ?? account.username,
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

List<String> _sideLabels(bool mine) => mine
    ? const ['Both colours', 'As White', 'As Black']
    : const ['Both colours', 'Their White', 'Their Black'];

const _clockLabels = ['All clocks', 'Blitz', 'Rapid', 'Classical'];

class _TreeFilterDialog extends StatefulWidget {
  const _TreeFilterDialog({
    required this.mine,
    required this.side,
    required this.clock,
  });
  final bool mine;
  final int side;
  final int clock;

  @override
  State<_TreeFilterDialog> createState() => _TreeFilterDialogState();
}

class _TreeFilterDialogState extends State<_TreeFilterDialog> {
  late int _side = widget.side;
  late int _clock = widget.clock;

  @override
  Widget build(BuildContext context) {
    final sides = _sideLabels(widget.mine);
    return PrepFilterPopup(
      title: 'Tree filters',
      onReset: () => Navigator.of(context).pop((0, 0)),
      onApply: () => Navigator.of(context).pop((_side, _clock)),
      children: [
        Text('Player colour', style: AppTypography.textSmMedium),
        SizedBox(height: 8.h),
        PrepFilterSelect<int>(
          label: 'Player colour',
          value: _side,
          items: [
            for (final (i, label) in sides.indexed)
              DropdownMenuItem(value: i, child: Text(label)),
          ],
          onChanged: (value) => setState(() => _side = value),
        ),
        Text('Time control', style: AppTypography.textSmMedium),
        SizedBox(height: 8.h),
        PrepFilterSelect<int>(
          label: 'Time control',
          value: _clock,
          items: [
            for (final (i, label) in _clockLabels.indexed)
              DropdownMenuItem(value: i, child: Text(label)),
          ],
          onChanged: (value) => setState(() => _clock = value),
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
                  compact: MediaQuery.textScalerOf(context).scale(14) > 20
                      ? true
                      : null,
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

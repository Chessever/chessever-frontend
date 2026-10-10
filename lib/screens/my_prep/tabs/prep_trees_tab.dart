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
          marks: PrepSourceMarks(
            sources: profile.accounts.map((a) => a.source),
            size: 14.sp,
          ),
          target: PrepProfileTreeTarget(profile: profile, repository: repo),
          gameCount: profile.gameCount,
          color: color,
          clock: clock,
          onSources: widget.onSources,
        ),
        SizedBox(height: 8.h),
        // Same order and card as the My games source list.
        for (final source in PrepSource.values)
          for (final account in profile.accounts.where(
            (a) => a.source == source,
          )) ...[
            _TreeRow(
              title: account.source.online
                  ? account.username
                  : account.displayName ?? account.username,
              semanticsLabel: account.source.label,
              leading: PrepSourceMark(source: account.source, size: 24.sp),
              target: PrepAccountTreeTarget(
                profile: profile,
                account: account,
                repository: repo,
              ),
              gameCount: account.gameCount,
              emptyLabel:
                  account.source != PrepSource.manual &&
                      account.lastSyncAtMs == null
                  ? 'Ready to download'
                  : 'No games yet',
              color: color,
              clock: clock,
              onSources: () =>
                  prepDownloadSource(context, ref, profile, account),
            ),
            SizedBox(height: 8.h),
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

/// One tree to build, laid out like the My games source card
/// ([PrepAccountRow]): mark, name over a status line, then the action.
class _TreeRow extends ConsumerWidget {
  const _TreeRow({
    required this.title,
    required this.target,
    required this.gameCount,
    required this.onSources,
    this.leading,
    this.marks,
    this.semanticsLabel,
    this.emptyLabel = 'No games yet',
    this.color,
    this.clock,
  });
  final String title;

  /// The source the title belongs to, for screen readers.
  final String? semanticsLabel;

  /// A single source's mark, ahead of the title.
  final Widget? leading;

  /// Several sources' marks, trailing the title.
  final Widget? marks;
  final GameTreeTarget target;
  final int gameCount;

  /// The status line while there are no games to build from.
  final String emptyLabel;
  final GamebasePlayerColor? color;
  final TimeControl? clock;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final status = ref.watch(
      gameTreeStatusProvider.select((s) => s[target.scopeId]),
    );
    final busy = status?.busy == true;
    final meta = busy
        ? status?.message ?? 'Building tree…'
        : gameCount == 0
        ? emptyLabel
        : prepGamesLabel(gameCount);
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 14.h),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, SizedBox(width: 14.w)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        semanticsLabel: semanticsLabel == null
                            ? null
                            : '$title on $semanticsLabel',
                        style: AppTypography.textSmBold.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (marks != null) ...[SizedBox(width: 8.w), marks!],
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textXsRegular.copyWith(
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          if (gameCount > 0 || busy)
            BuildTreeButton(
              target: target,
              color: color,
              timeControl: clock,
              compact: MediaQuery.textScalerOf(context).scale(14) > 20
                  ? true
                  : null,
            )
          else
            // No trailing padding, so the label ends on the card's inset.
            TextButton(
              onPressed: onSources,
              style: TextButton.styleFrom(
                foregroundColor: colors.textPrimary,
                padding: EdgeInsets.only(left: 12.w),
                minimumSize: const Size(44, 44),
                alignment: Alignment.centerRight,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: AppTypography.textSmMedium,
              ),
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }
}

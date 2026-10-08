import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_sources_screen.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filter_popup.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/game_filter/game_filter_choice_chips.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';

Future<PrepFilter?> showPrepFilterDialog({
  required BuildContext context,
  required PrepProfile profile,
  required PrepFilter currentFilter,
}) => showAlertModal<PrepFilter>(
  context: context,
  child: PrepFilterDialog(
    profile: profile,
    initialFilter: currentFilter,
    onManageSources: () {
      Navigator.of(context).pop();
      PrepSourcesScreen.open(context, profile.id);
    },
  ),
);

/// A draft stays local until Apply. Advanced filters reuse the app's dialog.
class PrepFilterDialog extends StatefulWidget {
  const PrepFilterDialog({
    super.key,
    required this.profile,
    required this.initialFilter,
    this.onManageSources,
  });
  final PrepProfile profile;
  final PrepFilter initialFilter;
  final VoidCallback? onManageSources;

  @override
  State<PrepFilterDialog> createState() => _PrepFilterDialogState();
}

class _PrepFilterDialogState extends State<PrepFilterDialog> {
  late PrepFilter _draft = widget.initialFilter;

  Future<void> _advanced() async {
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: _draft.dialogFilter,
      showLiveFilter: false,
      showColorFilter: false,
      showTimeControlFilter: false,
      showSortSection: true,
      allowMultiSort: true,
      showOpeningFilter: true,
      showFinishFilter: true,
      showLevelFilter: false,
      showRatingRange: true,
    );
    if (result == null || !mounted) return;
    setState(() {
      _draft = _draft.copyWith(
        base: result.copyWith(
          timeControl: _draft.base?.timeControl ?? GameTimeControlFilter.all,
        ),
        year: null,
        eco: null,
      );
    });
  }

  String get _clock =>
      _draft.speed?.name ??
      switch (_draft.base?.timeControl) {
        GameTimeControlFilter.blitz => 'fast',
        GameTimeControlFilter.rapid => 'rapid',
        GameTimeControlFilter.classical => 'classical',
        _ => 'all',
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PrepFilterPopup(
      title: 'Filters',
      onReset: () => Navigator.of(context).pop(const PrepFilter()),
      onApply: () => Navigator.of(context).pop(_draft),
      children: [
        _label('Source'),
        PrepFilterSelect<String>(
          label: 'Source',
          value:
              _draft.accountKey ??
              (_draft.source == null
                  ? 'combined'
                  : 'source:${_draft.source!.name}'),
          items: [
            const DropdownMenuItem(
              value: 'combined',
              child: Text('All attached sources'),
            ),
            if (_draft.accountKey == null && _draft.source != null)
              DropdownMenuItem(
                value: 'source:${_draft.source!.name}',
                child: Text('All ${_draft.source!.label} accounts'),
              ),
            for (final account in widget.profile.accounts)
              DropdownMenuItem(
                value: account.key,
                child: Row(
                  children: [
                    PrepSourceMark(source: account.source, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${account.source.label} · ${account.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.onManageSources != null)
              const DropdownMenuItem(
                value: 'manage',
                child: Text('Manage attached sources'),
              ),
          ],
          onChanged: (key) {
            if (key == 'manage') {
              widget.onManageSources?.call();
              return;
            }

            final account = widget.profile.accounts
                .where((a) => a.key == key)
                .firstOrNull;
            final source = PrepSource.values
                .where((s) => key == 'source:${s.name}')
                .firstOrNull;
            setState(
              () => _draft = _draft.copyWith(
                source: account?.source ?? source,
                accountKey: account?.key,
                accountFile: account == null
                    ? null
                    : PrepRepository.gamesFileName(account),
              ),
            );
          },
        ),
        _label('Dates'),
        PrepFilterSelect<PrepStatsWindow>(
          label: 'Dates',
          value: _draft.window,
          items: [
            for (final window in PrepStatsWindow.values)
              DropdownMenuItem(value: window, child: Text(window.label)),
          ],
          onChanged: (window) =>
              setState(() => _draft = _draft.copyWith(window: window)),
        ),
        _label('Time control'),
        PrepFilterSelect<String>(
          label: 'Time control',
          value: _clock,
          items: [
            const DropdownMenuItem(
              value: 'all',
              child: Text('All time controls'),
            ),
            const DropdownMenuItem(
              value: 'fast',
              child: Text('Bullet & Blitz'),
            ),
            for (final speed in PrepTimeControl.values)
              DropdownMenuItem(value: speed.name, child: Text(speed.label)),
          ],
          onChanged: (value) => setState(() {
            _draft = value == 'fast'
                ? _draft.copyWith(
                    speed: null,
                    base: (_draft.base ?? GameFilter()).copyWith(
                      timeControl: GameTimeControlFilter.blitz,
                    ),
                  )
                : _draft.withSpeed(
                    PrepTimeControl.values
                        .where((s) => s.name == value)
                        .firstOrNull,
                  );
          }),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.only(bottom: 12.h),
          title: Text('Colour & result', style: AppTypography.textSmMedium),
          subtitle: Text(
            [
              switch (_draft.side) {
                PrepSide.both => 'Both colours',
                PrepSide.white => 'White',
                PrepSide.black => 'Black',
              },
              switch (_draft.outcome) {
                null => 'All results',
                PrepOutcome.win => 'Wins',
                PrepOutcome.draw => 'Draws',
                PrepOutcome.loss => 'Losses',
                PrepOutcome.unknown => 'Unfinished',
              },
            ].join(' · '),
            style: AppTypography.textXsRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          initiallyExpanded:
              _draft.side != PrepSide.both || _draft.outcome != null,
          shape: const Border(),
          collapsedShape: const Border(),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label('Player colour'),
                GameFilterChoiceChips<PrepSide>(
                  values: PrepSide.values,
                  selected: _draft.side,
                  label: (side) => switch (side) {
                    PrepSide.both => 'Both',
                    PrepSide.white => 'White',
                    PrepSide.black => 'Black',
                  },
                  onTap: (side) =>
                      setState(() => _draft = _draft.copyWith(side: side)),
                ),
                SizedBox(height: 16.h),
                _label('Player result'),
                GameFilterChoiceChips<PrepOutcome?>(
                  values: const [
                    null,
                    PrepOutcome.win,
                    PrepOutcome.draw,
                    PrepOutcome.loss,
                  ],
                  selected: _draft.outcome,
                  label: (outcome) => switch (outcome) {
                    null => 'All',
                    PrepOutcome.win => 'Wins',
                    PrepOutcome.draw => 'Draws',
                    PrepOutcome.loss => 'Losses',
                    PrepOutcome.unknown => 'Unfinished',
                  },
                  onTap: (outcome) => setState(
                    () => _draft = _draft.copyWith(outcome: outcome),
                  ),
                ),
                SizedBox(height: 16.h),
              ],
            ),
          ],
        ),
        if (_draft.opening case final opening?)
          _facet(opening, () => _draft = _draft.copyWith(opening: null)),
        if (_draft.opponent case final opponent?)
          _facet(opponent, () => _draft = _draft.copyWith(opponent: null)),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('More game filters', style: AppTypography.textSmMedium),
          subtitle: Text(
            'Opening, rating, year, format and sort',
            style: AppTypography.textXsRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: colors.iconSecondary,
          ),
          onTap: _advanced,
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: EdgeInsets.only(bottom: 8.h),
    child: Text(text, style: AppTypography.textSmMedium),
  );

  Widget _facet(String label, VoidCallback clear) => Row(
    children: [
      Expanded(child: Text(label, style: AppTypography.textXsRegular)),
      IconButton(
        tooltip: 'Clear $label',
        onPressed: () => setState(clear),
        icon: const Icon(Icons.close_rounded, size: 18),
      ),
    ],
  );
}

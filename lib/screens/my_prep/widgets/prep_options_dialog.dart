import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:flutter/material.dart';

/// Which games to download for one account: its clocks and how far back.
/// The same choices desktop Prep's download options offer.
Future<PrepDownloadPreferences?> showPrepDownloadOptionsDialog(
  BuildContext context, {
  required PrepAccount account,
  bool download = false,
}) {
  return showAlertModal<PrepDownloadPreferences>(
    context: context,
    child: _OptionsDialog(account: account, download: download),
  );
}

class _OptionsDialog extends StatefulWidget {
  const _OptionsDialog({required this.account, required this.download});
  final PrepAccount account;
  final bool download;

  @override
  State<_OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<_OptionsDialog> {
  late Set<PrepTimeControl> _clocks = {
    ...widget.account.preferences.timeControls,
  };
  late PrepDateRange _range = widget.account.preferences.range;
  late DateTime? _from = widget.account.preferences.fromDate;
  late DateTime? _to = widget.account.preferences.toDate;

  Future<void> _pickDate(bool start) async {
    final value = await showDatePicker(
      context: context,
      initialDate: (start ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(1800),
      lastDate: DateTime.now(),
      helpText: start ? 'First game date' : 'Last game date',
    );
    if (value == null || !mounted) return;
    setState(() {
      final date = DateTime.utc(value.year, value.month, value.day);
      if (start) {
        _from = date;
      } else {
        _to = date;
      }
    });
  }

  PrepSource get _source => widget.account.source;

  @override
  Widget build(BuildContext context) {
    final offered = PrepTimeControl.offeredBy(_source);
    final next = PrepDownloadPreferences(
      timeControls: _clocks.intersection(offered.toSet()),
      range: _range,
      fromDate: _from,
      toDate: _to,
    );
    final changed = next != widget.account.preferences;
    return PrepDialogCard(
      icon: PrepSourceMark(source: _source, size: 22.sp),
      title: widget.download ? 'Download games' : 'Download options',
      subtitle: '${widget.account.username} on ${_source.label}',
      children: [
        const PrepFieldLabel('Time controls'),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            _Chip(
              label: 'All',
              selected: _clocks.isEmpty,
              onTap: () => setState(() => _clocks = {}),
            ),
            for (final clock in offered)
              _Chip(
                label: clock.labelFor(_source),
                selected: _clocks.contains(clock),
                onTap: () => setState(() {
                  _clocks = {..._clocks};
                  if (!_clocks.remove(clock)) _clocks.add(clock);
                }),
              ),
          ],
        ),
        SizedBox(height: 20.h),
        const PrepFieldLabel('Period'),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final range in PrepDateRange.values)
              _Chip(
                label: range.label,
                selected: _range == range,
                onTap: () => setState(() => _range = range),
              ),
          ],
        ),
        SizedBox(height: 14.h),
        if (_range == PrepDateRange.custom) ...[
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _pickDate(true),
                  child: Text(
                    _from == null ? 'Start date' : prepDateText(_from!),
                  ),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () => _pickDate(false),
                  child: Text(_to == null ? 'End date' : prepDateText(_to!)),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => setState(() {
              _from = null;
              _to = null;
            }),
            child: const Text('Clear dates'),
          ),
          if (next.validationError case final error?)
            Text(
              error,
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.danger,
              ),
            ),
        ],
        Text(
          _range == PrepDateRange.all
              ? 'Large accounts can hold tens of thousands of games. A '
                    'shorter period downloads and opens much faster.'
              : 'Changing these replaces this account’s downloaded games.',
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textSecondary,
            height: 16 / 12,
          ),
        ),
        SizedBox(height: 24.h),
        PrepDialogActions(
          confirmLabel: widget.download ? 'Download' : 'Save',
          onConfirm:
              (widget.download || changed) && next.validationError == null
              ? () {
                  HapticFeedbackService.medium();
                  Navigator.of(context).pop(next);
                }
              : null,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: TappableScale(
        scaleDown: 0.97,
        onTap: () {
          HapticFeedbackService.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: selected
                ? colors.textPrimary
                : colors.textPrimary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10.br),
          ),
          child: Text(
            label,
            style: AppTypography.textSmMedium.copyWith(
              color: selected ? colors.textInverse : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

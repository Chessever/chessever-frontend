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
/// The same choices desktop Prep's download options offer. Accounts added
/// together ([others]) are asked once; each keeps the clocks its site has.
Future<PrepDownloadPreferences?> showPrepDownloadOptionsDialog(
  BuildContext context, {
  required PrepAccount account,
  List<PrepAccount> others = const [],
  bool download = false,
  PrepDownloadPreferences? initial,
}) {
  return showAlertModal<PrepDownloadPreferences>(
    context: context,
    child: _OptionsDialog(
      account: account,
      others: others,
      download: download,
      initial: initial ?? account.preferences,
    ),
  );
}

class _OptionsDialog extends StatelessWidget {
  const _OptionsDialog({
    required this.account,
    required this.others,
    required this.download,
    required this.initial,
  });
  final PrepAccount account;
  final List<PrepAccount> others;
  final bool download;
  final PrepDownloadPreferences initial;

  @override
  Widget build(BuildContext context) {
    final sources = prepSourcesOf(account, others);
    return PrepDialogCard(
      icon: PrepSourceMarks(sources: sources, size: 22.sp),
      title: prepOptionsTitle(download: download),
      subtitle: others.isEmpty
          ? prepAccountOnSource(account)
          : sources.map((s) => s.label).join(' and '),
      children: [
        PrepOptionsForm(
          account: account,
          others: others,
          download: download,
          initial: initial,
          onConfirm: (options) => Navigator.of(context).pop(options),
        ),
      ],
    );
  }
}

String prepOptionsTitle({required bool download}) =>
    download ? 'Download games' : 'Download options';

/// "ClubPlayer on Lichess": whose games a download's choices are for.
String prepAccountOnSource(PrepAccount account) =>
    '${account.source.online ? account.username : account.displayName ?? account.username} on ${account.source.label}';

/// The sources [account] and the accounts asked along with it come from.
List<PrepSource> prepSourcesOf(PrepAccount account, List<PrepAccount> others) =>
    {account.source, for (final other in others) other.source}.toList();

/// An account's download choices and the actions that settle them: the
/// options dialog's body, and the second page of a source's popup.
class PrepOptionsForm extends StatefulWidget {
  const PrepOptionsForm({
    super.key,
    required this.account,
    required this.onConfirm,
    this.others = const [],
    this.download = false,
    this.initial,
    this.onCancel,
  });

  final PrepAccount account;
  final List<PrepAccount> others;

  /// A first download: it confirms the scope as it stands, with nothing yet
  /// to replace.
  final bool download;
  final PrepDownloadPreferences? initial;
  final ValueChanged<PrepDownloadPreferences> onConfirm;

  /// Where Cancel leads. Pops by default.
  final VoidCallback? onCancel;

  @override
  State<PrepOptionsForm> createState() => _PrepOptionsFormState();
}

class _PrepOptionsFormState extends State<PrepOptionsForm> {
  late PrepDownloadPreferences _value =
      widget.initial ?? widget.account.preferences;

  late final _sources = prepSourcesOf(widget.account, widget.others);

  @override
  Widget build(BuildContext context) {
    final next = _value.copyWith(
      timeControls: _value.timeControls.intersection(
        prepOfferedClocks(_sources).toSet(),
      ),
    );
    final changed = next != widget.account.preferences;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrepScopeFields(
          sources: _sources,
          value: _value,
          onChanged: (value) => setState(() => _value = value),
          // A first download has nothing to replace.
          replaces: !widget.download,
        ),
        SizedBox(height: 24.h),
        PrepDialogActions(
          confirmLabel: widget.download ? 'Download' : 'Save',
          onCancel: widget.onCancel,
          onConfirm:
              (widget.download || changed) && next.validationError == null
              ? () {
                  HapticFeedbackService.medium();
                  widget.onConfirm(next);
                }
              : null,
        ),
      ],
    );
  }
}

/// The clocks any of [sources] has, in their usual order.
List<PrepTimeControl> prepOfferedClocks(List<PrepSource> sources) => [
  for (final clock in PrepTimeControl.values)
    if (sources.any((s) => PrepTimeControl.offeredBy(s).contains(clock))) clock,
];

/// The clocks and period of a download, as chips. Shared by the options
/// dialog and the add dialog's per-source pages.
class PrepScopeFields extends StatelessWidget {
  const PrepScopeFields({
    super.key,
    required this.sources,
    required this.value,
    required this.onChanged,
    this.replaces = false,
  });

  final List<PrepSource> sources;
  final PrepDownloadPreferences value;
  final ValueChanged<PrepDownloadPreferences> onChanged;

  /// Whether saving replaces games this account already downloaded.
  final bool replaces;

  /// Rebuilt whole, since a cleared date cannot pass through `copyWith`.
  void _emit({
    Set<PrepTimeControl>? clocks,
    PrepDateRange? range,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
  }) => onChanged(
    PrepDownloadPreferences(
      timeControls: clocks ?? value.timeControls,
      range: range ?? value.range,
      fromDate: clearDates ? null : from ?? value.fromDate,
      toDate: clearDates ? null : to ?? value.toDate,
    ),
  );

  Future<void> _pickDate(BuildContext context, bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? value.fromDate : value.toDate) ?? DateTime.now(),
      firstDate: DateTime(1800),
      lastDate: DateTime.now(),
      helpText: start ? 'First game date' : 'Last game date',
    );
    if (picked == null || !context.mounted) return;
    final date = DateTime.utc(picked.year, picked.month, picked.day);
    _emit(from: start ? date : null, to: start ? null : date);
  }

  @override
  Widget build(BuildContext context) {
    // One site names its own clocks (Chess.com's Daily); several share the
    // common names.
    final source = sources.length == 1 ? sources.single : null;
    final clocks = value.timeControls;
    final range = value.range;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PrepFieldLabel('Time controls'),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            _Chip(
              label: 'All',
              selected: clocks.isEmpty,
              onTap: () => _emit(clocks: const {}),
            ),
            for (final clock in prepOfferedClocks(sources))
              _Chip(
                label: clock.labelFor(source),
                selected: clocks.contains(clock),
                onTap: () => _emit(
                  clocks: clocks.contains(clock)
                      ? clocks.difference({clock})
                      : {...clocks, clock},
                ),
              ),
          ],
        ),
        SizedBox(height: 20.h),
        const PrepFieldLabel('Period'),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final option in PrepDateRange.values)
              _Chip(
                label: option.label,
                selected: range == option,
                onTap: () => _emit(range: option),
              ),
          ],
        ),
        SizedBox(height: 14.h),
        if (range == PrepDateRange.custom) ...[
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _pickDate(context, true),
                  child: Text(
                    value.fromDate == null
                        ? 'Start date'
                        : prepDateText(value.fromDate!),
                  ),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () => _pickDate(context, false),
                  child: Text(
                    value.toDate == null
                        ? 'End date'
                        : prepDateText(value.toDate!),
                  ),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => _emit(clearDates: true),
            child: const Text('Clear dates'),
          ),
          if (value.validationError case final error?)
            Text(
              error,
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.danger,
              ),
            ),
        ],
        if (range == PrepDateRange.all || replaces)
          Text(
            range == PrepDateRange.all
                ? 'Large accounts can hold tens of thousands of games. A '
                      'shorter period downloads and opens much faster.'
                : 'Changing these replaces this account’s downloaded games.',
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
              height: 16 / 12,
            ),
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

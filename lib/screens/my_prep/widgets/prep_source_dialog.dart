import 'dart:async';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_source_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_options_dialog.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// One source in a popup: its games, download scope and ratings, with the
/// download options a step away on a second page of the same popup.
/// Completes with true when the reader asked for the profile.
Future<bool?> showPrepSourceDialog(
  BuildContext context, {
  required String profileId,
  required String accountKey,
}) => showAlertModal<bool>(
  context: context,
  child: _SourceDialog(profileId: profileId, accountKey: accountKey),
);

/// The step between the popup's pages, on the spring the add sheet's pages
/// step with. A [MotionCurve] reads its 0 to 1 as the spring's first second,
/// so it plays true over exactly that long.
final Curve _stepCurve = const CupertinoMotion.smooth(
  duration: Duration(milliseconds: 350),
).toCurve;
const _stepSettle = Duration(seconds: 1);

/// How far a page travels sideways while it changes hands with the next.
const _pageShift = 24.0;

/// The heading's back and close buttons: their tap target, and how far a
/// glyph sits inside it.
const _iconTarget = kMinInteractiveDimension;
double get _glyphSize => 20.ic;
double get _glyphInset => (_iconTarget - _glyphSize) / 2;

/// How far a heading button stands in from the popup's edge so that its
/// glyph, not its tap target, meets the margin the content keeps. On the
/// smallest phones the margin is narrower than the target's own inset.
double _buttonMargin(double pad) =>
    (pad - _glyphInset).clamp(0.0, double.infinity);

/// Room at the heading's end for the close button laid over it.
double get _closeInset => _iconTarget - _glyphInset + 4;

/// The line the heading's mark, page number and buttons share: a one-line
/// title over its subtitle, and never shorter than a button.
double _headingBand(BuildContext context) {
  final block = PrepDialogHeader.blockHeight(context);
  return block < _iconTarget ? _iconTarget : block;
}

double _ramp(double t, double from, double to) =>
    ((t - from) / (to - from)).clamp(0.0, 1.0);

class _SourceDialog extends ConsumerStatefulWidget {
  const _SourceDialog({required this.profileId, required this.accountKey});
  final String profileId;
  final String accountKey;

  @override
  ConsumerState<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends ConsumerState<_SourceDialog> {
  bool _onOptions = false;

  /// Whether the options page was opened to start a first download.
  bool _firstDownload = false;

  Future<void> _openOptions({bool download = false}) async {
    HapticFeedbackService.selection();
    if (!await ensurePrepAccess(context) || !mounted) return;
    setState(() {
      _firstDownload = download;
      _onOptions = true;
    });
  }

  void _back() {
    HapticFeedbackService.selection();
    setState(() => _onOptions = false);
  }

  Future<void> _startDownload(PrepAccount account) async {
    HapticFeedbackService.buttonPress();
    if (!await ensurePrepAccess(context) || !mounted) return;
    // The popup reports progress and failure itself, so nothing is raised
    // over it.
    unawaited(
      ref
          .read(prepSyncProvider.notifier)
          .syncAccount(widget.profileId, account, force: true),
    );
  }

  void _primary(PrepAccount account, bool syncing) {
    if (syncing) {
      HapticFeedbackService.buttonPress();
      ref.read(prepSyncProvider.notifier).cancel(account);
    } else if (account.source.online && account.lastSyncAtMs == null) {
      // An online account's first download offers its scope before it starts.
      _openOptions(download: true);
    } else {
      _startDownload(account);
    }
  }

  Future<void> _save(
    PrepAccount account,
    PrepDownloadPreferences options,
  ) async {
    final download = _firstDownload;
    final sync = ref.read(prepSyncProvider.notifier);
    setState(() => _onOptions = false);
    final live = await prepSaveDownloadOptions(
      ref,
      widget.profileId,
      account,
      options,
    );
    if (live != null && prepOptionsNeedDownload(live, download: download)) {
      unawaited(sync.syncAccount(widget.profileId, live, force: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref
        .watch(prepProfileProvider(widget.profileId))
        ?.accounts
        .where((a) => a.key == widget.accountKey)
        .firstOrNull;
    if (account == null) return const SizedBox.shrink();
    final status = ref.watch(
      prepSyncProvider.select((s) => s[widget.accountKey]),
    );
    final paged = account.source != PrepSource.manual;
    final onOptions = _onOptions && paged;
    final still = MediaQuery.disableAnimationsOf(context);
    final pad = 24.sp;
    final page = onOptions
        ? _OptionsPage(
            account: account,
            download: _firstDownload,
            onBack: _back,
            onSave: (options) => _save(account, options),
          )
        : _DetailsPage(
            account: account,
            status: status,
            paged: paged,
            onOptions: _openOptions,
            onPrimary: () => _primary(account, status != null),
            onProfile: () {
              HapticFeedbackService.cardTap();
              Navigator.of(context).pop(true);
            },
          );
    return PopScope(
      // The system back gesture steps back a page before it leaves.
      canPop: !onOptions,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: PrepDialogSurface(
        child: SingleChildScrollView(
          child: Stack(
            children: [
              // With animations disabled the pages simply swap.
              if (still)
                KeyedSubtree(key: ValueKey(onOptions), child: page)
              else
                AnimatedSize(
                  duration: _stepSettle,
                  curve: _stepCurve,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: _stepSettle,
                    switchInCurve: _stepCurve,
                    switchOutCurve: _stepCurve.flipped,
                    // The arriving page sizes the popup; the leaving one
                    // fades out over it from the same top edge, out of reach.
                    layoutBuilder: (current, previous) => Stack(
                      children: [
                        for (final child in previous)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: ExcludeSemantics(child: child),
                            ),
                          ),
                        ?current,
                      ],
                    ),
                    transitionBuilder: _stepTransition,
                    child: KeyedSubtree(key: ValueKey(onOptions), child: page),
                  ),
                ),
              // Outside the pages, so it holds still while they change hands.
              Positioned(
                top: pad + (_headingBand(context) - _iconTarget) / 2,
                right: _buttonMargin(pad),
                child: IconButton(
                  key: const ValueKey('prep_source_close'),
                  tooltip: 'Close',
                  constraints: const BoxConstraints.tightFor(
                    width: _iconTarget,
                    height: _iconTarget,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close_rounded,
                    size: _glyphSize,
                    color: context.colors.iconSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The leaving page is gone before the arriving one shows, so their text
  /// never overlaps. Options arrive from the right and leave back to it.
  Widget _stepTransition(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final arriving = child!.key == ValueKey(_onOptions);
        final toward = _onOptions ? 1.0 : -1.0;
        final t = arriving ? animation.value : 1 - animation.value;
        return Opacity(
          opacity: arriving ? _ramp(t, 0.25, 0.85) : 1 - _ramp(t, 0, 0.3),
          child: Transform.translate(
            offset: Offset(_pageShift * toward * (arriving ? 1 - t : -t), 0),
            child: child,
          ),
        );
      },
    );
  }
}

String _nameOf(PrepAccount account) => account.source.online
    ? account.username
    : account.displayName ?? account.username;

// ----------------------------------------------------------------- details

class _DetailsPage extends StatelessWidget {
  const _DetailsPage({
    required this.account,
    required this.status,
    required this.paged,
    required this.onOptions,
    required this.onPrimary,
    required this.onProfile,
  });

  final PrepAccount account;
  final PrepSyncStatus? status;

  /// Whether a second page follows, so this one is numbered.
  final bool paged;
  final VoidCallback onOptions;
  final VoidCallback onPrimary;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final syncing = status != null;
    return Padding(
      padding: EdgeInsets.all(24.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrepDialogHeader(
            leading: PrepSourceMark(source: account.source, size: 24.sp),
            title: _nameOf(account),
            subtitle: account.source.label,
            step: paged ? '1/2' : null,
            stepLabel: 'Page 1 of 2',
            trailingInset: _closeInset,
            band: _headingBand(context),
          ),
          SizedBox(height: 22.h),
          // A running download takes the count's place, so the popup holds
          // its size while it reports.
          IndexedStack(
            index: syncing ? 1 : 0,
            alignment: AlignmentDirectional.centerStart,
            children: [
              Row(
                // The count keeps to the start and its age to the end, each
                // within half the row.
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      prepGamesLabel(account.gameCount),
                      style: AppTypography.textLgBold.copyWith(
                        color: colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Flexible(
                    child: Text(
                      prepSyncedAgo(account.lastSyncAtMs),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textXsRegular.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (status case final running?)
                Semantics(
                  liveRegion: true,
                  child: PrepShimmerText(
                    running.message,
                    key: const ValueKey('prep_source_progress'),
                    semanticsLabel: 'Download progress: ${running.message}',
                    style: AppTypography.textSmRegular.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
            ],
          ),
          if (!syncing && account.error != null) ...[
            SizedBox(height: 10.h),
            Text(
              account.error!,
              style: AppTypography.textSmRegular.copyWith(color: colors.danger),
            ),
          ],
          if (paged) ...[
            SizedBox(height: 14.h),
            _DownloadScope(
              account: account,
              onEdit: syncing ? null : onOptions,
            ),
          ],
          if (account.ratings.isNotEmpty) ...[
            SizedBox(height: 20.h),
            _RatingGrid(account: account),
          ],
          SizedBox(height: 24.h),
          if (paged) ...[
            _PopupAction(
              key: const ValueKey('prep_source_primary'),
              primary: true,
              label: syncing
                  ? 'Stop download'
                  : account.lastSyncAtMs == null
                  ? 'Download games'
                  : 'Refresh games',
              leading: syncing
                  ? CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.textInverse,
                    )
                  : Icon(
                      account.lastSyncAtMs == null
                          ? Icons.download_rounded
                          : Icons.refresh_rounded,
                    ),
              onPressed: onPrimary,
            ),
            SizedBox(height: 8.h),
          ],
          _PopupAction(
            key: const ValueKey('prep_source_profile'),
            // An imported PGN has nothing to refresh: this is its one action.
            primary: !paged,
            label: 'Go to profile',
            trailing: const Icon(Icons.arrow_forward_rounded),
            onPressed: onProfile,
          ),
        ],
      ),
    );
  }
}

/// One of the popup's stacked actions: the filled one, or the quieter one
/// under it.
class _PopupAction extends StatelessWidget {
  const _PopupAction({
    super.key,
    required this.label,
    required this.onPressed,
    required this.primary,
    this.leading,
    this.trailing,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final glyph = 18.ic;
    // An icon and the spinner that replaces it fill the same square, so the
    // label holds still when one becomes the other.
    Widget slot(Widget child) => SizedBox.square(
      dimension: glyph,
      child: Center(
        child: child is Icon
            ? child
            : SizedBox.square(dimension: glyph - 3, child: child),
      ),
    );
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        backgroundColor: primary
            ? colors.textPrimary
            : colors.textPrimary.withValues(alpha: 0.06),
        foregroundColor: primary ? colors.textInverse : colors.textPrimary,
        iconSize: glyph,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.br),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[slot(leading!), SizedBox(width: 8.w)],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.textSmBold,
            ),
          ),
          if (trailing != null) ...[SizedBox(width: 8.w), slot(trailing!)],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- options

class _OptionsPage extends StatelessWidget {
  const _OptionsPage({
    required this.account,
    required this.download,
    required this.onBack,
    required this.onSave,
  });

  final PrepAccount account;
  final bool download;
  final VoidCallback onBack;
  final ValueChanged<PrepDownloadPreferences> onSave;

  @override
  Widget build(BuildContext context) {
    final pad = 24.sp;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          // The arrow's glyph, not its tap target, lines up with the fields.
          padding: EdgeInsets.fromLTRB(_buttonMargin(pad), pad, pad, 0),
          child: PrepDialogHeader(
            leading: IconButton(
              key: const ValueKey('prep_source_back'),
              tooltip: 'Back',
              constraints: const BoxConstraints.tightFor(
                width: _iconTarget,
                height: _iconTarget,
              ),
              onPressed: onBack,
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: context.colors.textPrimary,
                size: _glyphSize,
              ),
            ),
            // The title starts where the details page's does.
            gap: (24.sp + 14.w - (_iconTarget - _glyphInset)).clamp(
              0.0,
              double.infinity,
            ),
            title: prepOptionsTitle(download: download),
            subtitle: prepAccountOnSource(account),
            step: '2/2',
            stepLabel: 'Page 2 of 2',
            trailingInset: _closeInset,
            band: _headingBand(context),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 22.h, pad, pad),
          child: PrepOptionsForm(
            account: account,
            download: download,
            onCancel: onBack,
            onConfirm: onSave,
          ),
        ),
      ],
    );
  }
}

/// What this account downloads, as one tappable panel that opens the options.
class _DownloadScope extends StatelessWidget {
  const _DownloadScope({required this.account, required this.onEdit});
  final PrepAccount account;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final clocks = account.preferences.orderedTimeControls;
    final radius = BorderRadius.circular(14.br);
    return Semantics(
      button: true,
      enabled: onEdit != null,
      label: 'Download options',
      child: Material(
        key: const ValueKey('prep_download_scope'),
        color: colors.surfaceElevated,
        borderRadius: radius,
        child: InkWell(
          onTap: onEdit,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14.sp, 12.sp, 12.sp, 12.sp),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (clocks.isEmpty)
                        Text(
                          'All time controls',
                          style: AppTypography.textSmMedium.copyWith(
                            color: colors.textPrimary,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 14.w,
                          runSpacing: 6.h,
                          children: [
                            for (final clock in clocks)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PrepClockGlyph(clock, size: 16.ic),
                                  SizedBox(width: 6.w),
                                  Text(
                                    clock.labelFor(account.source),
                                    style: AppTypography.textSmMedium.copyWith(
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      SizedBox(height: 4.h),
                      Text(
                        account.preferences.rangeLabel,
                        style: AppTypography.textXsRegular.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12.w),
                Icon(
                  Icons.tune_rounded,
                  size: 20.ic,
                  color: onEdit == null
                      ? colors.textTertiary
                      : colors.iconSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The account's ratings, three to a row so every row shares its columns.
class _RatingGrid extends StatelessWidget {
  const _RatingGrid({required this.account});
  final PrepAccount account;

  static const _columns = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Known clocks first, in clock order; anything else keeps its own name.
    final cells = <(PrepTimeControl?, String, int)>[
      for (final clock in PrepTimeControl.values)
        for (final entry in account.ratings.entries)
          if (PrepTimeControl.forRatingKey(entry.key) == clock)
            (clock, clock.labelFor(account.source), entry.value),
      for (final entry in account.ratings.entries)
        if (PrepTimeControl.forRatingKey(entry.key) == null)
          (
            null,
            '${entry.key[0].toUpperCase()}${entry.key.substring(1)}',
            entry.value,
          ),
    ];
    return Column(
      children: [
        for (var row = 0; row < cells.length; row += _columns) ...[
          if (row > 0) SizedBox(height: 14.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = row; i < row + _columns; i++)
                Expanded(
                  child: i >= cells.length
                      ? const SizedBox.shrink()
                      : Semantics(
                          label: '${cells[i].$2} rating ${cells[i].$3}',
                          excludeSemantics: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (cells[i].$1 case final clock?) ...[
                                    PrepClockGlyph(clock, size: 14.ic),
                                    SizedBox(width: 5.w),
                                  ],
                                  Flexible(
                                    child: Text(
                                      cells[i].$2,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.textXsRegular
                                          .copyWith(
                                            color: colors.textSecondary,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 2.h),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${cells[i].$3}',
                                  style: AppTypography.textMdBold.copyWith(
                                    color: colors.textPrimary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

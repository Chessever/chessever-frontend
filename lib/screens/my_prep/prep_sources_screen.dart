import 'dart:async';

import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/prep_source_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class PrepSourcesScreen extends ConsumerWidget {
  const PrepSourcesScreen({super.key, required this.profileId});
  final String profileId;

  static Future<void> open(BuildContext context, String profileId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PrepSourcesScreen(profileId: profileId),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(prepProfileProvider(profileId));
    final colors = context.colors;
    final gutter = ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        centerTitle: true,
        title: Text(
          profile?.kind == PrepKind.mine ? 'My accounts' : 'Sources',
          style: AppTypography.textMdBold,
        ),
        actions: [
          if (profile != null)
            PopupMenuButton<PrepSource>(
              key: const ValueKey('prep_add_source'),
              tooltip: 'Add source',
              icon: const Icon(Icons.add_rounded),
              color: colors.surfaceElevated,
              onSelected: (source) => source == PrepSource.manual
                  ? prepImportSource(context, ref, profile)
                  : prepAddAccountTo(context, ref, profile, source: source),
              itemBuilder: (_) => [
                for (final source in PrepSource.values)
                  PopupMenuItem(
                    key: ValueKey('prep_attach_${source.name}'),
                    value: source,
                    enabled:
                        source != PrepSource.chessever ||
                        profile.databaseAccount == null,
                    child: Row(
                      children: [
                        PrepSourceMark(source: source, size: 22.sp),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Text(
                            source == PrepSource.manual
                                ? 'Import PGN'
                                : source.label,
                            style: AppTypography.textSmRegular,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          SizedBox(width: 8.w),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: profile == null
                ? const SizedBox.shrink()
                : ListView(
                    padding: EdgeInsets.fromLTRB(gutter, 8.h, gutter, 32.h),
                    children: [
                      Text(
                        profile.name,
                        style: AppTypography.textLgBold.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 20.h),
                      if (profile.accounts.isEmpty)
                        TextButton.icon(
                          onPressed: () =>
                              prepAddAccountTo(context, ref, profile),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add a source'),
                        )
                      else
                        Material(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(12.br),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (final source in PrepSource.values)
                                for (final account in profile.accounts.where(
                                  (account) => account.source == source,
                                ))
                                  PrepAccountRow(
                                    profile: profile,
                                    account: account,
                                  ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// One attached source: its mark, username, download state and actions.
class PrepAccountRow extends ConsumerWidget {
  const PrepAccountRow({
    super.key,
    required this.profile,
    required this.account,
  });
  final PrepProfile profile;
  final PrepAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final status = ref.watch(prepSyncProvider.select((s) => s[account.key]));
    final busy = status != null;
    final title = account.source.online
        ? account.username
        : account.displayName ?? account.username;
    return InkWell(
      key: ValueKey('prep_account_${account.key}'),
      onTap: () => _details(context, ref),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 14.h, 4.w, 14.h),
        child: Row(
          children: [
            PrepSourceMark(source: account.source, size: 24.sp),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    semanticsLabel: '$title on ${account.source.label}',
                    style: AppTypography.textSmBold.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  if (busy)
                    PrepShimmerText(
                      status.message,
                      semanticsLabel: 'Download progress: ${status.message}',
                      style: AppTypography.textXsRegular.copyWith(
                        color: colors.textSecondary,
                      ),
                    )
                  else
                    Text(
                      account.error != null
                          ? 'Download failed · Tap for details'
                          : account.source != PrepSource.manual &&
                                account.lastSyncAtMs == null &&
                                account.gameCount == 0
                          ? 'Ready to download'
                          : prepGamesLabel(account.gameCount),
                      style: AppTypography.textXsRegular.copyWith(
                        color: account.error != null
                            ? colors.danger
                            : colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            CardMoreButton(
              vertical: true,
              tooltip: 'Actions for $title on ${account.source.label}',
              color: colors.iconSecondary,
              actions: (_) => _menu(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _details(BuildContext context, WidgetRef ref) async {
    final action = await showAlertModal<_SourceDetailAction>(
      context: context,
      child: _SourceDetails(profileId: profile.id, accountKey: account.key),
    );
    if (!context.mounted || action == null) return;
    final liveProfile = ref.read(prepProfileProvider(profile.id));
    final live = liveProfile?.accounts
        .where((a) => a.key == account.key)
        .firstOrNull;
    if (liveProfile == null || live == null) return;
    switch (action) {
      case _SourceDetailAction.download:
        if (ref.read(prepSyncProvider).containsKey(live.key)) {
          ref.read(prepSyncProvider.notifier).cancel(live);
        } else {
          await prepDownloadSource(context, ref, liveProfile, live);
        }
      case _SourceDetailAction.options:
        await prepEditDownloadOptions(context, ref, liveProfile, live);
    }
  }

  List<LibraryMenuAction> _menu(BuildContext context, WidgetRef ref) => [
    LibraryMenuAction(
      icon: Icons.info_outline_rounded,
      label: 'Account details',
      onSelected: () => _details(context, ref),
    ),
    if (account.source != PrepSource.manual)
      LibraryMenuAction(
        icon: Icons.download_rounded,
        label: ref.read(prepSyncProvider).containsKey(account.key)
            ? 'Stop download'
            : account.lastSyncAtMs == null
            ? 'Download games'
            : 'Refresh games',
        onSelected: () => ref.read(prepSyncProvider).containsKey(account.key)
            ? ref.read(prepSyncProvider.notifier).cancel(account)
            : prepDownloadSource(context, ref, profile, account),
      ),
    if (account.source != PrepSource.manual)
      LibraryMenuAction(
        icon: Icons.tune_rounded,
        label: 'Download options',
        enabled: !ref.read(prepSyncProvider).containsKey(account.key),
        onSelected: () =>
            prepEditDownloadOptions(context, ref, profile, account),
      ),
    if (account.source.online)
      LibraryMenuAction(
        icon: Icons.edit_rounded,
        label: 'Change username',
        onSelected: () => prepChangeAccount(context, ref, profile, account),
      ),
    if (account.source != PrepSource.manual)
      LibraryMenuAction(
        icon: Icons.person_outline_rounded,
        label: 'Refresh profile details',
        onSelected: () async {
          final error = await prepRefreshProfileDetails(
            ref,
            profile.id,
            account: account,
          );
          if (context.mounted) {
            showAppSnack(
              context,
              error ?? 'Profile details refreshed',
              tone: error == null ? AppSnackTone.neutral : AppSnackTone.danger,
            );
          }
        },
      ),
    if (account.source.online)
      LibraryMenuAction(
        icon: Icons.open_in_new_rounded,
        label: 'Open ${account.source.label} profile',
        onSelected: () async {
          if (!await launchUrl(
                Uri.parse(account.profileUrl),
                mode: LaunchMode.externalApplication,
              ) &&
              context.mounted) {
            showAppSnack(
              context,
              'Could not open the profile.',
              tone: AppSnackTone.danger,
            );
          }
        },
      ),
    LibraryMenuAction(
      icon: Icons.ios_share_rounded,
      label: 'Export PGN',
      enabled:
          account.gameCount > 0 &&
          !ref.read(prepSyncProvider).containsKey(account.key),
      onSelected: () => prepExportSource(context, ref, profile, account),
    ),
    if (account.source != PrepSource.manual)
      LibraryMenuAction(
        icon: Icons.restart_alt_rounded,
        label: 'Download again',
        enabled: !ref.read(prepSyncProvider).containsKey(account.key),
        onSelected: () => prepReinstallSource(context, ref, profile, account),
      ),
    LibraryMenuAction(
      icon: Icons.link_off_rounded,
      label: 'Detach source',
      destructive: true,
      onSelected: () => prepDetachSource(context, ref, profile, account),
    ),
  ];
}

enum _SourceDetailAction { download, options }

/// Secondary account information stays off the source list.
class _SourceDetails extends ConsumerWidget {
  const _SourceDetails({required this.profileId, required this.accountKey});
  final String profileId;
  final String accountKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref
        .watch(prepProfileProvider(profileId))
        ?.accounts
        .where((a) => a.key == accountKey)
        .firstOrNull;
    if (account == null) return const SizedBox.shrink();
    final status = ref.watch(prepSyncProvider.select((s) => s[accountKey]));
    final colors = context.colors;
    return PrepDialogCard(
      icon: PrepSourceMark(source: account.source, size: 24.sp),
      title: account.source.online
          ? account.username
          : account.displayName ?? account.username,
      subtitle: account.source.label,
      children: [
        Row(
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
            Expanded(
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
        if (status != null || account.error != null) ...[
          SizedBox(height: 10.h),
          if (status != null)
            PrepShimmerText(
              status.message,
              style: AppTypography.textSmRegular.copyWith(
                color: colors.textSecondary,
              ),
            )
          else
            Text(
              account.error!,
              style: AppTypography.textSmRegular.copyWith(color: colors.danger),
            ),
        ],
        if (account.source != PrepSource.manual) ...[
          SizedBox(height: 14.h),
          _DownloadScope(
            account: account,
            onEdit: status == null
                ? () => Navigator.of(context).pop(_SourceDetailAction.options)
                : null,
          ),
        ],
        if (account.ratings.isNotEmpty) ...[
          SizedBox(height: 20.h),
          _RatingGrid(account: account),
        ],
        SizedBox(height: 24.h),
        if (account.source == PrepSource.manual)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: AppTypography.textSmMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Close',
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_SourceDetailAction.download),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: colors.textPrimary,
                    foregroundColor: colors.textInverse,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.br),
                    ),
                  ),
                  child: Text(
                    status != null
                        ? 'Stop download'
                        : account.lastSyncAtMs == null
                        ? 'Download games'
                        : 'Refresh games',
                    textAlign: TextAlign.center,
                    style: AppTypography.textSmBold,
                  ),
                ),
              ),
            ],
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

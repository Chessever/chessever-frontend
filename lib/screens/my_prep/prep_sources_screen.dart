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
                                  _Account(profile: profile, account: account),
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

class _Account extends ConsumerWidget {
  const _Account({required this.profile, required this.account});
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
                  Text(
                    busy
                        ? status.message
                        : account.error != null
                        ? 'Download failed · Tap for details'
                        : account.source != PrepSource.manual &&
                              account.lastSyncAtMs == null &&
                              account.gameCount == 0
                        ? 'Ready to download'
                        : prepGamesLabel(account.gameCount),
                    style: AppTypography.textXsRegular.copyWith(
                      color: account.error != null && !busy
                          ? colors.danger
                          : colors.textSecondary,
                    ),
                    semanticsLabel: busy
                        ? 'Download progress: ${status.message}'
                        : null,
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
    if (account.source.online)
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
        Text(
          prepGamesLabel(account.gameCount),
          style: AppTypography.textMdBold.copyWith(color: colors.textPrimary),
        ),
        SizedBox(height: 4.h),
        Text(
          prepSyncedAgo(account.lastSyncAtMs),
          style: AppTypography.textXsRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
        if (status != null || account.error != null) ...[
          SizedBox(height: 12.h),
          Text(
            status?.message ?? account.error!,
            style: AppTypography.textSmRegular.copyWith(
              color: status != null ? colors.textSecondary : colors.danger,
            ),
          ),
        ],
        if (account.source.online) ...[
          SizedBox(height: 16.h),
          Text(
            account.preferences.describe(account.source),
            style: AppTypography.textXsRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: status == null
                  ? () => Navigator.of(context).pop(_SourceDetailAction.options)
                  : null,
              child: Text(
                'Download options',
                style: AppTypography.textSmMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
        if (account.ratings.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.only(bottom: 16.h),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text('Ratings', style: AppTypography.textSmMedium),
            children: [
              for (final rating in account.ratings.entries)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 6.h),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${rating.key[0].toUpperCase()}${rating.key.substring(1)}',
                          style: AppTypography.textXsRegular.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '${rating.value}',
                        style: AppTypography.textXsMedium,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        SizedBox(height: 16.h),
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

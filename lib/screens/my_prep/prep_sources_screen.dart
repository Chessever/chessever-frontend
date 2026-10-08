import 'dart:async';

import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/prep_source_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
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
        title: Text('Sources', style: AppTypography.textMdBold),
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
                      SizedBox(height: 6.h),
                      Text(
                        'Attach the accounts that belong to this player. Games from all sources are read together.',
                        style: AppTypography.textSmRegular.copyWith(
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      for (final source in PrepSource.playerSources) ...[
                        Row(
                          children: [
                            PrepSourceMark(source: source, size: 24.sp),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: Text(
                                source.label,
                                style: AppTypography.textMdBold.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            if (source != PrepSource.chessever ||
                                profile.databaseAccount == null)
                              Flexible(
                                child: TextButton(
                                  key: ValueKey('prep_attach_${source.name}'),
                                  onPressed: () => prepAddAccountTo(
                                    context,
                                    ref,
                                    profile,
                                    source: source,
                                  ),
                                  child: Text(
                                    profile.accounts.any(
                                          (a) => a.source == source,
                                        )
                                        ? 'Add another'
                                        : 'Attach',
                                    style: AppTypography.textSmBold.copyWith(
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (!profile.accounts.any((a) => a.source == source))
                          Padding(
                            padding: EdgeInsets.only(bottom: 12.h),
                            child: Text(
                              source == PrepSource.chessever
                                  ? 'Optional. Search by name or FIDE ID.'
                                  : 'No account attached.',
                              style: AppTypography.textXsRegular.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        for (final account in profile.accounts.where(
                          (a) => a.source == source,
                        )) ...[
                          _Account(profile: profile, account: account),
                          SizedBox(height: 8.h),
                        ],
                        SizedBox(height: 12.h),
                      ],
                      Row(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 24.sp,
                            color: colors.textPrimary,
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Text(
                              'PGN files',
                              style: AppTypography.textMdBold.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                prepImportSource(context, ref, profile),
                            child: Text(
                              'Import',
                              style: AppTypography.textSmBold.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      for (final account in profile.accounts.where(
                        (a) => a.source == PrepSource.manual,
                      )) ...[
                        _Account(profile: profile, account: account),
                        SizedBox(height: 8.h),
                      ],
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
    return Container(
      key: ValueKey('prep_account_${account.key}'),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      padding: EdgeInsets.fromLTRB(14.sp, 8.sp, 6.sp, 10.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  account.displayName ?? account.username,
                  style: AppTypography.textSmBold.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              CardMoreButton(
                vertical: true,
                color: colors.iconPrimary,
                actions: (_) => _menu(context, ref),
              ),
            ],
          ),
          if (account.displayName != null &&
              account.displayName != account.username)
            Text(
              account.username,
              style: AppTypography.textXsRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
          if (account.ratings.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Wrap(
              spacing: 16.w,
              runSpacing: 6.h,
              children: [
                for (final rating in account.ratings.entries)
                  Text(
                    '${rating.key[0].toUpperCase()}${rating.key.substring(1)} ${rating.value}',
                    style: AppTypography.textXsMedium.copyWith(
                      color: colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ],
          SizedBox(height: 8.h),
          Text(
            status?.message ??
                account.error ??
                '${prepGamesLabel(account.gameCount)} · ${prepSyncedAgo(account.lastSyncAtMs)}',
            style: AppTypography.textXsRegular.copyWith(
              color: account.error != null && !busy
                  ? colors.danger
                  : colors.textSecondary,
            ),
            semanticsLabel: busy
                ? 'Download progress: ${status.message}'
                : null,
          ),
          if (account.source.online) ...[
            SizedBox(height: 4.h),
            Text(
              account.preferences.describe(account.source),
              style: AppTypography.textXsRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          Wrap(
            children: [
              if (account.source != PrepSource.manual)
                TextButton(
                  onPressed: busy
                      ? () =>
                            ref.read(prepSyncProvider.notifier).cancel(account)
                      : () =>
                            prepDownloadSource(context, ref, profile, account),
                  child: Text(
                    busy
                        ? 'Stop download'
                        : account.lastSyncAtMs == null
                        ? 'Download games'
                        : 'Refresh games',
                    style: AppTypography.textXsMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              if (account.source.online)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => prepEditDownloadOptions(
                          context,
                          ref,
                          profile,
                          account,
                        ),
                  child: Text(
                    'Options',
                    style: AppTypography.textXsMedium.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<LibraryMenuAction> _menu(BuildContext context, WidgetRef ref) => [
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

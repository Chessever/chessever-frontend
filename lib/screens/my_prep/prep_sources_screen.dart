import 'dart:async';

import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/prep_source_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_source_dialog.dart';
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
                                    // Sources is pushed from its profile.
                                    onOpenProfile: () =>
                                        Navigator.of(context).maybePop(),
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
    this.onOpenProfile,
  });
  final PrepProfile profile;
  final PrepAccount account;

  /// Where the popup's "Go to profile" leads. Opens the profile by default;
  /// a list already sitting on that profile leads back to it instead.
  final VoidCallback? onOpenProfile;

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
      onTap: () => _details(context),
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

  /// The source's popup, and the profile when the reader asks for it there.
  Future<void> _details(BuildContext context) async {
    final toProfile = await showPrepSourceDialog(
      context,
      profileId: profile.id,
      accountKey: account.key,
    );
    if (toProfile != true || !context.mounted) return;
    if (onOpenProfile case final open?) {
      open();
    } else {
      unawaited(PrepProfileScreen.open(context, profile.id));
    }
  }

  List<LibraryMenuAction> _menu(BuildContext context, WidgetRef ref) => [
    LibraryMenuAction(
      icon: Icons.info_outline_rounded,
      label: 'Account details',
      onSelected: () => _details(context),
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

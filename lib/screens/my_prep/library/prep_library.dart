import 'dart:async';

import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction;
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/library/prep_cloud_sync.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_index.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_games_tab.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/game_tree/build_tree_button.dart';
import 'package:chessever2/widgets/paywall/game_tree_access.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Library node ids for My Prep players. Never a cloud row id, so the
/// Library can tell a player's folder from a cloud folder by its id.
const String kPrepLibraryFolderPrefix = '__prep__:';

String? prepProfileIdOfLibraryFolder(String folderId) =>
    folderId.startsWith(kPrepLibraryFolderPrefix)
    ? folderId.substring(kPrepLibraryFolderPrefix.length)
    : null;

/// A My Prep player as a Library folder: on desktop each Prep player is a
/// Library folder holding a database per source, and so it is here.
LibraryFolder prepLibraryFolder(PrepProfile profile) => LibraryFolder(
  id: '$kPrepLibraryFolderPrefix${profile.id}',
  userId: '',
  name: profile.name,
  color: '#0FB4E5',
  icon: 'prep',
  orderIndex: 0,
  createdAt: DateTime.fromMillisecondsSinceEpoch(profile.createdAtMs),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(
    profile.lastSyncAtMs ?? profile.createdAtMs,
  ),
  nodeType: LibraryFolder.nodeTypeFolder,
);

LibraryFolder _databaseNode(
  PrepProfile profile,
  PrepAccount? account,
) => LibraryFolder(
  id: '$kPrepLibraryFolderPrefix${profile.id}:${account?.key ?? 'combined'}',
  userId: '',
  name: account == null ? 'Combined' : _accountLabel(account),
  color: '#0FB4E5',
  icon: 'database',
  orderIndex: 0,
  createdAt: DateTime.fromMillisecondsSinceEpoch(profile.createdAtMs),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(profile.createdAtMs),
  parentId: '$kPrepLibraryFolderPrefix${profile.id}',
);

String _accountLabel(PrepAccount account) =>
    '${account.source.label} · ${account.username}';

/// The players the Library lists, yours first, including profiles waiting
/// for their first source.
final prepLibraryProfilesProvider = Provider<List<PrepProfile>>((ref) {
  final all = ref.watch(prepProfilesProvider).valueOrNull ?? const [];
  return [
    for (final kind in PrepKind.values)
      for (final p in all)
        if (p.kind == kind) p,
  ];
});

/// Cloud folders a player was saved to. The Library shows the player's own
/// card for them, so they are not listed twice.
final prepLinkedCloudFolderIdsProvider = Provider<Set<String>>(
  (ref) => {
    for (final p in ref.watch(prepLibraryProfilesProvider))
      if (p.cloudFolderId case final id?) id,
  },
);

String? _fideIdOf(PrepProfile profile) =>
    profile.fideId ??
    kPrepFavorites.where((f) => f.id == profile.favoriteId).firstOrNull?.fideId;

/// One player's folder card in the Library list.
class PrepLibraryFolderCard extends ConsumerWidget {
  const PrepLibraryFolderCard({
    super.key,
    required this.profile,
    this.isFeatured = false,
  });

  final PrepProfile profile;
  final bool isFeatured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing = ref.watch(
      prepSyncProvider.select(
        (s) => profile.accounts.any((a) => s.containsKey(a.key)),
      ),
    );
    final databases = profile.accounts.length + 1;
    final subtitle = syncing
        ? 'Downloading games…'
        : '$databases databases · ${prepGamesLabel(profile.gameCount)}';
    return FolderCard(
      folder: prepLibraryFolder(profile),
      isExpanded: true,
      isFeatured: isFeatured,
      subtitle: subtitle,
      badge: profile.savedToCloud ? Icons.cloud_done_rounded : null,
      leading: Center(
        child: PrepAvatar(
          name: profile.name,
          size: isFeatured ? 56.sp : 36.h,
          photoUrl: profile.avatarUrl,
          fideId: _fideIdOf(profile),
          title: profile.title,
        ),
      ),
      onTap: () => PrepLibraryFolderScreen.open(context, profile.id),
      menuActions: (menuContext) => [
        LibraryMenuAction(
          icon: Icons.insights_rounded,
          label: 'Open in My Prep',
          prominent: true,
          onSelected: () => PrepProfileScreen.open(context, profile.id),
        ),
        ...prepProfileMenu(context, ref, profile, fromLibrary: true),
      ],
    );
  }
}

/// Save to cloud, or sync again once saved.
LibraryMenuAction prepCloudMenuAction(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
) => LibraryMenuAction(
  icon: profile.savedToCloud
      ? Icons.cloud_sync_rounded
      : Icons.cloud_upload_outlined,
  label: profile.savedToCloud ? 'Sync to cloud now' : 'Save to cloud',
  onSelected: () => prepSaveToCloud(context, ref, profile.id),
);

/// Saves (or brings up to date) a player's cloud copy, behind Premium.
Future<void> prepSaveToCloud(
  BuildContext context,
  WidgetRef ref,
  String profileId,
) async {
  HapticFeedbackService.buttonPress();
  if (!await ensurePrepCloudAccess(context) || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final first = ref.read(prepProfileProvider(profileId))?.savedToCloud != true;
  final error = await ref.read(prepCloudSyncProvider.notifier).save(profileId);
  if (messenger == null) return;
  final profile = ref.read(prepProfileProvider(profileId));
  showAppSnackOn(
    messenger,
    error ??
        (first
            ? '${profile?.name ?? 'Player'} is in your cloud Library'
            : '${profile?.name ?? 'Player'} is up to date in the cloud'),
    tone: error == null ? AppSnackTone.success : AppSnackTone.danger,
  );
}

// ------------------------------------------------------------------ trees

/// A player's Combined database as a tree: the profile's own index, the
/// one My Prep's Openings tab explores.
class PrepProfileTreeTarget extends GameTreeTarget {
  const PrepProfileTreeTarget({
    required this.profile,
    required this.repository,
  });

  final PrepProfile profile;
  final PrepRepository repository;

  @override
  String get scopeId => profile.id;
  @override
  String get title => profile.name;
  @override
  bool get playerScope => true;
  @override
  bool get requiresPremium => false;
  @override
  String? get country => profile.country;
  @override
  String? get playerTitle => profile.title;

  // The build is a quick no-op when nothing changed, so it always runs.
  @override
  Future<bool> isCurrent(GameTreeStore store) async => false;

  @override
  Future<GameTreeStore> build(void Function(GameTreeStatus) report) =>
      PrepIndex.ensureProfile(
        repository,
        profile,
        onProgress: (f) =>
            report(GameTreeStatus(phase: GameTreePhase.indexing, fraction: f)),
      );
}

/// One account's database as a tree of its own.
class PrepAccountTreeTarget extends GameTreeTarget {
  const PrepAccountTreeTarget({
    required this.profile,
    required this.account,
    required this.repository,
  });

  final PrepProfile profile;
  final PrepAccount account;
  final PrepRepository repository;

  @override
  String get scopeId => PrepIndex.accountScope(account);
  @override
  String get title => '${profile.name} · ${account.source.label}';
  @override
  bool get playerScope => true;
  @override
  bool get requiresPremium => false;
  @override
  String? get country => profile.country;
  @override
  String? get playerTitle => profile.title;

  @override
  Future<bool> isCurrent(GameTreeStore store) async => false;

  @override
  Future<GameTreeStore> build(void Function(GameTreeStatus) report) =>
      PrepIndex.ensureAccount(
        repository,
        profile,
        account,
        onProgress: (f) =>
            report(GameTreeStatus(phase: GameTreePhase.indexing, fraction: f)),
      );
}

// ------------------------------------------------------------------ screens

/// The header every Library node screen wears: back, a centred title over
/// a count line, and the node's actions at the right.
class _NodeHeader extends StatelessWidget {
  const _NodeHeader({
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final horizontal = ResponsiveHelper.adaptive(phone: 8.w, tablet: 16.w);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontal,
        MediaQuery.of(context).viewPadding.top + 8.h,
        horizontal,
        8.h,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: colors.textPrimary,
              size: 20.ic,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textMdBold.copyWith(
                    color: colors.textPrimary,
                    height: 1.25,
                  ),
                ),
                Text(
                  subtitle,
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
          ...actions,
          // Balance the back button when there is nothing on the right.
          if (actions.isEmpty) const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// A player's Library folder: their Combined database and one per account,
/// in desktop's order (Combined first, then by name).
class PrepLibraryFolderScreen extends ConsumerWidget {
  const PrepLibraryFolderScreen({super.key, required this.profileId});

  final String profileId;

  static Future<void> open(BuildContext context, String profileId) {
    HapticFeedbackService.cardTap();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrepLibraryFolderScreen(profileId: profileId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(prepProfileProvider(profileId));
    if (profile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return Scaffold(backgroundColor: context.colors.background);
    }
    final sync = ref.watch(prepSyncProvider);
    final accounts = [...profile.accounts]
      ..sort(
        (a, b) => _accountLabel(
          a,
        ).toLowerCase().compareTo(_accountLabel(b).toLowerCase()),
      );
    final databases = accounts.length + 1;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: ScreenWrapper(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.isTablet
                  ? ResponsiveHelper.contentMaxWidth
                  : double.infinity,
            ),
            child: Column(
              children: [
                _NodeHeader(
                  title: profile.name,
                  subtitle:
                      '$databases databases · ${prepGamesLabel(profile.gameCount)}',
                  actions: [
                    CardMoreButton(
                      vertical: true,
                      color: context.colors.textPrimary,
                      size: 22.ic,
                      actions: (_) => [
                        LibraryMenuAction(
                          icon: Icons.insights_rounded,
                          label: 'Open in My Prep',
                          prominent: true,
                          onSelected: () =>
                              PrepProfileScreen.open(context, profile.id),
                        ),
                        ...prepProfileMenu(
                          context,
                          ref,
                          profile,
                          fromLibrary: true,
                        ),
                      ],
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 32.h),
                    children: [
                      _CloudLine(profile: profile),
                      SizedBox(height: 12.h),
                      _DatabaseCard(
                        profile: profile,
                        account: null,
                        subtitle:
                            '${prepGamesLabel(profile.gameCount)} · every account',
                      ),
                      for (final account in accounts)
                        _DatabaseCard(
                          profile: profile,
                          account: account,
                          subtitle: sync.containsKey(account.key)
                              ? sync[account.key]!.message
                              : account.error ??
                                    (account.lastSyncAtMs == null
                                        ? 'Not downloaded yet'
                                        : '${prepGamesLabel(account.gameCount)} · '
                                              '${prepSyncedAgo(account.lastSyncAtMs)}'),
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

class _DatabaseCard extends ConsumerWidget {
  const _DatabaseCard({
    required this.profile,
    required this.account,
    required this.subtitle,
  });

  final PrepProfile profile;
  final PrepAccount? account;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = this.account;
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: FolderCard(
        folder: _databaseNode(profile, account),
        isExpanded: true,
        subtitle: subtitle,
        leading: account == null
            ? null
            : PrepSourceMark(source: account.source, size: 36.h),
        onTap: () => PrepLibraryDatabaseScreen.open(
          context,
          profileId: profile.id,
          accountKey: account?.key,
        ),
        menuActions: (_) => [
          if (account != null)
            LibraryMenuAction(
              icon: Icons.refresh_rounded,
              label: 'Refresh games',
              prominent: true,
              onSelected: () =>
                  prepRefreshAccount(context, ref, profile.id, account),
            )
          else
            LibraryMenuAction(
              icon: Icons.refresh_rounded,
              label: 'Refresh games',
              prominent: true,
              onSelected: () => prepRefreshProfile(context, ref, profile.id),
            ),
          LibraryMenuAction(
            icon: Icons.account_tree_rounded,
            label: 'Open tree',
            onSelected: () => openOrBuildGameTree(
              context,
              ref,
              _treeTarget(ref, profile, account),
            ),
          ),
          prepCloudMenuAction(context, ref, profile),
        ],
      ),
    );
  }
}

GameTreeTarget _treeTarget(
  WidgetRef ref,
  PrepProfile profile,
  PrepAccount? account,
) {
  final repository = ref.read(prepRepositoryProvider);
  return account == null
      ? PrepProfileTreeTarget(profile: profile, repository: repository)
      : PrepAccountTreeTarget(
          profile: profile,
          account: account,
          repository: repository,
        );
}

/// Where the player's cloud copy stands, with the one action that moves it.
class _CloudLine extends ConsumerWidget {
  const _CloudLine({required this.profile});

  final PrepProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final status = ref.watch(
      prepCloudSyncProvider.select((s) => s[profile.id]),
    );
    final saved = profile.savedToCloud;
    final uploaded = profile.accounts.fold<int>(
      0,
      (sum, a) => sum + a.cloudSyncedCount,
    );
    final String text;
    if (status != null) {
      final total = status.total;
      text = total == null || total == 0
          ? status.message
          : '${status.message} ${prepCount(status.done)} of ${prepCount(total)}';
    } else if (saved) {
      text =
          'In your cloud Library · ${prepGamesLabel(uploaded)}. '
          'New games follow after each download.';
    } else {
      text =
          'Save this player to your cloud Library to open them on '
          'desktop and the web.';
    }
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 4.h, 4.w, 4.h),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 18.sp,
            child: status != null
                ? CircularProgressIndicator(
                    strokeWidth: 2,
                    value: status.total == null || status.total == 0
                        ? null
                        : status.done / status.total!,
                    color: colors.textSecondary,
                  )
                : Icon(
                    saved
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_upload_outlined,
                    size: 18.sp,
                    color: colors.iconSecondary,
                  ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Text(
                text,
                style: AppTypography.textXsRegular.copyWith(
                  color: colors.textSecondary,
                  height: 16 / 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          SizedBox(width: 4.w),
          DiscoveryAction(
            label: status != null
                ? 'Stop'
                : saved
                ? 'Sync now'
                : 'Save to cloud',
            onTap: status != null
                ? () => ref
                      .read(prepCloudSyncProvider.notifier)
                      .cancel(profile.id)
                : () => prepSaveToCloud(context, ref, profile.id),
          ),
        ],
      ),
    );
  }
}

/// One of a player's databases: its games, newest first, on the Library's
/// game cards, with the tree at the top-right like every games view.
class PrepLibraryDatabaseScreen extends ConsumerStatefulWidget {
  const PrepLibraryDatabaseScreen({
    super.key,
    required this.profileId,
    this.accountKey,
  });

  final String profileId;

  /// Null for the Combined database.
  final String? accountKey;

  static Future<void> open(
    BuildContext context, {
    required String profileId,
    String? accountKey,
  }) {
    HapticFeedbackService.cardTap();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrepLibraryDatabaseScreen(
          profileId: profileId,
          accountKey: accountKey,
        ),
      ),
    );
  }

  @override
  ConsumerState<PrepLibraryDatabaseScreen> createState() =>
      _PrepLibraryDatabaseScreenState();
}

class _PrepLibraryDatabaseScreenState
    extends ConsumerState<PrepLibraryDatabaseScreen> {
  PrepFilter _filter = const PrepFilter();
  List<PrepGame>? _input;
  PrepFilter? _used;
  List<PrepGame> _output = const [];

  List<PrepGame> _games(List<PrepGame> all, PrepAccount? account) {
    if (!identical(all, _input) || _used != _filter) {
      _input = all;
      _used = _filter;
      final file = account == null
          ? null
          : PrepRepository.gamesFileName(account);
      _output = _filter.apply([
        for (final g in all)
          if (file == null || g.sourcePath.endsWith(file)) g,
      ]);
    }
    return _output;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(prepProfileProvider(widget.profileId));
    if (profile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return Scaffold(backgroundColor: context.colors.background);
    }
    final account = profile.accounts
        .where((a) => a.key == widget.accountKey)
        .firstOrNull;
    if (widget.accountKey != null && account == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return Scaffold(backgroundColor: context.colors.background);
    }
    final analysis = ref.watch(prepAnalysisProvider(profile.id));
    final indexing = ref.watch(
      gameTreeStatusProvider.select((s) => s[profile.id]?.percent),
    );
    final games = _games(
      analysis.valueOrNull?.games ?? const <PrepGame>[],
      account,
    );
    final count = account?.gameCount ?? profile.gameCount;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: ScreenWrapper(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.isTablet
                  ? ResponsiveHelper.contentMaxWidth
                  : double.infinity,
            ),
            child: Column(
              children: [
                _NodeHeader(
                  title: account == null ? 'Combined' : _accountLabel(account),
                  subtitle: '${profile.name} · ${prepGamesLabel(count)}',
                  actions: [
                    if (count > 0)
                      BuildTreeButton(
                        compact: false,
                        target: _treeTarget(ref, profile, account),
                      ),
                  ],
                ),
                Expanded(
                  child: analysis.when(
                    skipLoadingOnReload: true,
                    error: (error, _) => PrepMessage(
                      title: 'Could not read these games',
                      body: '$error',
                    ),
                    loading: () => PrepMessage(
                      title: indexing == null
                          ? 'Reading games…'
                          : 'Indexing games · $indexing%',
                      body:
                          'Done once on this phone. Later updates only '
                          'add new games.',
                      busy: true,
                    ),
                    data: (data) =>
                        games.isEmpty && _filter == const PrepFilter()
                        ? PrepMessage(
                            title: 'No games yet',
                            body:
                                account?.error ??
                                'Download games for this player in My Prep.',
                            actionLabel: 'Refresh games',
                            onAction: () => account == null
                                ? prepRefreshProfile(context, ref, profile.id)
                                : prepRefreshAccount(
                                    context,
                                    ref,
                                    profile.id,
                                    account,
                                  ),
                          )
                        : PrepGamesTab(
                            analysis: data,
                            games: games,
                            filter: _filter,
                            onFilterChanged: (f) => setState(() => _filter = f),
                          ),
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

/// Opens the Library node a My Prep folder id names.
void openPrepLibraryFolder(BuildContext context, String folderId) {
  final profileId = prepProfileIdOfLibraryFolder(folderId);
  if (profileId != null) {
    unawaited(PrepLibraryFolderScreen.open(context, profileId));
  }
}

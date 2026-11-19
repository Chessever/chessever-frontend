import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_index.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_games_tab.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_open_profile_button.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/game_tree/build_tree_button.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/home_top_bar.dart' show PageTitle;
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
          label: 'Open in Prep',
          prominent: true,
          onSelected: () => PrepProfileScreen.open(context, profile.id),
        ),
        ...prepProfileMenu(context, ref, profile, fromLibrary: true),
      ],
    );
  }
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

/// The status bar's inset over a Library node screen's header, kept apart
/// from it: a header that scrolls away folds up to this line, never into
/// the status bar.
double _headerInset(BuildContext context) =>
    MediaQuery.viewPaddingOf(context).top + 4.h;

/// The width a header's ⋮ takes ([CardMoreButton]'s square target): kept
/// while the menu has nothing to act on, so the title holds still.
const double _kMenuSlot = 44;

/// The header every Library node screen wears: back, a centred title over
/// a count line, and the node's actions at the right. It sits under
/// [_headerInset], its chevron where a search header's is
/// ([SearchHeaderMetrics]), its last action's glyph on the gutter.
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
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        SearchHeaderMetrics.leadingInset,
        0,
        math.max(
          0.0,
          SearchHeaderMetrics.gutter - SearchHeaderMetrics.trailingReach,
        ),
        SearchHeaderMetrics.bottomGap,
      ),
      // The chevron and the actions keep to the back row; a title that
      // grows (two lines, large text) grows the header downwards around
      // them instead of moving them.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageBackButton(),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: SearchHeaderMetrics.rowHeight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The one pushed-page title voice ([PageTitle]), read as
                  // a heading; it may take a second line here, the header
                  // growing around it.
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PageTitle.style(context).copyWith(height: 1.25),
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
          ),
          for (final action in actions)
            SizedBox(
              height: SearchHeaderMetrics.rowHeight,
              child: Center(child: action),
            ),
          // Balance the back button when there is nothing on the right.
          if (actions.isEmpty)
            const SizedBox(width: SearchHeaderMetrics.backTarget),
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
                SizedBox(height: _headerInset(context)),
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
                          label: 'Open in Prep',
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
                              : account.downloadError ??
                                    (account.lastSyncAtMs == null
                                        ? 'Not downloaded yet'
                                        : '${prepGamesLabel(account.gameCount)} · '
                                              '${prepSyncedAgo(account.lastSyncAtMs)}'),
                        ),
                      if (profile.gameCount > 0)
                        Padding(
                          padding: EdgeInsets.only(top: 8.h),
                          child: PrepOpenProfileButton(
                            key: const ValueKey('prep_library_open_profile'),
                            profileId: profile.id,
                          ),
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
        // Combined wears the database glyph bare at the marks' size, so all
        // the cards lead with the same weight.
        leading: account == null
            ? ChessDatabaseGlyph(color: context.colors.iconPrimary, size: 36.h)
            : PrepSourceMark(source: account.source, size: 36.h),
        // A database is its games, which open as Prep's Games tab does.
        onTap: () async {
          if (!await ensurePrepAccess(context, feature: 'prep_games') ||
              !context.mounted) {
            return;
          }
          unawaited(
            PrepLibraryDatabaseScreen.open(
              context,
              profileId: profile.id,
              accountKey: account?.key,
            ),
          );
        },
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

/// One of a player's databases: its games, newest first, on the Library's
/// game cards, with the tree at the top-right like every games view. The
/// search floats at the bottom-right and opens over the whole page, as a
/// profile's Games does.
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
    extends ConsumerState<PrepLibraryDatabaseScreen>
    with SingleTickerProviderStateMixin {
  PrepFilter _filter = const PrepFilter();
  final _gamesController = PrepGamesController();
  List<PrepGame>? _input;
  PrepFilter? _used;
  List<PrepGame> _output = const [];

  /// The header, pushed away by the list's scroll and back as it scrolls
  /// up, with the search button sliding out under it.
  late final ScrollChromeController _chrome = ScrollChromeController(
    vsync: this,
  );

  /// The full-page search: the search button's glass becomes the field in
  /// the header's place, over the same games, narrowing as the reader
  /// types. Back from it clears what was typed; the filters stay, counted on
  /// the list's own line (and on the search header's Filters while it is
  /// open).
  final SearchModeController _search = SearchModeController();

  /// What the games are narrowed to, as typed: '' the moment the search
  /// closes.
  final ValueNotifier<String> _query = ValueNotifier('');

  /// What the header's menu follows: the words, and how many games they
  /// leave on the list.
  late final Listenable _menuInputs = Listenable.merge([
    _query,
    _gamesController.shownCount,
  ]);

  void _onSearchMode() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchMode);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onSearchMode)
      ..dispose();
    _query.dispose();
    _gamesController.dispose();
    _chrome.dispose();
    super.dispose();
  }

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
    final unfiltered = _filter == const PrepFilter();
    // The database lists its games (not a message): it has a search.
    final listed =
        analysis.hasValue &&
        !analysis.hasError &&
        (games.isNotEmpty || !unfiltered);
    // The games gave way to a message (a read failed, the last game went):
    // the search goes with them. A read still running keeps it.
    final gamesGone =
        analysis.hasError || (analysis.hasValue && games.isEmpty && unfiltered);
    if (_search.isSearching && gamesGone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search.close();
      });
    }

    final bars = _NodeHeader(
      title: account == null ? 'Combined' : _accountLabel(account),
      subtitle: '${profile.name} · ${prepGamesLabel(count)}',
      actions: [
        if (count > 0)
          BuildTreeButton(
            compact: false,
            target: _treeTarget(ref, profile, account),
          ),
        // What saves or exports the games listed. Their count, filters and
        // layout are on the list's own line. The menu acts on the games the
        // list shows now, after its filters and its search: when they leave
        // none it has nothing to offer, so it goes (never an empty menu) and
        // its place stays, so the title does not move.
        if (listed)
          ListenableBuilder(
            listenable: _menuInputs,
            builder: (context, _) {
              // Without words the filters alone decide, known here at once;
              // a search's hits are the list's own count.
              final searched = _query.value.trim().isNotEmpty;
              final shown = games.isEmpty
                  ? 0
                  : searched
                  ? _gamesController.shownCount.value ?? games.length
                  : games.length;
              return shown == 0
                  ? const SizedBox(width: _kMenuSlot)
                  : CardMoreButton(
                      vertical: true,
                      color: context.colors.textPrimary,
                      size: 22.ic,
                      actions: (_) => prepGamesMenu(_gamesController),
                    );
            },
          ),
      ],
    );
    // The list's board view and Filters, as every Games search header ends;
    // its line under the header keeps the count.
    final search = SearchModeHeader(
      hintText: 'Search games',
      textFieldKey: const ValueKey('prep_library_games_search'),
      closeKey: const ValueKey('prep_library_search_close'),
      trailing: [
        PrepGamesSearchControls(
          filterCount: _filter.activeCount,
          games: _gamesController,
        ),
      ],
    );

    return SearchModeHost(
      controller: _search,
      chrome: _chrome,
      // The list narrows on the phone as each letter is typed.
      debounce: Duration.zero,
      onChanged: (query) => _query.value = query,
      child: Scaffold(
        backgroundColor: context.colors.background,
        // Kept while searching: the search's glass flies back into it.
        floatingActionButton: SlidingFabs(
          controller: _chrome,
          child: listed || _search.isSearching
              // The list's line counts its filters, and it is in view
              // whenever this button is (both come back as the list scrolls
              // up); while searching the search header's Filters count them.
              // So the button carries no count.
              ? const SearchInkFab(
                  key: ValueKey('prep_library_search_fab'),
                  label: 'Search games',
                )
              : const SizedBox.shrink(),
        ),
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
                  SizedBox(height: _headerInset(context)),
                  CollapsingChrome(
                    controller: _chrome,
                    child: SearchModeHeaderSlot(
                      header: SizedBox(width: double.infinity, child: bars),
                      search: search,
                    ),
                  ),
                  Expanded(
                    child: ScrollChromeRegion(
                      controller: _chrome,
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
                        data: (data) => games.isEmpty && unfiltered
                            ? PrepMessage(
                                title: 'No games yet',
                                body:
                                    account?.error ??
                                    'Download games for this player in Prep.',
                                actionLabel: 'Refresh games',
                                onAction: () => account == null
                                    ? prepRefreshProfile(
                                        context,
                                        ref,
                                        profile.id,
                                      )
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
                                controller: _gamesController,
                                // Typed in the search header.
                                search: _query,
                                onClearSearch: _search.text.clear,
                                filterButtonKey: const ValueKey(
                                  'prep_library_games_filters',
                                ),
                                onFilterChanged: (f) =>
                                    setState(() => _filter = f),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
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

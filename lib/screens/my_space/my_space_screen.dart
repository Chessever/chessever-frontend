import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/miniatures/miniatures_screen.dart';
import 'package:chessever2/screens/miniatures/providers/miniatures_provider.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/my_space/data/my_space_layout_repository.dart';
import 'package:chessever2/screens/my_space/domain/my_space_layout.dart';
import 'package:chessever2/screens/my_space/domain/my_space_shelf_state.dart';
import 'package:chessever2/screens/my_space/providers/my_space_content_providers.dart';
import 'package:chessever2/screens/my_space/providers/my_space_layout_provider.dart';
import 'package:chessever2/screens/my_space/services/my_space_miniature_opener.dart';
import 'package:chessever2/screens/my_space/widgets/my_space_shelf.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/studies/studies_browse_screen.dart';
import 'package:chessever2/screens/studies/study_detail_screen.dart';
import 'package:chessever2/screens/studies/providers/studies_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/liquid_glass/glass_kit.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef MySpaceAsyncAction = FutureOr<void> Function();
typedef MySpaceItemAction = FutureOr<void> Function(MySpaceContentItem item);
typedef MySpaceShelfAction = FutureOr<void> Function(MySpaceShelfType type);

/// Premium, layout-driven My Space with independently resolved content rails.
class MySpaceScreen extends ConsumerStatefulWidget {
  const MySpaceScreen({
    super.key,
    this.onAccountTap,
    this.onBrowseStudies,
    this.onDiscoverGames,
    this.onBrowseEvents,
    this.onOpenLibrary,
    this.onFindPlayers,
    this.onOpenItem,
    this.onOpenStudy,
    this.onOpenMiniature,
    this.onRetryShelf,
  });

  final MySpaceAsyncAction? onAccountTap;

  final MySpaceAsyncAction? onBrowseStudies;
  final MySpaceAsyncAction? onDiscoverGames;
  final MySpaceAsyncAction? onBrowseEvents;
  final MySpaceAsyncAction? onOpenLibrary;
  final MySpaceAsyncAction? onFindPlayers;
  final MySpaceItemAction? onOpenItem;
  final StudySelectedCallback? onOpenStudy;
  final MiniatureOpenCallback? onOpenMiniature;
  final MySpaceShelfAction? onRetryShelf;

  @override
  ConsumerState<MySpaceScreen> createState() => _MySpaceScreenState();
}

class _MySpaceScreenState extends ConsumerState<MySpaceScreen> {
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    final layoutValue = ref.watch(mySpaceLayoutProvider);
    final snapshot =
        layoutValue.valueOrNull ??
        MySpaceLayoutSnapshot.defaultLayout(
          persistenceAvailable: false,
          failure: layoutValue.error,
        );
    final descriptors = snapshot.layout.shelves
        .where((descriptor) => descriptor.visible)
        .toList(growable: false);
    final parentScaffold = Scaffold.maybeOf(context);

    return KeyedSubtree(
      key: e2eKey(E2eIds.mySpaceRoot),
      child: GlassFullScreenPage(
        key: const ValueKey<String>('my-space-full-screen-page'),
        backgroundColor: context.colors.background,
        contentPadding: const EdgeInsets.only(top: 72, bottom: 96),
        topOverlayPadding: const EdgeInsets.only(top: 4),
        topOverlay: GlassIslandTopBar(
          key: const ValueKey<String>('my-space-floating-top-overlay'),
          topPadding: 0,
          height: 48,
          leading: _AccountControl(
            onTap:
                () => unawaited(
                  _runAction(
                    widget.onAccountTap ??
                        () {
                          parentScaffold?.openDrawer();
                        },
                  ),
                ),
          ),
          title: const GlassTitleChip(label: 'My Space', maxWidth: 128),
          trailing: [
            if (snapshot.persistenceAvailable)
              _EditLayoutControl(
                isEditing: _isEditing,
                isSaving: snapshot.isSaving,
                onPressed:
                    snapshot.isSaving
                        ? null
                        : () => setState(() => _isEditing = !_isEditing),
              ),
            _AddShelfControl(
              isSaving: snapshot.isSaving,
              onPressed:
                  snapshot.isSaving ? null : () => unawaited(_handleAddShelf()),
            ),
          ],
        ),
        content: ListView(
          key: const PageStorageKey<String>('my-space-vertical-feed'),
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          physics: const BouncingScrollPhysics(),
          children: [
            if (layoutValue.isLoading)
              const _LayoutStatusBanner.loading()
            else if (snapshot.failure case final failure?)
              _LayoutStatusBanner.failure(
                failure: failure,
                onRetry:
                    snapshot.persistenceAvailable
                        ? () => unawaited(
                          ref.read(mySpaceLayoutProvider.notifier).reload(),
                        )
                        : null,
              ),
            for (final descriptor in descriptors)
              _MySpaceShelfProviderView(
                key: ValueKey<String>('my-space-shelf-${descriptor.id}'),
                descriptor: descriptor,
                onOpenItem: (item) => unawaited(_openItem(item)),
                onEmptyAction:
                    () => unawaited(_runAction(_emptyAction(descriptor.type))),
                onRetryShelf: widget.onRetryShelf,
                onManage:
                    _isEditing && snapshot.persistenceAvailable
                        ? () => unawaited(
                          _openShelfManagement(descriptor, snapshot.layout),
                        )
                        : null,
              ),
            _AddShelfContainer(
              persistenceAvailable: snapshot.persistenceAvailable,
              onPressed:
                  snapshot.isSaving ? null : () => unawaited(_handleAddShelf()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAddShelf() async {
    final snapshot = ref.read(mySpaceLayoutProvider).valueOrNull;
    if (snapshot == null || !mounted) {
      showGlassSnack(
        context,
        message: 'Your My Space layout is still loading. Try again shortly.',
      );
      return;
    }

    final result = await showAppGlassSheet<_CatalogResult>(
      context: context,
      builder: (sheetContext) {
        return _AddShelfCatalog(
          layout: snapshot.layout,
          persistenceAvailable: snapshot.persistenceAvailable,
          onClose: () => Navigator.of(sheetContext).pop(),
          onAdd:
              (type) => Navigator.of(sheetContext).pop(_AddCatalogShelf(type)),
          onReset:
              () => Navigator.of(sheetContext).pop(const _ResetCatalogLayout()),
        );
      },
    );
    if (result == null || !mounted) return;

    switch (result) {
      case _AddCatalogShelf(:final type):
        if (!await _passesClientPremiumGate() || !mounted) return;
        final defaultSize =
            type.supportsSize(MySpaceShelfSize.compact)
                ? MySpaceShelfSize.compact
                : MySpaceShelfSize.standard;
        await _performLayoutMutation(
          (notifier) => notifier.addShelf(
            MySpaceShelfDescriptor(
              id:
                  'custom_${type.rawType}_${DateTime.now().microsecondsSinceEpoch}',
              type: type,
              size: defaultSize,
            ),
          ),
          successMessage: '${_ShelfCopy.forType(type).title} added.',
        );
      case _ResetCatalogLayout():
        if (!await _passesClientPremiumGate() || !mounted) return;
        await _performLayoutMutation(
          (notifier) => notifier.resetToDefault(),
          successMessage: 'My Space reset to the curated layout.',
        );
    }
  }

  Future<void> _openShelfManagement(
    MySpaceShelfDescriptor descriptor,
    MySpaceLayout layout,
  ) async {
    if (!mounted) return;
    final index = layout.shelves.indexWhere((item) => item.id == descriptor.id);
    if (index < 0) return;
    final result = await showAppGlassSheet<_ShelfManagementResult>(
      context: context,
      builder:
          (sheetContext) => _ShelfManagementSheet(
            descriptor: descriptor,
            canMoveUp: index > 0,
            canMoveDown: index < layout.shelves.length - 1,
            onSelect: (value) => Navigator.of(sheetContext).pop(value),
            onClose: () => Navigator.of(sheetContext).pop(),
          ),
    );
    if (result == null || !mounted) return;
    if (!await _passesClientPremiumGate() || !mounted) return;

    switch (result) {
      case _ShelfManagementResult.moveUp:
        await _performLayoutMutation(
          (notifier) => notifier.moveShelf(descriptor.id, index - 1),
          successMessage: '${_ShelfCopy.forType(descriptor.type).title} moved.',
        );
      case _ShelfManagementResult.moveDown:
        await _performLayoutMutation(
          (notifier) => notifier.moveShelf(descriptor.id, index + 1),
          successMessage: '${_ShelfCopy.forType(descriptor.type).title} moved.',
        );
      case _ShelfManagementResult.compact:
        await _resizeShelf(descriptor, MySpaceShelfSize.compact);
      case _ShelfManagementResult.standard:
        await _resizeShelf(descriptor, MySpaceShelfSize.standard);
      case _ShelfManagementResult.featured:
        await _resizeShelf(descriptor, MySpaceShelfSize.featured);
      case _ShelfManagementResult.remove:
        await _performLayoutMutation(
          (notifier) => notifier.removeShelf(descriptor.id),
          successMessage:
              '${_ShelfCopy.forType(descriptor.type).title} removed.',
        );
    }
  }

  Future<void> _resizeShelf(
    MySpaceShelfDescriptor descriptor,
    MySpaceShelfSize size,
  ) {
    return _performLayoutMutation(
      (notifier) => notifier.resizeShelf(descriptor.id, size),
      successMessage:
          '${_ShelfCopy.forType(descriptor.type).title} is now ${size.rawValue}.',
    );
  }

  Future<bool> _passesClientPremiumGate() async {
    final subscription = ref.read(mySpaceSubscriptionStateProvider);
    if (subscription.isSubscribed) return true;
    // RevenueCat controls only the upgrade UX. Every accepted mutation still
    // goes through the server-authorized repository and may be rejected.
    return requirePremiumGuard(context, ref);
  }

  Future<void> _performLayoutMutation(
    Future<void> Function(MySpaceLayoutNotifier notifier) mutate, {
    required String successMessage,
  }) async {
    try {
      await mutate(ref.read(mySpaceLayoutProvider.notifier));
      if (!mounted) return;
      showGlassSnack(context, message: successMessage);
    } on MySpaceLayoutException catch (error) {
      if (!mounted) return;
      showGlassSnack(context, message: _layoutFailureMessage(error));
    } on FormatException catch (_) {
      if (!mounted) return;
      showGlassSnack(
        context,
        message: 'That shelf configuration is not supported.',
      );
    } catch (_) {
      if (!mounted) return;
      showGlassSnack(
        context,
        message: 'My Space could not save that change. Please try again.',
      );
    }
  }

  MySpaceAsyncAction _emptyAction(MySpaceShelfType type) {
    if (type == MySpaceShelfType.continueShelf ||
        type == MySpaceShelfType.savedStudies ||
        type == MySpaceShelfType.studyDiscovery) {
      return widget.onBrowseStudies ?? _openStudies;
    }
    if (type == MySpaceShelfType.miniatures) {
      return widget.onDiscoverGames ?? _openMiniatures;
    }
    if (type == MySpaceShelfType.myLikes) {
      return widget.onDiscoverGames ?? _openDiscovery;
    }
    if (type == MySpaceShelfType.savedEvents) {
      return widget.onBrowseEvents ?? _openEvents;
    }
    if (type == MySpaceShelfType.databases) {
      return widget.onOpenLibrary ?? _openLibrary;
    }
    if (type == MySpaceShelfType.favoritePlayers) {
      return widget.onFindPlayers ?? _findPlayers;
    }
    return _openDiscovery;
  }

  Future<void> _openItem(MySpaceContentItem item) async {
    final injected = widget.onOpenItem;
    if (injected != null) {
      await Future<void>.sync(() => injected(item));
      return;
    }

    try {
      switch (item) {
        case MySpaceAnalysisItem(:final analysis, :final isLiked):
          if (isLiked) {
            final subscription = ref.read(subscriptionProvider);
            final locked = isLikedGameLocked(
              analysis.createdAt.toLocal(),
              isSubscribed: subscription.isSubscribed,
              subscriptionLoading: subscription.isLoading,
            );
            if (locked) {
              final unlocked = await requirePremiumGuard(context, ref);
              if (!unlocked || !mounted) return;
            }
          }
          if (mounted) await loadSavedAnalysis(context, analysis);
        case MySpaceEventItem(:final event):
          await ref
              .read(tournamentNavigationProvider)
              .openTournament(
                context: context,
                id: event.eventId,
                category: GroupEventCategory.search,
              );
        case MySpaceLibraryItem(:final folder):
          if (!mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => FolderContentsScreen(folder: folder),
            ),
          );
        case MySpacePlayerItem(
          :final player,
          :final fideId,
          :final playerTitle,
          :final federation,
          :final rating,
        ):
          if (!mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder:
                  (_) => PlayerProfileScreen(
                    fideId: fideId,
                    playerName: player.playerName,
                    title: playerTitle,
                    federation: federation,
                    rating: rating,
                  ),
            ),
          );
        case MySpaceStudyItem(:final study):
          final injectedStudy = widget.onOpenStudy;
          if (injectedStudy != null) {
            await Future<void>.sync(() => injectedStudy(study));
          } else if (mounted) {
            await Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder:
                    (_) => StudyDetailScreen(
                      lichessStudyId: study.canonicalStudyId,
                    ),
              ),
            );
          }
        case MySpaceMiniatureItem(:final miniature):
          final injectedMiniature = widget.onOpenMiniature;
          if (injectedMiniature != null) {
            await Future<void>.sync(() => injectedMiniature(miniature));
          } else {
            await openMySpaceMiniature(
              context: context,
              ref: ref,
              miniature: miniature,
            );
          }
        case MySpaceUnavailableItem():
          return;
      }
    } on MySpaceMiniatureOpenException catch (error) {
      if (!mounted) return;
      showGlassSnack(context, message: error.message);
    } catch (_) {
      if (!mounted) return;
      showGlassSnack(
        context,
        message: 'This item is unavailable right now. Please try again.',
      );
    }
  }

  Future<void> _runAction(MySpaceAsyncAction action) async {
    try {
      await Future<void>.sync(action);
    } catch (_) {
      if (!mounted) return;
      showGlassSnack(context, message: 'That action is unavailable right now.');
    }
  }

  Future<void> _openStudies() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const StudiesBrowseScreen()),
    );
  }

  Future<void> _openMiniatures() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const MiniaturesScreen()),
    );
  }

  Future<void> _openDiscovery() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => GamebaseExplorerScreen.scoped()),
    );
  }

  Future<void> _openEvents() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const GroupEventScreen()),
    );
  }

  Future<void> _openLibrary() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const LibraryScreen()),
    );
  }

  Future<void> _findPlayers() =>
      Navigator.of(context).pushNamed<void>('/player_list_screen');
}

class _MySpaceShelfProviderView extends ConsumerWidget {
  const _MySpaceShelfProviderView({
    required this.descriptor,
    required this.onOpenItem,
    required this.onEmptyAction,
    required this.onRetryShelf,
    required this.onManage,
    super.key,
  });

  final MySpaceShelfDescriptor descriptor;
  final ValueChanged<MySpaceContentItem> onOpenItem;
  final VoidCallback onEmptyAction;
  final MySpaceShelfAction? onRetryShelf;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _ShelfCopy.forType(descriptor.type);
    final state = _watchShelf(ref, descriptor.type);
    return MySpaceShelf(
      descriptor: descriptor,
      title: copy.title,
      emptyDescription: copy.emptyDescription,
      emptyActionLabel: copy.emptyActionLabel,
      state: state,
      onItemPressed: onOpenItem,
      onEmptyAction: onEmptyAction,
      onRetry: () => _retry(ref),
      onManage: onManage,
    );
  }

  void _retry(WidgetRef ref) {
    final callback = onRetryShelf;
    if (callback != null) {
      unawaited(Future<void>.sync(() => callback(descriptor.type)));
      return;
    }
    final type = descriptor.type;
    if (type == MySpaceShelfType.continueShelf) {
      ref.invalidate(mySpaceRecentLibraryAnalysesProvider);
    } else if (type == MySpaceShelfType.myLikes) {
      ref.invalidate(likedGamesProvider);
    } else if (type == MySpaceShelfType.savedEvents) {
      ref.invalidate(favoriteEventsProvider);
    } else if (type == MySpaceShelfType.databases) {
      ref.invalidate(combinedLibraryFoldersProvider);
    } else if (type == MySpaceShelfType.favoritePlayers) {
      ref.invalidate(favoritePlayersProviderNew);
    } else if (type == MySpaceShelfType.studyDiscovery) {
      ref.invalidate(studiesProvider);
    } else if (type == MySpaceShelfType.miniatures) {
      ref.invalidate(miniaturesProvider);
    }
  }
}

MySpaceContentShelfState _watchShelf(WidgetRef ref, MySpaceShelfType type) {
  if (type == MySpaceShelfType.continueShelf) {
    return ref.watch(mySpaceContinueShelfProvider);
  }
  if (type == MySpaceShelfType.myLikes) {
    return ref.watch(mySpaceLikesShelfProvider);
  }
  if (type == MySpaceShelfType.savedEvents) {
    return ref.watch(mySpaceSavedEventsShelfProvider);
  }
  if (type == MySpaceShelfType.databases) {
    return ref.watch(mySpaceDatabasesShelfProvider);
  }
  if (type == MySpaceShelfType.savedStudies) {
    return ref.watch(mySpaceSavedStudiesShelfProvider);
  }
  if (type == MySpaceShelfType.favoritePlayers) {
    return ref.watch(mySpaceFavoritePlayersShelfProvider);
  }
  if (type == MySpaceShelfType.studyDiscovery) {
    return ref.watch(mySpaceStudyDiscoveryShelfProvider);
  }
  if (type == MySpaceShelfType.miniatures) {
    return ref.watch(mySpaceMiniaturesShelfProvider);
  }
  return const MySpaceShelfState<List<MySpaceContentItem>>.removed();
}

class _ShelfCopy {
  const _ShelfCopy({
    required this.title,
    required this.emptyDescription,
    required this.emptyActionLabel,
  });

  final String title;
  final String emptyDescription;
  final String emptyActionLabel;

  static _ShelfCopy forType(MySpaceShelfType type) {
    if (type == MySpaceShelfType.continueShelf) {
      return const _ShelfCopy(
        title: 'Continue',
        emptyDescription:
            'Recently opened Library analyses will appear here when there is something to resume.',
        emptyActionLabel: 'Browse Studies',
      );
    }
    if (type == MySpaceShelfType.myLikes) {
      return const _ShelfCopy(
        title: 'My Likes',
        emptyDescription: 'Like a game to keep its saved analysis close by.',
        emptyActionLabel: 'Discover games',
      );
    }
    if (type == MySpaceShelfType.savedEvents) {
      return const _ShelfCopy(
        title: 'Saved Events',
        emptyDescription: 'Favorite an event to follow it from this shelf.',
        emptyActionLabel: 'Browse events',
      );
    }
    if (type == MySpaceShelfType.databases) {
      return const _ShelfCopy(
        title: 'Databases',
        emptyDescription:
            'Your recent Library databases and folders will appear here.',
        emptyActionLabel: 'Open Library',
      );
    }
    if (type == MySpaceShelfType.savedStudies) {
      return const _ShelfCopy(
        title: 'Saved Studies',
        emptyDescription:
            'Study bookmarks are not connected yet, so this shelf does not invent content.',
        emptyActionLabel: 'Browse Studies',
      );
    }
    if (type == MySpaceShelfType.favoritePlayers) {
      return const _ShelfCopy(
        title: 'Favorite Players',
        emptyDescription: 'Follow players to keep their profiles one tap away.',
        emptyActionLabel: 'Find players',
      );
    }
    if (type == MySpaceShelfType.studyDiscovery) {
      return const _ShelfCopy(
        title: 'Study Discovery',
        emptyDescription:
            'Quality-ranked public Lichess Studies will appear here when available.',
        emptyActionLabel: 'Browse Studies',
      );
    }
    if (type == MySpaceShelfType.miniatures) {
      return const _ShelfCopy(
        title: 'Miniatures',
        emptyDescription:
            'Short decisive games will appear here when Gamebase has a complete source.',
        emptyActionLabel: 'Browse Miniatures',
      );
    }
    return const _ShelfCopy(
      title: 'Unavailable shelf',
      emptyDescription: 'This shelf type is not supported by this app version.',
      emptyActionLabel: 'Explore',
    );
  }
}

class _AddShelfControl extends StatelessWidget {
  const _AddShelfControl({required this.onPressed, required this.isSaving});

  final VoidCallback? onPressed;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Add shelf',
      button: true,
      enabled: onPressed != null,
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Add shelf',
          child: GlassIconButton(
            key: const ValueKey<String>('my-space-add-shelf-button'),
            icon:
                isSaving
                    ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.brandMuted,
                      ),
                    )
                    : Icon(
                      Icons.add_rounded,
                      color: context.colors.iconPrimary,
                    ),
            onPressed: onPressed,
            size: 48,
            iconSize: 22,
            useOwnLayer: true,
          ),
        ),
      ),
    );
  }
}

class _EditLayoutControl extends StatelessWidget {
  const _EditLayoutControl({
    required this.isEditing,
    required this.isSaving,
    required this.onPressed,
  });

  final bool isEditing;
  final bool isSaving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = isEditing ? 'Finish editing shelves' : 'Customize shelves';
    return Semantics(
      container: true,
      label: label,
      button: true,
      enabled: onPressed != null,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: GlassIconButton(
            key: const ValueKey<String>('my-space-edit-layout-button'),
            icon:
                isSaving
                    ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.brandMuted,
                      ),
                    )
                    : Icon(
                      isEditing ? Icons.check_rounded : Icons.tune_rounded,
                      color: context.colors.iconPrimary,
                    ),
            onPressed: onPressed,
            size: 48,
            iconSize: 22,
            useOwnLayer: true,
          ),
        ),
      ),
    );
  }
}

class _AccountControl extends StatelessWidget {
  const _AccountControl({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Open account',
      button: true,
      child: ExcludeSemantics(
        child: GlassIconButton(
          key: const ValueKey<String>('my-space-account-button'),
          icon: Icon(
            Icons.person_outline_rounded,
            color: context.colors.iconPrimary,
          ),
          onPressed: onTap,
          size: 48,
          iconSize: 22,
          useOwnLayer: true,
        ),
      ),
    );
  }
}

class _AddShelfContainer extends StatelessWidget {
  const _AddShelfContainer({
    required this.persistenceAvailable,
    required this.onPressed,
  });

  final bool persistenceAvailable;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final description =
        persistenceAvailable
            ? 'Open the catalog to add or restore a shelf.'
            : 'Preview the catalog. Saved customization is not enabled in this release.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Semantics(
        button: onPressed != null,
        enabled: onPressed != null,
        label: 'Add a shelf. $description',
        child: Material(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: const ValueKey<String>('my-space-add-shelf-container'),
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              constraints: const BoxConstraints(minHeight: 96),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.colors.divider),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceRecessed,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      color: context.colors.brandMuted,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Shelf',
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: context.colors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.colors.iconSecondary,
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

class _LayoutStatusBanner extends StatelessWidget {
  const _LayoutStatusBanner.loading()
    : failure = null,
      onRetry = null,
      isLoading = true;

  const _LayoutStatusBanner.failure({
    required this.failure,
    required this.onRetry,
  }) : isLoading = false;

  final Object? failure;
  final VoidCallback? onRetry;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final message =
        isLoading
            ? 'Loading your saved shelf layout…'
            : _layoutFailureMessage(failure!);
    return Semantics(
      liveRegion: true,
      label: message,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Material(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (isLoading)
                  SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.brandMuted,
                    ),
                  )
                else
                  Icon(
                    Icons.info_outline_rounded,
                    color: context.colors.brandMuted,
                    size: 22,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.colors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
                if (onRetry case final retry?)
                  TextButton(
                    onPressed: retry,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: context.colors.brandMuted,
                    ),
                    child: const Text('Reload'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

sealed class _CatalogResult {
  const _CatalogResult();
}

final class _AddCatalogShelf extends _CatalogResult {
  const _AddCatalogShelf(this.type);

  final MySpaceSupportedShelfType type;
}

final class _ResetCatalogLayout extends _CatalogResult {
  const _ResetCatalogLayout();
}

class _CatalogEntry {
  const _CatalogEntry({
    required this.type,
    required this.icon,
    required this.title,
    required this.description,
  });

  final MySpaceSupportedShelfType type;
  final IconData icon;
  final String title;
  final String description;
}

const _catalogEntries = <_CatalogEntry>[
  _CatalogEntry(
    type: MySpaceShelfType.continueShelf,
    icon: Icons.play_arrow_rounded,
    title: 'Continue',
    description: 'Resume recently opened Library analyses.',
  ),
  _CatalogEntry(
    type: MySpaceShelfType.miniatures,
    icon: Icons.bolt_rounded,
    title: 'Miniatures',
    description: 'Open short decisive games from complete Gamebase sources.',
  ),
  _CatalogEntry(
    type: MySpaceShelfType.studyDiscovery,
    icon: Icons.auto_stories_outlined,
    title: 'Study Discovery',
    description: 'Explore quality-ranked public Lichess Studies.',
  ),
  _CatalogEntry(
    type: MySpaceShelfType.myLikes,
    icon: Icons.favorite_outline_rounded,
    title: 'My Likes',
    description: 'Return to games you liked and saved.',
  ),
  _CatalogEntry(
    type: MySpaceShelfType.savedEvents,
    icon: Icons.emoji_events_outlined,
    title: 'Saved Events',
    description: 'Keep followed tournaments one tap away.',
  ),
  _CatalogEntry(
    type: MySpaceShelfType.databases,
    icon: Icons.storage_rounded,
    title: 'Databases',
    description: 'Open recent Library databases and folders.',
  ),
  _CatalogEntry(
    type: MySpaceShelfType.savedStudies,
    icon: Icons.bookmark_outline_rounded,
    title: 'Saved Studies',
    description: 'Ready for bookmarks once a canonical source is connected.',
  ),
  _CatalogEntry(
    type: MySpaceShelfType.favoritePlayers,
    icon: Icons.people_outline_rounded,
    title: 'Favorite Players',
    description: 'Jump directly to followed player profiles.',
  ),
];

class _AddShelfCatalog extends StatelessWidget {
  const _AddShelfCatalog({
    required this.layout,
    required this.persistenceAvailable,
    required this.onClose,
    required this.onAdd,
    required this.onReset,
  });

  final MySpaceLayout layout;
  final bool persistenceAvailable;
  final VoidCallback onClose;
  final ValueChanged<MySpaceSupportedShelfType> onAdd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final existingTypes = layout.shelves.map((shelf) => shelf.type).toSet();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Build your own My Space',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              persistenceAvailable
                  ? 'Premium customization can add, reorder, resize, and remove shelves. The server still verifies every save.'
                  : 'Explore the shelf catalog now. Saved customization is staged for a later rollout in this build.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            for (final entry in _catalogEntries)
              _CatalogShelfTile(
                key: ValueKey<String>('my-space-catalog-${entry.type.rawType}'),
                entry: entry,
                isAdded: existingTypes.contains(entry.type),
                persistenceAvailable: persistenceAvailable,
                onAdd: () => onAdd(entry.type),
              ),
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                persistenceAvailable
                    ? 'RevenueCat is an upgrade prompt only. Server entitlement and revision checks are authoritative.'
                    : 'Preview only — this cannot change your layout and makes no layout-network request.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (persistenceAvailable) ...[
              OutlinedButton.icon(
                key: const ValueKey<String>('my-space-reset-layout-button'),
                onPressed: onReset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: context.colors.divider),
                ),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset curated layout'),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: onClose,
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.brand,
                foregroundColor: context.colors.textInverse,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(persistenceAvailable ? 'Done' : 'Got it'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogShelfTile extends StatelessWidget {
  const _CatalogShelfTile({
    required this.entry,
    required this.isAdded,
    required this.persistenceAvailable,
    required this.onAdd,
    super.key,
  });

  final _CatalogEntry entry;
  final bool isAdded;
  final bool persistenceAvailable;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).scale(16) / 16;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.divider),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final copy = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(
                    dimension: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.colors.surfaceRecessed,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        entry.icon,
                        color: context.colors.brandMuted,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.description,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: context.colors.textSecondary,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final action = _CatalogShelfAction(
                controlKey: ValueKey<String>(
                  'my-space-catalog-add-${entry.type.rawType}',
                ),
                isAdded: isAdded,
                persistenceAvailable: persistenceAvailable,
                onAdd: onAdd,
              );
              if (constraints.maxWidth < 340 || scaler > 1.3) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    copy,
                    const SizedBox(height: 6),
                    Align(alignment: Alignment.centerRight, child: action),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 8),
                  action,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CatalogShelfAction extends StatelessWidget {
  const _CatalogShelfAction({
    required this.controlKey,
    required this.isAdded,
    required this.persistenceAvailable,
    required this.onAdd,
  });

  final Key controlKey;
  final bool isAdded;
  final bool persistenceAvailable;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (isAdded) {
      return Semantics(
        label: 'Already added',
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: context.colors.brandMuted,
                size: 20,
              ),
              const SizedBox(width: 5),
              Text(
                'Added',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!persistenceAvailable) {
      return SizedBox(
        height: 48,
        child: Center(
          child: Text(
            'Rollout coming',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return TextButton.icon(
      key: controlKey,
      onPressed: onAdd,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: context.colors.brandMuted,
      ),
      icon: const Icon(Icons.add_rounded, size: 20),
      label: const Text('Add'),
    );
  }
}

enum _ShelfManagementResult {
  moveUp,
  moveDown,
  compact,
  standard,
  featured,
  remove,
}

class _ShelfManagementSheet extends StatelessWidget {
  const _ShelfManagementSheet({
    required this.descriptor,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onSelect,
    required this.onClose,
  });

  final MySpaceShelfDescriptor descriptor;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<_ShelfManagementResult> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final copy = _ShelfCopy.forType(descriptor.type);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Manage ${copy.title}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Changes save through the server-authorized premium layout service.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            _ManagementActionTile(
              icon: Icons.arrow_upward_rounded,
              label: 'Move shelf up',
              enabled: canMoveUp,
              onPressed: () => onSelect(_ShelfManagementResult.moveUp),
            ),
            _ManagementActionTile(
              icon: Icons.arrow_downward_rounded,
              label: 'Move shelf down',
              enabled: canMoveDown,
              onPressed: () => onSelect(_ShelfManagementResult.moveDown),
            ),
            const SizedBox(height: 8),
            Text(
              'Shelf size',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.colors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final size in MySpaceShelfSize.values)
              if (descriptor.type.supportsSize(size))
                _ManagementActionTile(
                  icon:
                      descriptor.size == size
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                  label: '${_sizeLabel(size)} size',
                  enabled: descriptor.size != size,
                  onPressed: () => onSelect(_managementResultForSize(size)),
                ),
            const SizedBox(height: 8),
            _ManagementActionTile(
              key: const ValueKey<String>('my-space-remove-shelf-button'),
              icon: Icons.delete_outline_rounded,
              label: 'Remove shelf',
              isDestructive: true,
              onPressed: () => onSelect(_ShelfManagementResult.remove),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onClose,
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.brand,
                foregroundColor: context.colors.textInverse,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagementActionTile extends StatelessWidget {
  const _ManagementActionTile({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.isDestructive = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color =
        !enabled
            ? context.colors.textTertiary
            : isDestructive
            ? context.colors.danger
            : context.colors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.colors.divider),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 21),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
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

_ShelfManagementResult _managementResultForSize(MySpaceShelfSize size) {
  return switch (size) {
    MySpaceShelfSize.compact => _ShelfManagementResult.compact,
    MySpaceShelfSize.standard => _ShelfManagementResult.standard,
    MySpaceShelfSize.featured => _ShelfManagementResult.featured,
  };
}

String _sizeLabel(MySpaceShelfSize size) => switch (size) {
  MySpaceShelfSize.compact => 'Compact',
  MySpaceShelfSize.standard => 'Standard',
  MySpaceShelfSize.featured => 'Featured',
};

String _layoutFailureMessage(Object failure) {
  if (failure is! MySpaceLayoutException) {
    return 'Your saved layout is unavailable. The curated shelves remain usable.';
  }
  return switch (failure.kind) {
    MySpaceLayoutFailureKind.unauthenticated =>
      'Sign in to save a custom My Space layout. The curated shelves remain usable.',
    MySpaceLayoutFailureKind.premiumRequired =>
      'The server did not confirm Premium. Your previous layout was kept.',
    MySpaceLayoutFailureKind.revisionConflict =>
      'My Space changed on another device. The latest server layout was reloaded.',
    MySpaceLayoutFailureKind.invalidDocument =>
      'That layout is not valid in this app version. Your previous layout was kept.',
    MySpaceLayoutFailureKind.unavailable =>
      'The layout service is unavailable. Your current shelves remain usable.',
  };
}

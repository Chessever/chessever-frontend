import 'dart:async';

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
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/my_space/domain/my_space_layout.dart';
import 'package:chessever2/screens/my_space/domain/my_space_shelf_state.dart';
import 'package:chessever2/screens/my_space/providers/my_space_content_providers.dart';
import 'package:chessever2/screens/my_space/widgets/my_space_shelf.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/liquid_glass/glass_kit.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef MySpaceAsyncAction = FutureOr<void> Function();
typedef MySpaceItemAction = FutureOr<void> Function(MySpaceContentItem item);
typedef MySpaceShelfAction = FutureOr<void> Function(MySpaceShelfType type);

/// Curated free/default My Space. Layout persistence is intentionally absent
/// until a server-authorized capability is supplied by the owning layer.
class MySpaceScreen extends ConsumerStatefulWidget {
  const MySpaceScreen({
    super.key,
    this.onAccountTap,
    this.onAuthorizedAddShelf,
    this.onBrowseStudies,
    this.onDiscoverGames,
    this.onBrowseEvents,
    this.onOpenLibrary,
    this.onFindPlayers,
    this.onOpenItem,
    this.onRetryShelf,
  });

  final MySpaceAsyncAction? onAccountTap;

  /// This callback is the capability boundary for customization. It should be
  /// supplied only by an owner that performs authoritative server-side
  /// entitlement checks and persistence. Client premium state is not enough.
  final MySpaceAsyncAction? onAuthorizedAddShelf;

  final MySpaceAsyncAction? onBrowseStudies;
  final MySpaceAsyncAction? onDiscoverGames;
  final MySpaceAsyncAction? onBrowseEvents;
  final MySpaceAsyncAction? onOpenLibrary;
  final MySpaceAsyncAction? onFindPlayers;
  final MySpaceItemAction? onOpenItem;
  final MySpaceShelfAction? onRetryShelf;

  @override
  ConsumerState<MySpaceScreen> createState() => _MySpaceScreenState();
}

class _MySpaceScreenState extends ConsumerState<MySpaceScreen> {
  @override
  Widget build(BuildContext context) {
    final descriptors = MySpaceLayout.curatedDefault.shelves
        .where((descriptor) => descriptor.visible)
        .toList(growable: false);
    final parentScaffold = Scaffold.maybeOf(context);

    return GlassFullScreenPage(
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
          _AddShelfControl(onPressed: () => unawaited(_handleAddShelf())),
        ],
      ),
      content: ListView(
        key: const PageStorageKey<String>('my-space-vertical-feed'),
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        physics: const BouncingScrollPhysics(),
        children: [
          for (final descriptor in descriptors)
            _MySpaceShelfProviderView(
              key: ValueKey<String>('my-space-shelf-${descriptor.id}'),
              descriptor: descriptor,
              onOpenItem: (item) => unawaited(_openItem(item)),
              onEmptyAction:
                  () => unawaited(_runAction(_emptyAction(descriptor.type))),
              onRetryShelf: widget.onRetryShelf,
            ),
        ],
      ),
    );
  }

  Future<void> _handleAddShelf() async {
    final authorizedCapability = widget.onAuthorizedAddShelf;
    if (authorizedCapability != null) {
      await _runAction(authorizedCapability);
      return;
    }

    if (!mounted) return;
    await showAppGlassSheet<void>(
      context: context,
      builder: (sheetContext) {
        return _AddShelfCatalogPreview(
          onClose: () => Navigator.of(sheetContext).pop(),
          onExplorePremium: () async {
            Navigator.of(sheetContext).pop();
            if (!mounted) return;
            // The established guard is only an upgrade entry point here. A
            // successful client result never becomes permission to save.
            await requirePremiumGuard(context, ref);
          },
        );
      },
    );
  }

  MySpaceAsyncAction _emptyAction(MySpaceShelfType type) {
    if (type == MySpaceShelfType.continueShelf ||
        type == MySpaceShelfType.savedStudies) {
      return widget.onBrowseStudies ?? _explainStudiesUnavailable;
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
        case MySpaceUnavailableItem():
          return;
      }
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

  void _explainStudiesUnavailable() {
    showGlassSnack(
      context,
      message:
          'Study bookmarks are not connected yet. No placeholder Studies were added.',
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
    super.key,
  });

  final MySpaceShelfDescriptor descriptor;
  final ValueChanged<MySpaceContentItem> onOpenItem;
  final VoidCallback onEmptyAction;
  final MySpaceShelfAction? onRetryShelf;

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
    return const _ShelfCopy(
      title: 'Unavailable shelf',
      emptyDescription: 'This shelf type is not supported by this app version.',
      emptyActionLabel: 'Explore',
    );
  }
}

class _AddShelfControl extends StatelessWidget {
  const _AddShelfControl({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Add shelf',
      button: true,
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Add shelf',
          child: GlassIconButton(
            key: const ValueKey<String>('my-space-add-shelf-button'),
            icon: Icon(Icons.add_rounded, color: context.colors.iconPrimary),
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

class _AddShelfCatalogPreview extends StatelessWidget {
  const _AddShelfCatalogPreview({
    required this.onClose,
    required this.onExplorePremium,
  });

  final VoidCallback onClose;
  final VoidCallback onExplorePremium;

  @override
  Widget build(BuildContext context) {
    const catalog = <(IconData, String)>[
      (Icons.play_arrow_rounded, 'Continue'),
      (Icons.favorite_outline_rounded, 'My Likes'),
      (Icons.emoji_events_outlined, 'Saved Events'),
      (Icons.storage_rounded, 'Databases and folders'),
      (Icons.menu_book_outlined, 'Saved Studies'),
      (Icons.people_outline_rounded, 'Favorite Players'),
    ];

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
              'Premium customization can add, reorder, and resize personal shelves.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            for (final entry in catalog)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.colors.divider),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        entry.$1,
                        color: context.colors.brandMuted,
                        size: 21,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.$2,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                'Preview only — this cannot change your layout. A server-authorized save capability is not connected.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onExplorePremium,
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.brand,
                foregroundColor: context.colors.textInverse,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Explore Premium'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.textPrimary,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/for_you/open_for_you_event.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart'
    show twicDatabaseTotalGamesProvider;
import 'package:chessever2/screens/library/providers/library_auth_provider.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart'
    show recentDatabasesProvider;
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_space/library/space_library_bridge.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_prep_screen.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_hub_providers.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sheet.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show eventSpaceDraft;
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/hub_tile_art.dart';
import 'package:chessever2/widgets/hub_tile_captions.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What My Database says while it holds nothing: one line (the suggested
/// events under it speak for themselves). "tap +" is held together (a
/// no-break space), so the "+" never stands alone on a line of its own.
const String kMyDatabaseEmptyText =
    'Hold any card and choose Add to My Space, or tap +.';

/// How many live events a new user is offered to save.
const int kMySpaceSuggestions = 3;

/// Opens My Prep: the user's databases and saved openings, in the event
/// view's frame.
Future<void> openMyPrep(BuildContext context) {
  HapticFeedbackService.cardTap();
  return MyPrepScreen.open(context);
}

/// The My Space tab, laid out like Today: the My Likes and My Prep tiles on
/// top (Today's Favorites and Countrymen pair), then My Database: what the
/// user saved, grouped by type under quiet sub-headers, each group drawn
/// with the app's own cards (and live games where there are any), and the
/// tile that builds a Smart Event at the foot.
///
/// Works signed out too: the shortcuts provider keeps a device-local list
/// for guests.
class MySpaceView extends ConsumerWidget {
  const MySpaceView({super.key, this.scrollController});

  final ScrollController? scrollController;

  Future<void> _refresh(WidgetRef ref) async {
    HapticFeedbackService.medium();
    ref.invalidate(spaceEventBroadcastsProvider);
    ref.invalidate(spaceLiveEventGamesProvider);
    ref.invalidate(spacePlayersLiveGamesProvider);
    ref.read(spaceLiveFirstLatchProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    spaceTakeLiveFirstLatch(ref);
    final groups = ref.watch(spaceDatabaseGroupsProvider);
    // Whether the user has saved anything the groups show. The Players
    // group stands without a pin (the followed players are in it by
    // default), so a new user who followed players while onboarding still
    // has nothing saved: they keep the explainer and the events offered
    // to save, above the faces.
    final pinned = ref.watch(
      spaceShortcutsProvider.select(
        (s) => s.valueOrNull?.any(spaceShowsInDatabase) ?? false,
      ),
    );
    final tablet = ResponsiveHelper.isTablet;
    final gutter = hubGutter;

    // The body: the explainer and the suggested events while nothing is
    // saved, then the groups (each one sideways rail, on a tablet too, where
    // a rail simply shows more), or a skeleton while the saved list loads.
    final body = <({String key, Widget child})>[];
    if (groups == null) {
      body.add((key: 'space_skeleton', child: const _DatabaseSkeleton()));
    } else {
      if (!pinned) {
        body.add((key: 'space_empty_text', child: const _DatabaseEmpty()));
        body.add((key: 'space_suggestions', child: const _Suggestions()));
      }
      for (final g in groups) {
        body.add((
          key: 'space_group_${g.section.name}',
          child: SpaceDatabaseGroupView(group: g, gutter: gutter),
        ));
      }
    }
    final lead = 1;
    final count = lead + body.length + 1;

    Widget padded(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: child,
    );

    final list = ListView.builder(
      key: const PageStorageKey<String>('my_space_list'),
      controller: scrollController,
      scrollCacheExtent: kListScrollCacheExtent,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      // The foot clears the floating add button (home's FAB slot), so the
      // Build a Smart Event tile can scroll fully above it.
      padding: EdgeInsets.only(top: 16.sp, bottom: 24.sp + 72),
      itemCount: count,
      // Groups keep their state as saved things come and go around them.
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final at = body.indexWhere((b) => b.key == key.value);
        return at < 0 ? null : lead + at;
      },
      itemBuilder: (context, index) {
        if (index == 0) {
          return KeyedSubtree(
            key: const ValueKey<String>('my_space_tiles'),
            child: padded(const _MySpaceTiles()),
          );
        }
        if (index == count - 1) {
          return Padding(
            key: const ValueKey<String>('my_space_build'),
            padding: EdgeInsets.fromLTRB(gutter, 24.sp, gutter, 0),
            child: const _BuildSmartEventTile(),
          );
        }
        final at = index - lead;
        final item = body[at];
        return Padding(
          key: ValueKey<String>(item.key),
          // A group opens on its 44 sub-header, whose own air above the
          // words finishes the gap to what stands before it. The explainer
          // and the suggestions set their own.
          padding: EdgeInsets.only(
            top: at == 0 || !item.key.startsWith('space_group_') ? 0 : 12.sp,
          ),
          child: item.child,
        );
      },
    );

    final framed = tablet
        ? Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.contentMaxWidth,
              ),
              child: list,
            ),
          )
        : list;
    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: framed,
    );
  }
}

// ------------------------------------------------------------------ tiles

class _MySpaceTiles extends ConsumerWidget {
  const _MySpaceTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likes = ref.watch(likedGamesProvider.select(likesSummary));
    return HubTileRow(
      left: HubTile(
        key: const ValueKey('my_space_likes_tile'),
        title: 'My Likes',
        caption: hubLikesCaption(likes),
        // The pixel heart, large, filling the tile's right side.
        artwork: const HubPixelBackdrop(section: SpaceSection.likes),
        onTap: () {
          HapticFeedbackService.cardTap();
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MyLikesScreen()),
          );
        },
      ),
      right: const _MyPrepTile(),
    );
  }
}

/// My Prep: how many databases the user keeps (or the master database's
/// size); held, the three most recent databases one tap away.
class _MyPrepTile extends ConsumerWidget {
  const _MyPrepTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guest = ref.watch(libraryFolderAuthenticatedUserIdProvider) == null;
    final library = ref.watch(spaceLibraryFoldersProvider);
    final databases = library.folders
        .where((f) => !spaceIsProtectedFolder(f) && f.isDatabase)
        .length;
    final wantsMaster = guest || (library.settled && databases == 0);
    final master = wantsMaster
        ? ref.watch(twicDatabaseTotalGamesProvider)
        : null;
    final caption = hubPrepCaption(
      guest: guest,
      settled: library.settled,
      databases: databases,
      masterTotal: master,
    );
    // The Library's own pixel object, animated like the other hub tiles.
    const art = HubPixelBackdrop(section: SpaceSection.library);

    return Builder(
      builder: (anchor) => HubTile(
        key: const ValueKey('my_space_prep_tile'),
        title: 'My Prep',
        caption: caption,
        artwork: art,
        onTap: () => openMyPrep(context),
        onLongPressStart: (_) {
          HapticFeedbackService.buttonPress();
          CardContextMenu.open(
            anchor,
            onPreviewTap: () => openMyPrep(context),
            previewBuilder: (_) =>
                HubTileFace(title: 'My Prep', caption: caption, artwork: art),
            actions: (menuContext) => [
              if (!guest)
                for (final folder in ref.read(recentDatabasesProvider))
                  LibraryMenuAction(
                    icon: Icons.storage_rounded,
                    label: folder.name,
                    onSelected: () => spaceOpenLibraryFolder(context, folder),
                  ),
              LibraryMenuAction(
                icon: Icons.add_rounded,
                label: 'New database or PGN',
                onSelected: () async {
                  if (!await requireFullAuthGuard(context)) return;
                  if (!context.mounted) return;
                  await spaceLibraryAdd(context, ref);
                },
              ),
              LibraryMenuAction(
                icon: Icons.open_in_new_rounded,
                label: 'Open My Prep',
                onSelected: () => openMyPrep(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ empty

class _DatabaseEmpty extends StatelessWidget {
  const _DatabaseEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hubGutter, 4.sp, hubGutter, 16.sp),
      child: Text(
        kMyDatabaseEmptyText,
        style: AppTypography.textSmRegular.copyWith(
          color: context.colors.textSecondary,
          height: 20 / 14,
        ),
      ),
    );
  }
}

/// A new user's first saves: live and upcoming events from the For You
/// feed (followed ones first), each savable in one tap. Nothing is saved
/// until the user taps.
class _Suggestions extends ConsumerWidget {
  const _Suggestions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(forYouEventsProvider.select((s) => s.events));
    final loading = ref.watch(
      forYouEventsProvider.select((s) => s.isLoading && s.events.isEmpty),
    );
    final favoriteIds = <String>{
      for (final f in ref.watch(favoriteEventsProvider).valueOrNull ?? const [])
        f.eventId,
    };
    final hidden = ref.watch(spaceHiddenAutoKeysProvider);
    final saved = {
      for (final s
          in ref.watch(spaceShortcutsProvider).valueOrNull ??
              const <SpaceShortcut>[])
        s.key,
    };
    final picks = [
      for (final e in spaceCurrentEvents(events, favoriteIds))
        if (!hidden.contains(eventSpaceDraft(e).key) &&
            !saved.contains(eventSpaceDraft(e).key))
          e,
    ].take(kMySpaceSuggestions).toList();

    final gutter = hubGutter;
    final tablet = ResponsiveHelper.isTablet;
    final List<Widget> cards = loading
        ? [for (var i = 0; i < kMySpaceSuggestions; i++) const _EventPlate()]
        : [
            for (final e in picks)
              EventCard(
                key: ValueKey<String>('space_suggest_${e.id}'),
                tourEventCardModel: e,
                forceCompactLayout: true,
                heroTagSuffix: '_myspace_suggest',
                trailingWidget: SpaceSaveToggle(draft: eventSpaceDraft(e)),
                onTap: () => openForYouEvent(
                  context,
                  ref,
                  eventId: e.id,
                  source: ForYouEventSource.mySpace,
                ),
              ),
          ];
    if (cards.isEmpty) return const SizedBox.shrink();
    if (tablet) {
      final rows = <Widget>[];
      for (var i = 0; i < cards.length; i += 2) {
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[i]),
              SizedBox(width: 16.sp),
              Expanded(
                child: i + 1 < cards.length
                    ? cards[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      }
      cards
        ..clear()
        ..addAll(rows);
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(height: 12.sp),
            cards[i],
          ],
        ],
      ),
    );
  }
}

/// The compact event card's footprint, for a card still loading: its 6
/// padding around a 108 x 86.4 image.
class _EventPlate extends StatelessWidget {
  const _EventPlate();

  @override
  Widget build(BuildContext context) {
    return SkeletonWidget(
      ignoreContainers: true,
      child: Container(
        height: 108.w * 4 / 5 + 12.sp,
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(8.br),
        ),
      ),
    );
  }
}

class _DatabaseSkeleton extends StatelessWidget {
  const _DatabaseSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hubGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 44.w),
          const _EventPlate(),
          SizedBox(height: 12.sp),
          const _EventPlate(),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ build

/// What the Build smart event tile says under its title: the builder's own
/// prompt, in its words.
const String kBuildSmartEventCaption = 'Openings you care about';

/// "+ Build smart event": the builder opens in place, and what it builds is
/// saved into My Database, in the Smart Events group right above it. Its
/// mark is the smart events' own monochrome stacked boards (the glyph a
/// smart event's plate shows before anything is picked), in the builder's
/// ink: no hue, as every smart-event surface.
class _BuildSmartEventTile extends ConsumerWidget {
  const _BuildSmartEventTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HubTile(
      key: const ValueKey('my_space_build_smart_event'),
      title: 'Build smart event',
      titleIcon: Icons.add_rounded,
      caption: kBuildSmartEventCaption,
      artwork: const HubPixelBackdrop(section: SpaceSection.smartEvents),
      onTap: () {
        HapticFeedbackService.buttonPress();
        showSpaceAddSheet(context, ref, SpaceSection.smartEvents);
      },
    );
  }
}

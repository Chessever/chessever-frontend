import 'dart:async';

import 'package:chessever2/screens/my_space/actions/space_remove_confirmation.dart';
// import 'package:chessever2/providers/favorite_events_provider.dart';
// import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
// import 'package:chessever2/screens/for_you/open_for_you_event.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction;
import 'package:chessever2/screens/my_space/actions/space_edit_actions.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/collections/collection_plate_row.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_prep_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/widgets/hub_context_art.dart';
// import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_edit_mode_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_hub_providers.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_grid.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_tutorial.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
// import 'package:chessever2/widgets/event_card/event_card.dart';
// import 'package:chessever2/widgets/event_card/event_context_menu.dart'
//     show eventSpaceDraft;
import 'package:chessever2/widgets/hub_tile.dart';
// import 'package:chessever2/widgets/hub_tile_art.dart';
import 'package:chessever2/widgets/hub_tile_captions.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Guidance for the two supported My Space products.
const String kMyDatabaseEmptyText =
    'Add a database or build a smart event using +.';

/// How many live events a new user is offered to save.
const int kMySpaceSuggestions = 3;

/// Opens the My Prep placeholder in its existing route.
Future<void> openMyPrep(BuildContext context) {
  HapticFeedbackService.cardTap();
  return MyPrepScreen.open(context);
}

/// The My Space tab, with Smart Events and Library tiles, a permanent
/// My Likes archive card, and saved compact cards without category headers.
///
/// Works signed out too: the shortcuts provider keeps a device-local list
/// for guests.
class MySpaceView extends ConsumerStatefulWidget {
  const MySpaceView({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<MySpaceView> createState() => _MySpaceViewState();
}

class _MySpaceViewState extends ConsumerState<MySpaceView> {
  final _pageScroll = SpaceStartController();
  final _editScroll = SpaceStartController();
  final Set<String> _selected = {};
  bool _closing = false;

  @override
  void dispose() {
    _pageScroll.dispose();
    _editScroll.dispose();
    super.dispose();
  }

  void _setEditing(bool value) {
    HapticFeedbackService.buttonPress();
    ref.read(spaceEditModeProvider.notifier).state = value;
  }

  void _toggle(String key) {
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
    });
  }

  Future<void> _removeSelected(Set<String> all) async {
    final keys = _selected.intersection(all);
    if (keys.isEmpty) return;
    final pins =
        ref.read(spaceShortcutsProvider).valueOrNull ?? const <SpaceShortcut>[];
    final smartEvents = pins
        .where(
          (s) => keys.contains(s.key) && s.kind == SpaceShortcutKind.smartEvent,
        )
        .toList();
    if (smartEvents.isNotEmpty &&
        !await confirmSpaceSmartEventRemoval(context, smartEvents)) {
      return;
    }
    if (!mounted) return;
    setState(_selected.clear);
    final removed = spaceRemovePinsSelected(
      context: context,
      ref: ref,
      keys: keys,
    );
    if (keys.containsAll(all)) {
      _setEditing(false);
      setState(() => _closing = false);
    }
    await removed;
  }

  Future<void> _refresh() async {
    HapticFeedbackService.medium();
    ref.invalidate(spaceEventBroadcastsProvider);
    ref.invalidate(spaceLiveEventGamesProvider);
    ref.invalidate(spacePlayersLiveGamesProvider);
    ref.read(spaceLiveFirstLatchProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(spaceEditModeProvider, (previous, next) {
      if (previous == next) return;
      setState(() {
        _selected.clear();
        _closing = !next;
        if (next) {
          _pageScroll.start = _pageScroll.at ?? _pageScroll.start;
          _editScroll.start = 0;
        }
      });
      if (next &&
          (ref.read(spaceCompactDatabaseGroupsProvider)?.isNotEmpty ?? false)) {
        // Teach selection and reordering for the visible products.
        maybeShowSpaceEditTutorial(context, ref, SpaceSection.library);
      }
    });
    final editing = ref.watch(spaceEditModeProvider);
    final groups = ref.watch(spaceCompactDatabaseGroupsProvider);
    final pins = [
      for (final group in groups ?? <SpaceDatabaseGroup>[]) ...group.items,
    ];
    final keys = {for (final pin in pins) pin.key};
    _selected.retainAll(keys);
    // Automatic follows and legacy pins do not replace the empty state.
    final pinned = ref.watch(
      spaceShortcutsProvider.select(
        (s) => s.valueOrNull?.any((pin) => pin.canAddToMySpace) ?? false,
      ),
    );
    final tablet = ResponsiveHelper.isTablet;
    final gutter = hubGutter;

    Widget frame(Widget child) => tablet
        ? Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.contentMaxWidth,
              ),
              child: child,
            ),
          )
        : child;

    if (editing || _closing) {
      return PopScope(
        canPop: !editing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && editing) _setEditing(false);
        },
        child: frame(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, 8.sp, gutter, 4.sp),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'My Space',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textLgMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    DiscoveryAction(
                      key: const ValueKey<String>('space_edit_remove'),
                      label: _selected.isEmpty
                          ? 'Remove'
                          : 'Remove ${_selected.length}',
                      semanticsLabel: _selected.isEmpty
                          ? 'Remove, select something first'
                          : 'Remove ${_selected.length} from My Space',
                      onTap: !editing || _selected.isEmpty
                          ? null
                          : () => unawaited(_removeSelected(keys)),
                    ),
                    SizedBox(width: 16.w),
                    DiscoveryAction(
                      key: const ValueKey<String>('space_edit_done'),
                      label: 'Done',
                      semanticsLabel: 'Done editing',
                      onTap: editing ? () => _setEditing(false) : null,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: editing && pins.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(gutter),
                          child: Text(
                            groups == null
                                ? 'Loading My Space…'
                                : 'Nothing to edit yet.',
                            style: AppTypography.textSmMedium.copyWith(
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ),
                      )
                    : SpaceHomeEdit(
                        pins: pins,
                        selected: _selected,
                        onToggle: _toggle,
                        onReorder: (key, order) => unawaited(
                          ref
                              .read(spaceShortcutsProvider.notifier)
                              .moveWithinVisible(key, order),
                        ),
                        controller: widget.scrollController ?? _editScroll,
                        closing: _closing,
                        onClosed: () {
                          if (mounted) setState(() => _closing = false);
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    }

    // Only supported pins participate in the empty state and editable list.
    final body = <({String key, Widget child})>[];
    if (groups == null) {
      body.add((key: 'space_skeleton', child: const _DatabaseSkeleton()));
    } else {
      if (!pinned) {
        body.add((key: 'space_empty_text', child: const _DatabaseEmpty()));
        // Product scope: event suggestions are retained below for later.
        // body.add((key: 'space_suggestions', child: const _Suggestions()));
      }
      for (final g in groups) {
        body.add((
          key: 'space_group_${g.section.name}_${g.items.first.key}',
          child: SpaceDatabaseGroupView(
            group: g,
            gutter: gutter,
            compact: true,
          ),
        ));
      }
    }
    final lead = 2;
    final count = lead + body.length;

    Widget padded(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: child,
    );

    final list = ListView.builder(
      key: const PageStorageKey<String>('my_space_list'),
      controller: widget.scrollController ?? _pageScroll,
      scrollCacheExtent: kListScrollCacheExtent,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      // Keep the last row above My Space's restored add button.
      padding: EdgeInsets.only(top: 16.sp, bottom: 24.sp + 72),
      itemCount: count,
      // Groups keep their state as saved things come and go around them.
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        if (key.value == 'my_space_tiles') return 0;
        if (key.value == 'my_space_likes_card') return 1;
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
        if (index == 1) {
          return Padding(
            key: const ValueKey<String>('my_space_likes_card'),
            padding: EdgeInsets.fromLTRB(gutter, 12.sp, gutter, 16.sp),
            child: const _MyLikesCard(),
          );
        }
        final at = index - lead;
        final item = body[at];
        return Padding(
          key: ValueKey<String>(item.key),
          // Every saved card uses the Events list's gap. The explanation
          // and suggested cards set their own spacing.
          padding: EdgeInsets.only(
            top: at == 0 || !item.key.startsWith('space_group_') ? 0 : 12.sp,
          ),
          child: item.child,
        );
      },
    );

    return RefreshIndicator(
      onRefresh: _refresh,
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: frame(list),
    );
  }
}

// ------------------------------------------------------------------ tiles

class _MySpaceTiles extends StatelessWidget {
  const _MySpaceTiles();

  @override
  Widget build(BuildContext context) => HubTileRow(
    left: HubTile(
      key: const ValueKey('my_space_smart_events_tile'),
      title: 'Smart Events',
      caption: 'Your saved events',
      artwork: const HubSceneBackdrop(scene: HubScene.smartEvents),
      onTap: () => spaceOpenGroup(context, SpaceSection.smartEvents),
    ),
    right: const _LibraryTile(),
  );
}

/// Permanent archive entry, sharing the saved cards' horizontal event frame.
class _MyLikesCard extends ConsumerWidget {
  const _MyLikesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caption = hubLikesCaption(
      ref.watch(likedGamesProvider.select(likesSummary)),
    );
    return CollectionPlateRow(
      plate: Center(
        child: Icon(Icons.favorite, size: 40.sp, color: context.colors.danger),
      ),
      title: 'My Likes',
      meta: 'Your saved games',
      tally: caption,
      semanticsLabel: 'My Likes, your saved games, $caption',
      onTap: () {
        HapticFeedbackService.cardTap();
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const MyLikesScreen()));
      },
    );
  }
}

/// Library is the private workspace; publishing is an explicit action inside it.
class _LibraryTile extends StatelessWidget {
  const _LibraryTile();

  @override
  Widget build(BuildContext context) => HubTile(
    key: const ValueKey('my_space_library_tile'),
    title: 'Library',
    caption: 'Your databases',
    artwork: const HubLibraryBackdrop(),
    onTap: () {
      HapticFeedbackService.cardTap();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: LibraryScreen(databasesOnly: true)),
        ),
      );
    },
  );
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

// Event suggestions are temporarily outside My Space's product scope.
/*
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

*/

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

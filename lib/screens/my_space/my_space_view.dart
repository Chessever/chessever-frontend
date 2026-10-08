import 'dart:async';

import 'package:chessever2/screens/my_space/actions/space_remove_confirmation.dart';
// import 'package:chessever2/providers/favorite_events_provider.dart';
// import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
// import 'package:chessever2/screens/for_you/open_for_you_event.dart';
import 'package:chessever2/screens/my_space/actions/space_edit_actions.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/collections/collection_plate_row.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_prep_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/widgets/hub_context_art.dart';
// import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_edit_mode_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_home_layout_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_home_card_size_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_hub_providers.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_grid.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_tutorial.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';

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

/// Opens My Prep: the reader's games, opponents and favorite players.
Future<void> openMyPrep(BuildContext context) {
  HapticFeedbackService.cardTap();
  return MyPrepScreen.open(context);
}

/// The My Space tab: My Prep and Library tiles, a permanent My Likes card
/// and the saved compact cards, in one arrangement the reader owns ([+],
/// Edit). Edit happens in place: the page does not move as it starts, every
/// card (the page's own included) can be held and dropped anywhere, rows
/// hold at most two, and only saved cards can be removed.
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
  final _pageScroll = ScrollController();
  final Set<String> _selected = {};

  @override
  void dispose() {
    _pageScroll.dispose();
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

  /// A drop: the pins take their new order in the store, and the page's own
  /// cards their new places among them.
  void _reorder(String key, List<String> order) {
    ref.read(spaceHomeLayoutProvider.notifier).placeFrom(order);
    if (spaceHomeIsFixed(key)) return;
    unawaited(
      ref.read(spaceShortcutsProvider.notifier).moveWithinVisible(key, [
        for (final k in order)
          if (!spaceHomeIsFixed(k)) k,
      ]),
    );
  }

  /// Edit's save (the add button's check) removes what was selected, with
  /// one Undo; the order was already saved as it was dropped. Cancelling a
  /// smart event's confirmation puts the reader back in Edit, the selection
  /// as it was.
  Future<void> _removeSelected(Set<String> keys) async {
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
      if (!mounted) return;
      ref.read(spaceEditModeProvider.notifier).state = true;
      setState(() => _selected.addAll(keys));
      return;
    }
    if (!mounted) return;
    await spaceRemovePinsSelected(context: context, ref: ref, keys: keys);
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
      final picked = Set<String>.of(_selected);
      setState(_selected.clear);
      if (previous == true && !next) unawaited(_removeSelected(picked));
      if (next &&
          (ref.read(spaceCompactDatabaseGroupsProvider)?.isNotEmpty ?? false)) {
        // Teach selection and reordering for the visible products.
        maybeShowSpaceEditTutorial(
          context,
          ref,
          SpaceSection.library,
          home: true,
        );
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
    final order = spaceHomeOrder([
      for (final pin in pins) pin.key,
    ], ref.watch(spaceHomeLayoutProvider));
    final tablet = ResponsiveHelper.isTablet;

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

    // Under the last row, at the air the page has always left there.
    final Widget? footer = groups == null
        ? const _DatabaseSkeleton()
        : (!pinned ? const _DatabaseEmpty() : null);

    final grid = SpaceHomeGrid(
      pins: pins,
      fixed: _fixedCards(context),
      order: order,
      editing: editing,
      selected: _selected,
      onToggle: _toggle,
      onReorder: _reorder,
      controller: widget.scrollController ?? _pageScroll,
      top: 16.sp,
      // Keep the last row above My Space's restored add button.
      bottom: 24.sp + 72,
      footer: footer == null
          ? null
          : Padding(
              padding: EdgeInsets.only(top: 16.sp),
              child: footer,
            ),
    );

    return PopScope(
      canPop: !editing,
      onPopInvokedWithResult: (didPop, _) {
        // Back leaves Edit without removing anything; only the check saves
        // a removal.
        if (!didPop && editing) {
          setState(_selected.clear);
          _setEditing(false);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: RefreshIndicator(
              onRefresh: _refresh,
              // Edit holds the page still: a pull there is a reorder's
              // overscroll, not a refresh.
              notificationPredicate: editing
                  ? (_) => false
                  : defaultScrollNotificationPredicate,
              color: context.colors.textPrimary,
              backgroundColor: context.colors.surface,
              child: frame(grid),
            ),
          ),
        ],
      ),
    );
  }

  /// My Prep, Library and My Likes: the page's own cards. Any of them moves
  /// anywhere; none is ever removed.
  Map<String, SpaceEditItem> _fixedCards(BuildContext context) {
    final sizes = ref.watch(spaceHomeCardSizesProvider);
    bool small(String key) =>
        spaceHomeCardSizeFor(key, sizes) == SpaceHomeCardSize.small;
    void resize(String key) {
      HapticFeedbackService.selection();
      ref.read(spaceHomeCardSizesProvider.notifier).toggle(key);
    }

    return {
      kSpaceHomeMyPrep: SpaceEditItem(
        key: kSpaceHomeMyPrep,
        label: 'My Prep',
        selectable: false,
        wide: !small(kSpaceHomeMyPrep),
        onResize: () => resize(kSpaceHomeMyPrep),
        radius: 14.br,
        builder: (_, _) => const _MyPrepTile(),
      ),
      kSpaceHomeLibrary: SpaceEditItem(
        key: kSpaceHomeLibrary,
        label: 'Library',
        selectable: false,
        wide: !small(kSpaceHomeLibrary),
        onResize: () => resize(kSpaceHomeLibrary),
        radius: 14.br,
        builder: (_, _) => const _LibraryTile(),
      ),
      kSpaceHomeLikes: SpaceEditItem(
        key: kSpaceHomeLikes,
        label: 'My Likes',
        selectable: false,
        wide: !small(kSpaceHomeLikes),
        onResize: () => resize(kSpaceHomeLikes),
        builder: (_, _) => _MyLikesCard(
          key: const ValueKey<String>('my_space_likes_card'),
          small: small(kSpaceHomeLikes),
        ),
      ),
    };
  }
}

// ------------------------------------------------------------------ tiles

class _MyPrepTile extends StatelessWidget {
  const _MyPrepTile();

  @override
  Widget build(BuildContext context) => HubTile(
    key: const ValueKey('my_space_my_prep_tile'),
    title: 'My Prep',
    caption: 'Your games and opponents',
    ramp: false,
    artwork: const HubSceneBackdrop(scene: HubScene.myPrep),
    onTap: () => openMyPrep(context),
  );
}

/// Permanent archive entry, sharing the saved cards' horizontal event frame.
class _MyLikesCard extends ConsumerWidget {
  const _MyLikesCard({super.key, this.small = false});

  final bool small;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caption = hubLikesCaption(
      ref.watch(likedGamesProvider.select(likesSummary)),
    );
    return CollectionPlateRow(
      stacked: small,
      // The heart the Library's My Likes card wears, at the size it wears
      // it there, so the destination has one mark on both pages.
      plate: Center(child: LikesHeartMark(size: 64.0.h)),
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
    ramp: false,
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

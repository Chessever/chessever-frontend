import 'package:chessever2/config/feature_flags.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_game_card_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/space_game_rows.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What My Database lists: everything the user saved to My Space, newest
/// first. My Likes has its own tile above it, and streak cards stay out while
/// streaks are hidden. Null until the saved list has loaded.
final spaceDatabaseProvider = Provider.autoDispose<List<SpaceShortcut>?>((ref) {
  final saved = ref.watch(spaceShortcutsProvider);
  final list = saved.valueOrNull;
  if (list == null) return saved.hasError ? const [] : null;
  final shown = [
    for (final s in list)
      if (s.kind != SpaceShortcutKind.likes &&
          (FeatureFlags.streaks || s.kind != SpaceShortcutKind.streak))
        s,
  ];
  shown.sort((a, b) {
    final ad = a.createdAt, bd = b.createdAt;
    if (ad != null && bd != null) return bd.compareTo(ad);
    if (ad != null) return -1;
    if (bd != null) return 1;
    return b.sortIndex.compareTo(a.sortIndex);
  });
  return shown;
});

/// A saved broadcast as the Events list draws it, fresh from the server:
/// its current dates, rating and whether it is live. Null when the event
/// cannot be found; the card then falls back to what was saved with it.
final spaceEventCardModelProvider = FutureProvider.autoDispose
    .family<GroupEventCardModel?, String>((ref, id) async {
      final liveIds =
          ref.watch(liveGroupBroadcastIdsProvider).valueOrNull ??
          const <String>[];
      try {
        final broadcast = await ref
            .read(groupBroadcastRepositoryProvider)
            .getGroupBroadcastById(id);
        return GroupEventCardModel.fromGroupBroadcast(broadcast, liveIds);
      } catch (e) {
        debugPrint('[MySpace] event $id not resolved: $e');
        return null;
      }
    });

/// The card model an event shortcut carries itself: what the event card
/// showed when it was saved. Enough to draw the card at once, and all a
/// calendar or database-only event ever has.
GroupEventCardModel spaceEventCardModelFromShortcut(SpaceShortcut s) {
  String? str(String key) {
    final v = s.params[key];
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  TourEventCategory category() {
    final raw = str('category');
    for (final c in TourEventCategory.values) {
      if (c.name == raw) return c;
    }
    return TourEventCategory.completed;
  }

  final community =
      str('source') == 'calendar' ||
      str('eventSource') == EventSource.communityEvent.name;
  return GroupEventCardModel(
    id: s.targetId,
    title: s.title,
    dates: str('dates') ?? s.subtitle ?? '',
    maxAvgElo: 0,
    timeUntilStart: '',
    tourEventCategory: category(),
    timeControl: str('timeControl') ?? '',
    endDate: null,
    startDate: null,
    location: str('location'),
    eventSource: community
        ? EventSource.communityEvent
        : EventSource.lichessBroadcast,
  );
}

/// Whether an event shortcut is a broadcast the server can refresh. Calendar
/// and database-only events are not.
bool _isBroadcastEvent(SpaceShortcut s) {
  final id = s.targetId;
  if (s.params['source'] == 'calendar') return false;
  if (s.params['eventSource'] == EventSource.communityEvent.name) return false;
  return !id.startsWith('gamebase') && !id.startsWith('cal_event_');
}

/// One saved thing in My Database, drawn the way the rest of the app draws
/// it: an event as the Events list's card, a Smart Event as Today's, a game
/// as its game card, and anything else (a database, a position, a player)
/// as a row in the same card language. Tapping opens it exactly as the
/// shortcut always has; the long-press menu can take it back out.
class SpaceDatabaseItem extends StatelessWidget {
  const SpaceDatabaseItem({super.key, required this.shortcut});

  final SpaceShortcut shortcut;

  @override
  Widget build(BuildContext context) {
    return switch (shortcut.kind) {
      SpaceShortcutKind.event => _SavedEvent(shortcut: shortcut),
      SpaceShortcutKind.smartEvent => _SavedSmartEvent(shortcut: shortcut),
      SpaceShortcutKind.game => _SavedGame(shortcut: shortcut),
      _ => SpaceSavedRow(shortcut: shortcut),
    };
  }
}

class _SavedEvent extends ConsumerWidget {
  const _SavedEvent({required this.shortcut});

  final SpaceShortcut shortcut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fresh = _isBroadcastEvent(shortcut)
        ? ref.watch(spaceEventCardModelProvider(shortcut.targetId)).valueOrNull
        : null;
    final model = fresh ?? spaceEventCardModelFromShortcut(shortcut);
    return EventCard(
      tourEventCardModel: model,
      heroTagSuffix: '_myspace',
      forceCompactLayout: true,
      onTap: () => openSpaceShortcut(context, ref, shortcut),
    );
  }
}

class _SavedSmartEvent extends ConsumerWidget {
  const _SavedSmartEvent({required this.shortcut});

  final SpaceShortcut shortcut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = smartEventRequestFromSpaceShortcut(shortcut);
    if (saved == null) return SpaceSavedRow(shortcut: shortcut);
    // Server-fresh, as Today draws a saved Smart Event: the count and the
    // average come from the criteria against today's broadcasts.
    final resolved = ref
        .watch(smartEventResolvedEventsProvider(saved.criteria))
        .valueOrNull;
    final request = resolved == null ? saved : saved.withEvents(resolved);
    final events = request.events;
    final elos = [
      for (final e in events)
        if (e.maxAvgElo > 0) e.maxAvgElo,
    ];
    final avg = elos.isEmpty
        ? 0
        : (elos.reduce((a, b) => a + b) / elos.length).round();
    return SmartEventCard(
      tierLabel: request.tierLabel,
      minElo: request.minElo,
      liveCount: events.length,
      avgElo: avg,
      titleSuffix: request.titleSuffix,
      caption: request.caption,
      countSingular: request.countSingular,
      countPlural: request.countPlural,
      accentColor: smartEventAccentColor(request.scopeId),
      spaceDraft: smartEventSpaceDraft(request),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SmartEventScreen(request: request),
        ),
      ),
    );
  }
}

class _SavedGame extends ConsumerWidget {
  const _SavedGame({required this.shortcut});

  final SpaceShortcut shortcut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final face = watchSpaceGameFace(ref, shortcut);
    if (face.players == SpaceGamePlayers.missing) {
      return SpaceSavedRow(shortcut: shortcut);
    }
    if (face.players != SpaceGamePlayers.ready) {
      return SkeletonWidget(
        ignoreContainers: true,
        child: Container(
          height: 72.sp,
          decoration: BoxDecoration(
            color: context.colors.surfaceRecessed,
            borderRadius: BorderRadius.circular(8.br),
          ),
        ),
      );
    }
    final game = face.game;
    final viewMode = ref.watch(gamesListViewModeProvider);
    return GameCardWrapperWidget(
      game: game,
      gamesData: GamesScreenModel(
        gamesTourModels: [game],
        pinnedGamedIs: const [],
      ),
      gameIndex: 0,
      isChessBoardVisible: viewMode != GamesListViewMode.gamesCard,
      viewSource: ChessboardView.forYou,
      liveBatchKey: spaceLiveBatchKey(game),
      showPin: false,
      playerProfileDataSource: game.source == GameSource.supabase
          ? PlayerProfileDataSource.supabase
          : PlayerProfileDataSource.twic,
      onReturnFromChessboard: (_) {},
    );
  }
}

/// A saved database, position, opening, player or link as a row in the
/// Events card language: the card surface, a plate where an event keeps its
/// photo (here the thing's pixel object), its name and what it is.
class SpaceSavedRow extends ConsumerWidget {
  const SpaceSavedRow({super.key, required this.shortcut});

  final SpaceShortcut shortcut;

  /// What the row says the thing is, when the saved subtitle does not.
  static String kindLabel(SpaceShortcutKind kind) => switch (kind) {
    SpaceShortcutKind.player => 'Player',
    SpaceShortcutKind.playerGames => 'Player games',
    SpaceShortcutKind.playerOpenings => 'Player openings',
    SpaceShortcutKind.event => 'Event',
    SpaceShortcutKind.round => 'Round',
    SpaceShortcutKind.game => 'Game',
    SpaceShortcutKind.position => 'Position',
    SpaceShortcutKind.opening => 'Opening',
    SpaceShortcutKind.folder => 'Database',
    SpaceShortcutKind.smartEvent => 'Smart Event',
    SpaceShortcutKind.countrymen => 'Countrymen',
    SpaceShortcutKind.miniatures => 'Miniatures',
    SpaceShortcutKind.likes => 'Liked games',
    SpaceShortcutKind.streak => 'Streak',
    SpaceShortcutKind.link => 'Link',
  };

  /// The pixel object standing for the thing, from My Space's own set.
  static SpaceSection artFor(SpaceShortcutKind kind) => switch (kind) {
    SpaceShortcutKind.folder ||
    SpaceShortcutKind.miniatures => SpaceSection.library,
    SpaceShortcutKind.position ||
    SpaceShortcutKind.opening ||
    SpaceShortcutKind.playerOpenings => SpaceSection.openings,
    SpaceShortcutKind.event || SpaceShortcutKind.round => SpaceSection.events,
    SpaceShortcutKind.game => SpaceSection.games,
    SpaceShortcutKind.smartEvent => SpaceSection.smartEvents,
    SpaceShortcutKind.likes => SpaceSection.likes,
    SpaceShortcutKind.player ||
    SpaceShortcutKind.playerGames ||
    SpaceShortcutKind.countrymen ||
    SpaceShortcutKind.streak => SpaceSection.players,
    SpaceShortcutKind.link => SpaceSection.links,
  };

  void _open(BuildContext context, WidgetRef ref) {
    HapticFeedbackService.cardTap();
    openSpaceShortcut(context, ref, shortcut);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final isLight = context.isLightTheme;
    final subtitle = shortcut.subtitle?.trim();
    final kind = kindLabel(shortcut.kind);
    final meta = subtitle == null || subtitle.isEmpty || subtitle == kind
        ? kind
        : '$kind · $subtitle';
    final plateWidth = 108.w;
    final plateHeight = plateWidth * 4 / 5;
    final card = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        border: isLight
            ? Border.all(color: colors.divider.withValues(alpha: 0.4))
            : null,
      ),
      padding: EdgeInsets.all(6.sp),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6.br),
            child: ColoredBox(
              color: isLight ? colors.surfaceRecessed : kHubTileInk,
              child: SizedBox(
                width: plateWidth,
                height: plateHeight,
                child: _PlateArt(section: artFor(shortcut.kind)),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  shortcut.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    color: colors.textPrimary,
                    fontSize: 14.sp,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textXsMedium.copyWith(
                    color: colors.textPrimaryMuted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 4.w),
          Icon(
            Icons.chevron_right_rounded,
            size: 20.ic,
            color: colors.iconSecondary,
          ),
          SizedBox(width: 4.w),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: '${shortcut.title}, $meta',
      excludeSemantics: true,
      onTap: () => _open(context, ref),
      child: TappableScale(
        onTap: () => _open(context, ref),
        child: CardContextMenu(
          onPreviewTap: () => _open(context, ref),
          actions: (menuContext) => [
            LibraryMenuAction(
              icon: Icons.open_in_new_rounded,
              label: 'Open',
              onSelected: () => _open(context, ref),
            ),
            spaceMenuAction(context: menuContext, ref: ref, draft: shortcut),
          ],
          child: card,
        ),
      ),
    );
  }
}

/// A pixel object centred on a row's plate.
class _PlateArt extends StatelessWidget {
  const _PlateArt({required this.section});

  final SpaceSection section;

  @override
  Widget build(BuildContext context) {
    final tone = PixelTone.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        return PixelArtView(
          scene: PixelScene.inBox(
            PixelArt.door(section, tone: tone),
            size,
            spacePlateArtBox(size),
          ),
        );
      },
    );
  }
}

/// Where a pixel object sits on a card's plate: centred, small enough that
/// the plate reads as a frame around it rather than a crop of it.
Rect spacePlateArtBox(Size size) => Rect.fromCenter(
  center: size.center(Offset.zero),
  width: size.width * 0.52,
  height: size.height * 0.62,
);

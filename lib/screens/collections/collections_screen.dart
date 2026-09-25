import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart'
    show spacePlateArtBox;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Discovery › Collection: the collections, laid out as an event is, with
/// events and books on their own tabs and each entry drawn as an event card.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  static Future<void> open(BuildContext context) {
    HapticFeedbackService.cardTap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CollectionsScreen()));
  }

  static const _tabs = [CollectionKind.event, CollectionKind.book];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);
    return EventViewShell(
      title: 'Collection',
      tabs: const ['Events', 'Books'],
      pageBuilder: (context, index) {
        final kind = _tabs[index];
        return collections.when(
          data: (all) {
            final shown = [
              for (final c in all)
                if (c.kind == kind) c,
            ];
            return RefreshIndicator(
              color: context.colors.textPrimary,
              backgroundColor: context.colors.surface,
              onRefresh: () => ref.refresh(collectionsProvider.future),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  16.sp,
                  16.sp,
                  16.sp,
                  24.sp + MediaQuery.viewPaddingOf(context).bottom,
                ),
                itemCount: shown.isEmpty ? 1 : shown.length,
                itemBuilder: (context, i) {
                  if (shown.isEmpty) {
                    return _Notice(
                      text: kind == CollectionKind.event
                          ? 'No annotated events yet.'
                          : 'No books yet.',
                    );
                  }
                  return Padding(
                    padding: EdgeInsets.only(bottom: 12.sp),
                    child: CollectionCard(collection: shown[i]),
                  );
                },
              ),
            );
          },
          loading: () => const _CardsSkeleton(),
          error: (error, _) => _Notice(
            text: userFacingError(
              error,
              fallback: "Couldn't load collections.",
            ),
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(collectionsProvider),
          ),
        );
      },
    );
  }
}

/// A collection as the Events list draws an event: its cover (or its pixel
/// object) on the left, the title, and one meta line.
class CollectionCard extends StatelessWidget {
  const CollectionCard({super.key, required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLight = context.isLightTheme;
    final c = collection;
    final games = c.gameCount == 1 ? '1 game' : '${c.gameCount} games';
    // The count first, so a long place or name is what gives way.
    final meta = [
      games,
      if (c.kind == CollectionKind.book && c.author != null) 'by ${c.author}',
      if (c.kind == CollectionKind.event && c.subtitle != null) c.subtitle!,
    ].join(' · ');
    final plateWidth = 108.w;
    final plateHeight = plateWidth * 4 / 5;

    void open() {
      HapticFeedbackService.cardTap();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CollectionScreen(collection: c),
        ),
      );
    }

    return Semantics(
      button: true,
      label: '${c.title}, $meta',
      excludeSemantics: true,
      onTap: open,
      child: TappableScale(
        onTap: open,
        child: Container(
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
                child: SizedBox(
                  width: plateWidth,
                  height: plateHeight,
                  child: _Cover(collection: c),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c.title,
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
            ],
          ),
        ),
      ),
    );
  }
}

/// A collection's cover, or its pixel object (the trophy for an event, the
/// stacked boards for a book) when it has none.
class _Cover extends StatelessWidget {
  const _Cover({required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final isLight = context.isLightTheme;
    final plate = ColoredBox(
      color: isLight ? context.colors.surfaceRecessed : kHubTileInk,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
          return PixelArtView(
            scene: PixelScene.inBox(
              PixelArt.door(
                collection.kind == CollectionKind.book
                    ? SpaceSection.library
                    : SpaceSection.events,
                tone: PixelTone.of(context),
              ),
              size,
              spacePlateArtBox(size),
            ),
          );
        },
      ),
    );
    final url = collection.coverUrl;
    if (url == null) return plate;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => plate,
      errorWidget: (_, __, ___) => plate,
    );
  }
}

/// One collection, laid out as an event: About, Games (the annotated games,
/// as an event's Games tab lists them) and Players (everyone in it and how
/// many games each played; picking one shows their games).
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, required this.collection});

  final Collection collection;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  static const int _gamesTab = 1;

  final EventViewController _tabs = EventViewController();

  /// The player whose games the Games tab shows, or null for all.
  String? _player;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _showPlayer(String? name) {
    HapticFeedbackService.selection();
    setState(() => _player = name);
    if (name != null) _tabs.showTab(_gamesTab);
  }

  /// Collection games carry their whole PGN, so the board replays them as it
  /// replays an imported file.
  void _openGame(List<GamesTourModel> games, int index) {
    HapticFeedbackService.cardTap();
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChessBoardScreenNew(
          currentIndex: index,
          games: games,
          viewSource: ChessboardView.tour,
          showGamebaseButton: false,
          disableGamebaseOverlayByDefault: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.collection;
    final games = ref.watch(collectionGamesProvider(c.id));
    return EventViewShell(
      title: c.title,
      tabs: const ['About', 'Games', 'Players'],
      initialTab: _gamesTab,
      controller: _tabs,
      pageBuilder: (context, index) {
        return switch (index) {
          0 => _AboutPage(collection: c, games: games.valueOrNull),
          1 => games.when(
            data: (list) => _GamesPage(
              games: list,
              player: _player,
              onClearPlayer: () => _showPlayer(null),
              onOpen: _openGame,
            ),
            loading: () => const _CardsSkeleton(),
            error: (error, _) => _Notice(
              text: userFacingError(
                error,
                fallback: "Couldn't load the games.",
              ),
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(collectionGamesProvider(c.id)),
            ),
          ),
          _ => games.when(
            data: (list) => _PlayersPage(
              players: collectionPlayers(list),
              onPick: _showPlayer,
            ),
            loading: () => const _CardsSkeleton(),
            error: (error, _) => _Notice(
              text: userFacingError(
                error,
                fallback: "Couldn't load the players.",
              ),
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(collectionGamesProvider(c.id)),
            ),
          ),
        };
      },
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage({required this.collection, required this.games});

  final Collection collection;
  final List<CollectionGame>? games;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = collection;
    final paragraphs = [
      for (final p in (c.about ?? '').split(RegExp(r'\n\s*\n')))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    final players = games == null ? null : collectionPlayers(games!).length;
    final facts = [
      c.gameCount == 1 ? '1 game' : '${c.gameCount} games',
      if (players != null) players == 1 ? '1 player' : '$players players',
    ].join(' · ');
    final body = AppTypography.textSmRegular.copyWith(
      color: colors.textPrimary,
      fontSize: 15.f,
      height: 22 / 15,
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20.sp,
        20.sp,
        20.sp,
        32.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        if (c.coverUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8.br),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _Cover(collection: c),
            ),
          ),
          SizedBox(height: 16.sp),
        ],
        Text(
          c.title,
          style: AppTypography.textSmMedium.copyWith(
            color: colors.textPrimary,
            fontSize: 20.f,
            height: 26 / 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        if (c.author != null) ...[
          SizedBox(height: 4.sp),
          Text(
            c.kind == CollectionKind.book
                ? 'by ${c.author}'
                : 'Annotated by ${c.author}',
            style: AppTypography.textSmMedium.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (c.subtitle != null) ...[
          SizedBox(height: 4.sp),
          Text(
            c.subtitle!,
            style: AppTypography.textSmRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
        SizedBox(height: 4.sp),
        Text(
          facts,
          style: AppTypography.textSmRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
        for (final p in paragraphs) ...[
          SizedBox(height: 16.sp),
          Text(p, style: body),
        ],
      ],
    );
  }
}

class _GamesPage extends StatelessWidget {
  const _GamesPage({
    required this.games,
    required this.player,
    required this.onClearPlayer,
    required this.onOpen,
  });

  final List<CollectionGame> games;
  final String? player;
  final VoidCallback onClearPlayer;
  final void Function(List<GamesTourModel> games, int index) onOpen;

  bool _plays(GamesTourModel g, String name) {
    final key = name.toLowerCase();
    return g.whitePlayer.name.trim().toLowerCase() == key ||
        g.blackPlayer.name.trim().toLowerCase() == key;
  }

  @override
  Widget build(BuildContext context) {
    final picked = player;
    final shown = [
      for (final g in games)
        if (picked == null || _plays(g.game, picked)) g.game,
    ];
    if (games.isEmpty) {
      return const _Notice(text: 'No games in this collection yet.');
    }
    return ListView(
      padding: EdgeInsets.only(
        top: 16.sp,
        bottom: 24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        if (picked != null)
          Padding(
            padding: EdgeInsets.fromLTRB(20.sp, 0, 8.sp, 8.sp),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Games of $picked',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onClearPlayer,
                  child: Text(
                    'Show all',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.accentText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        DiscoveryGameList(games: shown, streamEnabled: false, onOpen: onOpen),
      ],
    );
  }
}

class _PlayersPage extends StatelessWidget {
  const _PlayersPage({required this.players, required this.onPick});

  final List<CollectionPlayer> players;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return const _Notice(text: 'No players in this collection yet.');
    }
    final colors = context.colors;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        16.sp,
        12.sp,
        16.sp,
        24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: players.length,
      separatorBuilder: (_, __) => SizedBox(height: 8.sp),
      itemBuilder: (context, i) {
        final p = players[i];
        final count = p.games == 1 ? '1 game' : '${p.games} games';
        final hasFlag = FederationFlag.hasVisibleFlag(p.federation);
        return Semantics(
          button: true,
          label: '${p.title ?? ''} ${p.name}, $count. Show their games'.trim(),
          excludeSemantics: true,
          child: TappableScale(
            onTap: () => onPick(p.name),
            child: Container(
              constraints: BoxConstraints(minHeight: 56.sp),
              padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 10.sp),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Row(
                children: [
                  if (hasFlag) ...[
                    FederationFlag(
                      federation: p.federation,
                      width: 20.sp,
                      height: 14.sp,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    SizedBox(width: 10.sp),
                  ],
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (p.title != null)
                            TextSpan(
                              text: '${p.title} ',
                              style: TextStyle(
                                color: colors.titleAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          TextSpan(text: p.name),
                          if (p.rating != null)
                            TextSpan(
                              text: '  ${p.rating}',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textSmMedium.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.sp),
                  Text(
                    count,
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20.sp, 32.sp, 20.sp, 32.sp),
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          SizedBox(height: 8.sp),
          Center(
            child: TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.accentText,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CardsSkeleton extends StatelessWidget {
  const _CardsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.all(16.sp),
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: SkeletonWidget(
              ignoreContainers: true,
              child: Container(
                height: 84.sp,
                decoration: BoxDecoration(
                  color: context.colors.surfaceRecessed,
                  borderRadius: BorderRadius.circular(8.br),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

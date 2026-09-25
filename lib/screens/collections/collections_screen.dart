import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show discoveryGutter;
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
import 'package:chessever2/screens/library/widgets/library_context_menu.dart'
    show LibraryMenuAction;
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/my_space/widgets/space_avatar.dart'
    show SpacePlayerAvatar;
import 'package:chessever2/screens/player_profile/utils/player_menu_actions.dart'
    show playerMenuActions;
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

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

/// [c] as a My Space shortcut: it sits with the databases and opens the
/// collection again from there.
SpaceShortcut collectionSpaceDraft(Collection c) {
  final games = c.gameCount == 1 ? '1 game' : '${c.gameCount} games';
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.collection,
    targetId: c.id,
    title: c.title,
    subtitle: games,
    params: {
      'slug': c.slug,
      'collectionKind': c.kind.name,
      'gameCount': c.gameCount,
      if (c.coverUrl != null) 'coverUrl': c.coverUrl,
    },
  );
}

/// A collection as the Events list draws an event: its cover (or its pixel
/// object) on the left, the title, and one meta line. Held, it lifts into
/// the focus menu with Open and My Space.
class CollectionCard extends StatelessWidget {
  const CollectionCard({super.key, required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLight = context.isLightTheme;
    final c = collection;
    final games = c.gameCount == 1 ? '1 game' : '${c.gameCount} games';
    final where = c.subtitle ?? collectionPlaceAndDates(c);
    // The count first, so a long place or name is what gives way.
    final meta = [
      games,
      if (c.kind == CollectionKind.book && c.author != null) 'by ${c.author}',
      if (c.kind == CollectionKind.event && where != null) where,
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
        child: Consumer(
          builder: (context, ref, child) => CardContextMenu(
            onPreviewTap: open,
            actions: (menuContext) => [
              LibraryMenuAction(
                icon: Icons.open_in_new_rounded,
                label: 'Open',
                onSelected: open,
              ),
              spaceMenuAction(
                context: menuContext,
                ref: ref,
                draft: collectionSpaceDraft(c),
              ),
            ],
            child: child!,
          ),
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
                          fontSize: 14.f,
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

/// "Saint Louis · Oct 2-14, 2025": an event's place and dates, or null when
/// it has neither.
String? collectionPlaceAndDates(Collection c) {
  final dates = collectionDateRange(c.dateStart, c.dateEnd);
  final parts = [?c.location, ?dates];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// "Oct 2, 2025", "Oct 2-14, 2025", "Sep 28 - Oct 3, 2025".
String? collectionDateRange(DateTime? start, DateTime? end) {
  final from = start ?? end;
  if (from == null) return null;
  final to = start == null ? null : end;
  final full = DateFormat('MMM d, yyyy');
  if (to == null ||
      (from.year == to.year && from.month == to.month && from.day == to.day)) {
    return full.format(from);
  }
  if (from.year == to.year && from.month == to.month) {
    return '${DateFormat('MMM d').format(from)}-${to.day}, ${to.year}';
  }
  if (from.year == to.year) {
    return '${DateFormat('MMM d').format(from)} - ${full.format(to)}';
  }
  return '${full.format(from)} - ${full.format(to)}';
}

/// Where section headers and the player line start: the game cards' edge.
double get _headerInset => discoveryGutter + 4.sp;

/// One collection, laid out as an event: About, Games (the annotated games
/// under their rounds, or a book's parts and chapters) and Players (everyone
/// in it and their games; picking one shows those games).
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, required this.collection});

  /// The list row it was opened from; the detail read fills in the rest.
  final Collection collection;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  static const int _gamesTab = 1;

  final EventViewController _tabs = EventViewController();

  /// The player whose games the Games tab shows, or null for all.
  CollectionPlayer? _player;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _showPlayer(CollectionPlayer? player) {
    HapticFeedbackService.selection();
    setState(() => _player = player);
    if (player != null) _tabs.showTab(_gamesTab);
  }

  /// Collection games carry their whole PGN, so the board replays them as it
  /// replays an imported file. [games] is the whole list in the order shown,
  /// so prev/next walks the collection.
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
    final slug = widget.collection.slug;
    final detail = ref.watch(collectionDetailProvider(slug));
    final c = detail.valueOrNull ?? widget.collection;
    final contents = ref.watch(collectionContentsProvider(slug));
    final players = ref.watch(collectionPlayersProvider(slug));
    return EventViewShell(
      title: c.title,
      tabs: const ['About', 'Games', 'Players'],
      initialTab: _gamesTab,
      controller: _tabs,
      pageBuilder: (context, index) {
        return switch (index) {
          0 => _AboutPage(
            collection: c,
            playerCount: players.valueOrNull?.length,
            // Only when there is nothing better than the list row to show;
            // hidden while a retry is in flight so the tap reads as taken.
            error: detail.hasError && !detail.hasValue && !detail.isLoading
                ? detail.error
                : null,
            onRetry: () => ref.invalidate(collectionDetailProvider(slug)),
          ),
          1 => contents.when(
            data: (data) => _GamesPage(
              contents: data,
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
              onAction: () {
                ref.invalidate(collectionDetailProvider(slug));
                ref.invalidate(collectionGamesProvider(slug));
              },
            ),
          ),
          _ => players.when(
            data: (list) => _PlayersPage(players: list, onPick: _showPlayer),
            loading: () => const _CardsSkeleton(),
            error: (error, _) => _Notice(
              text: userFacingError(
                error,
                fallback: "Couldn't load the players.",
              ),
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(collectionPlayersProvider(slug)),
            ),
          ),
        };
      },
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage({
    required this.collection,
    required this.playerCount,
    this.error,
    this.onRetry,
  });

  final Collection collection;

  /// Null until the Players read lands.
  final int? playerCount;

  /// Why the detail read failed, when [collection] is still just the list
  /// row (no About text, credits or edition).
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = collection;
    final paragraphs = _paragraphs(c.about);
    final players = playerCount;
    final facts = [
      c.gameCount == 1 ? '1 game' : '${c.gameCount} games',
      if (players != null && players > 0)
        players == 1 ? '1 player' : '$players players',
    ].join(' · ');
    final isBook = c.kind == CollectionKind.book;
    final credit = isBook ? c.author : c.annotator ?? c.author;
    final annotator = isBook && c.annotator != c.author ? c.annotator : null;
    final edition = isBook
        ? [?c.publisher, if (c.publishedYear != null) '${c.publishedYear}']
        : [?collectionPlaceAndDates(c)];
    final body = AppTypography.textSmRegular.copyWith(
      color: colors.textPrimary,
      fontSize: 15.f,
      height: 22 / 15,
    );
    final secondary = AppTypography.textSmRegular.copyWith(
      color: colors.textSecondary,
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
        if (credit != null) ...[
          SizedBox(height: 4.sp),
          Text(
            isBook ? 'by $credit' : 'Annotated by $credit',
            style: AppTypography.textSmMedium.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (annotator != null) ...[
          SizedBox(height: 4.sp),
          Text('Annotated by $annotator', style: secondary),
        ],
        if (c.subtitle != null) ...[
          SizedBox(height: 4.sp),
          Text(c.subtitle!, style: secondary),
        ],
        if (edition.isNotEmpty) ...[
          SizedBox(height: 4.sp),
          Text(edition.join(' · '), style: secondary),
        ],
        SizedBox(height: 4.sp),
        Text(facts, style: secondary),
        if (error != null) ...[
          SizedBox(height: 16.sp),
          Row(
            children: [
              Expanded(
                child: Text(
                  userFacingError(
                    error,
                    fallback: "Couldn't load the rest of this collection.",
                  ),
                  style: secondary,
                ),
              ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: Text(
                    'Try again',
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.accentText,
                    ),
                  ),
                ),
            ],
          ),
        ],
        for (final p in paragraphs) ...[
          SizedBox(height: 16.sp),
          Text(p, style: body),
        ],
      ],
    );
  }
}

/// [text]'s paragraphs: blank lines separate them.
List<String> _paragraphs(String? text) => [
  for (final p in (text ?? '').split(RegExp(r'\n\s*\n')))
    if (p.trim().isNotEmpty) p.trim(),
];

class _GamesPage extends StatelessWidget {
  const _GamesPage({
    required this.contents,
    required this.player,
    required this.onClearPlayer,
    required this.onOpen,
  });

  final CollectionContents contents;
  final CollectionPlayer? player;
  final VoidCallback onClearPlayer;
  final void Function(List<GamesTourModel> games, int index) onOpen;

  /// By key only: cards and player rows share it (`fide:<id>` or
  /// `name:<lower>`), and the Players tab counts games the same way. A name
  /// match across different keys is a namesake, not the same player.
  static bool _plays(CollectionGame g, CollectionPlayer p) =>
      g.card.involves(p.key);

  @override
  Widget build(BuildContext context) {
    if (contents.games.isEmpty) {
      return const _Notice(text: 'No games in this collection yet.');
    }
    final picked = player;
    final groups = groupCollectionGames(contents.sections, [
      for (final g in contents.games)
        if (picked == null || _plays(g, picked)) g,
    ]);
    // The order the board steps through: exactly the order drawn.
    final ordered = [
      for (final group in groups)
        for (final g in group.games) g.game,
    ];
    // A collection with no sections lists its games with no headers at all.
    final headed = groups.any((g) => g.section != null);
    final lead = picked == null ? 0 : 1;
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 16.sp,
        bottom: 24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: lead + (groups.isEmpty ? 1 : groups.length),
      itemBuilder: (context, i) {
        if (picked != null && i == 0) {
          return _PlayerLine(name: picked.name, onClear: onClearPlayer);
        }
        if (groups.isEmpty) {
          // Inline, not a _Notice: that one is a scrollable of its own.
          return Padding(
            padding: EdgeInsets.fromLTRB(20.sp, 24.sp, 20.sp, 0),
            child: Text(
              'No games of this player here.',
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          );
        }
        final index = i - lead;
        final group = groups[index];
        final intro = _paragraphs(group.section?.intro);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (headed)
              _SectionHeader(section: group.section, first: index == 0),
            if (intro.isNotEmpty) _SectionIntro(paragraphs: intro),
            if (group.games.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: 4.sp),
                child: DiscoveryGameList(
                  games: [for (final g in group.games) g.game],
                  streamEnabled: false,
                  onOpen: (_, local) => onOpen(ordered, group.offset + local),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The picked player's name over their games, and the way back to all.
class _PlayerLine extends StatelessWidget {
  const _PlayerLine({required this.name, required this.onClear});

  final String name;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(_headerInset, 0, 8.sp, 8.sp),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Games of $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            child: Text(
              'Show all',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.accentText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The header over a run of games: a round and its date, a book's part, a
/// chapter's number and title, or "Other games" for those in no section.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section, required this.first});

  /// Null for the games in no section.
  final CollectionSection? section;

  /// The first header sits right under the list's own top padding.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = section;
    final isPart = s?.kind == CollectionSectionKind.part;
    final main = isPart
        ? AppTypography.textSmMedium.copyWith(
            color: colors.textPrimary,
            fontSize: 17.f,
            height: 22 / 17,
            fontWeight: FontWeight.w700,
          )
        : AppTypography.textSmMedium.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          );
    final muted = main.copyWith(
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    String? lead;
    var title = 'Other games';
    String? date;
    if (s != null) {
      final named = s.title != null && s.title != s.label;
      switch (s.kind) {
        case CollectionSectionKind.part:
          lead = named ? s.label : null;
          title = named ? s.title! : s.label;
        case CollectionSectionKind.chapter:
          lead = named ? s.number ?? s.label : null;
          title = named ? s.title! : s.label;
        case CollectionSectionKind.round:
        case CollectionSectionKind.stage:
        case CollectionSectionKind.other:
          title = named ? '${s.label} · ${s.title}' : s.label;
          final day = s.startsOn;
          date = day == null ? null : DateFormat('MMM d, yyyy').format(day);
      }
      if (title.isEmpty) title = s.number ?? 'Games';
    }

    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _headerInset,
          first ? 0 : (isPart ? 28.sp : 20.sp),
          _headerInset,
          10.sp,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (lead != null) TextSpan(text: '$lead  ', style: muted),
                    TextSpan(text: title),
                  ],
                ),
                style: main,
              ),
            ),
            if (date != null) ...[
              SizedBox(width: 12.sp),
              Text(
                date,
                style: AppTypography.textXsMedium.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A chapter's introduction, read before its games.
class _SectionIntro extends StatelessWidget {
  const _SectionIntro({required this.paragraphs});

  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textSmRegular.copyWith(
      color: context.colors.textSecondary,
      height: 20 / 14,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(_headerInset, 0, _headerInset, 12.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < paragraphs.length; i++) ...[
            if (i > 0) SizedBox(height: 8.sp),
            Text(paragraphs[i], style: style),
          ],
        ],
      ),
    );
  }
}

class _PlayersPage extends StatelessWidget {
  const _PlayersPage({required this.players, required this.onPick});

  final List<CollectionPlayer> players;
  final ValueChanged<CollectionPlayer> onPick;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return const _Notice(text: 'No players in this collection yet.');
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        16.sp,
        12.sp,
        16.sp,
        24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: players.length,
      separatorBuilder: (_, __) => SizedBox(height: 8.sp),
      itemBuilder: (context, i) => _CollectionPlayerRow(
        key: ValueKey<String>('collection_player_${players[i].key}'),
        player: players[i],
        onPick: onPick,
      ),
    );
  }
}

/// One of a collection's players: their profile circle (photo, flag and
/// title, as every person on these pages wears it), the name and best
/// rating, and how many of the collection's games they play. Tap shows
/// their games here; a long press lifts the row into the player focus menu
/// (their games, My Space for the player and their Games tab, share).
class _CollectionPlayerRow extends ConsumerWidget {
  const _CollectionPlayerRow({
    super.key,
    required this.player,
    required this.onPick,
  });

  final CollectionPlayer player;
  final ValueChanged<CollectionPlayer> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = player;
    final colors = context.colors;
    final fideId = int.tryParse(p.fideId ?? '');
    final photo =
        fideId == null || fideId <= 0
            ? null
            : ref.watch(playerPhotoProvider(fideId)).valueOrNull;
    final title = p.title?.trim();
    final fed = p.fed?.trim();
    final count = p.games == 1 ? '1 game' : '${p.games} games';
    void pick() => onPick(p);
    return Semantics(
      button: true,
      label: '${title ?? ''} ${p.name}, $count. Show their games'.trim(),
      excludeSemantics: true,
      onTap: pick,
      child: TappableScale(
        onTap: pick,
        child: CardContextMenu(
          onPreviewTap: pick,
          actions:
              (menuContext) => playerMenuActions(
                menuContext,
                ref,
                playerName: p.name,
                fideId: fideId != null && fideId > 0 ? fideId : null,
                title: title == null || title.isEmpty ? null : title,
                federation: fed == null || fed.isEmpty ? null : fed,
                rating: p.bestElo,
                gamebasePlayerId: p.playerId,
                onOpen: pick,
                openLabel: 'Show their games',
                openIcon: Icons.open_in_new_rounded,
              ),
          child: Container(
            constraints: BoxConstraints(minHeight: 56.sp),
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8.br),
            ),
            child: Row(
              children: [
                SpacePlayerAvatar(
                  size: 40.sp,
                  name: p.name,
                  photoUrl: photo,
                  title: title,
                  federation: fed,
                  ring: colors.surface,
                ),
                SizedBox(width: 14.sp),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: p.name),
                        if (p.bestElo != null)
                          TextSpan(
                            text: '  ${p.bestElo}',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
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
      ),
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

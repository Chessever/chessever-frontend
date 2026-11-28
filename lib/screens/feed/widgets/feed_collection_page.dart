import 'dart:async';

import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/open_collection_game.dart';
import 'package:chessever2/screens/feed/models/feed_collection.dart';
import 'package:chessever2/screens/feed/widgets/feed_drag_handoff.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_pages.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart'
    show storyClockProvider, storyDayKey;
import 'package:chessever2/screens/stories/story_viewer.dart'
    show ensureStoryCollectionAccess, storyCollectionPageProvider;
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart'
    show premiumAccessProvider;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _collectionStoryGamesProvider = FutureProvider.autoDispose
    .family<List<CollectionGameCard>?, String>((ref, slug) {
      final repository = ref.watch(collectionsRepositoryProvider);
      final day = storyDayKey(ref.read(storyClockProvider)());
      return repository.fetchStoryGames(slug, day: day);
    });

// An ordered roster is reused by the separate cards from one collection.
final _collectionRosterProvider = FutureProvider.autoDispose
    .family<List<CollectionGame>, ({String slug, int seed})>((ref, key) {
      final link = ref.keepAlive();
      Timer? idle;
      ref.onCancel(() => idle = Timer(const Duration(minutes: 5), link.close));
      ref.onResume(() => idle?.cancel());
      ref.onDispose(() => idle?.cancel());
      return ref.watch(collectionsRepositoryProvider).fetchGames(key.slug);
    });

final _featuredFrameProvider = FutureProvider.autoDispose
    .family<
      StoryFrame?,
      ({
        String slug,
        String? gameId,
        int? gameIndex,
        int seed,
        String? anchorGameId,
      })
    >((ref, key) async {
      final repository = ref.watch(collectionsRepositoryProvider);
      final analyze = ref.watch(storyAnalyzerProvider);
      final storyGames = ref.watch(
        _collectionStoryGamesProvider(key.slug).future,
      );
      final roster = key.gameIndex == null
          ? null
          : ref.watch(
              _collectionRosterProvider((
                slug: key.slug,
                seed: key.seed,
              )).future,
            );

      List<CollectionGame>? games;
      CollectionGame? game;
      if (roster != null) {
        games = await roster;
        final index = key.gameIndex!;
        if (index >= games.length) return null;
        final anchor = games
            .where((game) => game.id == key.anchorGameId)
            .firstOrNull;
        if (anchor != null && index == 0) {
          game = anchor;
        } else if (anchor != null) {
          final remaining = games
              .where((game) => game.id != anchor.id)
              .toList();
          game = remaining[(key.seed + index - 1) % remaining.length];
        } else {
          game = games[(key.seed + index) % games.length];
        }
      }

      String? pgn;
      final gameId = game?.id ?? key.gameId;
      try {
        final stories = await storyGames;
        for (final card in stories ?? const []) {
          if (gameId != null && card.id != gameId) continue;
          game ??= CollectionGame.fromPreviewCard(card);
          if (game != null) {
            pgn = card.pgn;
            break;
          }
        }
      } on CollectionsRequestException {
        // Fall back to the collection's browse preview.
      }
      if (pgn == null) {
        games ??= await repository.fetchGames(key.slug);
        game ??=
            games.where((game) => game.id == gameId).firstOrNull ??
            latestStoryGame(games);
        if (game == null) return null;
        try {
          final detail = await repository.fetchCollection(key.slug);
          if (storyMovesReadable(detail)) {
            final moves = await repository.fetchPgnsOf(
              key.slug,
              {game.id},
              order: [for (final preview in games) preview.id],
            );
            pgn = moves[game.id];
          }
        } on CollectionsRequestException {
          // Keep the board preview when its annotated moves are unavailable.
        }
      }
      if (game == null) return null;
      final segments = pgn == null
          ? null
          : (await analyze([
              StoryAnalysisJob(id: game.id, pgn: pgn),
            ]))[game.id]?.segments;
      final story = segments == null
          ? stillStoryGame(game)
          : buildStoryGame(game, segments: segments);
      final annotated = story.segments.indexWhere(
        (segment) => segment.comment?.trim().isNotEmpty ?? false,
      );
      return StoryFrame(
        story: 0,
        segment: annotated < 0 ? 0 : annotated,
        value: story,
      );
    });

class FeedCollectionPage extends ConsumerStatefulWidget {
  const FeedCollectionPage({
    super.key,
    required this.card,
    this.active = false,
    this.onGameVisible,
    this.onGameOpened,
  });

  final FeedCollection card;
  final bool active;
  final ValueChanged<String>? onGameVisible;
  final ValueChanged<String>? onGameOpened;

  @override
  ConsumerState<FeedCollectionPage> createState() => _FeedCollectionPageState();
}

class _FeedCollectionPageState extends ConsumerState<FeedCollectionPage> {
  bool _opening = false;
  String? _reportedGameId;
  CollectionCheckpoint? _latest;

  Future<void> _open(String gameId, CollectionCheckpoint? checkpoint) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final saved = await openFeedCollectionGame(
        context,
        ref,
        collection: widget.card.collection,
        featuredGameId: gameId,
        checkpoint: checkpoint,
        onOpened: () {
          if (mounted) widget.onGameOpened?.call(gameId);
        },
      );
      if (saved != null && mounted) _latest = saved;
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openCollection() async {
    if (_opening) return;
    setState(() => _opening = true);
    final collection = widget.card.collection;
    final page = ref.read(storyCollectionPageProvider);
    try {
      if (!await ensureStoryCollectionAccess(context, ref, collection) ||
          !mounted) {
        return;
      }
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page(collection)));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.card.collection;
    final checkpoint = _latest ?? widget.card.resume;
    final provider = _featuredFrameProvider((
      slug: collection.slug,
      gameId: widget.card.featuredGameId ?? widget.card.resume?.gameId,
      gameIndex: widget.card.gameIndex,
      seed: widget.card.gameOrderSeed,
      anchorGameId: widget.card.anchorGameId ?? widget.card.featuredGameId,
    ));
    final read = ref.watch(provider);
    final frame = read.valueOrNull;
    final gameId = frame?.game.id;
    if (widget.active && gameId != null && gameId != _reportedGameId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !widget.active ||
            _reportedGameId == gameId ||
            ref.read(provider).valueOrNull?.game.id != gameId) {
          return;
        }
        _reportedGameId = gameId;
        widget.onGameVisible?.call(gameId);
      });
    }
    final needsUpgrade =
        collection.isPremium && !ref.watch(premiumAccessProvider);
    final gameLabel = needsUpgrade
        ? 'Upgrade'
        : checkpoint != null && checkpoint.gameId == gameId
        ? 'Continue'
        : 'Open game';
    VoidCallback? openGame;
    if (!_opening) {
      if (gameId != null) {
        openGame = () => _open(gameId, checkpoint);
      } else if (needsUpgrade) {
        openGame = _openCollection;
      }
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            collection.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: frame != null
                  // The annotation under the board scrolls in its own room,
                  // which takes every vertical drag that starts on it: one
                  // it cannot use turns the Feed's page instead.
                  ? FeedDragHandoff(
                      child: StoryFrameView(
                        key: ValueKey(frame.id),
                        frame: frame,
                        progress: const AlwaysStoppedAnimation(1.0),
                        active: false,
                        showPuzzle: false,
                      ),
                    )
                  : read.hasError
                  ? TextButton(
                      onPressed: () {
                        ref.invalidate(
                          _collectionStoryGamesProvider(collection.slug),
                        );
                        ref.invalidate(
                          _collectionRosterProvider((
                            slug: collection.slug,
                            seed: widget.card.gameOrderSeed,
                          )),
                        );
                        ref.invalidate(provider);
                      },
                      child: const Text('Retry game preview'),
                    )
                  : read.isLoading
                  ? const CircularProgressIndicator()
                  : const Text('No game preview available.'),
            ),
          ),
          StoryActions(
            gameLabel: gameLabel,
            collectionLabel: storyCollectionAction(collection),
            onOpenGame: openGame,
            onOpenCollection: _opening ? null : _openCollection,
          ),
        ],
      ),
    );
  }
}

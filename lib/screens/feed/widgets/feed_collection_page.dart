import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/open_collection_game.dart';
import 'package:chessever2/screens/feed/models/feed_collection.dart';
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

final _featuredFrameProvider = FutureProvider.autoDispose
    .family<StoryFrame?, ({String slug, String? resumeGameId})>((
      ref,
      key,
    ) async {
      final repository = ref.watch(collectionsRepositoryProvider);
      final analyze = ref.watch(storyAnalyzerProvider);
      final day = storyDayKey(ref.read(storyClockProvider)());
      CollectionGame? game;
      String? pgn;
      try {
        final stories = await repository.fetchStoryGames(key.slug, day: day);
        for (final card in stories ?? const []) {
          if (key.resumeGameId != null && card.id != key.resumeGameId) continue;
          game = CollectionGame.fromPreviewCard(card);
          if (game != null) {
            pgn = card.pgn;
            break;
          }
        }
      } on CollectionsRequestException {
        // Fall back to the collection's browse previews.
      }
      if (game == null) {
        final games = await repository.fetchGames(key.slug);
        game =
            games.where((game) => game.id == key.resumeGameId).firstOrNull ??
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
        game: story,
      );
    });

class FeedCollectionPage extends ConsumerStatefulWidget {
  const FeedCollectionPage({super.key, required this.card});

  final FeedCollection card;

  @override
  ConsumerState<FeedCollectionPage> createState() => _FeedCollectionPageState();
}

class _FeedCollectionPageState extends ConsumerState<FeedCollectionPage> {
  bool _opening = false;
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
      resumeGameId: checkpoint?.gameId,
    ));
    final read = ref.watch(provider);
    final frame = read.valueOrNull;
    final gameId = frame?.game.id;
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
                  ? StoryFrameView(
                      key: ValueKey(frame.id),
                      frame: frame,
                      progress: const AlwaysStoppedAnimation(1.0),
                      active: false,
                      showPuzzle: false,
                    )
                  : read.hasError
                  ? TextButton(
                      onPressed: () => ref.invalidate(provider),
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

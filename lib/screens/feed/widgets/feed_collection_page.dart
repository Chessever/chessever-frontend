import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/open_collection_game.dart';
import 'package:chessever2/screens/feed/models/feed_collection.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_pages.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart'
    show storyClockProvider, storyDayKey;
import 'package:chessever2/screens/stories/story_viewer.dart'
    show ensureStoryCollectionAccess, storyCollectionPageProvider;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _featuredGameProvider = FutureProvider.autoDispose
    .family<CollectionGame?, ({String slug, String? resumeGameId})>((
      ref,
      key,
    ) async {
      final repository = ref.watch(collectionsRepositoryProvider);
      if (key.resumeGameId == null) {
        final day = storyDayKey(ref.read(storyClockProvider)());
        try {
          final stories = await repository.fetchStoryGames(key.slug, day: day);
          for (final card in stories ?? const []) {
            final preview = CollectionGame.fromPreviewCard(card);
            if (preview != null) return preview;
          }
        } on CollectionsRequestException {
          // Fall back to public game previews if the story read is unavailable.
        }
      }
      final games = await ref.watch(collectionGamesProvider(key.slug).future);
      return games.where((game) => game.id == key.resumeGameId).firstOrNull ??
          latestStoryGame(games);
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

  Future<void> _open(
    CollectionGame game,
    CollectionCheckpoint? checkpoint,
  ) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final saved = await openFeedCollectionGame(
        context,
        ref,
        collection: widget.card.collection,
        featuredGameId: game.id,
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
    final provider = _featuredGameProvider((
      slug: collection.slug,
      resumeGameId: checkpoint?.gameId,
    ));
    final read = ref.watch(provider);
    final game = read.valueOrNull;
    final frame = game == null
        ? null
        : StoryFrame(story: 0, segment: 0, game: stillStoryGame(game));
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
            gameLabel: checkpoint != null && checkpoint.gameId == game?.id
                ? 'Continue'
                : 'Open game',
            collectionLabel: storyCollectionAction(collection),
            onOpenGame: _opening || game == null
                ? null
                : () => _open(game, checkpoint),
            onOpenCollection: _opening ? null : _openCollection,
          ),
        ],
      ),
    );
  }
}

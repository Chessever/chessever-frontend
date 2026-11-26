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
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _collectionStoryGamesProvider = FutureProvider.autoDispose
    .family<List<CollectionGameCard>?, String>((ref, slug) {
      final repository = ref.watch(collectionsRepositoryProvider);
      final day = storyDayKey(ref.read(storyClockProvider)());
      return repository.fetchStoryGames(slug, day: day);
    });

final _featuredFrameProvider = FutureProvider.autoDispose
    .family<
      StoryFrame?,
      ({String slug, String? gameId, List<CollectionGame>? games})
    >((ref, key) async {
      final repository = ref.watch(collectionsRepositoryProvider);
      final analyze = ref.watch(storyAnalyzerProvider);
      final storyGames = ref.watch(
        _collectionStoryGamesProvider(key.slug).future,
      );
      CollectionGame? game;
      String? pgn;
      try {
        final stories = await storyGames;
        for (final card in stories ?? const []) {
          if (key.gameId != null && card.id != key.gameId) continue;
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
        final games = key.games ?? await repository.fetchGames(key.slug);
        game = games.where((game) => game.id == key.gameId).firstOrNull;
        if (key.gameId == null || key.games == null) {
          game ??= latestStoryGame(games);
        }
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
  bool _browsing = false;
  String? _selectedGameId;
  List<CollectionGame>? _games;
  CollectionCheckpoint? _latest;

  Future<void> _browse(String visibleGameId, int direction) async {
    if (_opening || _browsing) return;
    setState(() => _browsing = true);
    try {
      final games =
          _games ??
          await ref
              .read(collectionsRepositoryProvider)
              .fetchGames(widget.card.collection.slug);
      if (!mounted) return;
      _games = games;
      if (games.length < 2) return;
      final current = games.indexWhere((game) => game.id == visibleGameId);
      final index = current < 0 ? 0 : (current + direction) % games.length;
      _selectedGameId = games[index].id;
    } catch (_) {
      if (mounted) {
        showAppSnack(context, 'Could not load collection games.');
      }
    } finally {
      if (mounted) setState(() => _browsing = false);
    }
  }

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
      gameId: _selectedGameId ?? checkpoint?.gameId,
      games: _games,
    ));
    final read = ref.watch(provider);
    final games = _games;
    final frame = read.valueOrNull;
    final gameId = frame?.game.id;
    final gameCount = games?.length ?? collection.gameCount;
    final gameIndex = games?.indexWhere((game) => game.id == gameId) ?? -1;
    final browseGameId = gameId ?? _selectedGameId;
    final canBrowse = browseGameId != null && !_browsing && !_opening;
    final needsUpgrade =
        collection.isPremium && !ref.watch(premiumAccessProvider);
    final gameLabel = needsUpgrade
        ? 'Upgrade'
        : checkpoint != null && checkpoint.gameId == gameId
        ? 'Continue'
        : 'Open game';
    VoidCallback? openGame;
    if (!_opening && !_browsing) {
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
                      onPressed: () {
                        ref.invalidate(
                          _collectionStoryGamesProvider(collection.slug),
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
          if (gameCount > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous collection game',
                  onPressed: canBrowse ? () => _browse(browseGameId, -1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  gameIndex >= 0
                      ? 'Game ${gameIndex + 1} of $gameCount'
                      : '$gameCount games',
                ),
                IconButton(
                  tooltip: 'Next collection game',
                  onPressed: canBrowse ? () => _browse(browseGameId, 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          StoryActions(
            gameLabel: gameLabel,
            collectionLabel: storyCollectionAction(collection),
            onOpenGame: openGame,
            onOpenCollection: _opening || _browsing ? null : _openCollection,
          ),
        ],
      ),
    );
  }
}

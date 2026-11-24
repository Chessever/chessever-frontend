import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/feed/news/news_links.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_publications.dart';
import 'package:chessever2/screens/stories/story_visit.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:chessever2/utils/youtube_video.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<StoryBatch> readPublishedStoryBatch(
  Ref ref,
  StoryPublicationKey key,
) async {
  final data = await readStoryPublication(key);
  final source = key.sourceSlug;
  final raw = data?['slides'];
  if (raw is! List) {
    return source == null
        ? StoryBatch(games: const [], ordered: const [])
        : ref.watch(storyBatchProvider(source).future);
  }
  final automatic = data?['mode'] == 'append' && source != null
      ? _automaticBatch(ref, source)
      : Future<StoryBatch?>.value();
  final slides = await Future.wait([
    for (final (i, slide) in raw.take(12).indexed)
      if (slide is Map<String, dynamic>) _publishedChapter(ref, key, i, slide),
  ]);
  final original = await automatic;
  final games = <StoryGame>[...?original?.games];
  final frames = <StoryFrame>[...?original?.frames];
  for (final chapter in slides.nonNulls) {
    final (id, game, media, layers) = chapter;
    final index = frames.isEmpty ? 0 : frames.last.story + 1;
    if (game != null) {
      games.add(game);
      for (var p = 0; p < game.segments.length; p++) {
        frames.add(
          StoryFrame(
            story: index,
            segment: p,
            value: game,
            publicationId: id,
            layers: layers,
          ),
        );
      }
    } else if (media != null) {
      frames.add(
        StoryFrame.media(
          story: index,
          publicationId: id,
          media: media,
          layers: layers,
        ),
      );
    }
  }
  if (frames.isEmpty && source != null) {
    return ref.watch(storyBatchProvider(source).future);
  }
  return StoryBatch(
    games: List.unmodifiable(games),
    ordered: original?.ordered ?? const [],
    featuredGame: true,
    publishedFrames: frames,
  );
}

Future<StoryBatch?> _automaticBatch(Ref ref, String slug) async {
  try {
    return await ref.watch(storyBatchProvider(slug).future);
  } catch (_) {
    return null;
  }
}

typedef _PublishedChapter = (
  String,
  StoryGame?,
  StoryEditorialMedia?,
  List<StoryLayer>,
);

Future<_PublishedChapter?> _publishedChapter(
  Ref ref,
  StoryPublicationKey key,
  int index,
  Map<String, dynamic> slide,
) async {
  final id = '${key.id}/${key.revision}/$index';
  final kind = storyText(slide['kind']);
  if (kind == null) return null;
  final layers = List<StoryLayer>.unmodifiable(
    StoryLayer.read(slide['layers']),
  );
  try {
    if (const {'collection_game', 'game', 'pgn', 'puzzle'}.contains(kind)) {
      final game = await _publishedBoard(
        ref,
        id,
        kind,
        slide,
      ).timeout(kStoryReplayWait);
      return game == null ? null : (id, game, null, layers);
    }
    final media = await _publishedMedia(
      ref,
      kind,
      slide,
    ).timeout(kStoryReplayWait);
    return media == null ? null : (id, null, media, layers);
  } catch (error) {
    debugPrint('[Stories] Published $kind chapter unavailable: $error');
    return null;
  }
}

Future<StoryGame?> _publishedBoard(
  Ref ref,
  String id,
  String kind,
  Map<String, dynamic> slide,
) async {
  final analyzer = ref.read(storyAnalyzerProvider);
  final title = storyText(slide['title']);
  final note = storyText(slide['body']);
  final collectionSlug = storyText(slide['collectionSlug']);
  final gameId = storyText(slide['gameId']);
  var pgn = storyText(slide['pgn']);
  GamesTourModel model;
  StoryBoardSource source;
  String? caption;
  switch (kind) {
    case 'collection_game':
      if (collectionSlug == null || gameId == null) return null;
      final repository = ref.read(collectionsRepositoryProvider);
      final visit = ref.read(storyVisitProvider);
      final games = await ref.watch(
        collectionGamesProvider(collectionSlug).future,
      );
      final selected = games.where((game) => game.id == gameId).firstOrNull;
      if (selected == null) return null;
      final preview = pgn == null
          ? await repository.fetchStoryGames(collectionSlug, day: visit.day)
          : null;
      pgn ??= preview?.where((card) => card.id == gameId).firstOrNull?.pgn;
      caption = storyCaption(selected);
      source = StoryBoardSource.collection;
      model = selected.game;
    case 'game':
      if (gameId == null) return null;
      final game = await ref
          .read(gameRepositoryProvider)
          .getGameByAnyId(gameId);
      pgn = storyText(game.pgn);
      caption = game.eventName ?? game.tourName;
      source = StoryBoardSource.broadcast;
      model = GamesTourModel.fromGame(game);
    default:
      if (pgn == null) return null;
      source = StoryBoardSource.pgn;
      model = chessGameToImportedGamesTourModel(
        ChessGame.fromPgn('imported_today_story_$id', pgn),
      ).copyWith(pgn: pgn);
  }
  if (pgn == null) {
    if (model.fen == null) return null;
    final segment = StorySegment.still(model.fen, null);
    return StoryGame(
      game: model,
      segments: [note == null ? segment : segment.withEditorialNote(note)],
      caption: title ?? caption,
      source: source,
      collectionSlug: collectionSlug,
    );
  }
  final positions = slide['plies'];
  final analysis = (await analyzer([
    StoryAnalysisJob(
      id: id,
      pgn: pgn,
      plies: positions is List
          ? positions.whereType<int>().take(3).toList()
          : const [],
      editorialPuzzle: kind == 'puzzle',
      note: note,
    ),
  ]))[id];
  if (analysis == null || analysis.segments.isEmpty) return null;
  return StoryGame(
    game: model,
    segments: analysis.segments,
    notation: analysis.notation,
    caption: title ?? caption ?? analysis.event,
    source: source,
    collectionSlug: collectionSlug,
  );
}

Future<StoryEditorialMedia?> _publishedMedia(
  Ref ref,
  String kind,
  Map<String, dynamic> slide,
) async {
  if (!const {
    'image',
    'announcement',
    'news',
    'event',
    'video',
    'short',
  }.contains(kind)) {
    return null;
  }
  final newsId = int.tryParse(storyText(slide['newsId']) ?? '');
  final publisher =
      NewsPublisher.ofSource(slide['newsSource']) ?? NewsPublisher.chessever;
  final news = kind == 'news' && newsId != null
      ? await ref.read(newsArticleLoaderProvider)(
          NewsLink(id: newsId, publisher: publisher),
        )
      : null;
  if (kind == 'news' && news == null) return null;
  final alt = storyText(slide['alt']);
  final title =
      storyText(slide['title']) ??
      news?.title ??
      (kind == 'event' ? 'Chess event' : null);
  final shortUrl = kind == 'short' ? storyHttpsUrl(slide['mediaUrl']) : null;
  if (kind == 'short' && shortUrl == null) return null;
  String? defaultPoster;
  if (shortUrl != null && !shortUrl.path.toLowerCase().endsWith('.mp4')) {
    try {
      final youtube = YoutubeVideo.parse(shortUrl.toString());
      defaultPoster = 'https://i.ytimg.com/vi/${youtube.id}/hqdefault.jpg';
    } on FormatException {
      return null;
    }
  }
  final image =
      storyHttpsUrl(slide['imageUrl'] ?? news?.imageUrl) ??
      storyHttpsUrl(news?.imageUrl);
  return StoryEditorialMedia(
    kind: kind,
    title: title ?? '',
    body: storyText(slide['body']) ?? storyText(news?.summary),
    alt: alt,
    eventId: kind == 'event' ? storyText(slide['eventId']) : null,
    imageUrl: image?.toString() ?? defaultPoster,
    link: storyHttpsUrl(slide['linkUrl']),
    news: news,
    shortUrl: shortUrl,
  );
}

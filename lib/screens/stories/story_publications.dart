import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _publicationPrefix = '\u0000today-story/';
const _requestTimeout = Duration(seconds: 4);

/// A published version is part of the circle's identity. A new edit gets a
/// fresh ring, and an open viewer keeps the version it started with.
typedef StoryPublicationKey = ({String id, int revision, String? sourceSlug});

StoryPublicationKey? storyPublicationKey(String slug) {
  if (!slug.startsWith(_publicationPrefix)) return null;
  final parts = slug.substring(_publicationPrefix.length).split('/');
  if (parts.length != 3) return null;
  final revision = int.tryParse(parts[1]);
  if (revision == null) return null;
  return (
    id: parts[0],
    revision: revision,
    sourceSlug: parts[2].isEmpty ? null : Uri.decodeComponent(parts[2]),
  );
}

typedef StoryLineupRequest = ({
  List<Collection> catalog,
  DateTime? missedDay,
  int rotation,
});

/// Null lets an offline app, or one connected to a backend before the
/// migration, use its built-in automatic selection.
final storyPublicationLineupProvider = FutureProvider.autoDispose
    .family<List<Collection>?, StoryLineupRequest>((ref, request) async {
      try {
        final response = await Supabase.instance.client
            .rpc<List<dynamic>>(
              'get_today_stories_v1',
              params: {
                'p_catalog': [
                  for (final c in request.catalog.take(1500))
                    {
                      'slug': c.slug,
                      'game_count': c.gameCount,
                      'updated_at': storyRecency(c)?.toUtc().toIso8601String(),
                    },
                ],
                'p_rotation': request.rotation,
                'p_has_missed_chances': request.missedDay != null,
              },
            )
            .timeout(_requestTimeout);
        return readStoryLineup(
          response,
          request.catalog,
          request.missedDay == null
              ? null
              : missedChancesCollection(request.missedDay!),
        );
      } catch (error) {
        debugPrint('[Stories] Lineup unavailable: $error');
        return null;
      }
    });

List<Collection> readStoryLineup(
  List<dynamic> entries,
  List<Collection> catalog,
  Collection? missed,
) {
  final bySlug = {for (final c in catalog) c.slug: c};
  final circles = <String, Collection>{};
  for (final value in entries.take(kStoryLineupSize)) {
    if (value is! Map<String, dynamic>) continue;
    final source = bySlug[value['collectionSlug']];
    final circle = switch (value['kind']) {
      'missed_chances' => missed,
      'collection' => source,
      'editorial' => _editorialCircle(value, source),
      _ => null,
    };
    if (circle != null) circles[circle.slug] = circle;
  }
  return List.unmodifiable(circles.values);
}

Collection? _editorialCircle(Map<String, dynamic> row, Collection? source) {
  final id = storyText(row['id']);
  final revision = row['revision'];
  final title = storyText(row['title']) ?? source?.title;
  if (id == null || revision is! int || title == null) return null;
  if (row['mode'] != 'standalone' && source == null) return null;
  final sourcePart = Uri.encodeComponent(source?.slug ?? '');
  return Collection(
    id: source?.id ?? id,
    slug: '$_publicationPrefix$id/$revision/$sourcePart',
    title: title,
    kind: source?.kind ?? CollectionKind.analysis,
    coverUrl: storyHttpsUrl(row['coverUrl'])?.toString() ?? source?.coverUrl,
    gameCount: source?.gameCount ?? 0,
    contentVersion: 'story:$id:$revision:${source?.contentVersion ?? ''}',
    access: source?.access ?? CollectionAccess.free,
  );
}

Future<Map<String, dynamic>?> readStoryPublication(
  StoryPublicationKey key,
) async {
  final row = await Supabase.instance.client
      .from('today_story_publications')
      .select('story')
      .eq('id', key.id)
      .eq('revision', key.revision)
      .maybeSingle()
      .timeout(_requestTimeout);
  final story = row?['story'];
  return story is Map<String, dynamic> ? story : null;
}

Future<String?> pickPublishedStoryGame(
  List<({String id, bool watched})> candidates,
  String? preferredId,
) async {
  if (candidates.length < 2) return null;
  try {
    return await Supabase.instance.client
        .rpc<String?>(
          'pick_today_story_game_v1',
          params: {
            'p_candidates': [
              for (final c in candidates) {'id': c.id, 'watched': c.watched},
            ],
            'p_preferred_id': preferredId,
          },
        )
        .timeout(const Duration(seconds: 2));
  } catch (_) {
    return null;
  }
}

@immutable
class StoryEditorialMedia {
  const StoryEditorialMedia({
    required this.kind,
    required this.title,
    this.body,
    this.imageUrl,
    this.alt,
    this.link,
    this.news,
    this.eventId,
    this.shortUrl,
  });

  final String kind;
  final String title;
  final String? body;
  final String? imageUrl;
  final String? alt;
  final Uri? link;
  final FeedNews? news;
  final String? eventId;
  final Uri? shortUrl;

  String? get action => switch (kind) {
    'news' when news != null => 'Read article',
    'event' when eventId != null => 'Open event',
    'video' when link != null => 'Watch video',
    'short' when link != null => 'Open link',
    'short' when shortUrl != null => 'Open video',
    _ when link != null => 'Open link',
    _ => null,
  };

  Duration get duration =>
      Duration(seconds: (6 + (body?.length ?? 0) ~/ 28).clamp(6, 30));
}

@immutable
class StoryLayer {
  const StoryLayer({
    required this.kind,
    required this.text,
    required this.x,
    required this.y,
    required this.size,
    required this.tone,
    this.link,
  });

  final String kind;
  final String text;
  final double x;
  final double y;
  final String size;
  final String tone;
  final Uri? link;

  static List<StoryLayer> read(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final layer in raw.take(8))
        if (_fromRow(layer) case final parsed?) parsed,
    ];
  }

  static StoryLayer? _fromRow(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final kind = storyText(raw['kind']);
    final text = storyText(raw['text']);
    final x = raw['x'];
    final y = raw['y'];
    if (kind == null ||
        !const {'text', 'emoji', 'link'}.contains(kind) ||
        text == null ||
        x is! num ||
        y is! num) {
      return null;
    }
    final link = kind == 'link' ? storyHttpsUrl(raw['linkUrl']) : null;
    if (kind == 'link' && link == null) return null;
    return StoryLayer(
      kind: kind,
      text: text,
      x: x.toDouble().clamp(0, 1),
      y: y.toDouble().clamp(0, 1),
      size: storyText(raw['size']) ?? 'medium',
      tone: storyText(raw['tone']) ?? 'light',
      link: link,
    );
  }
}

String? storyText(Object? value) => switch (value) {
  String() when value.trim().isNotEmpty => value.trim(),
  _ => null,
};

Uri? storyHttpsUrl(Object? value) {
  final text = storyText(value);
  final uri = text == null ? null : Uri.tryParse(text);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

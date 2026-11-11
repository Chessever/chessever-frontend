import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NewsGroupArticle {
  const NewsGroupArticle({
    required this.id,
    required this.title,
    required this.publishedAt,
    this.groupBroadcastId,
  });
  final int id;
  final String title;
  final DateTime publishedAt;
  final String? groupBroadcastId;
}

class NewsGroupPage {
  const NewsGroupPage(
    this.items, {
    required this.hasMore,
    this.groupBroadcastId,
  });
  final List<NewsGroupArticle> items;
  final bool hasMore;
  final String? groupBroadcastId;
}

final newsGroupRepositoryProvider = Provider((ref) => NewsGroupRepository());

/// Uses the web's published UTC-day scope: parent group, tour, round, game.
/// The server group key is authoritative; no parent inference. Bodies are
/// fetched only when a reader selects a sibling.
class NewsGroupRepository {
  NewsGroupRepository({this.client});
  final SupabaseClient? client;
  static const pageSize = 20;

  Future<NewsGroupPage> load(int articleId, {int offset = 0}) async {
    final client = this.client ?? Supabase.instance.client;
    final anchor = await client
        .from('news_group_articles')
        .select('group_day,group_key,group_broadcast_id')
        .eq('source', 'news')
        .eq('id', articleId)
        .maybeSingle()
        .timeout(const Duration(seconds: 12));
    if (anchor == null || anchor['group_day'] == null) {
      return const NewsGroupPage([], hasMore: false);
    }
    final rows = await client
        .from('news_group_articles')
        .select('id,title,feed_published_at,group_broadcast_id')
        .eq('source', 'news')
        .eq('group_day', anchor['group_day'])
        .eq('group_key', anchor['group_key'])
        .neq('id', articleId)
        .order('feed_published_at', ascending: false)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + pageSize)
        .timeout(const Duration(seconds: 12));
    return NewsGroupPage(
      [
        for (final row in rows.take(pageSize))
          NewsGroupArticle(
            id: row['id'] as int,
            groupBroadcastId: row['group_broadcast_id'] as String?,
            title: (row['title'] as String?)?.trim().isNotEmpty == true
                ? (row['title'] as String).trim()
                : 'Chess news',
            publishedAt: DateTime.parse(row['feed_published_at'] as String),
          ),
      ],
      hasMore: rows.length > pageSize,
      groupBroadcastId: anchor['group_broadcast_id'] as String?,
    );
  }
}

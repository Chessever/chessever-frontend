import 'package:chessever2/utils/png_asset.dart';
import 'package:flutter/foundation.dart';

/// Who published an article in the Feed: ChessEver itself (the `news`
/// table), or a partner publication whose articles `partner-news-sync`
/// brings into `partner_news`. A partner's articles carry its name and mark
/// and link back to its site.
///
/// The app shows only partners listed here: a `partner_news` source this
/// build does not know is left out rather than shown unbranded.
enum NewsPublisher {
  chessever(name: 'ChessEver News'),
  rookReview(
    name: 'RookReview',
    sourceId: 'rookreview',
    siteHost: 'rookreview.com',
    imageHosts: {'rookreview.com', 'rookreview.b-cdn.net'},
    mark: PngAsset.rookReviewMark,
    markAspectRatio: 102 / 113,
    coverAspectRatio: 675 / 300,
  );

  const NewsPublisher({
    required this.name,
    this.sourceId,
    this.siteHost,
    this.imageHosts = const {},
    this.mark,
    this.markAspectRatio = 1,
    this.coverAspectRatio,
  });

  /// As the publisher writes it, shown on its articles.
  final String name;

  /// `partner_news_sources.id`; null for ChessEver.
  final String? sourceId;

  /// The partner's site: its articles must live on it (or a subdomain).
  final String? siteHost;

  /// Hosts the partner's pictures load from.
  final Set<String> imageHosts;

  /// The partner's own mark, as published.
  final String? mark;
  final double markAspectRatio;

  /// The shape of the partner's covers. RookReview's are 675x300: drawn at
  /// that shape they are whole and sharp, where the Feed's tall full-bleed
  /// crop would blow them up five times and cut people out of them.
  final double? coverAspectRatio;

  bool get isPartner => sourceId != null;

  /// The partner a `partner_news.source_id` names, if this build knows it.
  static NewsPublisher? ofSource(Object? sourceId) {
    if (sourceId is! String) return null;
    for (final publisher in values) {
      if (publisher.sourceId == sourceId) return publisher;
    }
    return null;
  }

  /// Every partner's `source_id`, for the `partner_news` query.
  static List<String> get partnerSourceIds => [
    for (final publisher in values)
      if (publisher.sourceId case final String id) id,
  ];

  /// Whether [uri] is on this partner's site.
  bool ownsUri(Uri uri) {
    final site = siteHost;
    if (site == null) return false;
    final host = uri.host.toLowerCase();
    return host == site || host.endsWith('.$site');
  }
}

/// An article in the Feed: a published ChessEver News article (the web's
/// `news` table, status 'published'), or a partner's ([publisher]) from
/// `partner_news`.
///
/// ChessEver articles are built by `normalizeNewsRow` so title, summary and
/// content are cleaned the same way chessever.com cleans them, and [webUrl]
/// matches the web's canonical `/news/<id>/<slug>` path. Partner articles
/// are built by `normalizePartnerNewsRow`; their [webUrl] is the article on
/// the partner's site.
@immutable
class FeedNews {
  const FeedNews({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    required this.publishedAt,
    this.imageUrl,
    this.webUrl,
    this.updatedAt,
    this.sourceUrl,
    this.publisher = NewsPublisher.chessever,
  });

  /// The row id in [publisher]'s table: ids of different publishers can
  /// coincide, so tell articles apart by [key].
  final int id;
  final String title;

  /// May be empty when the row has no summary and the content is markers only.
  final String summary;

  /// Markdown body, paragraph-normalised like the web (`cleanContent`).
  final String content;
  final DateTime publishedAt;
  final String? imageUrl;

  /// `https://chessever.com/news/<id>/<slug>`, or for a partner's article
  /// the article on its site.
  final String? webUrl;

  /// Last edit; equals [publishedAt] when the row carries none.
  final DateTime? updatedAt;

  /// The row's `source_url` as stored (the web's `sourceUrl`): the event,
  /// standings or outside page the story is about. Resolve it with
  /// `newsSourceContextHref` before showing it.
  final String? sourceUrl;

  final NewsPublisher publisher;

  /// Unique across publishers: `7` for ChessEver's article 7 (as it always
  /// was), `rookreview:7` for RookReview's.
  String get key => publisher.isPartner ? '${publisher.sourceId}:$id' : '$id';

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'summary': summary,
    'content': content,
    'publishedAt': publishedAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'imageUrl': imageUrl,
    'webUrl': webUrl,
    'sourceUrl': sourceUrl,
    if (publisher.isPartner) 'publisher': publisher.sourceId,
  };

  /// Reads one cached item back; null when the entry is not a complete item.
  static FeedNews? fromJson(Object? json) {
    if (json is! Map) return null;
    // Absent before partners existed: ChessEver's own article.
    final publisher = json['publisher'] == null
        ? NewsPublisher.chessever
        : NewsPublisher.ofSource(json['publisher']);
    if (publisher == null) return null;
    final id = json['id'];
    final title = json['title'];
    final summary = json['summary'];
    final content = json['content'];
    final publishedAt = json['publishedAt'] is String
        ? DateTime.tryParse(json['publishedAt'] as String)
        : null;
    if (id is! int ||
        title is! String ||
        title.isEmpty ||
        summary is! String ||
        content is! String ||
        content.isEmpty ||
        publishedAt == null) {
      return null;
    }
    final updatedAt = json['updatedAt'] is String
        ? DateTime.tryParse(json['updatedAt'] as String)
        : null;
    final imageUrl = json['imageUrl'];
    final webUrl = json['webUrl'];
    final sourceUrl = json['sourceUrl'];
    return FeedNews(
      id: id,
      title: title,
      summary: summary,
      content: content,
      publishedAt: publishedAt,
      updatedAt: updatedAt,
      imageUrl: imageUrl is String && imageUrl.isNotEmpty ? imageUrl : null,
      webUrl: webUrl is String && webUrl.isNotEmpty ? webUrl : null,
      sourceUrl: sourceUrl is String && sourceUrl.isNotEmpty ? sourceUrl : null,
      publisher: publisher,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedNews &&
          other.id == id &&
          other.title == title &&
          other.summary == summary &&
          other.content == content &&
          other.publishedAt == publishedAt &&
          other.updatedAt == updatedAt &&
          other.imageUrl == imageUrl &&
          other.webUrl == webUrl &&
          other.sourceUrl == sourceUrl &&
          other.publisher == publisher;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    summary,
    content,
    publishedAt,
    updatedAt,
    imageUrl,
    webUrl,
    sourceUrl,
    publisher,
  );

  @override
  String toString() => 'FeedNews($key, $title)';
}

/// Byline resolved from a `<!-- news-author: ... -->` marker.
@immutable
class NewsAuthor {
  const NewsAuthor({required this.displayName, required this.role});

  final String displayName;
  final String role;
}

// -----------------------------------------------------------------------------
// Rich content blocks (port of the web's news-rich-content.ts)
// -----------------------------------------------------------------------------

/// One block of an article body, in order.
@immutable
sealed class NewsBlock {
  const NewsBlock();
}

/// A prose paragraph (markdown in the app).
final class NewsParagraphBlock extends NewsBlock {
  const NewsParagraphBlock(this.text);
  final String text;

  @override
  bool operator ==(Object other) =>
      other is NewsParagraphBlock && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'paragraph($text)';
}

/// A `<!-- news-section: ... -->` heading.
final class NewsSectionBlock extends NewsBlock {
  const NewsSectionBlock(this.text);
  final String text;

  @override
  bool operator ==(Object other) =>
      other is NewsSectionBlock && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'section($text)';
}

/// A `<!-- news-youtube: <11-char id> -->` embed.
final class NewsYoutubeBlock extends NewsBlock {
  const NewsYoutubeBlock(this.videoId);
  final String videoId;

  @override
  bool operator ==(Object other) =>
      other is NewsYoutubeBlock && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;

  @override
  String toString() => 'youtube($videoId)';
}

/// A validated team-results snapshot.
final class NewsResultsBlock extends NewsBlock {
  const NewsResultsBlock(this.snapshot);
  final NewsResultsSnapshot snapshot;
}

/// A validated team-pairings snapshot.
final class NewsPairingsBlock extends NewsBlock {
  const NewsPairingsBlock(this.snapshot);
  final NewsPairingsSnapshot snapshot;
}

/// A merged run of prose paragraphs, sanitised for the markdown renderer.
/// Only produced by `newsReaderBlocks`, never by `newsContentBlocks`.
final class NewsMarkdownBlock extends NewsBlock {
  const NewsMarkdownBlock(this.markdown);
  final String markdown;

  @override
  bool operator ==(Object other) =>
      other is NewsMarkdownBlock && other.markdown == markdown;

  @override
  int get hashCode => markdown.hashCode;

  @override
  String toString() => 'markdown($markdown)';
}

@immutable
class NewsTeam {
  const NewsTeam({required this.name, required this.federation, this.seed});

  final String name;

  /// FIDE federation code, e.g. `USA`.
  final String federation;
  final int? seed;
}

/// Official board disposition; legacy snapshots are always [played].
enum NewsBoardStatus { played, forfeit, notPlayed }

@immutable
class NewsResultGame {
  const NewsResultGame({
    required this.board,
    required this.playerA,
    required this.playerB,
    required this.colorA,
    required this.result,
    this.status = NewsBoardStatus.played,
    this.titleA,
    this.ratingA,
    this.titleB,
    this.ratingB,
  });

  final int board;
  final String playerA;
  final String playerB;

  /// `w`, `b` or empty when unknown.
  final String colorA;

  /// From team A's side: `1-0`, `0-1`, `0.5-0.5` or `0-0`.
  final String result;
  final NewsBoardStatus status;
  final String? titleA;
  final int? ratingA;
  final String? titleB;
  final int? ratingB;
}

@immutable
class NewsResultsMatch {
  const NewsResultsMatch({
    required this.teamA,
    required this.teamB,
    required this.score,
    required this.games,
  });

  final NewsTeam teamA;
  final NewsTeam teamB;

  /// Team A's score first, `.5` for halves (e.g. `2.5-1.5`).
  final String score;
  final List<NewsResultGame> games;
}

@immutable
class NewsResultsSnapshot {
  const NewsResultsSnapshot({
    required this.version,
    required this.title,
    required this.matches,
    this.round,
    this.sourceUrl,
    this.lastUpdate,
    this.notPaired = const [],
  });

  final int version;
  final String title;
  final List<NewsResultsMatch> matches;
  final int? round;
  final String? sourceUrl;
  final String? lastUpdate;
  final List<NewsTeam> notPaired;
}

@immutable
class NewsPairingGame {
  const NewsPairingGame({
    required this.board,
    required this.playerA,
    required this.playerB,
    required this.colorA,
    this.titleA,
    this.ratingA,
    this.titleB,
    this.ratingB,
  });

  final int board;
  final String playerA;
  final String playerB;

  /// `w` or `b`.
  final String colorA;
  final String? titleA;
  final int? ratingA;
  final String? titleB;
  final int? ratingB;
}

@immutable
class NewsPairingsMatch {
  const NewsPairingsMatch({
    required this.teamA,
    required this.teamB,
    required this.games,
  });

  final NewsTeam teamA;
  final NewsTeam teamB;

  /// Empty while boards are pending, otherwise four boards.
  final List<NewsPairingGame> games;
}

@immutable
class NewsPairingsSnapshot {
  const NewsPairingsSnapshot({
    required this.title,
    required this.matches,
    required this.round,
    required this.sourceUrl,
    required this.lastUpdate,
    this.notPaired = const [],
    this.byes = const [],
  });

  final String title;
  final List<NewsPairingsMatch> matches;
  final int round;
  final String sourceUrl;
  final String lastUpdate;
  final List<NewsTeam> notPaired;
  final List<NewsTeam> byes;
}

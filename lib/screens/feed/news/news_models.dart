import 'package:flutter/foundation.dart';

/// A published ChessEver News article (the web's `news` table, status
/// 'published'), shown in the Feed.
///
/// Built by `normalizeNewsRow` so title, summary and content are cleaned the
/// same way chessever.com cleans them, and [webUrl] matches the web's
/// canonical `/news/<id>/<slug>` path.
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
  });

  final int id;
  final String title;

  /// May be empty when the row has no summary and the content is markers only.
  final String summary;

  /// Markdown body, paragraph-normalised like the web (`cleanContent`).
  final String content;
  final DateTime publishedAt;
  final String? imageUrl;

  /// `https://chessever.com/news/<id>/<slug>`
  final String? webUrl;

  /// Last edit; equals [publishedAt] when the row carries none.
  final DateTime? updatedAt;

  /// The row's `source_url` as stored (the web's `sourceUrl`): the event,
  /// standings or outside page the story is about. Resolve it with
  /// `newsSourceContextHref` before showing it.
  final String? sourceUrl;

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
  };

  /// Reads one cached item back; null when the entry is not a complete item.
  static FeedNews? fromJson(Object? json) {
    if (json is! Map) return null;
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
          other.sourceUrl == sourceUrl;

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
  );

  @override
  String toString() => 'FeedNews($id, $title)';
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

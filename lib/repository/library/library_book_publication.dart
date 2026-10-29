import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show immutable;

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/config/gamebase_environment.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart'
    show kTwicBookId, kMiniaturesBookId;

/// Link sharing and catalog publication are independent. A share token alone
/// never makes a folder a public book.
bool libraryFolderCanPublish(LibraryFolder folder) =>
    !folder.isSubscribed &&
    !folder.isLikedGames &&
    folder.id != kTwicBookId &&
    folder.id != kMiniaturesBookId;

/// Who a collection's author credit names: the publishing account itself
/// ([self], pictured by its profile photo) or someone it publishes for
/// ([other], pictured by the collection's own author photo).
enum LibraryAuthorCredit {
  self,
  other;

  String get wire => name;
  static LibraryAuthorCredit? maybeParse(Object? raw) => switch (raw) {
    'self' => self,
    'other' => other,
    _ => null,
  };

  static LibraryAuthorCredit parse(Object? raw) =>
      raw == 'other' ? LibraryAuthorCredit.other : LibraryAuthorCredit.self;
}

/// One credited author of a collection: the name readers see and, when one
/// was uploaded, their own photo. Every author carries their own credit,
/// like the first author always could: [LibraryAuthorCredit.self] is their own
/// ChessEver account (linked by [userId]/[authProject] when it is not the
/// publishing account), pictured by its profile photo; [LibraryAuthorCredit.other]
/// credits the person, pictured by [photoUrl].
@immutable
class LibraryBookAuthor {
  const LibraryBookAuthor({
    required this.name,
    this.photoUrl = '',
    this.id = '',
    this.about,
    this.credit,
    this.userId,
    this.authProject,
  });

  final String name;
  final String photoUrl;

  /// The catalog identity (`account:`/`credit:`) the author's collections
  /// are filed under, when the server sent one.
  final String id;

  /// This author's description, when the payload carries one (a book's own
  /// detail and editor answers; list rows omit it). Null leaves it alone.
  final String? about;

  /// This author's own credit, when the payload carries one.
  final LibraryAuthorCredit? credit;

  /// The ChessEver account a `self` author is linked to (editor answers
  /// only; never on a public one).
  final String? userId;
  final String? authProject;

  bool get hasAccountLink => userId != null && authProject != null;

  @override
  bool operator ==(Object other) =>
      other is LibraryBookAuthor &&
      other.name == name &&
      other.photoUrl == photoUrl &&
      other.id == id &&
      other.about == about &&
      other.credit == credit &&
      other.userId == userId &&
      other.authProject == authProject;

  @override
  int get hashCode =>
      Object.hash(name, photoUrl, id, about, credit, userId, authProject);
}

/// How several authors read on one line: "A", "A and B", "A, B and C".
/// Blank names are skipped; no names give an empty string.
String bookAuthorCredit(Iterable<String> names) {
  final named = [
    for (final name in names)
      if (name.trim().isNotEmpty) name.trim(),
  ];
  if (named.length <= 1) return named.join();
  return '${named.take(named.length - 1).join(', ')} and ${named.last}';
}

/// The most authors one collection can credit, the first one included.
const libraryBookMaxAuthors = 6;

class LibraryBookMetadata {
  final Map<String, String>? gameVideos;
  final Map<String, String>? gameVideoLanguages;
  const LibraryBookMetadata({
    required this.title,
    this.gameVideos,
    this.gameVideoLanguages,
    this.subtitle = '',
    this.slug,
    this.annotator,
    this.author = '',
    this.about = '',
    this.foreword = '',
    this.publisher = '',
    this.publishedYear,
    this.coverUrl = '',
    this.authorCredit,
    this.authorPhotoUrl = '',
    this.coAuthors = const [],
    this.sendAuthorList = false,
    this.authorAbout,
    this.authorUserId,
    this.authorAuthProject,
  });

  final String title;
  final String subtitle;
  final String? slug;
  final String? annotator;
  final String author;
  final String about;
  final String foreword;
  final String publisher;
  final int? publishedYear;
  final String coverUrl;

  /// null means the key is absent from the save body entirely — the only safe
  /// value for an old server that rejects unknown keys with 400, and for a new
  /// book that never left "Me". [LibraryAuthorCredit.self]/[LibraryAuthorCredit.other] are
  /// sent verbatim: "other" when the user credited someone else, "self" (which
  /// also tells the server to drop any credited photo) when a book that
  /// already carried the key is switched back to Me.
  final LibraryAuthorCredit? authorCredit;

  /// The credited author's own photo, distinct from the cover and from the
  /// publishing account's profile photo. Empty when none is set.
  final String authorPhotoUrl;

  /// Everyone credited after the first author, in order. [author] and
  /// [authorPhotoUrl] stay the first author's, so a one-author collection
  /// reads and saves exactly as it always did.
  final List<LibraryBookAuthor> coAuthors;

  /// Whether a save writes the whole author list. Only set when there is more
  /// than one author, or the saved collection had more than one (so removing
  /// them reaches the server): an older server refuses the unknown key.
  final bool sendAuthorList;

  /// The first author's description of themselves, shown on their author
  /// page and under "About the author". Null when the server predates it (it
  /// then refuses the key), so it is only sent when known or when one is
  /// written.
  final String? authorAbout;

  /// The ChessEver account the first author is linked to when they are
  /// credited as themselves but are not the publishing account.
  final String? authorUserId;
  final String? authorAuthProject;

  bool get authorHasAccountLink =>
      authorUserId != null && authorAuthProject != null;

  /// Every credited author, the first one included.
  List<LibraryBookAuthor> get authors => [
    if (author.trim().isNotEmpty || coAuthors.isNotEmpty)
      LibraryBookAuthor(
        name: author.trim(),
        photoUrl: authorPhotoUrl,
        about: authorAbout,
        credit: authorHasAccountLink ? LibraryAuthorCredit.self : authorCredit,
        userId: authorUserId,
        authProject: authorAuthProject,
      ),
    ...coAuthors,
  ];

  /// The author list of a book payload, or empty when the server sent none.
  static List<LibraryBookAuthor> _authorsOf(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map && (item['name'] as Object?) is String)
          if ((item['name'] as String).trim().isNotEmpty)
            LibraryBookAuthor(
              name: (item['name'] as String).trim(),
              photoUrl: item['photoUrl'] as String? ?? '',
              id: item['id'] as String? ?? '',
              about: item['about'] as String?,
              credit: LibraryAuthorCredit.maybeParse(item['credit']),
              userId: item['userId'] as String?,
              authProject: item['authProject'] as String?,
            ),
    ];
  }

  factory LibraryBookMetadata.fromJson(Map<String, dynamic> json) {
    // With an author list the legacy `author` is every name joined for old
    // clients; the first entry is the one this form's name field edits.
    final listed = _authorsOf(json['authors']);
    return LibraryBookMetadata(
      gameVideos: json['gameVideos'] is Map
          ? Map<String, String>.from(json['gameVideos'] as Map)
          : null,
      gameVideoLanguages: json['gameVideoLanguages'] is Map
          ? Map<String, String>.from(json['gameVideoLanguages'] as Map)
          : null,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      slug: json['slug'] as String?,
      annotator: json.containsKey('annotator')
          ? json['annotator'] as String? ?? ''
          : null,
      author: listed.isNotEmpty
          ? listed.first.name
          : json['author'] as String? ?? '',
      about: json['about'] as String? ?? '',
      foreword: json['foreword'] as String? ?? '',
      publisher: json['publisher'] as String? ?? '',
      publishedYear: (json['publishedYear'] as num?)?.toInt(),
      coverUrl: json['coverUrl'] as String? ?? '',
      authorCredit: LibraryAuthorCredit.maybeParse(json['authorCredit']),
      authorPhotoUrl: listed.isNotEmpty && listed.first.photoUrl.isNotEmpty
          ? listed.first.photoUrl
          : json['authorPhotoUrl'] as String? ?? '',
      coAuthors: listed.skip(1).toList(growable: false),
      sendAuthorList:
          listed.length > 1 || listed.any((author) => author.hasAccountLink),
      authorAbout: json.containsKey('authorBio')
          ? json['authorBio'] as String? ?? ''
          : listed.isNotEmpty
          ? listed.first.about
          : null,
      authorUserId: listed.isNotEmpty ? listed.first.userId : null,
      authorAuthProject: listed.isNotEmpty ? listed.first.authProject : null,
    );
  }

  LibraryBookMetadata copyWith({
    String? author,
    LibraryAuthorCredit? authorCredit,
    bool clearAuthorCredit = false,
    String? authorPhotoUrl,
    List<LibraryBookAuthor>? coAuthors,
    bool? sendAuthorList,
    String? authorUserId,
    String? authorAuthProject,
    bool clearAuthorLink = false,
  }) => LibraryBookMetadata(
    title: title,
    gameVideos: gameVideos,
    gameVideoLanguages: gameVideoLanguages,
    subtitle: subtitle,
    slug: slug,
    annotator: annotator,
    author: author ?? this.author,
    about: about,
    foreword: foreword,
    publisher: publisher,
    publishedYear: publishedYear,
    coverUrl: coverUrl,
    authorCredit: clearAuthorCredit
        ? null
        : (authorCredit ?? this.authorCredit),
    authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
    coAuthors: coAuthors ?? this.coAuthors,
    sendAuthorList: sendAuthorList ?? this.sendAuthorList,
    authorAbout: authorAbout,
    authorUserId: clearAuthorLink ? null : (authorUserId ?? this.authorUserId),
    authorAuthProject: clearAuthorLink
        ? null
        : (authorAuthProject ?? this.authorAuthProject),
  );

  Map<String, dynamic> toJson() => {
    if (gameVideos != null) 'gameVideos': gameVideos,
    if (gameVideoLanguages != null) 'gameVideoLanguages': gameVideoLanguages,
    'title': title.trim(),
    'subtitle': _nullable(subtitle),
    if (slug != null && slug!.trim().isNotEmpty) 'slug': slug!.trim(),
    if (annotator != null) 'annotator': _nullable(annotator!),
    'author': _nullable(author),
    'about': _nullable(about),
    'foreword': _nullable(foreword),
    'publisher': _nullable(publisher),
    'publishedYear': publishedYear,
    'coverUrl': _nullable(coverUrl),
    // Omit the key unless it must travel: old servers 400 on unknown keys, so
    // a new "Me" book sends nothing. authorPhotoUrl is never written here — it
    // is only ever changed through the author-photo upload/remove endpoints.
    if (authorCredit != null) 'authorCredit': authorCredit!.wire,
    // Null clears what this collection wrote about its first author.
    if (authorAbout != null) 'authorAbout': _nullable(authorAbout!),
    // Each photo is changed through the author-photo endpoints, and the
    // server keeps a photo with its name when the list is edited. An empty
    // list is refused; with nobody left to credit, the null `author` above
    // is what clears the credit.
    if (sendAuthorList && _creditedNames.isNotEmpty)
      'authors': [
        for (final credited in authors)
          if (credited.name.trim().isNotEmpty)
            {
              'name': credited.name.trim(),
              if (credited.about != null) 'about': _nullable(credited.about!),
              if (credited.credit != null) 'credit': credited.credit!.wire,
              if (credited.hasAccountLink) 'userId': credited.userId,
              if (credited.hasAccountLink) 'authProject': credited.authProject,
            },
      ],
  };

  List<String> get _creditedNames => [
    for (final credited in authors)
      if (credited.name.trim().isNotEmpty) credited.name.trim(),
  ];

  static String? _nullable(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

/// Where a draft stands with ChessEver staff. A submission is not a status:
/// the book stays a draft, [pending] while it waits and [changesRequested]
/// once staff send it back with a note.
enum LibraryBookReviewState { none, pending, changesRequested }

/// The review round of a draft, as the server answers it. Servers that
/// predate reviews omit it; that reads as [none].
class LibraryBookReview {
  const LibraryBookReview({
    this.state = LibraryBookReviewState.none,
    this.submittedAt,
    this.note = '',
    this.decidedAt,
  });

  static const none = LibraryBookReview();

  final LibraryBookReviewState state;

  /// When it was last submitted; null unless it is pending.
  final DateTime? submittedAt;

  /// What staff asked to change; empty unless it was sent back.
  final String note;

  /// When staff sent it back; null unless it was sent back.
  final DateTime? decidedAt;

  factory LibraryBookReview.fromJson(Object? raw) {
    if (raw is! Map) return none;
    DateTime? when(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toLocal() : null;
    final note = raw['note'];
    return switch (raw['state']) {
      'pending' => LibraryBookReview(
        state: LibraryBookReviewState.pending,
        submittedAt: when(raw['submittedAt']),
      ),
      // Sent back without a note is not a state the author could act on.
      'changes_requested' when note is String && note.trim().isNotEmpty =>
        LibraryBookReview(
          state: LibraryBookReviewState.changesRequested,
          // The server caps a note at 1,000 characters; never trust that
          // with the dialog's layout.
          note: note.trim().length > 1000
              ? '${note.trim().substring(0, 1000)}…'
              : note.trim(),
          decidedAt: when(raw['decidedAt']),
        ),
      _ => none,
    };
  }
}

class LibraryBookPublication {
  const LibraryBookPublication({
    required this.status,
    required this.metadata,
    this.bookId,
    this.gameCount = 0,
    this.review = LibraryBookReview.none,
  });

  final String status;
  final LibraryBookMetadata metadata;
  final String? bookId;
  final int gameCount;
  final LibraryBookReview review;
  bool get isPublished => status == 'published';

  factory LibraryBookPublication.fromJson(
    Map<String, dynamic> json, {
    required String fallbackTitle,
  }) {
    final status = json['status'];
    if (!const {
      'unpublished',
      'draft',
      'published',
      'archived',
    }.contains(status)) {
      throw const FormatException('Unknown book publication state');
    }
    final rawBook = json['book'];
    final book = rawBook is Map ? Map<String, dynamic>.from(rawBook) : null;
    return LibraryBookPublication(
      status: status as String,
      metadata: book == null
          ? LibraryBookMetadata(title: fallbackTitle)
          : LibraryBookMetadata.fromJson(book),
      bookId: book?['id'] as String?,
      gameCount: (book?['gameCount'] as num?)?.toInt() ?? 0,
      review: LibraryBookReview.fromJson(book?['review']),
    );
  }
}

abstract class LibraryBookPublisher {
  bool get isConfigured;
  Future<LibraryBookPublication> load(LibraryFolder folder);
  Future<LibraryBookPublication> save(
    LibraryFolder folder,
    LibraryBookMetadata metadata, {
    bool publish = false,
    bool refreshGames = false,
  });
  Future<LibraryBookPublication> unpublish(LibraryFolder folder);
  Future<void> unpublishTree(LibraryFolder folder);

  /// The collection's own cover (shown in collection cards), never the
  /// profile photo. [image] is a prepared 2:3 image; the book's details must
  /// have been saved once.
  Future<LibraryBookPublication> uploadCover(
    LibraryFolder folder,
    Uint8List image,
  );
  Future<LibraryBookPublication> removeCover(LibraryFolder folder);

  /// The photo of the person the collection is credited to when it is
  /// published in someone else's name: a prepared square, separate from the
  /// cover and from the profile photo. Uploading credits someone else.
  Future<LibraryBookPublication> uploadAuthorPhoto(
    LibraryFolder folder,
    Uint8List image, {
    int index = 0,
  });
  Future<LibraryBookPublication> removeAuthorPhoto(
    LibraryFolder folder, {
    int index = 0,
  });

  /// Existing ChessEver authors a word of [name] starts, so a credited name
  /// keeps the spelling their other collections use. Never throws: any
  /// failure is simply no suggestions.
  Future<List<LibraryAuthorSuggestion>> suggestAuthors(String name);
}

class LibraryAuthorSuggestion {
  const LibraryAuthorSuggestion({
    required this.id,
    required this.name,
    this.bookCount = 0,
    this.avatarUrl,
    this.userId,
    this.authProject,
  });

  final String id;
  final String name;
  final int bookCount;
  final String? avatarUrl;
  final String? userId;
  final String? authProject;
  bool get hasAccount => userId != null && authProject != null;

  /// Null for a row that is not a usable suggestion.
  static LibraryAuthorSuggestion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] as String? ?? '').trim();
    if (name.isEmpty) return null;
    final avatar = raw['avatarUrl'];
    final uri = avatar is String ? Uri.tryParse(avatar) : null;
    return LibraryAuthorSuggestion(
      id: raw['id'] as String? ?? name,
      name: name,
      bookCount: (raw['bookCount'] as num?)?.toInt() ?? 0,
      userId: raw['userId'] as String?,
      authProject: raw['authProject'] as String?,
      avatarUrl: uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
          ? avatar as String
          : null,
    );
  }
}

typedef LibraryAuthorSuggestionRequest =
    Future<Map<String, dynamic>> Function({
      required String name,
      required int limit,
      required String bearer,
    });

class LibraryBookPublicationException implements Exception {
  const LibraryBookPublicationException(this.message);
  final String message;
}

typedef LibraryPublicationApiRequest =
    Future<Map<String, dynamic>> Function({
      required String folderId,
      required String method,
      required String bearer,
      Map<String, dynamic>? body,
      Map<String, dynamic>? query,
      required String resource,
    });

/// Uses the native production client or the explicitly configured test bridge,
/// with the current user's session and no fallback endpoint.
class GamebaseLibraryBookPublisher implements LibraryBookPublisher {
  GamebaseLibraryBookPublisher({
    required this.dio,
    required String? baseUrl,
    required this.accessToken,
    this.apiRequest,
    this.suggestionRequest,
    bool production = false,
  }) : _baseUrl = baseUrl == null
           ? null
           : production
           ? (baseUrl == 'https://service.chessever.com' ? baseUrl : '')
           : GamebaseEnvironment.validateTestBase(baseUrl),
       _configured = baseUrl?.trim().isNotEmpty ?? false;

  final Dio dio;
  final String? _baseUrl;
  final String? Function() accessToken;
  final LibraryPublicationApiRequest? apiRequest;
  final LibraryAuthorSuggestionRequest? suggestionRequest;
  final bool _configured;

  @override
  bool get isConfigured => _configured;

  @override
  Future<void> unpublishTree(LibraryFolder folder) async {
    await _request(folder, 'DELETE', query: {'includeDescendants': true});
  }

  @override
  Future<LibraryBookPublication> load(LibraryFolder folder) =>
      _request(folder, 'GET');

  @override
  Future<LibraryBookPublication> save(
    LibraryFolder folder,
    LibraryBookMetadata metadata, {
    bool publish = false,
    bool refreshGames = false,
  }) => _request(
    folder,
    'PUT',
    body: {
      ...metadata.toJson(),
      if (publish) 'publish': true,
      if (refreshGames) 'refreshGames': true,
    },
  );

  @override
  Future<LibraryBookPublication> unpublish(LibraryFolder folder) =>
      _request(folder, 'DELETE');

  @override
  Future<LibraryBookPublication> uploadCover(
    LibraryFolder folder,
    Uint8List image,
  ) => _request(
    folder,
    'POST',
    resource: 'book/cover',
    body: {'image': base64Encode(image)},
  );

  @override
  Future<LibraryBookPublication> removeCover(LibraryFolder folder) =>
      _request(folder, 'DELETE', resource: 'book/cover');

  @override
  Future<LibraryBookPublication> uploadAuthorPhoto(
    LibraryFolder folder,
    Uint8List image, {
    int index = 0,
  }) => _request(
    folder,
    'POST',
    resource: 'book/author-photo',
    query: index == 0 ? null : {'index': index},
    body: {'image': base64Encode(image)},
  );

  @override
  Future<LibraryBookPublication> removeAuthorPhoto(
    LibraryFolder folder, {
    int index = 0,
  }) => _request(
    folder,
    'DELETE',
    resource: 'book/author-photo',
    query: index == 0 ? null : {'index': index},
  );

  @override
  Future<List<LibraryAuthorSuggestion>> suggestAuthors(String name) async {
    final term = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final base = _baseUrl;
    final token = accessToken();
    if (term.length < 2 ||
        term.length > 60 ||
        base == null ||
        base.isEmpty ||
        token == null ||
        token.isEmpty) {
      return const [];
    }
    try {
      final envelope = suggestionRequest != null
          ? await suggestionRequest!(name: term, limit: 6, bearer: token)
          : (await dio.get<Map<String, dynamic>>(
              '$base/api/library/authors',
              queryParameters: {'name': term, 'limit': 6},
              options: Options(
                followRedirects: false,
                headers: {
                  'Authorization': 'Bearer $token',
                  'Accept': 'application/json',
                },
              ),
            )).data;
      final data = envelope?['data'];
      final items = data is Map ? data['items'] : null;
      if (items is! List) return const [];
      return items
          .map(LibraryAuthorSuggestion.fromJson)
          .whereType<LibraryAuthorSuggestion>()
          .take(6)
          .toList();
    } catch (_) {
      // Old servers (404), offline, or a bad row: no suggestions.
      return const [];
    }
  }

  Future<LibraryBookPublication> _request(
    LibraryFolder folder,
    String method, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    String resource = 'book',
  }) async {
    final creditsOther = body?['authorCredit'] == 'other';
    if (!libraryFolderCanPublish(folder)) {
      throw const LibraryBookPublicationException(
        'Only your own folders and databases can become books.',
      );
    }
    final base = _baseUrl;
    if (base == null || base.isEmpty) {
      throw const LibraryBookPublicationException(
        'Book publishing is not configured for this app.',
      );
    }
    final token = accessToken();
    if (token == null || token.isEmpty) {
      throw const LibraryBookPublicationException('Sign in to publish a book.');
    }
    try {
      final envelope = apiRequest != null
          ? await apiRequest!(
              folderId: folder.id,
              method: method,
              bearer: token,
              body: body,
              query: query,
              resource: resource,
            )
          : (await dio.request<Map<String, dynamic>>(
              '$base/api/library/folders/${Uri.encodeComponent(folder.id)}/$resource',
              data: body,
              queryParameters: query,
              options: Options(
                method: method,
                followRedirects: false,
                headers: {
                  'Authorization': 'Bearer $token',
                  'Accept': 'application/json',
                },
              ),
            )).data;
      final data = envelope?['data'];
      if (data is! Map) throw const FormatException('Missing publication');
      return LibraryBookPublication.fromJson(
        Map<String, dynamic>.from(data),
        fallbackTitle: folder.name,
      );
    } on DioException catch (error) {
      final body = error.response?.data;
      final failure = body is Map ? body['error'] : null;
      final deleting =
          failure is Map && failure['code'] == 'publication_deleting';
      final code = failure is Map ? failure['code'] : null;
      if (resource == 'book/author-photo') {
        throw LibraryBookPublicationException(switch (code) {
          'author_photo_type' => 'Use a JPEG, PNG or WebP photo.',
          'author_photo_animated' => 'Use a still photo, not an animation.',
          'author_photo_aspect' => 'The author photo must be a square.',
          'author_photo_too_small' => 'Use a photo at least 256 × 256 pixels.',
          'bad_base64' => 'This photo could not be read. Choose another one.',
          'author_photo_unavailable' =>
            'Author photo uploads are unavailable right now. Try again shortly.',
          'taken_down' =>
            'ChessEver took this collection down. Ask ChessEver to restore it.',
          _ => switch (error.response?.statusCode) {
            401 => 'Your session expired. Sign in again to continue.',
            403 => 'You do not have permission to change this collection.',
            409 => 'Save the collection details, then add the author photo.',
            413 => 'This photo is too large. Choose one under 8 MB.',
            404 ||
            405 ||
            503 => 'Author photo uploads are not available here yet.',
            _ => 'Could not save the author photo. Retry when connected.',
          },
        });
      }
      if (resource == 'book/cover') {
        throw LibraryBookPublicationException(switch (code) {
          'cover_type' => 'Use a JPEG, PNG or WebP photo.',
          'cover_animated' => 'Use a still photo, not an animation.',
          'cover_aspect' => 'The cover must be a 2:3 portrait.',
          'cover_too_small' => 'Use a photo at least 600 × 900 pixels.',
          'bad_base64' => 'This photo could not be read. Choose another one.',
          'cover_unavailable' =>
            'Cover uploads are unavailable right now. Try again shortly.',
          'taken_down' =>
            'ChessEver took this collection down. Ask ChessEver to restore it.',
          _ => switch (error.response?.statusCode) {
            401 => 'Your session expired. Sign in again to continue.',
            403 => 'You do not have permission to change this cover.',
            409 => 'Save the collection details, then add the cover.',
            413 => 'This photo is too large. Choose one under 8 MB.',
            404 || 503 => 'Cover uploads are not available here yet.',
            _ => 'Could not save the cover. Retry when connected.',
          },
        });
      }
      // An older server refuses the unknown credit key with a bare 400.
      final creditRefused =
          resource == 'book' &&
          method == 'PUT' &&
          creditsOther &&
          error.response?.statusCode == 400 &&
          code == null;
      if (creditRefused) {
        throw const LibraryBookPublicationException(
          'Crediting someone else is not available here yet. Choose Me for now; your details are still here.',
        );
      }
      final message = switch (error.response?.statusCode) {
        401 => 'Your session expired. Sign in again to continue.',
        403 => 'You do not have permission to publish this folder.',
        404 ||
        503 => 'Book publishing is not available in this environment yet.',
        413 =>
          'This folder exceeds the publishing limit of 1,000 games or 10 MB. Split it into smaller books.',
        409 when deleting =>
          'This folder is being deleted. Retry deleting it from Library to finish.',
        409 => 'This book is already being processed. Wait a moment and retry.',
        400 || 422 =>
          'Check the book details and add at least one game before publishing.',
        _ =>
          'Could not update the book. Your entered details are still here. Retry when connected.',
      };
      throw LibraryBookPublicationException(message);
    }
  }
}

/// Withdrawal must succeed before the private source is destroyed.
Future<void> deleteLibraryFolderWithPublications({
  required LibraryFolder folder,
  required LibraryBookPublisher publisher,
  required Future<void> Function(String folderId) deleteFolder,
  bool? requirePublicationCheck,
}) async {
  if (publisher.isConfigured ||
      (requirePublicationCheck ?? AppEnvironment.isTest)) {
    await publisher.unpublishTree(folder);
  }
  await deleteFolder(folder.id);
}

final libraryBookPublisherProvider = Provider<LibraryBookPublisher>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );
  ref.onDispose(() => dio.close());
  return GamebaseLibraryBookPublisher(
    dio: dio,
    production: !AppEnvironment.isTest,
    baseUrl: AppEnvironment.isTest
        ? const String.fromEnvironment('LIBRARY_BOOK_PUBLISHING_BASE')
        : 'https://service.chessever.com',
    apiRequest: AppEnvironment.isTest
        ? null
        : ref.read(gamebaseRepositoryProvider).requestLibraryBookPublication,
    suggestionRequest: AppEnvironment.isTest
        ? null
        : ref.read(gamebaseRepositoryProvider).requestLibraryAuthorSuggestions,
    accessToken: () {
      final client = Supabase.instance.client;
      return client.auth.currentSession?.accessToken;
    },
  );
});

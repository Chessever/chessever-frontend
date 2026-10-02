import 'dart:convert';
import 'dart:typed_data';

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

  static LibraryAuthorCredit parse(Object? raw) =>
      raw == 'other' ? LibraryAuthorCredit.other : LibraryAuthorCredit.self;
}

class LibraryBookMetadata {
  const LibraryBookMetadata({
    required this.title,
    this.subtitle = '',
    this.author = '',
    this.about = '',
    this.foreword = '',
    this.publisher = '',
    this.publishedYear,
    this.coverUrl = '',
    this.authorCredit,
    this.authorPhotoUrl = '',
  });

  final String title;
  final String subtitle;
  final String author;
  final String about;
  final String foreword;
  final String publisher;
  final int? publishedYear;
  final String coverUrl;

  /// Null when the server predates author credits (it then refuses the key),
  /// so it is only sent when known or when someone else is credited.
  final LibraryAuthorCredit? authorCredit;

  /// The credited author's own photo. Set only by its upload, never sent.
  final String authorPhotoUrl;

  factory LibraryBookMetadata.fromJson(Map<String, dynamic> json) =>
      LibraryBookMetadata(
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        author: json['author'] as String? ?? '',
        about: json['about'] as String? ?? '',
        foreword: json['foreword'] as String? ?? '',
        publisher: json['publisher'] as String? ?? '',
        publishedYear: (json['publishedYear'] as num?)?.toInt(),
        coverUrl: json['coverUrl'] as String? ?? '',
        authorCredit: json.containsKey('authorCredit')
            ? LibraryAuthorCredit.parse(json['authorCredit'])
            : null,
        authorPhotoUrl: json['authorPhotoUrl'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'subtitle': _nullable(subtitle),
    'author': _nullable(author),
    'about': _nullable(about),
    'foreword': _nullable(foreword),
    'publisher': _nullable(publisher),
    'publishedYear': publishedYear,
    'coverUrl': _nullable(coverUrl),
    if (authorCredit != null) 'authorCredit': authorCredit!.name,
  };

  static String? _nullable(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

class LibraryBookPublication {
  const LibraryBookPublication({
    required this.status,
    required this.metadata,
    this.bookId,
    this.gameCount = 0,
  });

  final String status;
  final LibraryBookMetadata metadata;
  final String? bookId;
  final int gameCount;
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
    Uint8List image,
  );
  Future<LibraryBookPublication> removeAuthorPhoto(LibraryFolder folder);

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
  });

  final String id;
  final String name;
  final int bookCount;
  final String? avatarUrl;

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
    Uint8List image,
  ) => _request(
    folder,
    'POST',
    resource: 'book/author-photo',
    body: {'image': base64Encode(image)},
  );

  @override
  Future<LibraryBookPublication> removeAuthorPhoto(LibraryFolder folder) =>
      _request(folder, 'DELETE', resource: 'book/author-photo');

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

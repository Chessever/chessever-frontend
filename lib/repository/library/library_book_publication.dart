import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/config/gamebase_environment.dart';
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
  });

  final String title;
  final String subtitle;
  final String author;
  final String about;
  final String foreword;
  final String publisher;
  final int? publishedYear;
  final String coverUrl;

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
}

class LibraryBookPublicationException implements Exception {
  const LibraryBookPublicationException(this.message);
  final String message;
}

/// Uses the explicitly configured test service and the current user's session.
/// There is no fallback endpoint or anonymous publication request.
class GamebaseLibraryBookPublisher implements LibraryBookPublisher {
  GamebaseLibraryBookPublisher({
    required this.dio,
    required String? baseUrl,
    required this.accessToken,
  }) : _baseUrl = baseUrl == null
           ? null
           : GamebaseEnvironment.validateTestBase(baseUrl),
       _configured = baseUrl?.trim().isNotEmpty ?? false;

  final Dio dio;
  final String? _baseUrl;
  final String? Function() accessToken;
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

  Future<LibraryBookPublication> _request(
    LibraryFolder folder,
    String method, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
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
      final response = await dio.request<Map<String, dynamic>>(
        '$base/api/library/folders/${Uri.encodeComponent(folder.id)}/book',
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
      );
      final data = response.data?['data'];
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
    // Publication is enabled only in the test flavor for this rollout.
    baseUrl: AppEnvironment.isTest
        ? const String.fromEnvironment('LIBRARY_BOOK_PUBLISHING_BASE')
        : null,
    accessToken: () {
      if (!AppEnvironment.isTest) return null;
      final client = Supabase.instance.client;
      return client.auth.currentSession?.accessToken;
    },
  );
});

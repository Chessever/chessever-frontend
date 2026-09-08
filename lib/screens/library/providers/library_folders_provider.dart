import 'dart:async';

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/shared_book_preview.dart';
import 'package:chessever2/screens/library/providers/library_auth_provider.dart';
import 'package:chessever2/screens/library/providers/library_cloud_changes_provider.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'library_auth_provider.dart';

/// Special TWIC book identifier — not a real Supabase folder.
const kTwicBookId = '__twic__';

/// Synthetic TWIC folder for display in the library list.
final kTwicFolder = LibraryFolder(
  id: kTwicBookId,
  userId: '',
  name: 'ChessEver',
  color: '#0FB4E5',
  icon: 'twic',
  orderIndex: -1,
  createdAt: DateTime(2000),
  updatedAt: DateTime(2000),
);

/// Special Miniatures database identifier — not a real Supabase folder.
const kMiniaturesBookId = '__miniatures__';

/// Synthetic Miniatures folder (community database of short decisive games),
/// pinned right after the TWIC master database in the library list.
final kMiniaturesFolder = LibraryFolder(
  id: kMiniaturesBookId,
  userId: '',
  name: 'Miniatures',
  color: '#0FB4E5',
  icon: 'miniatures',
  orderIndex: -1,
  createdAt: DateTime(2000),
  updatedAt: DateTime(2000),
);

typedef LibraryFolderStreamFactory = Stream<List<LibraryFolder>> Function();

final libraryFolderStreamFactoryProvider =
    Provider.autoDispose<LibraryFolderStreamFactory>((ref) {
      final repository = ref.watch(libraryRepositoryProvider);
      return repository.subscribeFolders;
    });

final libraryFoldersStreamProvider =
    StreamProvider.autoDispose<List<LibraryFolder>>((ref) {
      // Shared-file intents can reach the PGN preview while Supabase is still
      // restoring the session. Watching auth makes this provider restart as
      // soon as the user becomes available instead of keeping the first
      // unauthenticated stream error for the lifetime of the sheet.
      final userId = ref.watch(libraryFolderAuthenticatedUserIdProvider);
      if (userId == null) return const Stream<List<LibraryFolder>>.empty();

      final streamFactory = ref.watch(libraryFolderStreamFactoryProvider);
      final controller = StreamController<List<LibraryFolder>>();
      var disposed = false;
      var hasData = false;
      var recovering = false;
      var streamFailed = false;
      var reportedError = false;

      void showError(Object error, StackTrace stackTrace, String stage) {
        if (disposed) return;
        hasData = false;
        controller.addError(error, stackTrace);
        if (reportedError) return;
        reportedError = true;
        unawaited(_reportFolderLoadError(error, stackTrace, userId, stage));
      }

      Future<void> loadSnapshot() async {
        if (disposed || hasData || recovering) return;
        recovering = true;
        try {
          final folders = await ref
              .read(libraryRepositoryProvider)
              .getFolders()
              .timeout(const Duration(seconds: 10));
          // A live update or an auth change may have won the race with HTTP.
          if (disposed || hasData) return;
          hasData = true;
          reportedError = false;
          controller.add(folders);
        } catch (error, stackTrace) {
          if (!disposed && !hasData) {
            showError(error, stackTrace, 'http_fallback');
          }
        } finally {
          recovering = false;
        }
      }

      final subscription = streamFactory().listen(
        (folders) {
          if (disposed) return;
          hasData = true;
          reportedError = false;
          controller.add(folders);
        },
        onError: (Object error, StackTrace stackTrace) {
          streamFailed = true;
          if (error is RealtimeSubscribeException) {
            // The SDK combines HTTP results and websocket status in one
            // stream. A failed websocket does not make a loaded destination
            // unusable. Keep it, or fetch once over HTTP if none arrived yet.
            // Leave the subscription alive so SDK reconnects still update us.
            unawaited(loadSnapshot());
          } else {
            showError(error, stackTrace, 'stream');
          }
        },
        onDone: () {
          if (!streamFailed) unawaited(loadSnapshot());
        },
      );
      ref.onDispose(() {
        disposed = true;
        unawaited(subscription.cancel());
        unawaited(controller.close());
      });
      return controller.stream;
    });

Future<void> _reportFolderLoadError(
  Object error,
  StackTrace stackTrace,
  String userId,
  String stage,
) async {
  talker.handle(error, stackTrace, 'Library destination loading failed');
  try {
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setUser(SentryUser(id: userId));
        scope.setTag('area', 'library_destinations');
        scope.setTag('stage', stage);
      },
    ).timeout(const Duration(seconds: 2));
  } catch (_) {
    // Telemetry must never prevent loading or retrying the destination list.
  }
}

/// Analysis count per folder for subtitle display
final folderAnalysisCountProvider = FutureProvider.autoDispose
    .family<int, String>((ref, folderId) async {
      ref.watch(libraryCloudRevisionProvider);
      final repository = ref.watch(libraryRepositoryProvider);
      return repository.getAnalysisCountInFolder(folderId);
    });

/// Fetches folders the current user is subscribed to.
final subscribedBooksProvider = FutureProvider.autoDispose<List<LibraryFolder>>(
  (ref) async {
    final repository = ref.watch(libraryRepositoryProvider);
    return repository.getSubscribedBooks();
  },
);

/// Combined library folders: owned folders + subscribed books.
/// Owned folders come first (order_index), then subscribed books (alphabetical).
final combinedLibraryFoldersProvider =
    FutureProvider.autoDispose<List<LibraryFolder>>((ref) async {
      // Watch both owned stream and subscribed future
      final ownedAsync = ref.watch(libraryFoldersStreamProvider);
      final subscribedAsync = ref.watch(subscribedBooksProvider);

      final owned = ownedAsync.valueOrNull ?? [];
      final subscribed = subscribedAsync.valueOrNull ?? [];

      return [...owned, ...subscribed];
    });

/// Top-level (root) folders only
final rootLibraryFoldersProvider = Provider.autoDispose<List<LibraryFolder>>((
  ref,
) {
  final all = ref.watch(combinedLibraryFoldersProvider).valueOrNull ?? [];
  return all.where((f) => f.parentId == null).toList();
});

/// Children of a specific folder
final childLibraryFoldersProvider = Provider.autoDispose
    .family<List<LibraryFolder>, String>((ref, parentId) {
      final all = ref.watch(combinedLibraryFoldersProvider).valueOrNull ?? [];
      return all.where((f) => f.parentId == parentId).toList();
    });

/// Top 3 most recently updated databases for quick selection
final recentDatabasesProvider = Provider.autoDispose<List<LibraryFolder>>((
  ref,
) {
  final all = ref.watch(combinedLibraryFoldersProvider).valueOrNull ?? [];
  // Quick-pick is databases only: exclude TWIC, organization folders, and the
  // special Liked Games folder. Sort by updatedAt desc.
  final owned =
      all
          .where((f) => f.id != kTwicBookId && f.isDatabase && !f.isLikedGames)
          .toList();
  owned.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return owned.take(3).toList();
});

/// Preview data for a shared book by its share token (for deep link landing).
final sharedBookPreviewProvider = FutureProvider.autoDispose
    .family<SharedBookPreview?, String>((ref, shareToken) async {
      final repository = ref.watch(libraryRepositoryProvider);
      return repository.getBookByShareToken(shareToken);
    });

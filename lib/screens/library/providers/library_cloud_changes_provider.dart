import 'dart:async';

import 'package:chessever2/screens/library/providers/library_auth_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef LibraryCloudChangeStreamFactory = Stream<void> Function(String userId);

/// Only notifications cross this boundary. PGNs are fetched through the
/// existing repository queries, with their original pagination and filters.
final libraryCloudChangeStreamFactoryProvider =
    Provider.autoDispose<LibraryCloudChangeStreamFactory>((ref) {
      return (userId) {
        final client = Supabase.instance.client;
        late final RealtimeChannel channel;
        late final StreamController<void> controller;
        controller = StreamController<void>(
          onListen: () {
            channel = client.channel('library-content:$userId');
            for (final event in [
              PostgresChangeEvent.insert,
              PostgresChangeEvent.update,
            ]) {
              channel.onPostgresChanges(
                event: event,
                schema: 'public',
                table: 'user_saved_analyses',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'user_id',
                  value: userId,
                ),
                callback: (_) => controller.add(null),
              );
            }
            channel.subscribe((status, error) {
              if (status == RealtimeSubscribeStatus.subscribed) {
                // Also catch changes missed while this device was offline.
                controller.add(null);
              }
            });
          },
          onCancel: () async {
            await client.removeChannel(channel);
          },
        );
        return controller.stream;
      };
    });

final _libraryCloudChangesProvider = StreamProvider.autoDispose<int>((ref) {
  final userId = ref.watch(libraryFolderAuthenticatedUserIdProvider);
  if (userId == null) return Stream.value(0);

  final factory = ref.watch(libraryCloudChangeStreamFactoryProvider);
  final controller = StreamController<int>();
  var revision = 0;
  Timer? pending;
  controller.add(revision);

  void changed() {
    // A bulk PGN import produces one event per game. Coalesce them before
    // refetching the visible lists and counts.
    pending ??= Timer(const Duration(milliseconds: 500), () {
      pending = null;
      controller.add(++revision);
    });
  }

  final subscription = factory(userId).listen(
    (_) => changed(),
    // A notification failure must not replace usable Library data with an
    // error. The SDK reconnects; the catch-up timer below remains available.
    onError: (Object error, StackTrace stack) {},
  );
  // DELETE events cannot be filtered by account under Postgres Changes.
  // A bounded, read-only refresh while a cloud Library is visible catches
  // deletions and missed notifications without weakening row-level security.
  final catchUp = Timer.periodic(const Duration(seconds: 30), (_) => changed());
  ref.onDispose(() {
    pending?.cancel();
    catchUp.cancel();
    unawaited(subscription.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});

/// Include the account in the cache key: an account switch must refresh even
/// when both subscriptions happen to have the same revision number.
final libraryCloudRevisionProvider = Provider.autoDispose((ref) {
  final userId = ref.watch(libraryFolderAuthenticatedUserIdProvider);
  final revision = ref.watch(_libraryCloudChangesProvider).valueOrNull ?? 0;
  return (userId: userId, revision: revision);
});

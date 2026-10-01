import 'dart:async';

import 'package:chessever2/providers/app_resume_signal_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inbox_message.dart';
import 'inbox_repository.dart';

class InboxState {
  const InboxState({
    this.ownerId,
    this.messages = const [],
    this.loading = true,
    this.refreshing = false,
    this.syncError,
    this.cacheError,
    this.marking = const {},
    this.markErrors = const {},
  });
  final String? ownerId;
  final List<InboxMessage> messages;
  final bool loading;
  final bool refreshing;
  final String? syncError;
  final String? cacheError;
  final Set<String> marking;
  final Map<String, String> markErrors;
  bool get hasUnread => messages.any((m) => m.isUnread);

  InboxMessage? message(String id) {
    for (final item in messages) {
      if (item.id == id) return item;
    }
    return null;
  }

  InboxState copyWith({
    List<InboxMessage>? messages,
    bool? loading,
    bool? refreshing,
    String? syncError,
    bool clearSyncError = false,
    String? cacheError,
    bool clearCacheError = false,
    Set<String>? marking,
    Map<String, String>? markErrors,
  }) => InboxState(
    ownerId: ownerId,
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    syncError: clearSyncError ? null : syncError ?? this.syncError,
    cacheError: clearCacheError ? null : cacheError ?? this.cacheError,
    marking: marking ?? this.marking,
    markErrors: markErrors ?? this.markErrors,
  );
}

class InboxController extends StateNotifier<InboxState> {
  InboxController({
    required String ownerId,
    required this.source,
    required this.cache,
  }) : super(InboxState(ownerId: ownerId));

  InboxController.inactive()
    : source = null,
      cache = null,
      super(
        const InboxState(
          loading: false,
          syncError: 'Inbox is temporarily unavailable. Please retry.',
        ),
      );

  final InboxSource? source;
  final InboxCache? cache;
  Future<void>? _starting;
  Future<void>? _refresh;
  final _cacheReady = Completer<void>();
  final _confirmedReads = <String, DateTime>{};
  bool _cacheRestoreFailed = false;
  bool _hasServerSnapshot = false;

  bool _isCurrentOwner(String owner) =>
      mounted && state.ownerId == owner && source!.hasSession(owner);

  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    final owner = state.ownerId;
    if (owner == null) return;
    try {
      if (!source!.hasSession(owner)) {
        _cacheRestoreFailed = true;
        state = state.copyWith(
          loading: false,
          syncError: 'Inbox is temporarily unavailable. Please retry.',
        );
        return;
      }
      await _restoreCache(owner);
    } finally {
      _cacheReady.complete();
    }
    await _beginRefresh(retryCache: false);
  }

  Future<void> _restoreCache(String owner) async {
    if (!_isCurrentOwner(owner)) return;
    try {
      final cached = await cache!.load(owner);
      if (!_isCurrentOwner(owner)) return;
      _cacheRestoreFailed = false;
      if (cached != null) {
        _rememberReads(cached);
        // Recovery must not replace a newer server list or undo a confirmed
        // in-memory read while a delayed cache load was pending.
        final messages = _hasServerSnapshot ? state.messages : cached;
        final merged = messages.map((message) {
          final readAt = _confirmedReads[message.id];
          return readAt == null ? message : message.withReadAt(readAt);
        }).toList();
        state = state.copyWith(
          messages: List.unmodifiable(merged),
          markErrors: Map.fromEntries(
            state.markErrors.entries.where(
              (entry) => merged.any((m) => m.id == entry.key && m.isUnread),
            ),
          ),
          loading: false,
          clearCacheError: true,
        );
        if (_hasServerSnapshot) await _persist();
      } else {
        state = state.copyWith(clearCacheError: true);
      }
    } catch (_) {
      if (!_isCurrentOwner(owner)) return;
      _cacheRestoreFailed = true;
      state = state.copyWith(
        cacheError:
            'Offline Inbox storage is unavailable. Server reads remain saved.',
      );
    }
  }

  void _rememberReads(List<InboxMessage> messages) {
    for (final message in messages) {
      final readAt = message.readAt;
      final known = _confirmedReads[message.id];
      if (readAt != null && (known == null || readAt.isAfter(known))) {
        _confirmedReads[message.id] = readAt;
      }
    }
  }

  Future<void> refresh() {
    if (!mounted || state.ownerId == null) return Future<void>.value();
    if (_starting == null) return start();
    return _beginRefresh(retryCache: _cacheReady.isCompleted);
  }

  Future<void> _beginRefresh({required bool retryCache}) => _refresh ??=
      _refreshInbox(retryCache: retryCache).whenComplete(() => _refresh = null);

  Future<void> _refreshInbox({required bool retryCache}) async {
    await _cacheReady.future;
    if (!mounted) return;
    final owner = state.ownerId!;
    if (!_isCurrentOwner(owner)) return;
    if (retryCache && _cacheRestoreFailed) await _restoreCache(owner);
    if (!_isCurrentOwner(owner)) return;
    await _fetch();
  }

  Future<void> _fetch() async {
    await _cacheReady.future;
    if (!mounted) return;
    final owner = state.ownerId!;
    if (!_isCurrentOwner(owner)) return;
    state = state.copyWith(refreshing: true, clearSyncError: true);
    try {
      final fetched = await source!.fetch(owner);
      if (!_isCurrentOwner(owner)) return;
      _hasServerSnapshot = true;
      _rememberReads(fetched);
      // Read receipts are irreversible. A refresh begun before a successful
      // mark must not resurrect that row's unread indicator.
      final merged = fetched.map((message) {
        final readAt = _confirmedReads[message.id];
        return readAt == null ? message : message.withReadAt(readAt);
      }).toList();
      final unreadIds = merged
          .where((m) => m.isUnread)
          .map((m) => m.id)
          .toSet();
      state = state.copyWith(
        messages: List.unmodifiable(merged),
        markErrors: Map.fromEntries(
          state.markErrors.entries.where(
            (entry) => unreadIds.contains(entry.key),
          ),
        ),
        loading: false,
        refreshing: false,
        clearSyncError: true,
      );
      await _persist();
    } catch (_) {
      if (!_isCurrentOwner(owner)) return;
      // No clearing/mark-all, even when the missing migration returns an error.
      state = state.copyWith(
        loading: false,
        refreshing: false,
        syncError:
            'Could not refresh Inbox. Your saved messages are unchanged.',
      );
    }
  }

  Future<void> _persist() async {
    final owner = state.ownerId!;
    if (!_isCurrentOwner(owner)) return;
    final snapshot = state.messages;
    try {
      await cache!.save(owner, snapshot);
      if (_isCurrentOwner(owner)) {
        _cacheRestoreFailed = false;
        state = state.copyWith(clearCacheError: true);
      }
    } catch (_) {
      if (_isCurrentOwner(owner)) {
        state = state.copyWith(
          cacheError:
              'Offline Inbox storage is unavailable. Server reads remain saved.',
        );
      }
    }
  }

  /// Call ONLY after the exact detail's full text has been rendered. The list,
  /// drawer and avatar never call this. No optimistic clearing or queued marks.
  Future<bool> markOpened(String messageId) async {
    if (!mounted || state.ownerId == null) return false;
    final message = state.message(messageId);
    if (message == null) return false;
    if (!message.isUnread) return true;
    if (state.marking.contains(messageId)) return false;
    final owner = state.ownerId!;
    if (!_isCurrentOwner(owner)) return false;
    state = state.copyWith(
      marking: {...state.marking, messageId},
      markErrors: {...state.markErrors}..remove(messageId),
    );
    try {
      final readAt = await source!.markRead(owner, messageId);
      if (!_isCurrentOwner(owner)) return false;
      _confirmedReads[messageId] = readAt;
      state = state.copyWith(
        messages: List.unmodifiable(
          state.messages.map(
            (m) => m.id == messageId ? m.withReadAt(readAt) : m,
          ),
        ),
        marking: {...state.marking}..remove(messageId),
        markErrors: {...state.markErrors}..remove(messageId),
      );
      await _persist();
      return true;
    } catch (_) {
      if (_isCurrentOwner(owner)) {
        // A successful fetch can reconcile a lost RPC acknowledgement.
        if (_confirmedReads.containsKey(messageId)) {
          state = state.copyWith(
            marking: {...state.marking}..remove(messageId),
            markErrors: {...state.markErrors}..remove(messageId),
          );
          return true;
        }
        state = state.copyWith(
          marking: {...state.marking}..remove(messageId),
          markErrors: {
            ...state.markErrors,
            messageId:
                'Could not save this read. It stays unread until confirmed. Retry.',
          },
        );
      }
      return false;
    }
  }
}

final inboxSourceProvider = Provider<InboxSource>(
  (ref) => SupabaseInboxSource(() => Supabase.instance.client),
);
final inboxCacheProvider = Provider<InboxCache>(
  (ref) => SqliteInboxCache(AppDatabase.instance),
);

/// Recreating the controller on identity change drops every in-memory row,
/// receipt and pending operation. Guests use the existing anonymous-auth UUID.
final inboxProvider = StateNotifierProvider<InboxController, InboxState>((ref) {
  final owner = ref.watch(currentUserProvider.select((user) => user?.id));
  if (owner == null) return InboxController.inactive();
  final controller = InboxController(
    ownerId: owner,
    source: ref.read(inboxSourceProvider),
    cache: ref.read(inboxCacheProvider),
  );
  unawaited(controller.start());
  ref.listen(
    appResumedSignalProvider,
    (_, _) => unawaited(controller.refresh()),
  );
  // Foreground catch-up, independent of push permission and without Realtime
  // configuration. The app's existing resume signal also catches backgrounding.
  final timer = Timer.periodic(const Duration(minutes: 5), (_) {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      unawaited(controller.refresh());
    }
  });
  ref.onDispose(timer.cancel);
  return controller;
});
final inboxHasUnreadProvider = Provider<bool>(
  (ref) => ref.watch(inboxProvider.select((state) => state.hasUnread)),
);

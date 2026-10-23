import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_watch_link/flutter_watch_link.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/watch_account.dart';
import 'core/watch_models.dart';
import 'core/watch_repository.dart';

class WatchController extends ChangeNotifier {
  WatchController({required this.repository, WatchLink? link})
    : _link = link ?? WatchLink.instance;
  final WatchRepository repository;
  final WatchLink _link;
  WatchAccount account = const WatchAccount(revision: 0);
  WatchLinkState connection = WatchLinkState.unknown;
  List<WatchEvent> events = [];
  bool loading = false;
  bool hasMore = true;
  bool favoritesOnly = false;
  String? error;
  DateTime? updatedAt;
  bool _disposed = false;
  SharedPreferences? _storage;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _persisting = Future.value();

  List<WatchEvent> get visibleEvents {
    final result = favoritesOnly
        ? events.where((e) => account.followsEvent(e.id, e.name)).toList()
        : [...events];
    // Stable partition, preserving the phone feed's Elo ordering within groups.
    return [
      ...result.where((e) => account.followsEvent(e.id, e.name)),
      ...result.where((e) => !account.followsEvent(e.id, e.name)),
    ];
  }

  Future<void> initialize() async {
    try {
      _storage = await SharedPreferences.getInstance();
      final cached = _storage!.getString('watch_account_v1');
      if (cached != null) {
        _merge(Map<String, dynamic>.from(jsonDecode(cached) as Map));
      }
    } catch (_) {
      /* A damaged cache must not block connectivity. */
    }
    if (_disposed) return;
    try {
      _subscriptions.add(_link.messages.listen((m) => _merge(m.payload)));
      _subscriptions.add(
        _link.states.listen((state) {
          connection = state;
          _notify();
          if (state.activated) unawaited(_receiveContext());
          if (state.activated && state.reachable) unawaited(requestSync());
        }),
      );
      _subscriptions.add(_link.errors.listen((_) {}));
      await _link.activate();
      await _receiveContext();
    } catch (_) {
      /* Show connection instructions and allow public browsing. */
    }
    await refresh();
  }

  Future<void> _receiveContext() async {
    try {
      final context = await _link.receivedApplicationContext();
      if (context != null) _merge(context);
    } catch (_) {}
  }

  void _merge(Map<String, dynamic> json) {
    if (_disposed || json['kind'] != WatchAccount.kind) return;
    final next = WatchAccount.fromJson(json);
    if (next.revision <= account.revision) return;
    final wasConfigured = repository.configured;
    account = next;
    if (next.publicApiKey.isNotEmpty) repository.apiKey = next.publicApiKey;
    if (!next.signedIn) favoritesOnly = false;
    _notify();
    _persisting = _persisting
        .then((_) async {
          await _storage?.setString(
            'watch_account_v1',
            jsonEncode(next.toJson()),
          );
        })
        .catchError((Object _) {});
    if (!wasConfigured && repository.configured) unawaited(refresh());
  }

  Future<bool> requestSync() async {
    await _receiveContext();
    if (!connection.activated || !connection.counterpartReady) return false;
    try {
      if (connection.reachable) {
        await _link.sendMessage({
          'kind': 'chessever.sync.v1',
          'revision': account.revision,
        });
      } else if (await _link.outstandingTransferCount() == 0) {
        await _link.transferUserInfo({
          'kind': 'chessever.sync.v1',
          'revision': account.revision,
        });
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openOnPhone(String gameId) async {
    if (!connection.reachable) return false;
    try {
      final reply = await _link
          .sendMessageWithReply({
            'kind': 'chessever.open-game.v1',
            'gameId': gameId,
          })
          .timeout(const Duration(seconds: 8));
      return reply['accepted'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> refresh({bool more = false}) async {
    if (loading || _disposed || (more && !hasMore)) return;
    loading = true;
    error = null;
    _notify();
    try {
      final page = await repository.events(offset: more ? events.length : 0);
      if (_disposed) return;
      events = more ? [...events, ...page] : page;
      hasMore = page.length == WatchRepository.pageSize;
      updatedAt = DateTime.now();
    } catch (e) {
      error = e is WatchDataException ? e.message : 'No connection. Try again.';
    } finally {
      loading = false;
      _notify();
    }
  }

  void toggleFavorites() {
    favoritesOnly = !favoritesOnly;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    repository.dispose();
    super.dispose();
  }
}

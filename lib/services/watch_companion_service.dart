import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_watch_link/flutter_watch_link.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../watch/core/watch_account.dart';
import '../watch/core/watch_repository.dart';
import '../utils/favorite_event_ids.dart';

/// The iPhone remains the sole account and notification owner. WatchConnectivity
/// carries a versioned display snapshot, never authentication credentials.
class WatchCompanionService with WidgetsBindingObserver {
  WatchCompanionService._();
  static final instance = WatchCompanionService._();
  final _link = WatchLink.instance;
  SupabaseClient? _client;
  String _publicKey = '';
  WatchLinkState _state = WatchLinkState.unknown;
  RealtimeChannel? _changes;
  String? _subscribedUser;
  Timer? _debounce;
  bool _started = false;
  bool _sending = false;
  bool _sendAgain = false;
  int _revision = 0;
  int _accountGeneration = 0;
  void Function(String gameId)? _openGame;
  String? _lastUserId;
  bool get _canSync =>
      _state.activated && (_state.counterpartReady || _state.reachable);

  Future<void> initialize({
    required SupabaseClient client,
    required String publicKey,
    required String url,
    required void Function(String gameId) openGame,
  }) async {
    if (_started ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        url.replaceFirst(RegExp(r'/$'), '') != WatchRepository.productionUrl ||
        !_isPublicKey(publicKey)) {
      return;
    }
    _started = true;
    _client = client;
    _publicKey = publicKey;
    _openGame = openGame;
    _lastUserId = client.auth.currentUser?.id;
    try {
      if (!await _link.isSupported()) return;
      final previous = await _link.sentApplicationContext();
      _revision = (previous?['revision'] as num?)?.toInt() ?? 0;
      _link.states.listen((state) {
        _state = state;
        if (_canSync) scheduleSync();
      });
      _link.errors.listen((_) => scheduleSync());
      _link.messages.listen((message) {
        if (message.payload['kind'] == 'chessever.sync.v1') {
          final revision = message.payload['revision'];
          if (revision is int &&
              revision > _revision &&
              revision < 9007199254740991) {
            _revision = revision;
          }
          scheduleSync();
        }
        if (message.payload['kind'] == 'chessever.open-game.v1') {
          final id = message.payload['gameId'];
          final valid =
              id is String && RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id);
          if (valid) _openGame?.call(id);
          if (message.expectsReply) {
            unawaited(message.reply({'accepted': valid}));
          }
        }
      });
      client.auth.onAuthStateChange.listen((auth) {
        _accountGeneration++;
        final userId = auth.session?.user.id;
        if (userId != _lastUserId) {
          _lastUserId = userId;
          _subscribe(null);
          // Clear the old display immediately, even if an old user's fetch is
          // in flight. Its generation check prevents it from restoring data.
          unawaited(_clearAccount());
        }
        scheduleSync(immediate: true);
      });
      WidgetsBinding.instance.addObserver(this);
      await _link.activate();
    } catch (_) {
      // An absent watch/native bridge must never prevent phone startup.
      _started = false;
      debugPrint('[WatchCompanion] Connectivity unavailable.');
    }
  }

  static bool _isPublicKey(String key) {
    if (key.startsWith('sb_publishable_')) return true;
    try {
      final payload =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(key.split('.')[1])),
                ),
              )
              as Map;
      return payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }

  void scheduleSync({bool immediate = false}) {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 500),
      () => unawaited(_sync()),
    );
  }

  int _nextRevision() {
    final now = DateTime.now().microsecondsSinceEpoch;
    _revision = now > _revision ? now : _revision + 1;
    return _revision;
  }

  Future<void> _clearAccount() async {
    if (!_canSync) return;
    try {
      await _publish(
        WatchAccount(
          revision: _nextRevision(),
          publicApiKey: _publicKey,
        ).toJson(),
      );
    } catch (_) {
      scheduleSync();
    }
  }

  Future<void> _publish(Map<String, Object?> snapshot) async {
    await _link.updateApplicationContext(snapshot);
    if (_state.reachable) {
      try {
        await _link.sendMessage(snapshot);
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) scheduleSync();
  }

  Future<List<Map<String, dynamic>>> _rows(
    String table,
    String columns,
    String userId,
  ) async {
    final all = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await _client!
          .from(table)
          .select(columns)
          .eq('user_id', userId)
          .order('id')
          .range(offset, offset + 499)
          .timeout(const Duration(seconds: 10));
      all.addAll(page);
      if (page.length < 500) return all;
    }
  }

  Future<void> _sync() async {
    if (!_canSync || _client == null) {
      return;
    }
    if (_sending) {
      _sendAgain = true;
      return;
    }
    _sending = true;
    final generation = _accountGeneration;
    final user = _client!.auth.currentUser;
    try {
      _subscribe(user?.id);
      final events = user == null
          ? <Map<String, dynamic>>[]
          : await _rows(
              'user_favorite_events',
              'id,event_id,event_name,metadata',
              user.id,
            );
      final players = user == null
          ? <Map<String, dynamic>>[]
          : await _rows(
              'user_favorite_players',
              'id,fide_id,player_name',
              user.id,
            );
      final preferences = user == null
          ? null
          : await _client!
                .from('user_notification_preferences')
                .select(
                  'favorite_event_alerts,favorite_player_alerts,heads_up_alerts',
                )
                .eq('user_id', user.id)
                .maybeSingle()
                .timeout(const Duration(seconds: 10));
      if (generation != _accountGeneration ||
          user?.id != _client!.auth.currentUser?.id) {
        _sendAgain = true;
        return;
      }
      final snapshot = WatchAccount(
        revision: _nextRevision(),
        userId: user?.id,
        name:
            user?.userMetadata?['display_name'] as String? ??
            user?.userMetadata?['full_name'] as String? ??
            'ChessEver account',
        eventIds: events
            .expand((r) {
              final id = r['event_id'].toString();
              final metadata = r['metadata'] as Map? ?? {};
              return <String>{
                ...favoriteEventIdCandidates(
                  id,
                  eventName: r['event_name'] as String?,
                ),
                if (!isNonEventFavoriteId(id)) ...[
                  if (metadata['source_event_id'] is String)
                    metadata['source_event_id'] as String,
                  if (metadata['cal_event_alias'] is String)
                    metadata['cal_event_alias'] as String,
                ],
              };
            })
            .toSet()
            .toList(),
        playerIds: players
            .where((r) => r['fide_id'] != null)
            .map((r) => r['fide_id'].toString())
            .toList(),
        playerNames: players
            .map((r) => r['player_name'] as String? ?? '')
            .toList(),
        preferences: {
          for (final entry in (preferences ?? {}).entries)
            if (entry.value is bool) entry.key: entry.value as bool,
        },
        publicApiKey: _publicKey,
      ).toJson();
      // WatchConnectivity's context has a ~65 kB ceiling. Refuse rather than
      // silently send a truncated set of account favorites.
      if (utf8.encode(jsonEncode(snapshot)).length > 60000) {
        throw StateError('Watch account snapshot exceeds transport limit');
      }
      await _publish(snapshot);
    } catch (_) {
      // Leave the last complete snapshot intact and retry on request/resume.
      // Signing out skips all network reads and publishes an empty account.
      debugPrint('[WatchCompanion] Sync will retry.');
    } finally {
      _sending = false;
      if (_sendAgain) {
        _sendAgain = false;
        scheduleSync(immediate: true);
      }
    }
  }

  void _subscribe(String? userId) {
    if (_subscribedUser == userId) return;
    final previous = _changes;
    if (previous != null) unawaited(_client!.removeChannel(previous));
    _subscribedUser = userId;
    _changes = null;
    if (userId == null) return;
    var channel = _client!.channel('watch-account-$userId');
    for (final table in [
      'user_favorite_events',
      'user_favorite_players',
      'user_notification_preferences',
    ]) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (_) => scheduleSync(),
      );
    }
    _changes = channel..subscribe();
  }
}

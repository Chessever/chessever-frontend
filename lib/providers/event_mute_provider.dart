import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_state_provider.dart';

/// Whether the current user has muted notifications for a given event
/// (keyed by groupBroadcastId). Returns `true` if muted.
final eventMuteProvider =
    AutoDisposeAsyncNotifierProvider.family<EventMuteNotifier, bool, String>(
      EventMuteNotifier.new,
    );

class EventMuteNotifier extends AutoDisposeFamilyAsyncNotifier<bool, String> {
  SupabaseClient get _supabase => Supabase.instance.client;
  bool _listening = false;

  String get _groupBroadcastId => arg;

  @override
  Future<bool> build(String arg) async {
    if (!_listening) {
      _listening = true;
      ref.listen(currentUserProvider, (prev, next) {
        if (prev?.id != next?.id) {
          unawaited(_reload());
        }
      });
    }
    return _fetchMuted();
  }

  Future<void> _reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchMuted);
  }

  String? _currentUserId() => _supabase.auth.currentUser?.id;

  Future<bool> _fetchMuted() async {
    final userId = _currentUserId();
    if (userId == null) return false;

    try {
      final response =
          await _supabase
              .from('user_muted_events')
              .select('id')
              .eq('user_id', userId)
              .eq('group_broadcast_id', _groupBroadcastId)
              .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('[EventMute] Error fetching mute state: $e');
      return false;
    }
  }

  Future<void> toggleMute() async {
    final userId = _currentUserId();
    if (userId == null) return;

    final currentlyMuted = state.valueOrNull ?? false;
    // Optimistic update
    state = AsyncValue.data(!currentlyMuted);

    try {
      if (currentlyMuted) {
        // Unmute: delete the row
        await _supabase
            .from('user_muted_events')
            .delete()
            .eq('user_id', userId)
            .eq('group_broadcast_id', _groupBroadcastId);
      } else {
        // Mute: insert a row
        await _supabase.from('user_muted_events').upsert({
          'user_id': userId,
          'group_broadcast_id': _groupBroadcastId,
        }, onConflict: 'user_id,group_broadcast_id');
      }
    } catch (e) {
      debugPrint('[EventMute] Error toggling mute: $e');
      // Revert on failure
      state = AsyncValue.data(currentlyMuted);
    }
  }
}

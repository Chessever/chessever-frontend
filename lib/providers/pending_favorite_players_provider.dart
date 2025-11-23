import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PendingFavoritePlayer {
  const PendingFavoritePlayer({
    required this.fideId,
    required this.playerName,
    this.countryCode,
    this.rating,
    this.title,
    required this.isSelected,
  });

  final String fideId;
  final String playerName;
  final String? countryCode;
  final int? rating;
  final String? title;
  final bool isSelected;

  PendingFavoritePlayer copyWith({
    String? fideId,
    String? playerName,
    String? countryCode,
    int? rating,
    String? title,
    bool? isSelected,
  }) {
    return PendingFavoritePlayer(
      fideId: fideId ?? this.fideId,
      playerName: playerName ?? this.playerName,
      countryCode: countryCode ?? this.countryCode,
      rating: rating ?? this.rating,
      title: title ?? this.title,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

final pendingFavoriteSelectionsProvider = StateNotifierProvider<
    PendingFavoriteSelectionsNotifier,
    Map<String, PendingFavoritePlayer>>((ref) {
  return PendingFavoriteSelectionsNotifier(ref);
});

class PendingFavoriteSelectionsNotifier
    extends StateNotifier<Map<String, PendingFavoritePlayer>> {
  PendingFavoriteSelectionsNotifier(this._ref) : super({});

  final Ref _ref;

  SupabaseClient get _supabase => Supabase.instance.client;

  void setSelection(PendingFavoritePlayer pending) {
    state = {
      ...state,
      pending.fideId: pending,
    };
  }

  Future<void> flushToSupabase() async {
    final user = _supabase.auth.currentUser;
    final isAuthenticated = user != null && user.isAnonymous != true;
    if (!isAuthenticated) return;

    final toSync = state.values.where((p) => p.isSelected).toList();
    if (toSync.isEmpty) return;

    try {
      final payload = toSync
          .map((pending) => {
                'user_id': user!.id,
                'fide_id': pending.fideId,
                'player_name': pending.playerName,
                'metadata': <String, dynamic>{
                  if (pending.countryCode != null)
                    'countryCode': pending.countryCode,
                  if (pending.rating != null) 'rating': pending.rating,
                  if (pending.title != null) 'title': pending.title,
                },
              })
          .toList();

      await _supabase.from('user_favorite_players').upsert(payload);

      state = {};
      await _ref.read(favoritePlayersProviderNew.notifier).syncFromSupabase();
    } catch (e, st) {
      // Keep pending selections so we can retry later
      debugPrint('[PendingFavorites] Failed to flush pending favorites: $e');
      debugPrint('[PendingFavorites] Stack: $st');
    }
  }
}

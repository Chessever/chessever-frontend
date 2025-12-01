import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/board_settings/models/board_settings_model.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Board color enum matching index values stored in Supabase
enum BoardColor {
  defaultColor, // index 0
  brown,        // index 1
  grey,         // index 2
  green,        // index 3
  orange,       // index 4
  purple,       // index 5
  blue,         // index 6
  pink          // index 7
}

/// Board settings configuration class
class BoardSettingsNew {
  const BoardSettingsNew({
    this.boardColorIndex = 0,
    this.showEvaluationBar = true,
    this.soundEnabled = true,
    this.chatEnabled = true,
    this.pieceStyleIndex = 0,
  });

  final int boardColorIndex;
  final bool showEvaluationBar;
  final bool soundEnabled;
  final bool chatEnabled;
  final int pieceStyleIndex;

  BoardColor get boardColor {
    switch (boardColorIndex) {
      case 0:
        return BoardColor.defaultColor;
      case 1:
        return BoardColor.brown;
      case 2:
        return BoardColor.grey;
      case 3:
        return BoardColor.green;
      case 4:
        return BoardColor.orange;
      case 5:
        return BoardColor.purple;
      case 6:
        return BoardColor.blue;
      case 7:
        return BoardColor.pink;
      default:
        return BoardColor.defaultColor;
    }
  }

  Color get boardColorValue {
    switch (boardColor) {
      case BoardColor.defaultColor:
        return const Color(0xFF0FB4E5); // Teal/Default
      case BoardColor.brown:
        return Colors.brown;
      case BoardColor.grey:
        return Colors.grey;
      case BoardColor.green:
        return Colors.green;
      case BoardColor.orange:
        return Colors.orange;
      case BoardColor.purple:
        return Colors.purple;
      case BoardColor.blue:
        return Colors.blue;
      case BoardColor.pink:
        return Colors.pink;
    }
  }

  PieceStyle get pieceStyle {
    if (pieceStyleIndex >= 0 && pieceStyleIndex < PieceStyle.values.length) {
      return PieceStyle.values[pieceStyleIndex];
    }
    return PieceStyle.standard;
  }

  BoardSettingsNew copyWith({
    int? boardColorIndex,
    bool? showEvaluationBar,
    bool? soundEnabled,
    bool? chatEnabled,
    int? pieceStyleIndex,
  }) {
    return BoardSettingsNew(
      boardColorIndex: boardColorIndex ?? this.boardColorIndex,
      showEvaluationBar: showEvaluationBar ?? this.showEvaluationBar,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      chatEnabled: chatEnabled ?? this.chatEnabled,
      pieceStyleIndex: pieceStyleIndex ?? this.pieceStyleIndex,
    );
  }
}

/// Provider for managing board settings with Supabase + SharedPreferences sync
final boardSettingsProviderNew =
    AsyncNotifierProvider<BoardSettingsNotifierNew, BoardSettingsNew>(
      BoardSettingsNotifierNew.new,
    );

class BoardSettingsNotifierNew extends AsyncNotifier<BoardSettingsNew> {
  static const String _cacheKey = 'cached_board_settings';

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  Future<BoardSettingsNew> build() async {
    return await _loadSettings();
  }

  Future<BoardSettingsNew> _loadSettings() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[BoardSettings] No user logged in, returning defaults');
        return const BoardSettingsNew();
      }

      // Fetch from Supabase (source of truth)
      // Note: Using user_engine_settings table (unified settings table)
      final response = await _supabase
          .from('user_engine_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        debugPrint(
          '[BoardSettings] No settings found in Supabase, creating defaults',
        );
        // Save defaults to Supabase (upsert handles race conditions)
        try {
          await _saveToSupabase(const BoardSettingsNew(), userId);
        } catch (e) {
          // Ignore duplicate errors - another process may have created it
          debugPrint(
            '[BoardSettings] Info: ${e.toString().contains('duplicate') ? 'Settings already exist' : 'Error creating defaults: $e'}',
          );
        }
        return const BoardSettingsNew();
      }

      final model = BoardSettingsModel.fromSupabase(response);
      final settings = BoardSettingsNew(
        boardColorIndex: model.boardColorIndex,
        showEvaluationBar: model.showEvaluationBar,
        soundEnabled: model.soundEnabled,
        chatEnabled: model.chatEnabled,
        pieceStyleIndex: model.pieceStyleIndex,
      );

      // Cache locally
      await _cacheSettings(settings);

      debugPrint('[BoardSettings] Fetched settings from Supabase');
      return settings;
    } catch (e, st) {
      debugPrint('[BoardSettings] Error fetching from Supabase: $e');
      debugPrint('[BoardSettings] Stack: $st');

      // Fallback to local cache
      return await _getCachedSettings();
    }
  }

  /// Set board color by index
  Future<void> setBoardColorIndex(int index) async {
    final clamped = index.clamp(0, 7); // 0-7 for the 8 color options
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(boardColorIndex: clamped);
    debugPrint('🎨 BoardSettings: Color changed to index=$clamped');
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Set board color by Color value
  Future<void> setBoardColor(Color color) async {
    int index = 0;
    if (color == Colors.brown) {
      index = 1;
    } else if (color == Colors.grey) {
      index = 2;
    } else if (color == Colors.green) {
      index = 3;
    } else if (color == Colors.orange) {
      index = 4;
    } else if (color == Colors.purple) {
      index = 5;
    } else if (color == Colors.blue) {
      index = 6;
    } else if (color == Colors.pink) {
      index = 7;
    }
    await setBoardColorIndex(index);
  }

  /// Toggle evaluation bar visibility
  Future<void> toggleEvaluationBar(bool value) async {
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(showEvaluationBar: value);
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Toggle sound
  Future<void> toggleSound(bool value) async {
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(soundEnabled: value);
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Toggle chat
  Future<void> toggleChat(bool value) async {
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(chatEnabled: value);
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Set piece style
  Future<void> setPieceStyle(PieceStyle style) async {
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(pieceStyleIndex: style.index);
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Refresh settings from Supabase
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadSettings());
  }

  /// Sync settings from Supabase to local cache
  Future<void> syncFromSupabase() async {
    debugPrint('[BoardSettings] Starting sync...');
    try {
      await refresh();
      debugPrint('[BoardSettings] Sync complete');
    } catch (e, st) {
      debugPrint('[BoardSettings] Error syncing: $e');
      debugPrint('[BoardSettings] Stack: $st');
    }
  }

  // Private methods

  Future<void> _persist(BoardSettingsNew settings) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[BoardSettings] No user logged in, skipping persist');
        return;
      }

      // Cache locally first (fast, immediate)
      await _cacheSettings(settings);

      // Save to Supabase in background (fire-and-forget, non-blocking)
      unawaited(
        _saveToSupabase(settings, userId),
      );
    } catch (e, st) {
      debugPrint('[BoardSettings] Error persisting settings: $e');
      debugPrint('[BoardSettings] Stack: $st');
      // Don't rethrow - we don't want to block UI on persistence errors
    }
  }

  Future<void> _saveToSupabase(BoardSettingsNew settings, String userId) async {
    try {
      // Use upsert with onConflict to handle existing records
      // Note: Using user_engine_settings table (unified settings table)
      await _supabase.from('user_engine_settings').upsert(
        {
          'user_id': userId,
          'board_color_index': settings.boardColorIndex,
          'show_evaluation_bar': settings.showEvaluationBar,
          'sound_enabled': settings.soundEnabled,
          'chat_enabled': settings.chatEnabled,
          'piece_style_index': settings.pieceStyleIndex,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id', // Specify conflict column
      );
      debugPrint('[BoardSettings] ✅ Saved to Supabase');
    } catch (e) {
      debugPrint('[BoardSettings] ❌ Error saving to Supabase: $e');
      rethrow;
    }
  }

  Future<void> _cacheSettings(BoardSettingsNew settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode({
        'boardColorIndex': settings.boardColorIndex,
        'showEvaluationBar': settings.showEvaluationBar,
        'soundEnabled': settings.soundEnabled,
        'chatEnabled': settings.chatEnabled,
        'pieceStyleIndex': settings.pieceStyleIndex,
      });
      await prefs.setString(_cacheKey, json);
      debugPrint('[BoardSettings] Cached settings locally');
    } catch (e) {
      debugPrint('[BoardSettings] Error caching settings: $e');
    }
  }

  Future<BoardSettingsNew> _getCachedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);
      if (json == null) {
        debugPrint('[BoardSettings] No cached settings, using defaults');
        return const BoardSettingsNew();
      }

      final map = jsonDecode(json) as Map<String, dynamic>;
      final settings = BoardSettingsNew(
        boardColorIndex: map['boardColorIndex'] as int? ?? 0,
        showEvaluationBar: map['showEvaluationBar'] as bool? ?? true,
        soundEnabled: map['soundEnabled'] as bool? ?? true,
        chatEnabled: map['chatEnabled'] as bool? ?? true,
        pieceStyleIndex: map['pieceStyleIndex'] as int? ?? 0,
      );
      debugPrint('[BoardSettings] Loaded settings from cache');
      return settings;
    } catch (e) {
      debugPrint('[BoardSettings] Error getting cached settings: $e');
      return const BoardSettingsNew();
    }
  }

  /// Clear cache (useful on sign out)
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      debugPrint('[BoardSettings] Cleared cache');
    } catch (e) {
      debugPrint('[BoardSettings] Error clearing cache: $e');
    }
  }
}

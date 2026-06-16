import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/live_activity_mode_provider.dart';
import 'package:chessever2/providers/pip_mode_provider.dart';
import 'package:chessever2/repository/board_settings/models/board_settings_model.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/utils/board_customization_utils.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Board color enum matching index values stored in Supabase (DEPRECATED - kept for migration)
enum BoardColor {
  defaultColor, // index 0
  brown, // index 1
  grey, // index 2
  green, // index 3
  orange, // index 4
  purple, // index 5
  blue, // index 6
  pink, // index 7
}

/// Board settings configuration class
class BoardSettingsNew {
  const BoardSettingsNew({
    this.boardColorIndex = 0,
    this.boardThemeIndex = 9, // Grey (default chessground theme)
    this.showEvaluationBar = true,
    this.soundEnabled = true,
    this.chatEnabled = true,
    this.pieceStyleIndex = 0, // cburnett (Colin M.L. Burnett)
    this.gamesListViewModeIndex = 1, // chessBoardGrid (Grid)
    this.useFigurine =
        true, // Use chess piece symbols (♔♕♖♗♘) instead of letters
    this.showCoordinates = true,
    this.rawPgnMode = false,
    this.pipModeIndex = 1, // PipMode.live (default)
    this.liveActivityModeIndex = 0, // LiveActivityMode.off (default)
  });

  /// DEPRECATED: Kept for backwards compatibility migration only
  final int boardColorIndex;

  /// New: Index into kBoardThemes list (chessground themes)
  final int boardThemeIndex;
  final bool showEvaluationBar;
  final bool soundEnabled;
  final bool chatEnabled;

  /// Index into PieceSet.values (chessground piece sets)
  final int pieceStyleIndex;

  /// Games list view mode: 0=gamesCard, 1=chessBoardGrid, 2=chessBoard
  final int gamesListViewModeIndex;

  /// Use figurine notation (chess piece symbols) instead of letters (K, Q, R, B, N)
  final bool useFigurine;

  /// Show A-H and 1-8 labels along the board edges.
  final bool showCoordinates;

  /// Hide auto symbols (NAGs / Lichess annotations) and PGN comments in the
  /// move-list notation. Renders the moves as clean PGN.
  final bool rawPgnMode;

  /// Picture-in-Picture eligibility, stored as the PipMode index
  /// (0=off, 1=live). Defaults to live when the device supports PiP.
  final int pipModeIndex;

  /// Picture-in-Picture mode as an enum.
  PipMode get pipMode => PipModeInfo.fromIndex(pipModeIndex);

  /// Live Activity / live-notification eligibility, stored as the
  /// LiveActivityMode index (0=off, 1=live, 2=all).
  final int liveActivityModeIndex;

  /// Live Activity mode as an enum.
  LiveActivityMode get liveActivityMode =>
      LiveActivityModeInfo.fromIndex(liveActivityModeIndex);

  /// Get the current piece set from chessground
  PieceSet get pieceSet => getPieceSetByIndex(pieceStyleIndex);

  /// Get the PieceAssets for the current piece set
  PieceAssets get pieceAssets => pieceSet.assets;

  /// Get the ChessboardColorScheme with our custom last move highlight
  ChessboardColorScheme get colorScheme =>
      getColorSchemeByIndex(boardThemeIndex);

  /// Get the board theme option
  BoardThemeOption get boardTheme => getBoardThemeByIndex(boardThemeIndex);

  // DEPRECATED: Legacy accessors kept for backwards compatibility
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

  BoardSettingsNew copyWith({
    int? boardColorIndex,
    int? boardThemeIndex,
    bool? showEvaluationBar,
    bool? soundEnabled,
    bool? chatEnabled,
    int? pieceStyleIndex,
    int? gamesListViewModeIndex,
    bool? useFigurine,
    bool? showCoordinates,
    bool? rawPgnMode,
    int? pipModeIndex,
    int? liveActivityModeIndex,
  }) {
    return BoardSettingsNew(
      boardColorIndex: boardColorIndex ?? this.boardColorIndex,
      boardThemeIndex: boardThemeIndex ?? this.boardThemeIndex,
      showEvaluationBar: showEvaluationBar ?? this.showEvaluationBar,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      chatEnabled: chatEnabled ?? this.chatEnabled,
      pieceStyleIndex: pieceStyleIndex ?? this.pieceStyleIndex,
      gamesListViewModeIndex:
          gamesListViewModeIndex ?? this.gamesListViewModeIndex,
      useFigurine: useFigurine ?? this.useFigurine,
      showCoordinates: showCoordinates ?? this.showCoordinates,
      rawPgnMode: rawPgnMode ?? this.rawPgnMode,
      pipModeIndex: pipModeIndex ?? this.pipModeIndex,
      liveActivityModeIndex:
          liveActivityModeIndex ?? this.liveActivityModeIndex,
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
      final response =
          await _supabase
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

      // Migration: If boardThemeIndex is 0 (default) but boardColorIndex is set,
      // migrate old color to new theme
      int boardThemeIndex = model.boardThemeIndex;
      if (boardThemeIndex == 0 && model.boardColorIndex > 0) {
        boardThemeIndex = migrateOldBoardColorToTheme(model.boardColorIndex);
        debugPrint(
          '[BoardSettings] Migrated old boardColorIndex ${model.boardColorIndex} to boardThemeIndex $boardThemeIndex',
        );
      }

      final settings = BoardSettingsNew(
        boardColorIndex: model.boardColorIndex,
        boardThemeIndex: boardThemeIndex,
        showEvaluationBar: model.showEvaluationBar,
        soundEnabled: model.soundEnabled,
        chatEnabled: model.chatEnabled,
        pieceStyleIndex: model.pieceStyleIndex,
        gamesListViewModeIndex: model.gamesListViewModeIndex,
        useFigurine: model.useFigurine,
        showCoordinates: model.showCoordinates,
        rawPgnMode: model.rawPgnMode,
        // pip_mode isn't part of BoardSettingsModel's mapper; read it straight
        // from the row so we don't need to regenerate the dart_mappable code.
        pipModeIndex: (response['pip_mode'] as int?) ?? 1,
        liveActivityModeIndex: (response['live_activity_mode'] as int?) ?? 0,
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

  /// Set board theme by index (chessground themes)
  Future<void> setBoardThemeIndex(int index) async {
    final clamped = index.clamp(0, kBoardThemes.length - 1);
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(boardThemeIndex: clamped);
    debugPrint(
      '🎨 BoardSettings: Board theme changed to index=$clamped (${kBoardThemes[clamped].name})',
    );
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Set piece set by index (chessground piece sets)
  Future<void> setPieceSetIndex(int index) async {
    final clamped = index.clamp(0, PieceSet.values.length - 1);
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(pieceStyleIndex: clamped);
    debugPrint(
      '♟️ BoardSettings: Piece set changed to index=$clamped (${PieceSet.values[clamped].label})',
    );
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Set games list view mode index (0=gamesCard, 1=chessBoardGrid, 2=chessBoard)
  Future<void> setGamesListViewModeIndex(int index) async {
    final clamped = index.clamp(0, 2);
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(gamesListViewModeIndex: clamped);
    debugPrint(
      '📋 BoardSettings: Games list view mode changed to index=$clamped',
    );
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Set Picture-in-Picture mode (premium-gated by the caller).
  Future<void> setPipMode(PipMode mode) async {
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(pipModeIndex: mode.index);
    debugPrint('📺 BoardSettings: PiP mode changed to ${mode.label}');
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Set Live Activity / live-notification mode.
  Future<void> setLiveActivityMode(LiveActivityMode mode) async {
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(
      liveActivityModeIndex: mode.index,
    );
    debugPrint('🔔 BoardSettings: Live Activity mode changed to ${mode.label}');
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Toggle figurine notation (chess piece symbols instead of letters)
  Future<void> toggleFigurine(bool value) async {
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(useFigurine: value);
    debugPrint(
      '♔ BoardSettings: Figurine notation ${value ? 'enabled' : 'disabled'}',
    );
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Toggle board coordinates (A-H, 1-8)
  Future<void> toggleShowCoordinates(bool value) async {
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(showCoordinates: value);
    debugPrint(
      '🔤 BoardSettings: Coordinates ${value ? 'shown' : 'hidden'}',
    );
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Toggle raw PGN mode (hide auto symbols + comments in notation)
  Future<void> toggleRawPgnMode(bool value) async {
    final currentState = state.valueOrNull ?? const BoardSettingsNew();
    final newSettings = currentState.copyWith(rawPgnMode: value);
    debugPrint(
      '📜 BoardSettings: Raw PGN mode ${value ? 'enabled' : 'disabled'}',
    );
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
      unawaited(_saveToSupabase(settings, userId));
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
          'board_theme_index': settings.boardThemeIndex,
          'show_evaluation_bar': settings.showEvaluationBar,
          'sound_enabled': settings.soundEnabled,
          'chat_enabled': settings.chatEnabled,
          'piece_style_index': settings.pieceStyleIndex,
          'games_list_view_mode_index': settings.gamesListViewModeIndex,
          'use_figurine': settings.useFigurine,
          'show_coordinates': settings.showCoordinates,
          'raw_pgn_mode': settings.rawPgnMode,
          'pip_mode': settings.pipModeIndex,
          'live_activity_mode': settings.liveActivityModeIndex,
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
      final db = AppDatabase.instance;
      final json = jsonEncode({
        'boardColorIndex': settings.boardColorIndex,
        'boardThemeIndex': settings.boardThemeIndex,
        'showEvaluationBar': settings.showEvaluationBar,
        'soundEnabled': settings.soundEnabled,
        'chatEnabled': settings.chatEnabled,
        'pieceStyleIndex': settings.pieceStyleIndex,
        'gamesListViewModeIndex': settings.gamesListViewModeIndex,
        'useFigurine': settings.useFigurine,
        'showCoordinates': settings.showCoordinates,
        'rawPgnMode': settings.rawPgnMode,
        'pipModeIndex': settings.pipModeIndex,
        'liveActivityModeIndex': settings.liveActivityModeIndex,
      });
      await db.setString(_cacheKey, json);
      debugPrint('[BoardSettings] Cached settings locally');
    } catch (e) {
      debugPrint('[BoardSettings] Error caching settings: $e');
    }
  }

  Future<BoardSettingsNew> _getCachedSettings() async {
    try {
      final db = AppDatabase.instance;
      final json = await db.getString(_cacheKey);
      if (json == null) {
        debugPrint('[BoardSettings] No cached settings, using defaults');
        return const BoardSettingsNew();
      }

      final map = jsonDecode(json) as Map<String, dynamic>;
      final boardColorIndex = map['boardColorIndex'] as int? ?? 0;
      int boardThemeIndex = map['boardThemeIndex'] as int? ?? 0;

      // Migration: If boardThemeIndex is 0 (default) but boardColorIndex is set,
      // migrate old color to new theme
      if (boardThemeIndex == 0 && boardColorIndex > 0) {
        boardThemeIndex = migrateOldBoardColorToTheme(boardColorIndex);
        debugPrint(
          '[BoardSettings] Cache migration: boardColorIndex $boardColorIndex -> boardThemeIndex $boardThemeIndex',
        );
      }

      final settings = BoardSettingsNew(
        boardColorIndex: boardColorIndex,
        boardThemeIndex: boardThemeIndex,
        showEvaluationBar: map['showEvaluationBar'] as bool? ?? true,
        soundEnabled: map['soundEnabled'] as bool? ?? true,
        chatEnabled: map['chatEnabled'] as bool? ?? true,
        pieceStyleIndex: map['pieceStyleIndex'] as int? ?? 0,
        gamesListViewModeIndex: map['gamesListViewModeIndex'] as int? ?? 0,
        useFigurine: map['useFigurine'] as bool? ?? true,
        showCoordinates: map['showCoordinates'] as bool? ?? true,
        rawPgnMode: map['rawPgnMode'] as bool? ?? false,
        pipModeIndex: map['pipModeIndex'] as int? ?? 1,
        liveActivityModeIndex: map['liveActivityModeIndex'] as int? ?? 0,
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
      final db = AppDatabase.instance;
      await db.remove(_cacheKey);
      debugPrint('[BoardSettings] Cleared cache');
    } catch (e) {
      debugPrint('[BoardSettings] Error clearing cache: $e');
    }
  }
}

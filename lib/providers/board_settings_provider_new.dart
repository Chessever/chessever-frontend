import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/utils/board_customization_utils.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    this.boardThemeIndex = 0, // New: chessground theme index
    this.showEvaluationBar = true,
    this.soundEnabled = true,
    this.chatEnabled = true,
    this.pieceStyleIndex = 0, // Now used for chessground PieceSet
    this.gamesListViewModeIndex = 0,
    this.useFigurine =
        true, // Use chess piece symbols (♔♕♖♗♘) instead of letters
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
    );
  }
}

/// Provider for managing board settings as device-local preferences.
final boardSettingsProviderNew =
    AsyncNotifierProvider<BoardSettingsNotifierNew, BoardSettingsNew>(
      BoardSettingsNotifierNew.new,
    );

class BoardSettingsNotifierNew extends AsyncNotifier<BoardSettingsNew> {
  static const String _cacheKey = 'cached_board_settings';

  @override
  Future<BoardSettingsNew> build() async {
    return await _loadSettings();
  }

  Future<BoardSettingsNew> _loadSettings() async {
    try {
      // Board/UI preferences are device-local. Do not fetch them from
      // Supabase, otherwise desktop and phone overwrite each other.
      return await _getCachedSettings();
    } catch (e, st) {
      debugPrint('[BoardSettings] Error loading local settings: $e');
      debugPrint('[BoardSettings] Stack: $st');
      return const BoardSettingsNew();
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

  /// Refresh settings from the on-device cache.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadSettings());
  }

  /// Refresh device-local settings from the on-device cache.
  Future<void> syncFromSupabase() async {
    debugPrint('[BoardSettings] Refreshing local settings...');
    try {
      await refresh();
      debugPrint('[BoardSettings] Local refresh complete');
    } catch (e, st) {
      debugPrint('[BoardSettings] Error syncing: $e');
      debugPrint('[BoardSettings] Stack: $st');
    }
  }

  // Private methods

  Future<void> _persist(BoardSettingsNew settings) async {
    try {
      // Cache locally first (fast, immediate). Board/UI preferences are
      // intentionally not synced across platforms because desktop and phone
      // users can choose different layouts, board themes, notation, sounds,
      // and other device-specific settings.
      await _cacheSettings(settings);
    } catch (e, st) {
      debugPrint('[BoardSettings] Error persisting settings: $e');
      debugPrint('[BoardSettings] Stack: $st');
      // Don't rethrow - we don't want to block UI on persistence errors
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

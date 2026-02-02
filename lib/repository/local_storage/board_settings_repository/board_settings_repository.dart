import 'dart:convert';

import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Add an enum for board colors
enum BoardColor { defaultColor, brown, grey, green, orange, purple, blue, pink }

// Chess board theme class - ADD THIS CLASS
class ChessBoardTheme {
  const ChessBoardTheme({
    required this.lightSquareColor,
    required this.darkSquareColor,
    required this.name,
  });

  final Color lightSquareColor;
  final Color darkSquareColor;
  final String name;
}

final boardSettingsRepository = AutoDisposeProvider<_BoardSettingsRepository>((
  ref,
) {
  return _BoardSettingsRepository(ref);
});

enum BoardSettingsKey { boardSettings }

class _BoardSettingsRepository {
  _BoardSettingsRepository(this.ref);

  final Ref ref;
  static const String _boardSettingsKey = 'board_settings';

  // Get the actual Color object from the BoardColor enum
  Color getBoardColorFromEnum(BoardColor boardColor) {
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

  // Get the BoardColor enum from a Color object
  BoardColor getBoardColorEnum(Color color) {
    if (color.value == const Color(0xFF0FB4E5).value) {
      return BoardColor.defaultColor;
    } else if (color.value == Colors.brown.value) {
      return BoardColor.brown;
    } else if (color.value == Colors.grey.value) {
      return BoardColor.grey;
    } else if (color.value == Colors.green.value) {
      return BoardColor.green;
    } else if (color.value == Colors.orange.value) {
      return BoardColor.orange;
    } else if (color.value == Colors.purple.value) {
      return BoardColor.purple;
    } else if (color.value == Colors.blue.value) {
      return BoardColor.blue;
    } else if (color.value == Colors.pink.value) {
      return BoardColor.pink;
    } else {
      // Default fallback
      return BoardColor.brown;
    }
  }

  // Get chess board theme based on BoardColor
  ChessBoardTheme getBoardTheme(Color boardColor) {
    final boardColorEnum = getBoardColorEnum(boardColor);

    switch (boardColorEnum) {
      case BoardColor.defaultColor:
        return const ChessBoardTheme(
          lightSquareColor: Color(0xFFD1E9E9), // Light grey-white
          darkSquareColor: Color(0xFF6B939F), // Your default teal color
          name: 'Default',
        );

      case BoardColor.brown:
        return const ChessBoardTheme(
          lightSquareColor: Color(0xFFF0D9B5), // Classic chess.com light brown
          darkSquareColor: Color(0xFFB58863), // Classic chess.com dark brown
          name: 'Brown',
        );

      case BoardColor.grey:
        return const ChessBoardTheme(
          lightSquareColor: Color(0xFFF5F5F5), // Light grey
          darkSquareColor: Color(0xFF9E9E9E), // Medium grey
          name: 'Grey',
        );

      case BoardColor.green:
        return const ChessBoardTheme(
          lightSquareColor: Color(0xFFEEFFEE), // Very light green
          darkSquareColor: Color(0xFF4CAF50), // Material green
          name: 'Green',
        );

      case BoardColor.orange:
        return const ChessBoardTheme(
          lightSquareColor: Color(0xFFFCE6C9), // Soft peach/beige
          darkSquareColor: Color(0xFFD18B47), // Muted terracotta
          name: 'Orange',
        );

      case BoardColor.purple:
        return const ChessBoardTheme(
          lightSquareColor: Color(0xFFE8E0F0), // Pale lavender
          darkSquareColor: Color(0xFF8B6B9E), // Muted grape
          name: 'Purple',
        );

      case BoardColor.blue:
        return const ChessBoardTheme(
          lightSquareColor: Color(0xFFDEE3E6), // Cool grey-white
          darkSquareColor: Color(0xFF7D99A8), // Slate blue
          name: 'Blue',
        );

      case BoardColor.pink:
        return const ChessBoardTheme(
          lightSquareColor: Color(0xFFF0D9E0), // Pale rose
          darkSquareColor: Color(0xFFB57281), // Dusty rose
          name: 'Pink',
        );
    }
  }

  Future<void> saveBoardSettings(BoardSettings settings) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final Map<String, dynamic> data = {
        'boardColorIndex': getBoardColorEnum(settings.boardColor).index,
        'showEvaluationBar': settings.showEvaluationBar,
        'soundEnabled': settings.soundEnabled,
        'chatEnabled': settings.chatEnabled,
        'pieceStyle': settings.pieceStyle.index,
      };

      await db.setString(_boardSettingsKey, jsonEncode(data));
    } catch (error, _) {
      // Local storage failure is not critical - Supabase is source of truth
    }
  }

  Future<BoardSettings?> loadBoardSettings() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final String? settingsString = await db.getString(_boardSettingsKey);

      if (settingsString == null) {
        return null;
      }

      try {
        final Map<String, dynamic> data = jsonDecode(settingsString);

        final boardColorIndex =
            data['boardColorIndex'] ?? BoardColor.brown.index;
        final boardColorEnum = BoardColor.values[boardColorIndex];

        return BoardSettings(
          boardColor: getBoardColorFromEnum(boardColorEnum),
          showEvaluationBar: data['showEvaluationBar'],
          soundEnabled: data['soundEnabled'],
          chatEnabled: data['chatEnabled'] ?? true,
          pieceStyle: PieceStyle.values[data['pieceStyle']],
        );
      } catch (e) {
        return null;
      }
    } catch (error, _) {
      // Local storage failure is not critical - return null and use defaults
      return null;
    }
  }
}

import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:convert';

// Add an enum for board colors
enum BoardColor { defaultColor, brown, grey, green }

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
    }
  }

  Future<void> saveBoardSettings(BoardSettings settings) async {
    try {
      final prefs = ref.read(sharedPreferencesRepository);
      final Map<String, dynamic> data = {
        'boardColorIndex': getBoardColorEnum(settings.boardColor).index,
        'showEvaluationBar': settings.showEvaluationBar,
        'soundEnabled': settings.soundEnabled,
        'chatEnabled': settings.chatEnabled,
        'pieceStyle': settings.pieceStyle.index,
      };

      await prefs.setString(_boardSettingsKey, jsonEncode(data));
    } catch (error, _) {
      rethrow;
    }
  }

  Future<BoardSettings?> loadBoardSettings() async {
    try {
      final prefs = ref.read(sharedPreferencesRepository);
      final String? settingsString = await prefs.getString(_boardSettingsKey);

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
      rethrow;
    }
  }
}

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:convert';
import '../../../providers/board_settings_provider.dart';

// Add an enum for board colors
enum BoardColor { defaultColor, brown, grey, green }

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

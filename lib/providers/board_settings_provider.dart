import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../repository/local_storage/board_settings_repository/board_settings_repository.dart';

enum PieceStyle {
  standard('Standard'),
  modern('Modern'),
  classic('Classic'),
  pixel('Pixel Art'),
  fantasy('Fantasy');

  final String display;
  const PieceStyle(this.display);
}

class BoardSettings {
  final Color boardColor;
  final bool showEvaluationBar;
  final bool soundEnabled;
  final bool chatEnabled;
  final PieceStyle pieceStyle;

  const BoardSettings({
    required this.boardColor,
    required this.showEvaluationBar,
    required this.soundEnabled,
    required this.chatEnabled,
    required this.pieceStyle,
  });

  BoardSettings copyWith({
    Color? boardColor,
    bool? showEvaluationBar,
    bool? soundEnabled,
    bool? chatEnabled,
    PieceStyle? pieceStyle,
  }) {
    return BoardSettings(
      boardColor: boardColor ?? this.boardColor,
      showEvaluationBar: showEvaluationBar ?? this.showEvaluationBar,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      chatEnabled: chatEnabled ?? this.chatEnabled,
      pieceStyle: pieceStyle ?? this.pieceStyle,
    );
  }
}

final boardSettingsProvider =
    StateNotifierProvider<_BoardSettingsNotifier, BoardSettings>((ref) {
      return _BoardSettingsNotifier(ref: ref);
    });

class _BoardSettingsNotifier extends StateNotifier<BoardSettings> {
  _BoardSettingsNotifier({required this.ref})
    : super(
        const BoardSettings(
          boardColor: Color(0xFF0FB4E5),
          showEvaluationBar: true,
          soundEnabled: true,
          chatEnabled: true,
          pieceStyle: PieceStyle.standard,
        ),
      ) {
    init();
  }

  final Ref ref;

  Future<void> init() async {
    try {
      final savedSettings =
          await ref.read(boardSettingsRepository).loadBoardSettings();
      if (savedSettings != null) {
        state = savedSettings;
      }
    } catch (error, _) {
      rethrow;
    }
  }

  void setBoardColor(Color color) {
    state = state.copyWith(boardColor: color);
    _saveSettings();
  }

  void toggleEvaluationBar() {
    state = state.copyWith(showEvaluationBar: !state.showEvaluationBar);
    _saveSettings();
  }

  void toggleSound() {
    state = state.copyWith(soundEnabled: !state.soundEnabled);
    _saveSettings();
  }

  void toggleChat() {
    state = state.copyWith(chatEnabled: !state.chatEnabled);
    _saveSettings();
  }

  void setPieceStyle(PieceStyle style) {
    state = state.copyWith(pieceStyle: style);
    _saveSettings();
  }

  Future<void> _saveSettings() async {
    try {
      await ref.read(boardSettingsRepository).saveBoardSettings(state);
    } catch (error, _) {
      rethrow;
    }
  }
}

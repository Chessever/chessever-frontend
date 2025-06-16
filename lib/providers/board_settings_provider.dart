import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../services/settings_service.dart';

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
  final PieceStyle pieceStyle;

  const BoardSettings({
    required this.boardColor,
    required this.showEvaluationBar,
    required this.soundEnabled,
    required this.pieceStyle,
  });

  BoardSettings copyWith({
    Color? boardColor,
    bool? showEvaluationBar,
    bool? soundEnabled,
    PieceStyle? pieceStyle,
  }) {
    return BoardSettings(
      boardColor: boardColor ?? this.boardColor,
      showEvaluationBar: showEvaluationBar ?? this.showEvaluationBar,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      pieceStyle: pieceStyle ?? this.pieceStyle,
    );
  }
}

class BoardSettingsNotifier extends StateNotifier<BoardSettings> {
  BoardSettingsNotifier()
    : super(
        const BoardSettings(
          boardColor: Colors.brown,
          showEvaluationBar: true,
          soundEnabled: true,
          pieceStyle: PieceStyle.standard,
        ),
      ) {
    // Load saved settings when initialized
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final savedSettings = await SettingsService.loadBoardSettings();
    if (savedSettings != null) {
      state = savedSettings;
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

  void setPieceStyle(PieceStyle style) {
    state = state.copyWith(pieceStyle: style);
    _saveSettings();
  }

  Future<void> _saveSettings() async {
    await SettingsService.saveBoardSettings(state);
  }
}

final boardSettingsProvider =
    StateNotifierProvider<BoardSettingsNotifier, BoardSettings>(
      (ref) => BoardSettingsNotifier(),
    );

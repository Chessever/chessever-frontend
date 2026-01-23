import 'package:dart_mappable/dart_mappable.dart';

part 'board_settings_model.mapper.dart';

@MappableClass()
class BoardSettingsModel with BoardSettingsModelMappable {
  final String id;
  final String userId;
  final int boardColorIndex; // DEPRECATED: 0=default, 1=brown, 2=grey, 3=green, 4=orange, 5=purple, 6=blue, 7=pink
  final int boardThemeIndex; // NEW: Index into chessground's board themes
  final bool showEvaluationBar;
  final bool soundEnabled;
  final bool chatEnabled;
  final int pieceStyleIndex; // Index into chessground's PieceSet
  final int gamesListViewModeIndex; // 0=gamesCard, 1=chessBoardGrid, 2=chessBoard
  final DateTime createdAt;
  final DateTime updatedAt;

  const BoardSettingsModel({
    required this.id,
    required this.userId,
    required this.boardColorIndex,
    required this.boardThemeIndex,
    required this.showEvaluationBar,
    required this.soundEnabled,
    required this.chatEnabled,
    required this.pieceStyleIndex,
    required this.gamesListViewModeIndex,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create BoardSettingsModel from Supabase response
  /// Note: Reads from user_engine_settings table (unified settings table)
  factory BoardSettingsModel.fromSupabase(Map<String, dynamic> json) {
    return BoardSettingsModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      boardColorIndex: json['board_color_index'] as int? ?? 0,
      boardThemeIndex: json['board_theme_index'] as int? ?? 0,
      showEvaluationBar: json['show_evaluation_bar'] as bool? ?? true,
      soundEnabled: json['sound_enabled'] as bool? ?? true,
      chatEnabled: json['chat_enabled'] as bool? ?? true,
      pieceStyleIndex: json['piece_style_index'] as int? ?? 0,
      gamesListViewModeIndex: json['games_list_view_mode_index'] as int? ?? 1, // Default to chessBoardGrid
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to Supabase format (for updates)
  Map<String, dynamic> toSupabase() {
    return {
      'id': id,
      'user_id': userId,
      'board_color_index': boardColorIndex,
      'board_theme_index': boardThemeIndex,
      'show_evaluation_bar': showEvaluationBar,
      'sound_enabled': soundEnabled,
      'chat_enabled': chatEnabled,
      'piece_style_index': pieceStyleIndex,
      'games_list_view_mode_index': gamesListViewModeIndex,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Convert to Supabase format for upsert (without id, timestamps auto-generated)
  Map<String, dynamic> toSupabaseUpsert(String userId) {
    return {
      'user_id': userId,
      'board_color_index': boardColorIndex,
      'board_theme_index': boardThemeIndex,
      'show_evaluation_bar': showEvaluationBar,
      'sound_enabled': soundEnabled,
      'chat_enabled': chatEnabled,
      'piece_style_index': pieceStyleIndex,
      'games_list_view_mode_index': gamesListViewModeIndex,
    };
  }

  /// Default settings
  factory BoardSettingsModel.defaultSettings(String userId) {
    return BoardSettingsModel(
      id: '',
      userId: userId,
      boardColorIndex: 0, // DEPRECATED
      boardThemeIndex: 0, // Brown (default)
      showEvaluationBar: true,
      soundEnabled: true,
      chatEnabled: true,
      pieceStyleIndex: 0, // cburnett (default)
      gamesListViewModeIndex: 1, // chessBoardGrid view (default)
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'saved_analysis.mapper.dart';

@MappableClass()
class SavedAnalysis with SavedAnalysisMappable {
  final String id;
  final String userId;
  final String? folderId;
  final String title;

  // Original game reference (if from live game)
  final String? sourceGameId;
  final String? sourceTournamentId;

  // Core game data
  final ChessGame chessGame;

  // Analysis-specific data
  final Map<String, dynamic> analysisState;
  final Map<String, String> variationComments;
  final int lastViewedPosition;

  // Metadata
  final List<String> tags;
  final String? notes;
  final bool isFavorite;

  // Timestamps
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;

  const SavedAnalysis({
    required this.id,
    required this.userId,
    this.folderId,
    required this.title,
    this.sourceGameId,
    this.sourceTournamentId,
    required this.chessGame,
    required this.analysisState,
    required this.variationComments,
    required this.lastViewedPosition,
    required this.tags,
    this.notes,
    required this.isFavorite,
    required this.createdAt,
    required this.updatedAt,
    this.lastOpenedAt,
  });

  /// Create SavedAnalysis from Supabase response
  factory SavedAnalysis.fromSupabase(Map<String, dynamic> json) {
    return SavedAnalysis(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      folderId: json['folder_id'] as String?,
      title: json['title'] as String,
      sourceGameId: json['source_game_id'] as String?,
      sourceTournamentId: json['source_tournament_id'] as String?,
      chessGame: ChessGame.fromJson(
        json['chess_game'] as Map<String, dynamic>,
      ),
      analysisState: (json['analysis_state'] as Map<String, dynamic>?) ?? {},
      variationComments:
          ((json['variation_comments'] as Map<String, dynamic>?) ?? {})
              .cast<String, String>(),
      lastViewedPosition: json['last_viewed_position'] as int? ?? -1,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      notes: json['notes'] as String?,
      isFavorite: json['is_favorite'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastOpenedAt: json['last_opened_at'] != null
          ? DateTime.parse(json['last_opened_at'] as String)
          : null,
    );
  }

  /// Convert to Supabase format (for updates)
  Map<String, dynamic> toSupabase() {
    return {
      'id': id,
      'user_id': userId,
      'folder_id': folderId,
      'title': title,
      'source_game_id': sourceGameId,
      'source_tournament_id': sourceTournamentId,
      'chess_game': chessGame.toJson(),
      'analysis_state': analysisState,
      'variation_comments': variationComments,
      'last_viewed_position': lastViewedPosition,
      'tags': tags,
      'notes': notes,
      'is_favorite': isFavorite,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (lastOpenedAt != null)
        'last_opened_at': lastOpenedAt!.toIso8601String(),
    };
  }

  /// Convert to Supabase format for insert (without id, timestamps auto-generated)
  Map<String, dynamic> toSupabaseInsert() {
    return {
      'user_id': userId,
      'folder_id': folderId,
      'title': title,
      'source_game_id': sourceGameId,
      'source_tournament_id': sourceTournamentId,
      'chess_game': chessGame.toJson(),
      'analysis_state': analysisState,
      'variation_comments': variationComments,
      'last_viewed_position': lastViewedPosition,
      'tags': tags,
      'notes': notes,
      'is_favorite': isFavorite,
    };
  }


  /// Get move count from chess game
  int get moveCount => chessGame.mainline.length;

  /// Get opening name if available from metadata
  String? get openingName => chessGame.metadata['Opening'] as String?;

  /// Get player names if available from metadata
  String? get whiteName => chessGame.metadata['White'] as String?;
  String? get blackName => chessGame.metadata['Black'] as String?;
}

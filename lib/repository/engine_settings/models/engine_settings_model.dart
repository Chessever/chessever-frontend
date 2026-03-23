import 'package:dart_mappable/dart_mappable.dart';

part 'engine_settings_model.mapper.dart';

@MappableClass()
class EngineSettingsModel with EngineSettingsModelMappable {
  final String id;
  final String userId;
  final bool showEngineGauge;
  final bool showDepthOverlay;
  final bool showPvArrows;
  final bool
  showEngineAnalysis; // Controls visibility of PV cards & arrows (computer icon)
  final int searchTimeIndex;
  final int principalVariationIndex;
  final int
  maxArrowsOnBoard; // Max arrows to show on board (index 0-4 = 1-5 arrows)
  final DateTime createdAt;
  final DateTime updatedAt;

  const EngineSettingsModel({
    required this.id,
    required this.userId,
    required this.showEngineGauge,
    required this.showDepthOverlay,
    required this.showPvArrows,
    required this.showEngineAnalysis,
    required this.searchTimeIndex,
    required this.principalVariationIndex,
    required this.maxArrowsOnBoard,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create EngineSettingsModel from Supabase response
  factory EngineSettingsModel.fromSupabase(Map<String, dynamic> json) {
    return EngineSettingsModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      showEngineGauge: json['show_engine_gauge'] as bool? ?? true,
      showDepthOverlay: json['show_depth_overlay'] as bool? ?? true,
      showPvArrows: json['show_pv_arrows'] as bool? ?? true,
      showEngineAnalysis: json['show_engine_analysis'] as bool? ?? true,
      searchTimeIndex: json['search_time_index'] as int? ?? 0,
      principalVariationIndex: json['principal_variation_index'] as int? ?? 4,
      maxArrowsOnBoard: json['max_arrows_on_board'] as int? ?? 2,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to Supabase format (for updates)
  Map<String, dynamic> toSupabase() {
    return {
      'id': id,
      'user_id': userId,
      'show_engine_gauge': showEngineGauge,
      'show_depth_overlay': showDepthOverlay,
      'show_pv_arrows': showPvArrows,
      'show_engine_analysis': showEngineAnalysis,
      'search_time_index': searchTimeIndex,
      'principal_variation_index': principalVariationIndex,
      'max_arrows_on_board': maxArrowsOnBoard,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Convert to Supabase format for upsert (without id, timestamps auto-generated)
  Map<String, dynamic> toSupabaseUpsert(String userId) {
    return {
      'user_id': userId,
      'show_engine_gauge': showEngineGauge,
      'show_depth_overlay': showDepthOverlay,
      'show_pv_arrows': showPvArrows,
      'show_engine_analysis': showEngineAnalysis,
      'search_time_index': searchTimeIndex,
      'principal_variation_index': principalVariationIndex,
      'max_arrows_on_board': maxArrowsOnBoard,
    };
  }

  /// Default settings
  factory EngineSettingsModel.defaultSettings(String userId) {
    return EngineSettingsModel(
      id: '',
      userId: userId,
      showEngineGauge: true,
      showDepthOverlay: true,
      showPvArrows: true,
      showEngineAnalysis: true, // Engine visibility enabled by default
      searchTimeIndex: 0, // 5 seconds default
      principalVariationIndex: 4, // Default to 5 lines (index 4)
      maxArrowsOnBoard: 2, // Default to 3 arrows (index 2)
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

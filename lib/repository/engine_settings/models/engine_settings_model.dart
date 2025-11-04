import 'package:dart_mappable/dart_mappable.dart';

part 'engine_settings_model.mapper.dart';

@MappableClass()
class EngineSettingsModel with EngineSettingsModelMappable {
  final String id;
  final String userId;
  final bool showEngineGauge;
  final bool showDepthOverlay;
  final bool showPvArrows;
  final int searchTimeIndex;
  final int principalVariationCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EngineSettingsModel({
    required this.id,
    required this.userId,
    required this.showEngineGauge,
    required this.showDepthOverlay,
    required this.showPvArrows,
    required this.searchTimeIndex,
    required this.principalVariationCount,
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
      searchTimeIndex: json['search_time_index'] as int? ?? 2,
      principalVariationCount: json['principal_variation_count'] as int? ?? 3,
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
      'search_time_index': searchTimeIndex,
      'principal_variation_count': principalVariationCount,
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
      'search_time_index': searchTimeIndex,
      'principal_variation_count': principalVariationCount,
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
      searchTimeIndex: 2, // 20s default
      principalVariationCount: 3,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

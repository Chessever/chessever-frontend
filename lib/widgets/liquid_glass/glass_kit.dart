/// Chessever adapters for the full `liquid_glass_widgets` public surface.
///
/// Import this module when modernizing a screen — it re-exports the package
/// and provides app-shaped helpers so every control path can use glass
/// consistently (loading, toast, dialog, sheet, search, lists, badges).
///
/// Package design rule (always):
/// - Glass = navigation / control layer only
/// - Content lists/cards stay opaque
/// - Never nest interactive glass inside GlassCard/GlassContainer
library;

export 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

export 'glass_avatar_island.dart';
export 'glass_back_button.dart';
export 'glass_detail_app_bar.dart';
export 'glass_feedback.dart';
export 'glass_island_search.dart';
export 'glass_island_top_bar.dart';
export 'glass_loading.dart';
export 'glass_motion.dart';
export 'home_search_providers.dart';
export 'scroll_chrome_mapper.dart';
export 'scroll_chrome_provider.dart';
export 'search_expand_state.dart';

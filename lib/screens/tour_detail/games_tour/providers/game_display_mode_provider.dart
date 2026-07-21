import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Scoped per tour id. Each tournament has its own "Focus on live games /
// Show finished / Show all" preference, defaulting to `all`. State must NOT
// bleed across tournaments — a finished game would silently vanish from the
// next event's Games tab while the round was still live (e.g. the Mamedov
// Round-10 game during Bucharest Grand Prix 2026).
//
// Within a single tournament the family entry is kept alive across tab swipes
// and category-dropdown changes (both republish `tourDetailScreenProvider`
// and tear down the screen notifier), so the toggle still sticks while the
// user stays in that event. `tournament_detail_screen` invalidates the whole
// family on `deactivate` so leaving the event resets the preference.
//
// Note: `GameDisplayMode.hideFinishedGames` is the "Focus on live games"
// mode. It no longer filters finished boards out — it only freezes a
// live-first snapshot order via [liveFocusSnapshotProvider].
final gameDisplayModeProvider =
    StateProvider.family<GameDisplayMode, String>(
      (ref, tourId) => GameDisplayMode.all,
    );

/// Frozen set of board ids that were live when "Focus on live games" was
/// activated for this tour. `null` means focus mode is off (normal order).
///
/// While non-null, the Games tab partitions each round as live-snapshot first
/// then the rest, without re-evaluating liveness on stream updates. Cleared
/// on "Show all games" and when the tournament detail screen deactivates.
final liveFocusSnapshotProvider =
    StateProvider.family<Set<String>?, String>((ref, tourId) => null);

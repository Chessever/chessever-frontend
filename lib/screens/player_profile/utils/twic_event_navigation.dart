import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/utils/twic_event_identity.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Routes a tapped event card/group from a player profile to the right place.
///
/// - Non-TWIC (real ChessEver events): resolve the canonical event page by id,
///   preserving the previous behaviour (including the error snackbar).
/// - TWIC/database events: try to resolve the canonical ChessEver event via
///   the Lichess broadcast slug carried in [site]; open its event page when it
///   exists. Otherwise open the normal tournament detail screen backed by a
///   virtual Gamebase event. TWIC events never surface "Unable to open event" —
///   a database-only event is an expected, useful destination, not an error.
///
/// See Trello "Route TWIC database event clicks to ChessEver Database".
Future<void> openProfileEvent({
  required BuildContext context,
  required WidgetRef ref,
  required PlayerProfileDataSource dataSource,
  required String tourId,
  required String eventName,
  String? site,
  String? broadcastSlug,
  String? canonicalBroadcastId,
}) async {
  HapticFeedbackService.buttonPress();
  final repo = ref.read(groupBroadcastRepositoryProvider);

  Future<bool> openBroadcastById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return false;
    try {
      final broadcast = await repo.getGroupBroadcastById(trimmed);
      ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
      if (!context.mounted) return true;
      ref.read(selectedTourModeProvider.notifier).state =
          TournamentDetailScreenMode.games;
      Navigator.pushNamed(context, '/tournament_detail_screen');
      return true;
    } catch (_) {
      return false;
    }
  }

  if (canonicalBroadcastId != null &&
      canonicalBroadcastId.trim().isNotEmpty &&
      await openBroadcastById(canonicalBroadcastId)) {
    return;
  }

  // Real ChessEver event — resolve by id (unchanged behaviour).
  if (dataSource != PlayerProfileDataSource.twic) {
    if (!await openBroadcastById(tourId)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open event')));
    }
    return;
  }

  // TWIC/database event: resolve the canonical ChessEver broadcast. Try the
  // Lichess `Site` slug first (broadcast-linked games), then the slugified
  // event name (games whose Site is a venue string, e.g. "Pasching AUT") —
  // the name slugifies to the same `tours.slug` ChessEver stores.
  final siteSlug = broadcastSlugFromSite(site);
  final nameSlug = eventNameToBroadcastSlug(eventName);
  final candidates = <String>{
    if (broadcastSlug != null && broadcastSlug.trim().isNotEmpty)
      broadcastSlug.trim(),
    if (siteSlug != null && siteSlug.isNotEmpty) siteSlug,
    if (nameSlug.isNotEmpty) nameSlug,
  };
  for (final candidate in candidates) {
    try {
      final broadcast = await repo.getGroupBroadcastBySlug(candidate);
      if (broadcast != null) {
        ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
        if (!context.mounted) return;
        ref.read(selectedTourModeProvider.notifier).state =
            TournamentDetailScreenMode.games;
        Navigator.pushNamed(context, '/tournament_detail_screen');
        return;
      }
    } catch (_) {
      // Try the next candidate / fall through to the database view.
    }
  }

  // No canonical cloud event — render a gamebase-only event through the same
  // TournamentDetailScreen shell as broadcast events, backed by virtual tours
  // and games synthesized from /api/event.
  if (!context.mounted) return;
  ref
      .read(selectedBroadcastModelProvider.notifier)
      .state = virtualGroupBroadcastForEvent(
    eventName.trim(),
    site: site,
    slug:
        (broadcastSlug != null && broadcastSlug.trim().isNotEmpty)
            ? broadcastSlug.trim()
            : siteSlug ?? (nameSlug.isNotEmpty ? nameSlug : null),
  );
  ref.read(selectedTourModeProvider.notifier).state =
      TournamentDetailScreenMode.games;
  Navigator.pushNamed(context, '/tournament_detail_screen');
}

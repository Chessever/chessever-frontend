import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/gamebase/event_view/database_event_screen.dart';
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
///   exists. Otherwise open the ChessEver Database (TWIC contents) pre-filtered
///   by [eventName]. TWIC events never surface "Unable to open event" — a
///   database-only event is an expected, useful destination, not an error.
///
/// See Trello "Route TWIC database event clicks to ChessEver Database".
Future<void> openProfileEvent({
  required BuildContext context,
  required WidgetRef ref,
  required PlayerProfileDataSource dataSource,
  required String tourId,
  required String eventName,
  String? site,
}) async {
  HapticFeedbackService.buttonPress();
  final repo = ref.read(groupBroadcastRepositoryProvider);

  // Real ChessEver event — resolve by id (unchanged behaviour).
  if (dataSource != PlayerProfileDataSource.twic) {
    try {
      final broadcast = await repo.getGroupBroadcastById(tourId);
      ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
      if (!context.mounted) return;
      Navigator.pushNamed(context, '/tournament_detail_screen');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open event')),
      );
    }
    return;
  }

  // TWIC/database event: try the canonical event page via the Lichess slug.
  final slug = broadcastSlugFromSite(site);
  if (slug != null) {
    try {
      final broadcast = await repo.getGroupBroadcastBySlug(slug);
      if (broadcast != null) {
        ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
        if (!context.mounted) return;
        Navigator.pushNamed(context, '/tournament_detail_screen');
        return;
      }
    } catch (_) {
      // Slug lookup failed — fall through to the database view.
    }
  }

  // No canonical event — synthesize one from the gamebase and open it in the
  // SAME tournament detail view broadcast events use (via a sentinel
  // GroupBroadcast). If the gamebase has no view for it, fall back to the
  // DatabaseEventScreen empty/search experience.
  final cleanName = eventName.trim();
  final view = await ref.read(gamebaseEventViewProvider(cleanName).future);
  if (!context.mounted) return;

  if (view == null) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DatabaseEventScreen(eventName: cleanName, site: site),
      ),
    );
    return;
  }

  ref.read(selectedBroadcastModelProvider.notifier).state =
      virtualGroupBroadcastForEvent(cleanName);
  Navigator.pushNamed(context, '/tournament_detail_screen');
}

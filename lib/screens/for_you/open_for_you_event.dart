import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Where a For You event tap came from, logged as the `category` of
/// 'Tournament Opened' so For You taps never blend into the Events lists.
enum ForYouEventSource {
  /// The Today feed. Keeps `forYou`, the label it logged while it lived under
  /// Events, so dashboards segmented on category=forYou keep counting it.
  today('forYou'),

  /// For You search results.
  search('forYouSearch'),

  /// The Discovery tab.
  discovery('forYouDiscovery');

  const ForYouEventSource(this.analyticsLabel);

  final String analyticsLabel;
}

/// Opens an event from a For You surface.
///
/// For You holds no Events list, so this goes straight to the shared
/// tournament navigator (which fetches the broadcast by id) instead of
/// spinning up the Events screen's controller just to borrow its tap handler.
///
/// [source] says which For You surface the tap came from. [category] is the
/// older Events-list label, kept only so existing callers compile: when
/// [source] is omitted, `search` maps to [ForYouEventSource.search] and
/// anything else to [ForYouEventSource.today].
Future<void> openForYouEvent(
  BuildContext context,
  WidgetRef ref, {
  required String eventId,
  ForYouEventSource? source,
  GroupEventCategory? category,
}) async {
  final resolvedSource =
      source ??
      (category == GroupEventCategory.search
          ? ForYouEventSource.search
          : ForYouEventSource.today);
  final navigation = ref.read(tournamentNavigationProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await navigation.openTournament(
      context: context,
      id: eventId,
      category: category ?? GroupEventCategory.current,
      analyticsSource: resolvedSource.analyticsLabel,
    );
  } catch (error) {
    debugPrint('[ForYou] open event $eventId failed: $error');
    if (messenger != null && messenger.mounted) {
      showAppSnackOn(
        messenger,
        "Couldn't open this event",
        tone: AppSnackTone.danger,
      );
    }
  }
}

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/utils/library_utils.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether the user is allowed to save [gamesToAdd] more games to their library.
///
/// Premium users always pass. Free users are capped at [kFreeSavedGamesLimit]
/// total saved games across every database; when adding [gamesToAdd] would
/// push the total above the cap, the paywall is shown and the future resolves
/// to whether the user subscribed during that sheet.
///
/// [gamesToAdd] is the count being added in this operation (1 for a single
/// save, N for a bulk/import action). The lookup uses the nearest
/// [ProviderScope] so this can be called from places that don't have a
/// `WidgetRef` (e.g. top-level `showXxxSheet` functions).
Future<bool> canSaveMoreGames(
  BuildContext context, {
  int gamesToAdd = 1,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);

  if (container.read(subscriptionProvider).isSubscribed) return true;

  final analyses = await container.read(libraryAnalysesProvider.future);
  if (analyses.length + gamesToAdd <= kFreeSavedGamesLimit) return true;

  if (!context.mounted) return false;
  return await showPremiumPaywallSheet(context: context);
}

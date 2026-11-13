import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Opens [groupId] in Combined, behind the Premium gate.
///
/// A subscriber switches at once. Anyone else sees the paywall and lands in
/// Combined after a confirmed purchase or restore. Returns whether Combined
/// was turned on.
///
/// [context] must outlive the menu, dropdown or dialog that called this: pass
/// the screen's or the app-bar chip's context, never a row inside an overlay
/// that closes on tap.
Future<bool> openCombinedCategory(
  BuildContext context, {
  required String groupId,
  required String returnTo,
}) async {
  if (groupId.isEmpty || !context.mounted) return false;
  // Read before the gate: the caller's own scope may be gone by the time a
  // purchase completes.
  final container = ProviderScope.containerOf(context, listen: false);
  final prefs = container.read(combinedCategoryPrefsProvider.notifier);
  final gamesTab = container.read(combinedGamesTabRequestProvider.notifier);
  if (container.read(combinedCategoryEntitledProvider)) {
    await prefs.setSelected(groupId, true);
    gamesTab.state++;
    return true;
  }
  var opened = false;
  await requirePremiumGuardNoRef(
    context,
    featureId: kCombinedCategoryFeatureId,
    returnTo: returnTo,
    onEntitled: () async {
      opened = true;
      await prefs.setSelected(groupId, true);
      gamesTab.state++;
    },
  );
  return opened;
}

/// Leaves Combined for [groupId]; the event shows its real category again.
Future<void> closeCombinedCategory(WidgetRef ref, String groupId) => ref
    .read(combinedCategoryPrefsProvider.notifier)
    .setSelected(groupId, false);

import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Opens [groupId] in Combined and remembers the choice for this event.
/// Returns whether Combined was turned on.
Future<bool> openCombinedCategory(
  BuildContext context, {
  required String groupId,
}) async {
  if (groupId.isEmpty || !context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  final prefs = container.read(combinedCategoryPrefsProvider.notifier);
  final gamesTab = container.read(combinedGamesTabRequestProvider.notifier);
  await prefs.setSelected(groupId, true);
  gamesTab.state++;
  return true;
}

/// Leaves Combined for [groupId]; the event shows its real category again.
Future<void> closeCombinedCategory(WidgetRef ref, String groupId) => ref
    .read(combinedCategoryPrefsProvider.notifier)
    .setSelected(groupId, false);

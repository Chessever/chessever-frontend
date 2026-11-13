import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Real round ids scope each source group independently of its time bucket.
/// Parent-round folding and background arrivals keep these choices intact.
final combinedGroupExpansionProvider =
    StateNotifierProvider<CombinedGroupExpansion, Map<String, bool>>(
      (ref) => CombinedGroupExpansion(),
    );

class CombinedGroupExpansion extends StateNotifier<Map<String, bool>> {
  CombinedGroupExpansion() : super(const {});
  void toggle(String roundId) =>
      state = {...state, roundId: !(state[roundId] ?? true)};
}

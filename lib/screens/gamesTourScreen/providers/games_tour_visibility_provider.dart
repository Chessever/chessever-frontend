import 'package:hooks_riverpod/hooks_riverpod.dart';

// Provider to track which round is currently most visible
final currentVisibleRoundProvider = StateProvider<String?>((ref) => null);

// Provider notifier for updating visible round
final roundVisibilityNotifierProvider = 
    Provider<RoundVisibilityNotifier>((ref) => RoundVisibilityNotifier(ref));

class RoundVisibilityNotifier {
  final Ref ref;
  
  RoundVisibilityNotifier(this.ref);
  
  void updateVisibleRound(String? roundId) {
    final current = ref.read(currentVisibleRoundProvider);
    if (current != roundId) {
      ref.read(currentVisibleRoundProvider.notifier).state = roundId;
    }
  }
}
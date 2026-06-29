import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Bumped after the app returns to foreground and Stockfish background cleanup
/// has had a chance to finish.
///
/// Engine-backed eval providers watch this so evaluations cancelled during
/// background teardown are retried without each game-card surface owning app
/// lifecycle plumbing.
final stockfishForegroundGenerationProvider = StateProvider<int>((ref) => 0);

void notifyStockfishForegroundResumed(WidgetRef ref) {
  final notifier = ref.read(stockfishForegroundGenerationProvider.notifier);
  notifier.state = notifier.state + 1;
}

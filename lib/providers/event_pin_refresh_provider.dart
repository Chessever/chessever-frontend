import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Per-event signal used to force For You snapshots to recompute when pin state
/// changes from outside the For You tab or other event-scoped refreshes happen.
final eventPinRefreshProvider = StateProvider.family<int, String>(
  (ref, eventId) => 0,
);

void bumpEventPinRefreshSignal(Ref ref, String? eventId) {
  if (eventId == null || eventId.isEmpty) {
    return;
  }

  final notifier = ref.read(eventPinRefreshProvider(eventId).notifier);
  notifier.state++;
}

/// Global signal used to ask all active For You event snapshots to revalidate.
final forYouEventsRefreshProvider = StateProvider<int>((ref) => 0);

void bumpForYouEventsRefreshSignal(Ref ref) {
  final notifier = ref.read(forYouEventsRefreshProvider.notifier);
  notifier.state++;
}

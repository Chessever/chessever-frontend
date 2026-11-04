import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One explicit smart-event mutation per container. All star, edit and
/// background snapshot paths share this gate; a double tap is not a toggle
/// queued against yesterday's state. Other event types are unaffected.
final smartEventMutationBusyProvider = StateProvider<bool>((ref) => false);

Future<T> withSmartEventMutation<T>(
  ProviderContainer container,
  Future<T> Function() action,
) async {
  if (container.read(smartEventMutationBusyProvider)) {
    throw StateError(
      'A Smart Event is still saving. Try again when it finishes.',
    );
  }
  container.read(smartEventMutationBusyProvider.notifier).state = true;
  try {
    return await action();
  } finally {
    container.read(smartEventMutationBusyProvider.notifier).state = false;
  }
}

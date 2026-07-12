import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _triggerProvider = StateProvider<bool>((ref) => false);

class _DeferredRefReader extends ConsumerStatefulWidget {
  const _DeferredRefReader();

  @override
  ConsumerState<_DeferredRefReader> createState() => _DeferredRefReaderState();
}

class _DeferredRefReaderState extends ConsumerState<_DeferredRefReader> {
  final _actions = GroupEventPostFrameActions();

  @override
  Widget build(BuildContext context) {
    ref.listen(_triggerProvider, (_, __) {
      _actions.schedule(() => ref.read(_triggerProvider));
    });
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _actions.dispose();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pending group event post-frame work is cancelled on teardown', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _DeferredRefReader(),
      ),
    );

    container.read(_triggerProvider.notifier).state = true;
    await tester.pumpWidget(const SizedBox.shrink());

    expect(tester.takeException(), isNull);
  });

  test('captured For You visibility controller supports teardown cleanup', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final visibilityController = container.read(
      forYouSurfaceVisibleProvider.notifier,
    );
    visibilityController.state = true;

    // Mirrors ForYouGamesWidget.dispose: cleanup uses the controller captured
    // while the consumer ref was valid, not a disposed widget ref.
    visibilityController.state = false;

    expect(container.read(forYouSurfaceVisibleProvider), isFalse);
  });
}

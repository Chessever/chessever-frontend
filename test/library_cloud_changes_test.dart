import 'dart:async';

import 'package:chessever2/screens/library/providers/library_auth_provider.dart';
import 'package:chessever2/screens/library/providers/library_cloud_changes_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('two clients coalesce a bulk import into one refresh each', (
    tester,
  ) async {
    final changes = StreamController<void>.broadcast();
    final accounts = <String>[];
    ProviderContainer client() => ProviderContainer(
      overrides: [
        libraryFolderAuthenticatedUserIdProvider.overrideWithValue('account-a'),
        libraryCloudChangeStreamFactoryProvider.overrideWithValue((userId) {
          accounts.add(userId);
          return changes.stream;
        }),
      ],
    );
    final phone = client();
    final desktop = client();
    phone.listen(libraryCloudRevisionProvider, (_, __) {});
    desktop.listen(libraryCloudRevisionProvider, (_, __) {});
    await tester.pump(Duration.zero);
    expect(accounts, ['account-a', 'account-a']);
    expect(phone.read(libraryCloudRevisionProvider).revision, 0);

    for (var i = 0; i < 500; i++) {
      changes.add(null);
    }
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 500));
    expect(phone.read(libraryCloudRevisionProvider).revision, 1);
    expect(desktop.read(libraryCloudRevisionProvider).revision, 1);

    changes.addError(StateError('temporary notification failure'));
    await tester.pump(const Duration(seconds: 1));
    expect(phone.read(libraryCloudRevisionProvider).revision, 1);
    expect(desktop.read(libraryCloudRevisionProvider).revision, 1);
    phone.dispose();
    desktop.dispose();
    await tester.pump(Duration.zero);
    await changes.close();
  });

  testWidgets('account changes cancel pending events and old subscriptions', (
    tester,
  ) async {
    final account = StateProvider<String?>((ref) => 'account-a');
    var active = 0;
    StreamController<void> source() => StreamController<void>.broadcast(
      onListen: () => active++,
      onCancel: () => active--,
    );
    final first = source();
    final second = source();
    final container = ProviderContainer(
      overrides: [
        libraryFolderAuthenticatedUserIdProvider.overrideWith(
          (ref) => ref.watch(account),
        ),
        libraryCloudChangeStreamFactoryProvider.overrideWithValue(
          (userId) => userId == 'account-a' ? first.stream : second.stream,
        ),
      ],
    );
    container.listen(libraryCloudRevisionProvider, (_, __) {});
    await tester.pump(Duration.zero);
    first.add(null);
    await tester.pump(Duration.zero);
    container.read(account.notifier).state = 'account-b';
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(seconds: 1));
    expect(active, 1);
    expect(container.read(libraryCloudRevisionProvider), (
      userId: 'account-b',
      revision: 0,
    ));
    first.add(null);
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(libraryCloudRevisionProvider).revision, 0);

    second.add(null);
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(libraryCloudRevisionProvider).revision, 1);
    container.read(account.notifier).state = null;
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(minutes: 1));
    expect(active, 0);
    expect(container.read(libraryCloudRevisionProvider), (
      userId: null,
      revision: 0,
    ));
    container.dispose();
    await first.close();
    await second.close();
  });

  testWidgets('missed changes are caught up and disposal stops refreshes', (
    tester,
  ) async {
    final changes = StreamController<void>.broadcast();
    final container = ProviderContainer(
      overrides: [
        libraryFolderAuthenticatedUserIdProvider.overrideWithValue('account-a'),
        libraryCloudChangeStreamFactoryProvider.overrideWithValue(
          (_) => changes.stream,
        ),
      ],
    );
    final revisions = <int>[];
    final listener = container.listen(
      libraryCloudRevisionProvider,
      (_, next) => revisions.add(next.revision),
      fireImmediately: true,
    );
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 500));
    expect(revisions.last, 1);
    listener.close();
    await tester.pump(Duration.zero);
    final previous = List<int>.of(revisions);
    await tester.pump(const Duration(minutes: 1));
    expect(revisions, previous);
    container.dispose();
    await tester.pump(Duration.zero);
    expect(changes.hasListener, isFalse);
    await changes.close();
  });
}

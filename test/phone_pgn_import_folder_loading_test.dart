import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/widgets/library_folder_load_error.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _testUserIdProvider = StateProvider<String?>((ref) => null);

final _database = LibraryFolder(
  id: 'database-1',
  userId: 'user-1',
  name: 'My Database',
  color: '#0FB4E5',
  icon: 'database',
  orderIndex: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test('folder stream waits for restored auth and then subscribes', () async {
    var subscribeCalls = 0;
    final container = ProviderContainer(
      overrides: [
        libraryFolderAuthenticatedUserIdProvider.overrideWith(
          (ref) => ref.watch(_testUserIdProvider),
        ),
        libraryFolderStreamFactoryProvider.overrideWithValue(() {
          subscribeCalls++;
          return Stream.value([_database]);
        }),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      libraryFoldersStreamProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final foldersFuture = container.read(libraryFoldersStreamProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(subscribeCalls, 0);

    container.read(_testUserIdProvider.notifier).state = 'user-1';
    final folders = await foldersFuture.timeout(const Duration(seconds: 1));

    expect(subscribeCalls, 1);
    expect(folders, [_database]);
  });

  testWidgets('folder load error offers a working retry action', (
    tester,
  ) async {
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: LibraryFolderLoadError(onRetry: () => retries++),
            );
          },
        ),
      ),
    );

    expect(find.text('Couldn’t load your databases'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });
}

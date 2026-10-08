import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/my_space/providers/space_home_card_size_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_home_layout_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = (await SharedPreferencesService.instance.initialize())!;
  });
  setUp(() async => prefs.clear());

  test('existing arrangements retain small doors and full-row saved cards', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sizes = container.read(spaceHomeCardSizesProvider);
    expect(
      spaceHomeCardSizeFor(kSpaceHomeLibrary, sizes),
      SpaceHomeCardSize.small,
    );
    expect(
      spaceHomeCardSizeFor(kSpaceHomeMyPrep, sizes),
      SpaceHomeCardSize.small,
    );
    for (final key in [
      kSpaceHomeLikes,
      'folder:a',
      'event:b',
      'collection:c',
      'smartEvent:d',
    ]) {
      expect(spaceHomeCardSizeFor(key, sizes), SpaceHomeCardSize.fullRow);
    }
  });

  test('sizes survive a reload and reordering never changes them', () async {
    final first = ProviderContainer();
    final notifier = first.read(spaceHomeCardSizesProvider.notifier);
    notifier.toggle(kSpaceHomeLibrary);
    notifier.toggle('folder:a');
    notifier.toggle('event:b');
    notifier.toggle('event:b');
    first.read(spaceHomeLayoutProvider.notifier).placeFrom([
      'folder:a',
      kSpaceHomeLikes,
      kSpaceHomeLibrary,
      kSpaceHomeMyPrep,
    ]);
    final before = first.read(spaceHomeCardSizesProvider);
    await Future<void>.delayed(Duration.zero);
    first.dispose();
    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    expect(reloaded.read(spaceHomeCardSizesProvider), before);
    expect(
      spaceHomeCardSizeFor(kSpaceHomeLibrary, before),
      SpaceHomeCardSize.fullRow,
    );
    expect(spaceHomeCardSizeFor('folder:a', before), SpaceHomeCardSize.small);
    expect(spaceHomeCardSizeFor('event:b', before), SpaceHomeCardSize.fullRow);
    expect(
      spaceHomeOrder(['folder:a'], reloaded.read(spaceHomeLayoutProvider)),
      ['folder:a', kSpaceHomeLikes, kSpaceHomeLibrary, kSpaceHomeMyPrep],
    );
  });

  test(
    'malformed preferences recover and future values do not lose valid sizes',
    () async {
      for (final raw in [
        'broken',
        '[]',
        jsonEncode({
          'home:library': 'future',
          'folder:a': 'small',
          'folder:b': 1,
        }),
      ]) {
        await prefs.setString(kSpaceHomeCardSizesKey, raw);
        final container = ProviderContainer();
        final sizes = container.read(spaceHomeCardSizesProvider);
        expect(
          spaceHomeCardSizeFor(kSpaceHomeLibrary, sizes),
          SpaceHomeCardSize.small,
        );
        expect(
          spaceHomeCardSizeFor('folder:a', sizes),
          raw.startsWith('{')
              ? SpaceHomeCardSize.small
              : SpaceHomeCardSize.fullRow,
        );
        expect(
          spaceHomeCardSizeFor('folder:b', sizes),
          SpaceHomeCardSize.fullRow,
        );
        container.dispose();
      }
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_photo_provider.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _photo = 'https://example.com/player.jpg';
const _account = PrepAccount(
  source: PrepSource.chesscom,
  username: 'ClubPlayer',
  lastSyncAtMs: 123,
  syncedScope: 'downloaded-scope',
  gameCount: 42,
);
const _profile = PrepProfile(
  id: 'saved-player',
  kind: PrepKind.opponent,
  name: 'Club Player',
  createdAtMs: 1,
  accounts: [_account],
);

class _Photos extends PrepRepository {
  _Photos(this.result)
    : super(
        GamebaseRepository(
          Dio(),
          baseUrl: 'https://example.invalid',
          apiKey: 'test-key',
        ),
      );
  final Future<String?> result;
  final requested = Completer<void>();
  int calls = 0;

  @override
  Future<String?> lookupPhoto(PrepAccount account) {
    calls++;
    if (!requested.isCompleted) requested.complete();
    return result;
  }
}

Future<ProviderContainer> _container(
  PrepProfile profile,
  PrepRepository repo, {
  String? fidePhoto,
}) async {
  final directory = Directory.systemTemp.createTempSync('prep_photos_');
  final file = File('${directory.path}/prep/profiles.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    jsonEncode({
      'profiles': [profile.toJson()],
    }),
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => directory.path,
  );
  final container = ProviderContainer(
    overrides: [
      prepRepositoryProvider.overrideWithValue(repo),
      prepFidePhotoProvider.overrideWith((ref, id) async => fidePhoto),
    ],
  );
  final loaded = Completer<void>();
  final sub = container.listen(prepProfilesProvider, (_, next) {
    if (!next.isLoading && !loaded.isCompleted) loaded.complete();
  }, fireImmediately: true);
  await loaded.future;
  sub.close();
  addTearDown(() async {
    await container.read(prepProfilesProvider.notifier).debugDrainWrites();
    container.dispose();
    repo.dispose();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    directory.deleteSync(recursive: true);
  });
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ranked and legacy favorites keep their known photo identity', () {
    PrepProfile favorite(String id) => PrepProfile(
      id: 'profile',
      kind: PrepKind.opponent,
      name: 'Player',
      createdAtMs: 1,
      favoriteId: id,
    );
    expect(prepFavoriteFide(favorite('1503014')), '1503014');
    expect(prepFavoriteFide(favorite('carlsen')), '1503014');
    expect(prepFavoriteFide(favorite('0')), isNull);
    expect(prepFavoriteFide(favorite('unknown')), isNull);
  });

  test(
    'old online profiles persist photos without undoing edits or sync',
    () async {
      final result = Completer<String?>();
      final repo = _Photos(result.future);
      final container = await _container(_profile, repo);
      final sub = container.listen(
        prepProfilePhotoProvider(_profile.id),
        (_, _) {},
      );
      addTearDown(sub.close);
      await repo.requested.future;
      container
          .read(prepProfilesProvider.notifier)
          .edit(
            _profile.id,
            (p) => p
                .copyWith(name: 'Renamed')
                .replaceAccount(
                  _account.copyWith(gameCount: 99, lastSyncAtMs: 456),
                ),
          );
      result.complete(_photo);
      expect(
        await container.read(prepProfilePhotoProvider(_profile.id).future),
        _photo,
      );
      final saved = container.read(prepProfileProvider(_profile.id))!;
      expect(saved.name, 'Renamed');
      expect(saved.accounts.single.avatarUrl, _photo);
      expect(saved.accounts.single.gameCount, 99);
      expect(saved.accounts.single.lastSyncAtMs, 456);
      expect(saved.accounts.single.syncedScope, 'downloaded-scope');
      expect(PrepProfile.fromJson(saved.toJson())!.avatarUrl, _photo);
    },
  );

  test('a late photo never restores a detached source', () async {
    final result = Completer<String?>();
    final repo = _Photos(result.future);
    final container = await _container(_profile, repo);
    final sub = container.listen(
      prepProfilePhotoProvider(_profile.id),
      (_, _) {},
    );
    addTearDown(sub.close);
    await repo.requested.future;
    container
        .read(prepProfilesProvider.notifier)
        .edit(_profile.id, (p) => p.copyWith(accounts: []));
    result.complete(_photo);
    expect(
      await container.read(prepProfilePhotoProvider(_profile.id).future),
      isNull,
    );
    expect(container.read(prepProfileProvider(_profile.id))!.accounts, isEmpty);
  });

  test(
    'online-only ranked profiles resolve the ChessEver photo first',
    () async {
      final repo = _Photos(Future.value(null));
      final ranked = PrepProfile(
        id: _profile.id,
        kind: _profile.kind,
        name: _profile.name,
        createdAtMs: 1,
        favoriteId: '1234567',
        accounts: [_account],
      );
      final container = await _container(ranked, repo, fidePhoto: _photo);
      final sub = container.listen(
        prepProfilePhotoProvider(ranked.id),
        (_, _) {},
      );
      addTearDown(sub.close);
      expect(
        await container.read(prepProfilePhotoProvider(ranked.id).future),
        _photo,
      );
      expect(repo.calls, 0);
    },
  );

  for (final light in [false, true]) {
    testWidgets(
      'small prep title remains readable and inside its portrait ($light)',
      (tester) async {
        for (final size in [36.0, 56.0]) {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
                home: Builder(
                  builder: (context) {
                    ResponsiveHelper.init(context);
                    return Scaffold(
                      body: Center(
                        child: PrepAvatar(
                          name: 'Vasif Durarbayli',
                          size: size,
                          title: 'GM',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          final title = find.text('GM');
          expect(
            tester.widget<Text>(title).style!.fontSize,
            greaterThanOrEqualTo(9),
          );
          final face = tester.getRect(find.byType(PrepAvatar));
          final label = tester.getRect(title);
          expect(label.left, greaterThanOrEqualTo(face.left + 2));
          expect(label.right, lessThanOrEqualTo(face.right - 2));
          expect(label.bottom, lessThan(face.bottom));
          expect(tester.takeException(), isNull);
        }
      },
    );
    testWidgets(
      'prep fallback is centered, tonal, and fits large text ($light)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Scaffold(
                    body: Center(
                      child: MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: const TextScaler.linear(3)),
                        child: const PrepAvatar(
                          name: 'Durarbayli, Vasif',
                          size: 80,
                          width: 100,
                          title: 'GM',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final face = find.byType(PrepAvatar);
        expect(tester.getSize(face), const Size(100, 80));
        final initials = find.text('VD');
        expect(initials, findsOneWidget);
        final faceRect = tester.getRect(face);
        final initialsRect = tester.getRect(initials);
        expect(initialsRect.center.dx, closeTo(faceRect.center.dx, 0.1));
        expect(
          initialsRect.center.dy,
          closeTo(faceRect.top + (80 - 80 * 0.23) / 2, 0.1),
        );
        expect(
          faceRect.contains(tester.getRect(find.text('GM')).center),
          isTrue,
        );
        final gradients = tester
            .widgetList<DecoratedBox>(
              find.descendant(of: face, matching: find.byType(DecoratedBox)),
            )
            .where(
              (w) =>
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).gradient != null,
            );
        expect(gradients, isEmpty);
        final colors = light ? AppColors.light : AppColors.dark;
        final text = tester.widget<Text>(initials);
        expect(text.style!.color, colors.textPrimaryMuted);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

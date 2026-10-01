import 'dart:ui' as ui;
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/profile_avatar_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _user = AppUser(
  id: 'photo-owner',
  displayName: 'Published Author',
  avatarUrl: 'https://example.com/oauth.jpg',
  createdAt: DateTime(2026),
);

class _Auth extends AuthController {
  @override
  Future<AppAuthState> build() async => AppAuthState.authenticated(_user);
  void replacePhoto(String url) {
    state = AsyncData(
      AppAuthState.authenticated(_user.copyWith(avatarUrl: url)),
    );
  }
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<Uint8List> _widePhoto() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.red, BlendMode.src);
  canvas.drawRect(
    const Rect.fromLTWH(160, 0, 320, 320),
    Paint()..color = const Color(0xff0000ff),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(640, 320);
  picture.dispose();
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

void main() {
  test(
    'photo observer updates without changing existing account identity equality',
    () async {
      final container = ProviderContainer(
        overrides: [authStateProvider.overrideWith(_Auth.new)],
      );
      addTearDown(container.dispose);
      final keep = container.listen(profileAvatarUrlProvider, (_, __) {});
      addTearDown(keep.close);
      await container.read(authStateProvider.future);
      expect(
        container.read(profileAvatarUrlProvider),
        'https://example.com/oauth.jpg',
      );
      (container.read(authStateProvider.notifier) as _Auth).replacePhoto(
        'https://example.com/new.jpg',
      );
      expect(
        container.read(profileAvatarUrlProvider),
        'https://example.com/new.jpg',
      );
      expect(_user.copyWith(avatarUrl: 'https://example.com/new.jpg'), _user);
    },
  );

  const mediaChannel = MethodChannel('com.chessever/media_picker');
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('avatar chooses one gallery photo on $platform', (
      tester,
    ) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(mediaChannel, null));
      var calls = 0;
      await tester.runAsync(() async {
        final source = await _widePhoto();
        messenger.setMockMethodCallHandler(mediaChannel, (call) async {
          expect(call.method, 'pickProfileImage');
          expect(call.arguments, isNull);
          calls++;
          return {'bytes': source, 'fileName': 'gallery.png'};
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final output = await container.read(profileAvatarPickerProvider)();
        expect(output, isNotNull);
        final codec = await ui.instantiateImageCodec(output!);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 512);
        expect(image.height, 512);
        image.dispose();
        codec.dispose();
      });
      expect(calls, 1);
    }, variant: TargetPlatformVariant({platform}));
  }

  test('cancelling gallery selection preserves the OAuth photo', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(mediaChannel, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(mediaChannel, null));
    final container = ProviderContainer(
      overrides: [authStateProvider.overrideWith(_Auth.new)],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
    expect(await container.read(profileAvatarPickerProvider)(), isNull);
    expect(container.read(profileAvatarUrlProvider), _user.avatarUrl);
  });

  testWidgets('gallery rejects unreadable and oversized photos', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(mediaChannel, null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    for (final payload in [
      {'bytes': Uint8List(0)},
      {'bytes': Uint8List(5 * 1024 * 1024 + 1)},
    ]) {
      messenger.setMockMethodCallHandler(mediaChannel, (call) async => payload);
      await expectLater(
        container.read(profileAvatarPickerProvider)(),
        throwsFormatException,
      );
    }
    messenger.setMockMethodCallHandler(mediaChannel, (call) async {
      throw PlatformException(code: 'READ_FAILED');
    });
    await expectLater(
      container.read(profileAvatarPickerProvider)(),
      throwsFormatException,
    );
  });

  testWidgets(
    'wide photo is center cropped without stretching and oversized input is refused',
    (tester) async {
      await tester.runAsync(() async {
        final output = await prepareProfileAvatar(await _widePhoto());
        final codec = await ui.instantiateImageCodec(output);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 512);
        expect(image.height, 512);
        final pixels = (await image.toByteData())!;
        // Both edges belong to the blue center, rather than stretched red margins.
        for (final x in [2, 509]) {
          final offset = (256 * 512 + x) * 4;
          expect(pixels.getUint8(offset), 0);
          expect(pixels.getUint8(offset + 2), 255);
        }
        image.dispose();
        codec.dispose();
        await expectLater(
          prepareProfileAvatar(Uint8List(5 * 1024 * 1024 + 1)),
          throwsFormatException,
        );
      });
    },
  );

  for (final variant in [(false, 1.4), (true, 1.4), (false, 2.0)]) {
    final light = variant.$1;
    final textScale = variant.$2;
    testWidgets(
      'avatar overlay previews and cancels without adding a page in ${light ? 'light' : 'dark'} theme at $textScale',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final photo = await tester.runAsync(
          () async => prepareProfileAvatar(await _widePhoto()),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWithValue(_user),
              profileAvatarUrlProvider.overrideWithValue(null),
              subscriptionProvider.overrideWith((_) => _Subscription()),
              profileAvatarPickerProvider.overrideWithValue(() async => photo),
            ],
            child: MaterialApp(
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => showProfileAvatarEditor(context),
                        child: const Text('Open avatar'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open avatar'));
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsOneWidget);
        await tester.tap(find.text('Upload'));
        await tester.pumpAndSettle();
        expect(find.text('Save'), findsOneWidget);
        final preview = find.byType(Image);
        expect(preview, findsOneWidget);
        expect(tester.getCenter(preview).dx, closeTo(393 / 2, 1));
        expect(tester.getSize(preview).width, tester.getSize(preview).height);
        expect(tester.getRect(find.text('Save')).bottom, lessThan(852));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.text('Open avatar'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

// O6: a phone that updated from a build with the OneSignal SDK keeps its
// OneSignal registration until it registers with ChessEver's notification
// service directly. Pushes sent to it meanwhile arrive in OneSignal's
// envelope: on iOS a tap whose userInfo holds `custom` ({"i", "a", "u"}) and
// no gcm.message_id; on Android a data-only FCM message with `custom` as a
// JSON string and the text beside it, which nothing draws now that the SDK
// is gone. The app unwraps the envelope (onesignal_push_payload.dart), draws
// the Android message itself through its local-notification path
// (DirectPushService.presentOneSignalPush, from the background handler and
// the foreground onMessage handler), and a tap routes like the same push
// sent directly. Until the server drops a mirror that a direct registration
// superseded, both deliver: once this install has registered directly
// (`direct_push_owner`), a OneSignal-format message is that duplicate and is
// not drawn. Routing itself is covered in
// deep_link_routing_regressions_test.dart (O6 group).

import 'dart:convert';

import 'package:chessever2/services/direct_push_service.dart';
import 'package:chessever2/services/direct_push_tap_router.dart';
import 'package:chessever2/services/onesignal_push_payload.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _id = '7f2c1a9e-4b1d-4f0e-9c3a-2d6b8e1f0a55';

/// An iOS tap's userInfo as the native side hands it over (aps dropped):
/// `custom` is a dictionary there.
Map<String, dynamic> _iosTap(Map<String, Object?> sent, {String? launch}) => {
  'custom': {'i': _id, 'a': sent, 'u': ?launch},
};

/// The FCM data of OneSignal's Android message: `custom` is JSON text.
Map<String, dynamic> _androidData(
  Map<String, Object?> sent, {
  String id = _id,
  String title = 'Carlsen vs Nakamura',
  String body = 'The game has started.',
}) => {
  'custom': jsonEncode({'i': id, 'a': sent}),
  'title': title,
  'alert': body,
  'pri': '5',
  'vis': '1',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseOneSignalPush', () {
    test('an iOS tap: custom.a is the push, every value a string', () {
      final push = parseOneSignalPush(
        _iosTap({
          'type': 'collection_games_added',
          'collection_slug': 'us-chess-championships',
          'added': 3,
          'live': true,
          'gone': null,
        }),
      )!;
      expect(push.id, _id);
      expect(push.data, {
        'type': 'collection_games_added',
        'collection_slug': 'us-chess-championships',
        'added': '3',
        'live': 'true',
      });
    });

    test('an Android message: custom is JSON text, the text beside it', () {
      final push = parseOneSignalPush(
        _androidData({'type': 'game_started', 'game_id': 'XBnzfSW7'}),
      )!;
      expect(push.data, {'type': 'game_started', 'game_id': 'XBnzfSW7'});
      expect(push.title, 'Carlsen vs Nakamura');
      expect(push.body, 'The game has started.');
      // OneSignal's own keys (priority, visibility) never reach the router.
      expect(push.data.containsKey('pri'), isFalse);
    });

    test('headings and contents are read when title and alert are absent', () {
      final push = parseOneSignalPush({
        'custom': jsonEncode({'i': _id, 'a': <String, Object?>{}}),
        'headings': 'New games',
        'contents': '3 new games just landed.',
      })!;
      expect(push.title, 'New games');
      expect(push.body, '3 new games just landed.');
    });

    test('type and route set beside the envelope are kept', () {
      final push = parseOneSignalPush({
        'custom': {'i': _id, 'a': <String, Object?>{}},
        'route': '/app/collections',
        'type': 'call_to_action',
      })!;
      expect(push.data, {
        'route': '/app/collections',
        'type': 'call_to_action',
      });
    });

    test('a launch URL stands in only for a chessever.com page the app opens '
        'and only when the data names nothing', () {
      String? url(Map<String, Object?> sent, String launch) =>
          parseOneSignalPush(_iosTap(sent, launch: launch))!.data['url']
              as String?;
      const collection = 'https://chessever.com/collections/zurich-1953';
      expect(url({}, collection), collection);
      expect(
        url({}, 'https://chessever.com/app/reports/missed_chance'),
        'https://chessever.com/app/reports/missed_chance',
      );
      // A browser link is ignored: it would open in the app's WebView.
      expect(url({}, 'https://example.com/promo'), isNull);
      expect(url({}, 'https://chessever.com/privacy-policy'), isNull);
      expect(url({}, 'http://chessever.com/collections/zurich-1953'), isNull);
      // Routed by its data, never by the launch URL.
      expect(url({'type': 'game_started', 'game_id': 'A'}, collection), isNull);
      expect(url({'route': '/app/feed'}, collection), isNull);
    });

    test('anything that is not OneSignal\'s envelope is left alone', () {
      for (final raw in <Map<String, dynamic>>[
        {'type': 'game_started', 'game_id': 'XBnzfSW7'},
        {'custom': 'not json'},
        {
          'custom': jsonEncode({'a': <String, Object?>{}}),
        },
        {
          'custom': {'i': ''},
        },
      ]) {
        expect(parseOneSignalPush(raw), isNull, reason: '$raw');
        expect(unwrapOneSignalPush(raw), same(raw));
      }
    });

    test('a OneSignal id names one Android notification, the same every '
        'time', () {
      expect(oneSignalNotificationId(_id), oneSignalNotificationId(_id));
      expect(oneSignalNotificationId(_id), inInclusiveRange(0, 0x7fffffff));
      expect(
        oneSignalNotificationId(_id),
        isNot(oneSignalNotificationId('$_id-2')),
      );
    });
  });

  group('Android draws a data-only OneSignal message itself', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'initialize' ? true : null;
      });
      // An install that has not registered directly yet (no
      // direct_push_owner), with an empty memory of drawn OneSignal ids.
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
      SharedPreferencesAsyncPlatform.instance = null;
    });

    List<Map<Object?, Object?>> shown() => [
      for (final call in calls)
        if (call.method == 'show') call.arguments as Map<Object?, Object?>,
    ];

    test(
      'the background handler draws it, payload the unwrapped push',
      () async {
        await directPushBackgroundHandler(
          RemoteMessage(
            data: _androidData({'type': 'game_started', 'game_id': 'XBnzfSW7'}),
          ),
        );
        expect(calls.first.method, 'initialize');
        final show = shown().single;
        expect(show['id'], oneSignalNotificationId(_id));
        expect(show['title'], 'Carlsen vs Nakamura');
        expect(show['body'], 'The game has started.');
        expect(jsonDecode(show['payload']! as String), {
          'type': 'game_started',
          'game_id': 'XBnzfSW7',
        });
        final android = show['platformSpecifics']! as Map<Object?, Object?>;
        expect(android['channelId'], 'chessever_direct');
      },
    );

    test('delivered twice, it is one notification', () async {
      final data = _androidData({'type': 'game_started', 'game_id': 'A'});
      expect(await DirectPushService.presentOneSignalPush(data), isTrue);
      expect(await DirectPushService.presentOneSignalPush(data), isTrue);
      expect(shown().single['id'], oneSignalNotificationId(_id));
    });

    group('not registered directly yet: drawn once per OneSignal id', () {
      test('the background handler, delivered twice', () async {
        final message = RemoteMessage(
          data: _androidData({'type': 'game_started', 'game_id': 'A'}),
        );
        await directPushBackgroundHandler(message);
        await directPushBackgroundHandler(message);
        final show = shown().single;
        expect(show['id'], oneSignalNotificationId(_id));
        expect(jsonDecode(show['payload']! as String), {
          'type': 'game_started',
          'game_id': 'A',
        });
      });

      test('the foreground handler, delivered twice', () async {
        final message = RemoteMessage(
          data: _androidData({'type': 'game_started', 'game_id': 'A'}),
        );
        await DirectPushService.instance.handleForegroundMessage(message);
        await DirectPushService.instance.handleForegroundMessage(message);
        final show = shown().single;
        expect(show['id'], oneSignalNotificationId(_id));
        expect(show['title'], 'Carlsen vs Nakamura');
      });

      test('once in the background, again in the foreground', () async {
        final message = RemoteMessage(
          data: _androidData({'type': 'game_started', 'game_id': 'A'}),
        );
        await directPushBackgroundHandler(message);
        await DirectPushService.instance.handleForegroundMessage(message);
        expect(shown().single['id'], oneSignalNotificationId(_id));
      });
    });

    // The server keeps a OneSignal mirror after a direct registration until
    // admin PR #19's migration drops it, so the same push arrives both ways.
    group('registered directly: a OneSignal message is the mirror\'s '
        'duplicate and is not drawn', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({
          'direct_push_owner': 'reader-1',
        });
      });

      test('the background handler', () async {
        await directPushBackgroundHandler(
          RemoteMessage(
            data: _androidData({'type': 'game_started', 'game_id': 'A'}),
          ),
        );
        expect(calls, isEmpty);
      });

      test('the foreground handler', () async {
        await DirectPushService.instance.handleForegroundMessage(
          RemoteMessage(
            data: _androidData({'type': 'game_started', 'game_id': 'A'}),
          ),
        );
        expect(calls, isEmpty);
        expect(
          await DirectPushService.presentOneSignalPush(
            _androidData({'type': 'game_started', 'game_id': 'A'}),
          ),
          isTrue,
          reason: 'taken, so nothing else handles it',
        );
        expect(calls, isEmpty);
      });

      test('a ChessEver push in the foreground is still shown', () async {
        await DirectPushService.instance.handleForegroundMessage(
          const RemoteMessage(
            messageId: 'fcm-1',
            data: {'type': 'game_started', 'game_id': 'A'},
            notification: RemoteNotification(
              title: 'Carlsen vs Nakamura',
              body: 'The game has started.',
            ),
          ),
        );
        final show = shown().single;
        expect(show['title'], 'Carlsen vs Nakamura');
        expect(jsonDecode(show['payload']! as String), {
          'type': 'game_started',
          'game_id': 'A',
        });
      });
    });

    test('a registration the app makes while the background isolate is up '
        'stops the next mirror push there', () async {
      await directPushBackgroundHandler(
        RemoteMessage(data: _androidData({'type': 'game_started'})),
      );
      expect(shown(), hasLength(1));
      // The app's isolate registers: it writes the owner to storage, not to
      // the copy this isolate read on the first push.
      await SharedPreferencesStorePlatform.instance.setValue(
        'String',
        'flutter.direct_push_owner',
        'reader-1',
      );
      await directPushBackgroundHandler(
        RemoteMessage(
          data: _androidData({'type': 'game_started'}, id: '$_id-2'),
        ),
      );
      expect(shown(), hasLength(1));
    });

    test('a ChessEver push, data-only or not, is not drawn here', () async {
      expect(
        await DirectPushService.presentOneSignalPush({
          'type': 'game_started',
          'game_id': 'XBnzfSW7',
        }),
        isFalse,
      );
      await directPushBackgroundHandler(
        RemoteMessage(
          data: _androidData({'type': 'game_started'}),
          notification: const RemoteNotification(title: 'Drawn by FCM'),
        ),
      );
      expect(shown(), isEmpty);
    });

    test('a silent one (no text) is taken but draws nothing', () async {
      expect(
        await DirectPushService.presentOneSignalPush({
          'custom': jsonEncode({'i': _id, 'a': <String, Object?>{}}),
        }),
        isTrue,
      );
      expect(shown(), isEmpty);
    });

    test('on iOS the system draws it: nothing here', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        await DirectPushService.presentOneSignalPush(
          _androidData({'type': 'game_started'}),
        ),
        isFalse,
      );
      await DirectPushService.instance.handleForegroundMessage(
        RemoteMessage(data: _androidData({'type': 'game_started'})),
      );
      expect(calls, isEmpty);
    });
  });

  test('an iOS OneSignal tap delivered by the scene and the delegate routes '
      'once (its native id is onesignal:<custom.i>)', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final tap = {
      'messageId': 'onesignal:$_id',
      'data': _iosTap({'type': 'game_started', 'game_id': 'XBnzfSW7'}),
    };
    messenger.setMockMethodCallHandler(
      DirectPushTapRouter.channel,
      (_) async => tap,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(DirectPushTapRouter.channel, null);
      DirectPushTapRouter.channel.setMethodCallHandler(null);
    });
    final received = <Map<String, dynamic>>[];
    final router = DirectPushTapRouter();
    await router.initializeNative(received.add);
    await messenger.handlePlatformMessage(
      DirectPushTapRouter.channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('notificationOpened', tap),
      ),
      (_) {},
    );
    expect(received, hasLength(1));
    expect(unwrapOneSignalPush(received.single), {
      'type': 'game_started',
      'game_id': 'XBnzfSW7',
    });
  });
}

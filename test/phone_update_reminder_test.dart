import 'dart:async';
import 'dart:convert';

import 'package:chessever2/services/phone_update_reminder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late SharedPreferences prefs;
  late PhoneUpdateReminder reminder;
  final clickedAt = DateTime.utc(2026, 9, 30, 19, 0, 0, 123, 456);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = clickedAt;
    reminder = PhoneUpdateReminder(
      now: () => now,
      preferences: () async => prefs,
    );
  });

  Future<bool> offer({
    String installed = '35.25.3',
    String? target = '35.25.4',
    bool mandatory = false,
    bool manual = false,
  }) => reminder.shouldOffer(
    installedVersion: installed,
    offeredVersion: target,
    mandatory: mandatory,
    manual: manual,
  );

  test(
    'exact label is specified by the widget suite; cooldown is 72 hours',
    () {
      expect(PhoneUpdateReminder.cooldown, const Duration(hours: 72));
    },
  );

  for (final (name, elapsed, expected) in [
    (
      'before',
      const Duration(hours: 72) - const Duration(microseconds: 1),
      false,
    ),
    ('exactly at', const Duration(hours: 72), true),
    ('after', const Duration(hours: 72, microseconds: 1), true),
  ]) {
    test('$name 72 hours from the click', () async {
      expect(await reminder.snooze('35.25.4'), isTrue);
      now = clickedAt.add(elapsed);
      expect(await offer(), expected);
    });
  }

  test('a newer optional version cannot defeat the cooldown', () async {
    await reminder.snooze('35.25.4');
    now = clickedAt.add(const Duration(hours: 71));
    expect(await offer(target: '36.0.0'), isFalse);
    now = clickedAt.add(const Duration(hours: 72));
    expect(await offer(target: '36.0.0'), isTrue);
    final record = jsonDecode(
      prefs.getString(PhoneUpdateReminder.preferencesKey)!,
    );
    expect(record['version'], '35.25.4');
  });

  test(
    'restart restores the deadline and target from persisted preferences',
    () async {
      await reminder.snooze('35.25.4');
      final raw = prefs.getString(PhoneUpdateReminder.preferencesKey)!;
      SharedPreferences.setMockInitialValues({
        PhoneUpdateReminder.preferencesKey: raw,
      });
      final restartedPrefs = await SharedPreferences.getInstance();
      reminder = PhoneUpdateReminder(
        now: () => now,
        preferences: () async => restartedPrefs,
      );
      now = clickedAt.add(const Duration(hours: 48));
      expect(await offer(), isFalse);
      now = clickedAt.add(const Duration(hours: 72));
      expect(await offer(), isTrue);
    },
  );

  for (final installed in ['35.25.4', '35.25.5', '35.26.0', '36.0.0']) {
    test(
      'installed $installed clears the snoozed target, even offline',
      () async {
        await reminder.snooze('35.25.4');
        expect(await offer(installed: installed, target: null), isFalse);
        expect(prefs.containsKey(PhoneUpdateReminder.preferencesKey), isFalse);
        expect(await offer(installed: installed, target: '36.1.0'), isTrue);
      },
    );
  }

  test(
    'older installed/offer versions do not retire the original target',
    () async {
      await reminder.snooze('35.25.10');
      expect(await offer(installed: '35.25.9', target: '35.25.8'), isFalse);
      expect(prefs.containsKey(PhoneUpdateReminder.preferencesKey), isTrue);
      expect(await offer(installed: '35.25.9', target: '35.25.10'), isFalse);
    },
  );

  test(
    'mandatory and manual bypass without deleting the optional snooze',
    () async {
      await reminder.snooze('35.25.4');
      expect(await offer(mandatory: true), isTrue);
      expect(await offer(manual: true), isTrue);
      expect(await offer(), isFalse);
      expect(prefs.containsKey(PhoneUpdateReminder.preferencesKey), isTrue);
    },
  );

  test(
    'failed/missing checks preserve snooze and never offer an update',
    () async {
      await reminder.snooze('35.25.4');
      now = clickedAt.add(const Duration(hours: 73));
      expect(await offer(target: null), isFalse);
      expect(prefs.containsKey(PhoneUpdateReminder.preferencesKey), isTrue);
      expect(
        await reminder.shouldOffer(
          installedVersion: null,
          offeredVersion: '35.25.4',
        ),
        isFalse,
      );
      expect(await offer(target: '35.25.3', mandatory: true), isFalse);
    },
  );

  test('capture click time before delayed preference initialization', () async {
    final pending = Completer<SharedPreferences?>();
    reminder = PhoneUpdateReminder(
      now: () => now,
      preferences: () => pending.future,
    );
    final save = reminder.snooze('35.25.4');
    now = clickedAt.add(const Duration(hours: 1));
    pending.complete(prefs);
    expect(await save, isTrue);
    final record = jsonDecode(
      prefs.getString(PhoneUpdateReminder.preferencesKey)!,
    );
    expect(
      record['until'],
      clickedAt.add(const Duration(hours: 72)).microsecondsSinceEpoch,
    );
  });

  test(
    'unavailable preferences cannot pretend a reminder was persisted',
    () async {
      reminder = PhoneUpdateReminder(
        now: () => now,
        preferences: () async => null,
      );
      expect(await reminder.snooze('35.25.4'), isFalse);
      expect(await offer(), isFalse);
      expect(await offer(manual: true), isTrue);
      expect(await offer(mandatory: true), isTrue);
    },
  );

  test(
    'corrupt reminder records are retired without crashing launch',
    () async {
      await prefs.setString(PhoneUpdateReminder.preferencesKey, '{invalid');
      expect(await offer(), isTrue);
      expect(prefs.containsKey(PhoneUpdateReminder.preferencesKey), isFalse);
    },
  );
}

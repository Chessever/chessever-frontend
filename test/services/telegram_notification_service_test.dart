import 'dart:io';

import 'package:chessever2/services/telegram_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Release builds only relay feedback when Codemagic passes these dart-defines.
/// Flutter-Default Workflow must include the quoted forms; this file is the
/// in-repo copy of that contract.
const _tokenDefine =
    '--dart-define=TELEGRAM_FEEDBACK_BOT_TOKEN="\$TELEGRAM_FEEDBACK_BOT_TOKEN"';
const _chatDefine =
    '--dart-define=TELEGRAM_FEEDBACK_CHAT_ID="\$TELEGRAM_FEEDBACK_CHAT_ID"';

void main() {
  test(
    'CODEMAGIC_DART_DEFINES documents the quoted Telegram feedback flags',
    () {
      final docs = File('CODEMAGIC_DART_DEFINES.txt').readAsStringSync();
      expect(docs, contains(_tokenDefine));
      expect(docs, contains(_chatDefine));
    },
  );

  test(
    'TelegramNotificationService compiles the dart-define keys fromEnvironment',
    () {
      final src = File(
        'lib/services/telegram_notification_service.dart',
      ).readAsStringSync();
      expect(
        src,
        contains(
          "String.fromEnvironment(\n      'TELEGRAM_FEEDBACK_BOT_TOKEN'",
        ),
      );
      expect(
        src,
        contains("String.fromEnvironment(\n      'TELEGRAM_FEEDBACK_CHAT_ID'"),
      );
    },
  );

  test('direct feedback message has no rating or survey framing', () {
    final message = buildDirectFeedbackMessage(
      feedback: 'The clocks are unclear.',
      source: 'sidebar',
      appVersion: '34.8.16 (3389)',
      platform: 'android',
    );

    expect(message, contains('New App Feedback'));
    expect(message, contains('The clocks are unclear.'));
    expect(message, isNot(contains('User ID')));
    expect(message, isNot(contains('/5')));
    expect(message, isNot(contains('Feature Request')));
  });

  test(
    'sendDirectFeedbackNotification returns false when bot is not configured',
    () async {
      final sent = await TelegramNotificationService.instance
          .sendDirectFeedbackNotification(
            feedback: 'unit-test: must not hit Telegram',
            source: 'sidebar',
          );
      expect(sent, isFalse);
    },
  );

  test(
    'sendFeedbackNotification returns false when the bot is not configured',
    () async {
      final sent = await TelegramNotificationService.instance
          .sendFeedbackNotification(
            rating: 5,
            feedback: 'unit-test: must not hit Telegram',
            source: 'telegram_notification_service_test',
          );
      expect(sent, isFalse);
    },
  );
}

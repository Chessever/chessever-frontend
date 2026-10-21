import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/services/telegram_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

void main() {
  test('direct feedback message has no rating or survey framing', () {
    final message = buildDirectFeedbackMessage(
      feedback: 'The clocks are unclear.',
      source: 'sidebar',
      sender: null,
      appVersion: '34.8.16 (3389)',
      platform: 'android',
    );

    expect(message, contains('New App Feedback'));
    expect(message, contains('The clocks are unclear.'));
    expect(message, isNot(contains('/5')));
    expect(message, isNot(contains('Feature Request')));
  });

  test('direct feedback message carries the sender account', () {
    final message = buildDirectFeedbackMessage(
      feedback: 'Hide results until I open the game.',
      source: 'sidebar',
      sender: const FeedbackSender(
        userId: '0b6f1c2e-5a7d-4e1b-9c3f-2d8a6e4b7f10',
        name: 'Dieter',
        email: 'dieter@example.com',
        signIn: 'google',
        lichessUsername: 'dieter_l',
      ),
      appVersion: '35.42.0 (3549)',
      platform: 'android',
    );

    expect(message, contains('User ID: 0b6f1c2e-5a7d-4e1b-9c3f-2d8a6e4b7f10'));
    expect(message, contains('Name: Dieter'));
    expect(message, contains('Email: dieter@example.com'));
    expect(message, contains('Sign-in: google'));
    expect(message, contains('Lichess: dieter_l'));
    expect(message, isNot(contains('Chess.com:')));
    // Above the message, so a capped caption can never cut it off.
    expect(message.indexOf('User ID:'), lessThan(message.indexOf('Message:')));
  });

  test('direct feedback message says when nobody is signed in', () {
    final message = buildDirectFeedbackMessage(
      feedback: 'x',
      source: 'sidebar',
      sender: null,
    );
    expect(message, contains('User ID: Not signed in'));
  });

  test('FeedbackSender reads the Supabase user', () {
    final sender = FeedbackSender.fromUser(
      User.fromJson({
        'id': 'user-1',
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
        'email': 'dieter@example.com',
        'is_anonymous': false,
        'app_metadata': {'provider': 'apple'},
        'user_metadata': {
          'full_name': '  Dieter  ',
          kChesscomUsernameMetadataKey: 'dieter_c',
          kLichessUsernameMetadataKey: '',
        },
      })!,
    )!;

    expect(sender.userId, 'user-1');
    expect(sender.name, 'Dieter');
    expect(sender.email, 'dieter@example.com');
    expect(sender.signIn, 'apple');
    expect(sender.chesscomUsername, 'dieter_c');
    expect(sender.lichessUsername, isNull);
    expect(FeedbackSender.fromUser(null), isNull);
  });

  test('documentFileName keeps a basename with an extension', () {
    expect(documentFileName(null), 'feedback-picture.jpg');
    expect(documentFileName(''), 'feedback-picture.jpg');
    expect(documentFileName('board'), 'board.jpg');
    expect(documentFileName('board.png'), 'board.png');
    expect(documentFileName('/tmp/IMG_1234.HEIC'), 'IMG_1234.HEIC');
  });
}

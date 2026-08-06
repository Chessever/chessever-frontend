import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Service to send notifications to Telegram bot for immediate feedback alerts.
///
/// The bot token and chat ID come from the environment and are never written
/// into source. Release builds receive them via `--dart-define`; debug builds
/// read the git-ignored `.env`. This repo and the desktop repo are both public
/// open source, so a literal credential here is published the moment it is
/// pushed.
class TelegramNotificationService {
  TelegramNotificationService._();

  static final TelegramNotificationService instance =
      TelegramNotificationService._();

  /// Compile-time values injected by CI.
  ///
  /// `String.fromEnvironment` only resolves inside a const context, so each key
  /// is spelled out literally rather than looked up through a variable.
  static const Map<String, String> _release = <String, String>{
    'TELEGRAM_FEEDBACK_BOT_TOKEN': String.fromEnvironment(
      'TELEGRAM_FEEDBACK_BOT_TOKEN',
      defaultValue: '',
    ),
    'TELEGRAM_FEEDBACK_CHAT_ID': String.fromEnvironment(
      'TELEGRAM_FEEDBACK_CHAT_ID',
      defaultValue: '',
    ),
  };

  static String _env(String key) {
    final release = _release[key];
    if (release != null && release.isNotEmpty) return release;
    try {
      final value = dotenv.env[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {
      // dotenv not initialized (release build, or debug run without a .env).
    }
    return '';
  }

  static String get _botToken => _env('TELEGRAM_FEEDBACK_BOT_TOKEN');

  /// Private group chat ID (prefix -100 + group ID from URL).
  static String get _chatId => _env('TELEGRAM_FEEDBACK_CHAT_ID');

  static const String _baseUrl = 'https://api.telegram.org/bot';

  /// Send feedback notification to Telegram
  Future<bool> sendFeedbackNotification({
    required int rating,
    required String feedback,
    required String source,
    String? userId,
    String? appVersion,
    String? platform,
  }) async {
    final botToken = _botToken;
    final chatId = _chatId;
    if (botToken.isEmpty || chatId.isEmpty) {
      debugPrint(
        '[Telegram] Not configured — set TELEGRAM_FEEDBACK_BOT_TOKEN and '
        'TELEGRAM_FEEDBACK_CHAT_ID in .env (debug) or via --dart-define '
        '(release). Feedback was not relayed.',
      );
      return false;
    }

    try {
      final stars = '⭐' * rating + '☆' * (5 - rating);
      final message =
          StringBuffer()
            ..writeln('📣 *New App Feedback*')
            ..writeln()
            ..writeln('$stars ($rating/5)')
            ..writeln()
            ..writeln('*Source:* $source')
            ..writeln('*Platform:* ${platform ?? 'Unknown'}')
            ..writeln('*Version:* ${appVersion ?? 'Unknown'}')
            ..writeln()
            ..writeln('*Message:*')
            ..writeln(feedback)
            ..writeln()
            ..writeln('---')
            ..writeln('_User ID: ${userId ?? 'Anonymous'}_');

      final url = Uri.parse('$_baseUrl$botToken/sendMessage');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'message_thread_id': 19,
          'text': message.toString(),
          'parse_mode': 'Markdown',
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('[Telegram] Feedback notification sent successfully');
        return true;
      } else {
        debugPrint('[Telegram] Failed to send notification: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[Telegram] Error sending notification: $e');
      return false;
    }
  }
}

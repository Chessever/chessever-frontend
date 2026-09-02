import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

String buildDirectFeedbackMessage({
  required String feedback,
  required String source,
  String? appVersion,
  String? platform,
}) {
  return (StringBuffer()
        ..writeln('📣 New App Feedback')
        ..writeln()
        ..writeln('Source: $source')
        ..writeln('Platform: ${platform ?? 'Unknown'}')
        ..writeln('Version: ${appVersion ?? 'Unknown'}')
        ..writeln()
        ..writeln('Message:')
        ..writeln(feedback))
      .toString();
}

/// Telegram rejects an empty document name and treats a path as the filename.
/// Keep a real basename with an extension so sendDocument stays valid.
String documentFileName(String? name) {
  final base = (name ?? '').trim().split(RegExp(r'[/\\]')).last;
  if (base.isEmpty) return 'feedback-picture.jpg';
  if (base.contains('.')) return base;
  return '$base.jpg';
}

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

  /// Forum topic used by the private feedback group.
  static const int _feedbackThreadId = 19;

  /// Telegram document captions are capped at 1024 characters.
  static const int _captionLimit = 1024;

  /// Relay feedback opened deliberately from the sidebar. Unlike the
  /// engagement review flow, this has no star rating or feature survey.
  Future<bool> sendDirectFeedbackNotification({
    required String feedback,
    required String source,
    String? appVersion,
    String? platform,
    Uint8List? pictureBytes,
    String? pictureFileName,
  }) async {
    final botToken = _botToken;
    final chatId = _chatId;
    final hasPicture = pictureBytes != null && pictureBytes.isNotEmpty;
    debugPrint(
      '[Telegram] relaying direct feedback '
      '(picture: $hasPicture, configured: ${botToken.isNotEmpty && chatId.isNotEmpty})',
    );
    if (botToken.isEmpty || chatId.isEmpty) {
      debugPrint(
        '[Telegram] Not configured — direct feedback was not relayed.',
      );
      return false;
    }

    final message = buildDirectFeedbackMessage(
      feedback: feedback,
      source: source,
      appVersion: appVersion,
      platform: platform,
    );

    try {
      if (pictureBytes != null && pictureBytes.isNotEmpty) {
        final sentDocument = await _sendDocument(
          botToken: botToken,
          chatId: chatId,
          caption: message,
          bytes: pictureBytes,
          fileName: pictureFileName,
        );
        if (sentDocument) return true;
        debugPrint(
          '[Telegram] sendDocument failed; falling back to text-only sendMessage',
        );
      }

      return await _sendText(
        botToken: botToken,
        chatId: chatId,
        message: message,
      );
    } catch (e) {
      debugPrint('[Telegram] Error sending direct feedback: $e');
      return false;
    }
  }

  Future<bool> _sendDocument({
    required String botToken,
    required String chatId,
    required String caption,
    required Uint8List bytes,
    String? fileName,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$_baseUrl$botToken/sendDocument'),
          )
          ..fields['chat_id'] = chatId
          ..fields['message_thread_id'] = '$_feedbackThreadId'
          ..fields['caption'] =
              caption.length <= _captionLimit
                  ? caption
                  : caption.substring(0, _captionLimit)
          ..files.add(
            http.MultipartFile.fromBytes(
              'document',
              bytes,
              filename: documentFileName(fileName),
            ),
          );
    final response = await request.send();
    if (response.statusCode != 200) {
      debugPrint(
        '[Telegram] sendDocument failed: ${response.statusCode} '
        '${await response.stream.bytesToString()}',
      );
      return false;
    }
    debugPrint('[Telegram] sendDocument succeeded');
    return true;
  }

  Future<bool> _sendText({
    required String botToken,
    required String chatId,
    required String message,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl$botToken/sendMessage'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'chat_id': chatId,
        'message_thread_id': _feedbackThreadId,
        'text': message,
      }),
    );
    if (response.statusCode != 200) {
      debugPrint(
        '[Telegram] sendMessage failed: ${response.statusCode} '
        '${response.body}',
      );
      return false;
    }
    debugPrint('[Telegram] sendMessage succeeded');
    return true;
  }

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
          'message_thread_id': _feedbackThreadId,
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

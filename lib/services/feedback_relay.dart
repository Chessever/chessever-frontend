import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Public feedback endpoint. Bot credentials and destinations exist only on
/// the server. No app configuration or user credential is sent to the relay.
class FeedbackRelay {
  FeedbackRelay({this.client});

  final http.Client? client;
  static final Uri endpoint = Uri.parse(
    'https://chessever-feedback.young-sun-69a8.workers.dev/v1/feedback',
  );

  Future<bool> send(String message, {Uint8List? picture}) async {
    if (message.trim().isEmpty || message.length > 16000) return false;
    if (picture != null && picture.length > 8 * 1024 * 1024) return false;
    final body = jsonEncode({
      'message': message,
      if (picture != null && picture.isNotEmpty)
        'picture': {'base64': base64Encode(picture)},
    });
    try {
      final response =
          await (client?.post(
                    endpoint,
                    headers: {'Content-Type': 'application/json'},
                    body: body,
                  ) ??
                  http.post(
                    endpoint,
                    headers: {'Content-Type': 'application/json'},
                    body: body,
                  ))
              .timeout(const Duration(seconds: 45));
      return response.statusCode == 200 &&
          (jsonDecode(response.body) as Map<String, dynamic>)['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}

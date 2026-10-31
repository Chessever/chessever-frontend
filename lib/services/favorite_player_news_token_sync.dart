import 'dart:convert';

import 'package:http/http.dart' as http;

/// Preferred notification-service transport. The client-writable Supabase token
/// mirror remains a game/event compatibility path, never News authority.
class DirectPushDeviceTransport {
  DirectPushDeviceTransport({required this.baseUri, required this.client});

  final Uri baseUri;
  final http.Client client;

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    final response = await client
        .post(
          baseUri.resolve(path),
          headers: {
            'content-type': 'application/json',
            if (accessToken != null) 'authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      // Never expose a response body, JWT, installation proof or push token.
      throw DirectPushDeviceException(response.statusCode);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Missing notification-service acknowledgement',
      );
    }
    return decoded;
  }
}

class DirectPushDeviceException implements Exception {
  const DirectPushDeviceException(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'Notification-service request failed (HTTP $statusCode)';
}

/// Every new-client operation requires the exact installation/revision ack.
/// An old server's 200 / {} is not remote preference or detach confirmation.
bool validNewsDeviceAck(
  Map<String, dynamic> ack, {
  required String installationId,
  required int revision,
  bool? enabled,
  bool detached = false,
}) =>
    ack['newsProtocol'] is int &&
    ack['newsProtocol'] == 1 &&
    ack['newsDrainPending'] == false &&
    ack['id'] == installationId &&
    ack['registrationRevision'] is int &&
    ack['registrationRevision'] == revision &&
    (detached ? ack['detached'] == true : ack['favoritePlayerNews'] == enabled);

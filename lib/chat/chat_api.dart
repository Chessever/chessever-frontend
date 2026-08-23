import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatApiException implements Exception {
  const ChatApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.title,
    required this.locale,
    required this.updatedAt,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    return ChatConversation(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'New chat',
      locale: json['locale'] as String? ?? 'en',
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;
  final String title;
  final String locale;
  final DateTime updatedAt;

  ChatConversation copyWith({String? title}) {
    return ChatConversation(
      id: id,
      title: title ?? this.title,
      locale: locale,
      updatedAt: updatedAt,
    );
  }
}

String chatTitleFromQuestion(String question) {
  final normalized = question.trim().replaceAll(RegExp(r'\s+'), ' ');
  final codePoints = normalized.runes.toList();
  if (codePoints.length <= 60) return normalized;
  return '${String.fromCharCodes(codePoints.take(59))}…';
}

class ChatReference {
  const ChatReference({
    required this.type,
    required this.id,
    required this.label,
  });

  factory ChatReference.fromJson(Map<String, dynamic> json) {
    return ChatReference(
      type: json['type'] as String? ?? 'tournament',
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }

  final String type;
  final String id;
  final String label;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.references = const [],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawReferences = json['citations'] as List<dynamic>? ?? const [];
    return ChatMessage(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String? ?? '',
      references:
          rawReferences
              .whereType<Map<String, dynamic>>()
              .map(ChatReference.fromJson)
              .toList(),
    );
  }

  final String id;
  final String role;
  final String content;
  final List<ChatReference> references;

  ChatMessage copyWith({
    String? id,
    String? content,
    List<ChatReference>? references,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role,
      content: content ?? this.content,
      references: references ?? this.references,
    );
  }
}

class ChatStreamEvent {
  const ChatStreamEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;
}

class ChatQuotaStatus {
  const ChatQuotaStatus({
    required this.limit,
    required this.used,
    required this.remaining,
    required this.isPremium,
    required this.resetsAt,
  });

  factory ChatQuotaStatus.fromJson(Map<String, dynamic> json) {
    return ChatQuotaStatus(
      limit: json['limit'] as int? ?? 0,
      used: json['used'] as int? ?? 0,
      remaining: json['remaining'] as int? ?? 0,
      isPremium: json['isPremium'] as bool? ?? false,
      resetsAt: DateTime.tryParse(json['resetsAt'] as String? ?? ''),
    );
  }

  final int limit;
  final int used;
  final int remaining;
  final bool isPremium;
  final DateTime? resetsAt;
}

const _productionChatApiBaseUrl =
    'https://chessever-chat.young-sun-69a8.workers.dev';
const _testChatApiBaseUrl =
    'https://chessever-chat-test.young-sun-69a8.workers.dev';

String resolveChatApiBaseUrl({
  required String configuredUrl,
  required String supabaseUrl,
}) {
  final configured = configuredUrl.trim();
  if (configured.isNotEmpty) return configured;
  return supabaseUrl.contains('odmekzlfunfocvedqusl')
      ? _testChatApiBaseUrl
      : _productionChatApiBaseUrl;
}

class ChatApi {
  ChatApi({http.Client? client}) : _client = client ?? http.Client();

  static final baseUrl = resolveChatApiBaseUrl(
    configuredUrl: const String.fromEnvironment('CHAT_API_BASE_URL'),
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
  );
  static const buildEnabled = bool.fromEnvironment(
    'CHATBOT_ENABLED',
    defaultValue: true,
  );

  final http.Client _client;

  String get _token {
    final user = Supabase.instance.client.auth.currentUser;
    final session = Supabase.instance.client.auth.currentSession;
    if (user == null || user.isAnonymous || session == null) {
      throw const ChatApiException('Sign in to use Botvinnik', statusCode: 401);
    }
    return session.accessToken;
  }

  Uri _uri(String path) {
    if (!buildEnabled || baseUrl.trim().isEmpty) {
      throw const ChatApiException('Botvinnik is not enabled in this build.');
    }
    return Uri.parse('${baseUrl.replaceFirst(RegExp(r'/$'), '')}$path');
  }

  Map<String, String> get _headers => {
    'authorization': 'Bearer $_token',
    'content-type': 'application/json',
  };

  Future<Map<String, dynamic>> _json(http.Response response) async {
    final decoded =
        response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatApiException(
        decoded['message'] as String? ??
            decoded['error'] as String? ??
            'Chat request failed',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<List<ChatConversation>> conversations() async {
    final response = await _client.get(
      _uri('/v1/chat/conversations'),
      headers: _headers,
    );
    final json = await _json(response);
    return (json['conversations'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatConversation.fromJson)
        .toList();
  }

  Future<ChatQuotaStatus> quota() async {
    final response = await _client.get(
      _uri('/v1/chat/quota'),
      headers: _headers,
    );
    final json = await _json(response);
    return ChatQuotaStatus.fromJson(json['quota'] as Map<String, dynamic>);
  }

  Future<ChatConversation> createConversation({required String locale}) async {
    final response = await _client.post(
      _uri('/v1/chat/conversations'),
      headers: _headers,
      body: jsonEncode({'locale': locale}),
    );
    final json = await _json(response);
    return ChatConversation.fromJson(
      json['conversation'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteConversation(String id) async {
    final response = await _client.delete(
      _uri('/v1/chat/conversations/$id'),
      headers: _headers,
    );
    if (response.statusCode != 204) await _json(response);
  }

  Future<List<ChatMessage>> messages(String conversationId) async {
    final response = await _client.get(
      _uri('/v1/chat/conversations/$conversationId/messages'),
      headers: _headers,
    );
    final json = await _json(response);
    return (json['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
  }

  Stream<ChatStreamEvent> send({
    required String conversationId,
    required String content,
    required String locale,
    required String timezone,
  }) async* {
    final request = http.Request(
      'POST',
      _uri('/v1/chat/conversations/$conversationId/messages'),
    );
    request.headers.addAll(_headers);
    request.body = jsonEncode({
      'content': content,
      'locale': locale,
      'timezone': timezone,
    });
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      final decoded =
          body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(body) as Map<String, dynamic>;
      throw ChatApiException(
        decoded['message'] as String? ??
            decoded['error'] as String? ??
            'Chat request failed',
        statusCode: response.statusCode,
      );
    }
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final data = jsonDecode(line) as Map<String, dynamic>;
      yield ChatStreamEvent(data['type'] as String? ?? 'error', data);
    }
  }

  void close() => _client.close();
}

import 'package:chessever2/chat/chat_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects the chat deployment that matches the Supabase environment', () {
    expect(
      resolveChatApiBaseUrl(
        configuredUrl: '',
        supabaseUrl: 'https://odmekzlfunfocvedqusl.supabase.co',
      ),
      'https://chessever-chat-test.young-sun-69a8.workers.dev',
    );
    expect(
      resolveChatApiBaseUrl(
        configuredUrl: '',
        supabaseUrl: 'https://oelbsuggrzyqwzmvidju.supabase.co',
      ),
      'https://chessever-chat.young-sun-69a8.workers.dev',
    );
  });

  test('allows an explicit chat API endpoint override', () {
    expect(
      resolveChatApiBaseUrl(
        configuredUrl: 'https://preview.example.workers.dev',
        supabaseUrl: 'https://oelbsuggrzyqwzmvidju.supabase.co',
      ),
      'https://preview.example.workers.dev',
    );
  });

  test('parses a conversation returned by the chat API', () {
    final conversation = ChatConversation.fromJson({
      'id': 'conversation-1',
      'title': 'Hindi tournament chat',
      'locale': 'hi-IN',
      'updated_at': '2026-08-23T12:00:00Z',
    });

    expect(conversation.id, 'conversation-1');
    expect(conversation.locale, 'hi-IN');
    expect(conversation.updatedAt.toUtc(), DateTime.utc(2026, 8, 23, 12));
  });

  test('parses verified action references on an assistant message', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'role': 'assistant',
      'content': 'यह खेल अभी चल रहा है।',
      'citations': [
        {'type': 'game', 'id': 'game-1', 'label': 'Player A - Player B'},
      ],
    });

    expect(message.references, hasLength(1));
    expect(message.references.single.type, 'game');
    expect(message.references.single.id, 'game-1');
  });

  test('parses the authenticated daily quota', () {
    final quota = ChatQuotaStatus.fromJson({
      'limit': 50,
      'used': 3,
      'remaining': 47,
      'isPremium': true,
      'resetsAt': '2026-08-24T00:00:00.000Z',
    });

    expect(quota.limit, 50);
    expect(quota.used, 3);
    expect(quota.remaining, 47);
    expect(quota.isPremium, isTrue);
  });

  test('creates a compact conversation title from the first question', () {
    expect(
      chatTitleFromQuestion('  Which   events were played last month?  '),
      'Which events were played last month?',
    );

    final longTitle = chatTitleFromQuestion(List.filled(80, 'ख').join());
    expect(longTitle.runes.length, 60);
    expect(longTitle, endsWith('…'));
  });
}

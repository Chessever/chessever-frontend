import 'package:chessever2/chat/chat_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}

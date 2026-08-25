import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
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

  test('builds versioned client metadata for tailored app help', () {
    const context = ChatClientContext(
      platform: 'android',
      surface: 'mobile',
      formFactor: 'phone',
      appVersion: '34.7.28',
      buildNumber: '3369',
    );

    expect(context.toJson(), {
      'schemaVersion': 1,
      'platform': 'android',
      'surface': 'mobile',
      'formFactor': 'phone',
      'appVersion': '34.7.28',
      'buildNumber': '3369',
      'capabilities': ['app-help-v1', 'event-navigation-v1'],
    });
    expect(chatSurfaceForPlatform('web'), 'web');
    expect(chatSurfaceForPlatform('macos'), 'desktop');
    expect(
      chatFormFactor(surface: 'web', viewportWidth: 390, shortestSide: 390),
      'phone',
    );
    expect(
      chatFormFactor(surface: 'web', viewportWidth: 1440, shortestSide: 900),
      'desktop',
    );
  });

  test('builds current tournament screen metadata', () {
    const context = ChatScreenContext(
      screen: 'tournament',
      eventId: 'event-1',
      eventName: 'World Championship',
      tournamentId: 'tour-rapid',
      tournamentName: 'Rapid',
    );

    expect(context.toJson(), {
      'schemaVersion': 1,
      'screen': 'tournament',
      'eventId': 'event-1',
      'eventName': 'World Championship',
      'tournamentId': 'tour-rapid',
      'tournamentName': 'Rapid',
    });
  });

  test('restores the tournament conversation when it is still available', () {
    final conversations = [
      ChatConversation(
        id: 'latest',
        title: 'Latest chat',
        locale: 'en',
        updatedAt: DateTime.utc(2026, 8, 24),
      ),
      ChatConversation(
        id: 'tournament-chat',
        title: 'Tournament chat',
        locale: 'en',
        updatedAt: DateTime.utc(2026, 8, 23),
      ),
    ];

    expect(
      chatConversationForOpen(conversations, 'tournament-chat').id,
      'tournament-chat',
    );
    expect(chatConversationForOpen(conversations, 'missing').id, 'latest');
  });

  test(
    'normalizes unsupported HTML breaks without breaking markdown tables',
    () {
      expect(
        normalizeChatMarkdown('| Round 1 | Game A<br>Game B<br/>Game C |'),
        '| Round 1 | Game A; Game B; Game C |',
      );
      expect(normalizeChatMarkdown('First<br />Second'), 'First\nSecond');
    },
  );

  test('uses tournament-specific empty chat suggestions', () {
    final suggestions = chatSuggestionsForScreen('tournament');

    expect(suggestions.map((suggestion) => suggestion.label), [
      'Tournament overview',
      'Schedule and rounds',
      'Current standings',
    ]);
    expect(suggestions.first.prompt, contains('this tournament'));
    expect(chatSuggestionsForScreen('home').first.label, 'Live games');
  });

  test('groups tournament links with their games and keeps pending links', () {
    const references = [
      ChatReference(type: 'tournament', id: 'tour-1', label: 'Tournament 1'),
      ChatReference(type: 'tournament', id: 'tour-2', label: 'Tournament 2'),
      ChatReference(
        type: 'game',
        id: 'game-2',
        label: 'Game 2',
        tourId: 'tour-2',
      ),
      ChatReference(type: 'round', id: 'round-1', label: 'Round 1'),
      ChatReference(
        type: 'game',
        id: 'game-1',
        label: 'Game 1',
        tourId: 'tour-1',
      ),
      ChatReference(type: 'event', id: 'event-1', label: 'Pending event'),
    ];

    final groups = structureChatReferences(references);
    expect(
      groups.map((group) => group.map((reference) => reference.id).toList()),
      [
        ['tour-1', 'game-1'],
        ['tour-2', 'game-2'],
        ['round-1', 'event-1'],
      ],
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

  test('keeps an empty conversation as a local draft', () {
    final draft = ChatConversation.draft(locale: 'hi-IN');

    expect(draft.isDraft, isTrue);
    expect(draft.id, startsWith('local-draft-'));
    expect(draft.title, 'New chat');
    expect(draft.locale, 'hi-IN');
  });

  test('parses verified action references on an assistant message', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'role': 'assistant',
      'content': 'यह खेल अभी चल रहा है।',
      'feedback': 'like',
      'citations': [
        {
          'type': 'game',
          'id': 'game-1',
          'label': 'Player A - Player B',
          'tourId': 'tour-1',
        },
      ],
    });

    expect(message.references, hasLength(1));
    expect(message.references.single.type, 'game');
    expect(message.references.single.id, 'game-1');
    expect(message.references.single.tourId, 'tour-1');
    expect(message.feedback, 'like');
    expect(message.withFeedback(null).feedback, isNull);
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

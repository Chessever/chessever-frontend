import 'package:chessever2/screens/inbox/inbox_message.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/services/attention_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'inbox_fakes.dart';

/// An Inbox already holding [messages], with no source behind it.
class _FixedInbox extends InboxController {
  _FixedInbox(List<InboxMessage> messages) : super.inactive() {
    state = InboxState(
      ownerId: inboxOwnerA,
      messages: List.unmodifiable(messages),
      loading: false,
    );
  }
}

void main() {
  final signedUp = DateTime.utc(2026, 10, 1);

  ProviderContainer inboxAt(
    DateTime now,
    List<InboxMessage> messages, {
    DateTime? createdAt,
  }) {
    final container = ProviderContainer(
      overrides: [
        inboxProvider.overrideWith((ref) => _FixedInbox(messages)),
        accountCreatedAtProvider.overrideWithValue(createdAt ?? signedUp),
        attentionClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  InboxMessage published(String id, DateTime at, {DateTime? readAt}) =>
      inboxFixture(id, publishedAt: at, readAt: readAt);

  test('messages from before the account are not listed at all', () {
    final container = inboxAt(DateTime.utc(2026, 10, 2), [
      published('backlog', DateTime.utc(2026, 9, 20)),
      published('welcome', DateTime.utc(2026, 10, 1, 1)),
    ]);
    expect(container.read(inboxListedMessagesProvider).map((m) => m.id), [
      'welcome',
    ]);
    // Listed, but the first week asks for nothing.
    expect(container.read(inboxAttentionProvider), isEmpty);
    expect(container.read(inboxHasUnreadProvider), isFalse);
    expect(container.read(inboxUnreadCountProvider), 0);
    // A link to the older message still opens it.
    expect(container.read(inboxProvider).message('backlog'), isNotNull);
  });

  test('the quiet week is absorbed, not held back for day eight', () {
    final container = inboxAt(DateTime.utc(2026, 10, 9), [
      published('quiet-week', DateTime.utc(2026, 10, 5)),
      published('after', DateTime.utc(2026, 10, 8, 1)),
    ]);
    expect(container.read(inboxListedMessagesProvider).map((m) => m.id), [
      'quiet-week',
      'after',
    ]);
    expect(container.read(inboxAttentionProvider).map((m) => m.id), ['after']);
    expect(container.read(inboxUnreadCountProvider), 1);
  });

  test(
    'an unread message stops asking after a month; a read one never asks',
    () {
      final container = inboxAt(DateTime.utc(2026, 10, 28), [
        published('stale', DateTime.utc(2026, 9, 27)),
        published('fresh', DateTime.utc(2026, 10, 20)),
        published(
          'read',
          DateTime.utc(2026, 10, 21),
          readAt: DateTime.utc(2026, 10, 22),
        ),
      ], createdAt: DateTime.utc(2025));
      expect(container.read(inboxListedMessagesProvider), hasLength(3));
      expect(container.read(inboxAttentionProvider).map((m) => m.id), [
        'fresh',
      ]);
    },
  );

  test('the shared rule', () {
    final now = DateTime.utc(2026, 10, 28);
    bool asks(DateTime publishedAt, DateTime? createdAt) => mayAskForAttention(
      publishedAt: publishedAt,
      accountCreatedAt: createdAt,
      now: now,
    );
    expect(asks(DateTime.utc(2026, 10, 27), null), isTrue);
    expect(asks(DateTime.utc(2026, 9, 20), null), isFalse);
    expect(
      asks(DateTime.utc(2026, 10, 27), DateTime.utc(2026, 10, 25)),
      isFalse,
    );
    expect(
      asks(DateTime.utc(2026, 10, 27), DateTime.utc(2026, 10, 20)),
      isTrue,
    );
    expect(isBeforeAccount(DateTime.utc(2026, 10, 1), null), isFalse);
    expect(isQuietAccount(DateTime.utc(2026, 10, 22), now), isTrue);
    expect(isQuietAccount(DateTime.utc(2026, 10, 21), now), isFalse);
  });
}

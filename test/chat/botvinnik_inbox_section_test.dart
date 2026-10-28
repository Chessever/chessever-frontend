import 'package:chessever2/chat/chat_assistant_bubble.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'dart:async';

import 'package:chessever2/chat/botvinnik_inbox_section.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/screens/inbox/inbox_message.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_screen.dart';
import 'package:chessever2/services/attention_policy.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../inbox_fakes.dart';

final _owner = StateProvider<String?>((ref) => inboxOwnerA);

class _Harness {
  _Harness(this.source) {
    container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith((ref) {
          final owner = ref.watch(_owner);
          return owner == null
              ? null
              : AppUser(
                  id: owner,
                  createdAt: DateTime.utc(2026),
                  isAnonymous: true,
                );
        }),
        attentionClockProvider.overrideWithValue(inboxFixtureNow),
        inboxSourceProvider.overrideWithValue(source),
        inboxCacheProvider.overrideWithValue(FakeInboxCache()),
      ],
    );
  }
  final FakeInboxSource source;
  late final ProviderContainer container;
  final navigator = GlobalKey<NavigatorState>();

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }

  Widget host({Key? sectionKey, bool exposed = true, double maxHeight = 250}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Column(
                  children: [
                    SizedBox(
                      height: maxHeight,
                      child: BotvinnikInboxTimeline(
                        key: sectionKey,
                        emptyState: const SizedBox.shrink(),
                        exposed: exposed,
                      ),
                    ),
                    const Expanded(
                      child: Center(child: Text('Conversation stays separate')),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

InboxMessage _longMessage() => InboxMessage(
  id: inboxIdA,
  title: 'Long first message',
  body: List.filled(
    25,
    'Full editorial body, only for the Inbox reader.',
  ).join('\n'),
  publishedAt: DateTime.utc(2026, 9, 30),
);

Future<_Harness> _pump(
  WidgetTester tester,
  FakeInboxSource source, {
  bool exposed = true,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final harness = _Harness(source);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    harness.container.dispose();
  });
  await tester.pumpWidget(harness.host(exposed: exposed));
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  for (final light in [false, true]) {
    for (final width in [360.0, 800.0]) {
      testWidgets(
        'notices align with assistant replies: light=$light width=$width',
        (tester) async {
          tester.view.physicalSize = Size(width, 852);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final source = FakeInboxSource();
          source.rows[inboxOwnerA] = [
            InboxMessage(
              id: inboxIdA,
              title: 'Did you try ChessEver desktop?',
              body:
                  'Follow tournaments, understand games with Game Report, and build your preparation in one desktop workspace.',
              publishedAt: DateTime.utc(2026, 9, 30),
            ),
          ];
          final harness = _Harness(source);
          addTearDown(harness.container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: harness.container,
              child: MaterialApp(
                theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
                home: Builder(
                  builder: (context) {
                    ResponsiveHelper.init(context);
                    return MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: const TextScaler.linear(1.3)),
                      child: Scaffold(
                        body: BotvinnikInboxTimeline(
                          emptyState: const Text('How can I help?'),
                          conversationItemCount: 1,
                          conversationItemBuilder: (_, _) => ChatMessageBubble(
                            message: const ChatMessage(
                              id: 'answer',
                              role: 'assistant',
                              content: 'Your tournament starts tomorrow.',
                            ),
                            isStreaming: false,
                            feedbackPending: false,
                            onReferencePressed: (_) {},
                            onFeedbackPressed: (_, _) {},
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Inbox'), findsNothing);
          expect(find.text('How can I help?'), findsNothing);
          expect(find.byType(ListView), findsOneWidget);
          expect(find.byType(ChatAssistantBubble), findsNWidgets(2));
          final notice = find.byType(ChatAssistantBubble).first;
          final response = find.byType(ChatAssistantBubble).last;
          expect(tester.getTopLeft(notice).dx, 16);
          expect(tester.getSize(notice).width, width - 32);
          expect(tester.getTopLeft(response).dx, tester.getTopLeft(notice).dx);
          expect(tester.getSize(response).width, tester.getSize(notice).width);
          final title = find.text('Did you try ChessEver desktop?');
          final body = find.byKey(const ValueKey('inbox-full-text'));
          expect(tester.getTopLeft(title).dx, tester.getTopLeft(body).dx);
          expect(
            tester.getTopLeft(title).dx,
            tester.getTopLeft(find.text('BOTVINNIK').first).dx,
          );
          final titleText = tester.widget<Text>(title);
          final theme = Theme.of(tester.element(title));
          expect(
            titleText.style!.fontSize,
            theme.textTheme.bodyMedium!.fontSize,
          );
          await harness.close(tester);
        },
      );
    }
  }

  testWidgets(
    'only visible bodies mark read, retained until chat is reopened',
    (tester) async {
      final source = FakeInboxSource();
      source.rows[inboxOwnerA] = [_longMessage(), inboxFixture(inboxIdB)];
      final harness = await _pump(tester, source);
      expect(source.marks, [(inboxOwnerA, inboxIdA)]);
      expect(harness.container.read(inboxUnreadCountProvider), 1);
      expect(find.text('Long first message'), findsOneWidget);

      final scrollable = find
          .descendant(
            of: find.byType(BotvinnikInboxTimeline),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text(inboxFixture(inboxIdB).title),
        150,
        scrollable: scrollable,
      );
      await tester.drag(scrollable, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(source.marks, [(inboxOwnerA, inboxIdA), (inboxOwnerA, inboxIdB)]);
      expect(harness.container.read(inboxHasUnreadProvider), false);

      await tester.pumpWidget(harness.host(sectionKey: UniqueKey()));
      await tester.pumpAndSettle();
      expect(find.byType(InboxMessageContent), findsNothing);
      expect(find.text('Conversation stays separate'), findsOneWidget);
      await harness.close(tester);
    },
  );

  testWidgets('failed reads stay pending and retry saves shared receipt', (
    tester,
  ) async {
    final source = FakeInboxSource()..failMark = true;
    source.rows[inboxOwnerA] = [inboxFixture(inboxIdA)];
    final harness = await _pump(tester, source);
    expect(harness.container.read(inboxUnreadCountProvider), 1);
    expect(source.marks, hasLength(1));
    source.failMark = false;
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(harness.container.read(inboxUnreadCountProvider), 0);
    expect(source.marks, hasLength(2));
    await harness.close(tester);
  });

  testWidgets(
    'external reads, arrivals, account changes and sign out share state',
    (tester) async {
      final source = FakeInboxSource();
      source.rows[inboxOwnerA] = [inboxFixture(inboxIdA)];
      final harness = await _pump(tester, source, exposed: false);
      expect(source.marks, isEmpty);
      await harness.container.read(inboxProvider.notifier).markOpened(inboxIdA);
      await tester.pumpAndSettle();
      expect(harness.container.read(inboxUnreadCountProvider), 0);
      expect(find.text(inboxFixture(inboxIdA).title), findsOneWidget);
      source.rows[inboxOwnerA]!.add(inboxFixture(inboxIdB));
      await harness.container.read(inboxProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(harness.container.read(inboxUnreadCountProvider), 1);
      expect(find.text(inboxFixture(inboxIdB).title), findsOneWidget);

      harness.container.read(_owner.notifier).state = inboxOwnerB;
      await tester.pumpAndSettle();
      expect(find.text(inboxFixture(inboxIdA).title), findsNothing);
      harness.container.read(_owner.notifier).state = null;
      await tester.pumpAndSettle();
      expect(find.byType(InboxMessageContent), findsNothing);
      expect(harness.container.read(inboxUnreadCountProvider), 0);
      await harness.close(tester);
    },
  );

  testWidgets(
    'background and covered routes do not read; resume and return do',
    (tester) async {
      final source = FakeInboxSource();
      source.rows[inboxOwnerA] = [inboxFixture(inboxIdA)];
      final harness = await _pump(tester, source, exposed: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpWidget(harness.host());
      await tester.pumpAndSettle();
      expect(source.marks, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(source.marks, [(inboxOwnerA, inboxIdA)]);

      unawaited(
        harness.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      source.rows[inboxOwnerA]!.add(inboxFixture(inboxIdB));
      await harness.container.read(inboxProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(source.marks, hasLength(1));
      harness.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(source.marks, [(inboxOwnerA, inboxIdA), (inboxOwnerA, inboxIdB)]);
      await harness.close(tester);
    },
  );

  testWidgets('a visible title alone does not read a body below the viewport', (
    tester,
  ) async {
    final source = FakeInboxSource();
    source.rows[inboxOwnerA] = [inboxFixture(inboxIdA)];
    final harness = await _pump(tester, source, exposed: false);
    await tester.pumpWidget(harness.host(maxHeight: 60));
    await tester.pumpAndSettle();
    expect(find.text(inboxFixture(inboxIdA).title), findsOneWidget);
    expect(source.marks, isEmpty);
    await tester.pumpWidget(harness.host());
    await tester.pumpAndSettle();
    expect(source.marks, [(inboxOwnerA, inboxIdA)]);
    await harness.close(tester);
  });

  testWidgets('receipt is not cleared until the shared operation confirms', (
    tester,
  ) async {
    final source = FakeInboxSource();
    source.rows[inboxOwnerA] = [inboxFixture(inboxIdA)];
    final gate = Completer<DateTime>();
    source.markOverride = (_, _) => gate.future;
    final harness = await _pump(tester, source);
    expect(harness.container.read(inboxUnreadCountProvider), 1);
    gate.complete(inboxReadTime);
    await tester.pumpAndSettle();
    expect(harness.container.read(inboxUnreadCountProvider), 0);
    await harness.close(tester);
  });
}

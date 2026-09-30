import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_lobby_screen.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'puzzle_race_fakes.dart';

/// The race's top bar and opponents strip: the lives before the room
/// answers, the speaker, and a room too big to show whole.

class _TestBoardSettings extends BoardSettingsNotifierNew {
  _TestBoardSettings({this.sound = true});

  final bool sound;

  @override
  Future<BoardSettingsNew> build() async =>
      BoardSettingsNew(soundEnabled: sound);
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  RaceHarness h, {
  required FeedSfx feed,
  bool boardSound = true,
  double width = 393,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final container = ProviderContainer(
    overrides: [
      raceDepsProvider.overrideWithValue(h.deps()),
      boardSettingsProviderNew.overrideWith(
        () => _TestBoardSettings(sound: boardSound),
      ),
      feedSfxProvider.overrideWithValue(feed),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const RaceLobbyScreen();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _unmount(WidgetTester tester) async {
  final scope = tester.widgetList<UncontrolledProviderScope>(
    find.byType(UncontrolledProviderScope),
  );
  final containers = [for (final s in scope) s.container];
  await tester.pumpWidget(const SizedBox.shrink());
  for (final c in containers) {
    c.dispose();
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<ProviderContainer> _startSolo(
  WidgetTester tester,
  RaceHarness h, {
  required FeedSfx feed,
  bool boardSound = true,
}) async {
  final container = await _pump(tester, h, feed: feed, boardSound: boardSound);
  await tester.tap(find.byKey(const ValueKey('race_start_solo')));
  await _settle(tester);
  h.server.last.push(snapshot());
  await _settle(tester);
  h.server.last.push(snapshot(state: 'running', startedAt: h.clock - 2000));
  h.server.last.push(puzzle());
  await _settle(tester);
  return container;
}

FeedGlyph _speaker(WidgetTester tester) => tester.widget<FeedGlyph>(
  find.descendant(
    of: find.byKey(const ValueKey('race_sound')),
    matching: find.byType(FeedGlyph),
  ),
);

void main() {
  testWidgets('solo Survival shows its three lives before the room answers', (
    tester,
  ) async {
    final h = RaceHarness();
    await _pump(tester, h, feed: FeedSfx.forTesting());
    await tester.tap(find.byKey(const ValueKey('race_start_solo')));
    await _settle(tester);

    expect(find.text('Setting up your race'), findsOneWidget);
    expect(find.bySemanticsLabel('3 lives left'), findsOneWidget);
    expect(find.text('No limit'), findsNothing);

    // The room's own count takes over once it answers.
    h.server.last.push(snapshot());
    await _settle(tester);
    expect(find.bySemanticsLabel('3 lives left'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('solo Infinite says No limit from the first frame', (
    tester,
  ) async {
    final h = RaceHarness();
    await _pump(tester, h, feed: FeedSfx.forTesting());
    await tester.tap(find.byKey(const ValueKey('race_mode_infinite')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('race_start_solo')));
    await _settle(tester);

    expect(find.text('Setting up your race'), findsOneWidget);
    expect(find.text('No limit'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'lives? left')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('the speaker silences the race without ending it', (
    tester,
  ) async {
    final h = RaceHarness();
    final feed = FeedSfx.forTesting();
    final container = await _startSolo(tester, h, feed: feed);
    int warmUps() => h.audio.calls.where((c) => c == 'warmUp').length;

    expect(_speaker(tester).svg, FeedGlyphs.soundOn);
    final before = warmUps();

    await tester.tap(find.byKey(const ValueKey('race_sound')));
    await tester.pump();
    // The Feed's own speaker, and the race re-reads it at once.
    expect(feed.muted, isTrue);
    expect(_speaker(tester).svg, FeedGlyphs.soundOff);
    expect(warmUps(), before + 1);
    expect(container.read(raceControllerProvider).phase, RacePhase.running);

    await tester.tap(find.byKey(const ValueKey('race_sound')));
    await tester.pump();
    expect(feed.muted, isFalse);
    expect(_speaker(tester).svg, FeedGlyphs.soundOn);
    expect(warmUps(), before + 2);
    await _unmount(tester);
  });

  testWidgets('with board sound off the speaker says why instead', (
    tester,
  ) async {
    final h = RaceHarness();
    final feed = FeedSfx.forTesting(boardSoundEnabled: false);
    await _startSolo(tester, h, feed: feed, boardSound: false);

    expect(_speaker(tester).svg, FeedGlyphs.soundOff);
    await tester.tap(find.byKey(const ValueKey('race_sound')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sound is off in board settings'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);
    expect(feed.muted, isFalse);
    await tester.pump(const Duration(seconds: 6));
    await _unmount(tester);
  });

  testWidgets('a full room: whole leaders, a count, and your place', (
    tester,
  ) async {
    const width = 360.0;
    final h = RaceHarness(token: 'jwt');
    await _pump(tester, h, feed: FeedSfx.forTesting(), width: width);
    await tester.tap(find.byKey(const ValueKey('race_multiplayer')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('race_create_room')));
    await _settle(tester);
    final socket = h.server.last;

    const names = [
      'Alexandra Kosteniuk',
      'Maxime Vachier-Lagrave',
      'Ian Nepomniachtchi',
      'Hikaru',
      'Alireza Firouzja',
      'Gukesh',
      'Praggnanandhaa',
    ];
    const scores = [9, 7, 5, 3, 2, 1, 0];
    final players = [
      player(score: 5),
      for (var i = 0; i < names.length; i++)
        player(
          id: 'rival$i',
          name: names[i],
          score: scores[i],
          // Level on solves with this player, but one miss behind.
          mistakes: i == 2 ? 1 : 0,
          ready: true,
        ),
    ];
    socket.push(snapshot(multiplayer: true, players: players));
    await _settle(tester);
    socket.push(
      snapshot(
        multiplayer: true,
        state: 'running',
        startedAt: h.clock - 2000,
        players: players,
      ),
    );
    socket.push(puzzle());
    await _settle(tester);
    expect(tester.takeException(), isNull);

    final strip = find.byKey(const ValueKey('race_opponents'));
    final stripRect = tester.getRect(strip);
    // Inside the top bar's gutter: 8 to the frame, 12 more inside it.
    expect(stripRect.left, greaterThanOrEqualTo(8 + 12 - 0.01));
    expect(stripRect.right, lessThanOrEqualTo(width - 8 - 12 + 0.01));

    // Two solved more; the one level on solves has a miss more.
    expect(find.text('3rd of 8'), findsOneWidget);

    final more = tester.widget<Text>(
      find.byKey(const ValueKey('race_opponents_more')),
    );
    final hidden = int.parse(more.data!.substring(1));
    expect(hidden, greaterThan(0));

    var shown = 0;
    for (final name in names) {
      final entry = find.descendant(of: strip, matching: find.text(name));
      if (entry.evaluate().isEmpty) continue;
      shown += 1;
      final rect = tester.getRect(entry);
      expect(rect.left, greaterThanOrEqualTo(stripRect.left - 0.01));
      expect(rect.right, lessThanOrEqualTo(stripRect.right + 0.01));
    }
    expect(shown, greaterThan(0));
    expect(shown + hidden, names.length);
    // The leader always shows.
    expect(
      find.descendant(of: strip, matching: find.text(names.first)),
      findsOneWidget,
    );
    await _unmount(tester);
  });
}

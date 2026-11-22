import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/utils/pgn_comment_annotations.dart'
    show pgnCommentProse;
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart'
    show GameCardChessboard;
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/settings/widgets/story_row_settings_body.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart'
    show EvaluationBarWidget;
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart'
    show FeedEval, feedCachedEvalProvider;
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_pages.dart';
import 'package:chessever2/screens/stories/story_row.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/screens/stories/story_viewer.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart'
    show Arrow, Chessboard, ChessboardController, PlayerSide;
import 'package:dartchess/dartchess.dart'
    show NormalMove, Position, Rule, Setup, Side, Square, makeLegalMoves;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'support/memory_story_row_store.dart';

// ------------------------------------------------------------- the games

/// The Scholar's mate: one position worth a stop, the mate.
const _pgn = '''[Event "Test"]
[White "Alpha"]
[Black "Beta"]
[Result "1-0"]

1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0''';

/// The same mate marked brilliant: a strong move that asks to be found.
const _puzzlePgn = '''[Event "Test"]
[White "Alpha"]
[Black "Beta"]
[Result "1-0"]

1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7#!! 1-0''';

/// The Opera game as a book annotates it: words, arrows, glyphs, and the
/// mate at the end.
const _operaPgn = '''[Event "Paris Opera 1858"]
[White "Morphy, Paul"]
[Black "Duke Karl"]
[Result "1-0"]

1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 { [%clk 0:58:10] [%cal Gb3f7,Gb3b7] The queen eyes f7 and b7 at once. } 7... Qe7 8. Nc3 c6 9. Bg5 b5?! 10. Nxb5! { White gives the knight to open lines toward the king. } 10... cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7! { The exchange goes back: every white piece joins the attack. } 13... Rxd7 14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+!! { The queen is given so the rook can mate on d8. } 16... Nxb8 17. Rd8# 1-0''';

/// A report's PGN: evaluations on every move, its verdict codes, and the
/// engine's line beside the missed win (mate on f7, missed).
const _missedPgn = '''[Event "Round 2: A - B"]
[BroadcastName "Club Championship"]
[White "Alpha"]
[Black "Beta"]
[Result "1/2-1/2"]

1. e4 \$247 { [%eval 0.2] } 1... e5 \$247 { [%eval 0.2] } 2. Bc4 { [%eval 0.1] } 2... Nc6 { [%eval 0.1] } 3. Qh5 { [%eval 0.0] } 3... Nf6 \$4 \$246 { [%eval #1] } ( 3... g6 4. Qf3 Nf6 ) 4. Qf3 \$4 \$243 { [%eval 0.1] } ( 4. Qxf7# ) 4... Be7 { [%eval 0.1] } 1/2-1/2''';

/// Black misses a win at move 5 (the screenshot's case: Black stood at
/// −3.3), with the engine's line beside the miss and an evaluation on every
/// move.
const _blackMissPgn = '''[Event "Myvatn OI Open 2026"]
[Site "Sel Hotel Myvatn"]
[White "Alpha"]
[Black "Beta"]
[Result "1-0"]

1. e4 { [%eval 0.3] } 1... e5 { [%eval 0.3] } 2. Nf3 { [%eval 0.3] } 2... Nc6 { [%eval 0.3] } 3. Bc4 { [%eval 0.3] } 3... Nd4 { [%eval 0.9] } 4. Nxe5 { [%eval -1.0] } 4... Qg5 { [%eval -1.0] } 5. Nxf7 { [%eval -3.3] } 5... d6 { [%eval 6.0] } ( 5... Qxg2 6. Rf1 Qxe4+ 7. Be2 Nf3# ) 6. Nxg5 { [%eval 6.2] } 1-0''';

/// A book's commented move with the engine's numbers beside the words.
const _commentedEvalPgn = '''[Event "Test"]
[White "Alpha"]
[Black "Beta"]
[Result "*"]

1. e4 { [%eval 0.3] } 1... e5 { [%eval 0.3] } 2. Nf3 { [%eval 0.2] The knight hits e5 at once. } 2... Nc6 { [%eval 0.3] } *''';

/// A quiet game: no words, no glyphs, no evaluation, nothing won.
const _quietPgn = '''[Result "1/2-1/2"]

1. Nf3 Nf6 2. g3 g6 3. Bg2 Bg7 4. O-O O-O 1/2-1/2''';

StorySegment _only(String pgn) {
  final segments = pickStorySegments(parseStoryPgn(pgn)!);
  expect(segments, hasLength(1));
  return segments.single;
}

// ---------------------------------------------------------------- harness

class _MemoryStorage implements StorySeenStorage {
  _MemoryStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

/// The row's choice in memory, signed out unless a test signs it in.
class _RowStore extends MemoryStoryRowStore {
  _RowStore({super.id, super.server});
}

class _Board extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

/// Every sound a story puzzle asks for, by move and class; nothing plays.
class _Sounds extends StoryPuzzleSounds {
  _Sounds();

  final List<(String, MoveClass?)> played = [];
  int warmed = 0;

  @override
  void move({required String san, MoveClass? moveClass}) =>
      played.add((san, moveClass));

  @override
  void warmUp() => warmed++;
}

/// Every haptic the stories ask the platform for, by its type.
class _Haptics {
  _Haptics(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add('${call.arguments}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  final calls = <String>[];

  /// [HapticFeedbackService.success] and the Feed puzzle's miss.
  int get medium =>
      calls.where((c) => c == 'HapticFeedbackType.mediumImpact').length;
}

final _now = DateTime(2026, 11, 21, 10);

Collection _collection(
  String slug, {
  int games = 3,
  String? version,
  DateTime? updated,
  CollectionKind kind = CollectionKind.event,
}) => Collection(
  id: slug,
  slug: slug,
  kind: kind,
  title: 'Collection $slug',
  author: 'Author $slug',
  gameCount: games,
  contentVersion: version ?? 'v-$slug',
  updatedAt: updated,
  access: CollectionAccess.free,
);

CollectionGame _game(
  String id, {
  DateTime? updated,
  bool annotated = false,
  String result = '1-0',
}) => CollectionGame.fromPreviewCard(
  CollectionGameCard(
    id: id,
    white: const CollectionPlayerSide(
      name: 'Alpha, Ann',
      key: 'name:alpha',
      elo: 2700,
      title: 'GM',
      fed: 'NOR',
    ),
    black: const CollectionPlayerSide(
      name: 'Beta, Bo',
      key: 'name:beta',
      elo: 2650,
      title: 'IM',
      fed: 'USA',
    ),
    result: result,
    event: 'Test Open',
    eco: 'C20',
    opening: "King's Pawn",
    finalFen:
        'r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4',
    lastMove: 'h5f7',
    updatedAt: updated,
    hasAnnotations: annotated,
  ),
)!;

/// [count] stories of [slug], each one game of [pgn].
StoryBatch _batch(String slug, int count, {String pgn = _pgn}) {
  final games = [for (var i = 0; i < count; i++) _game('$slug$i')];
  final collection = _collection(slug, games: count);
  return StoryBatch(
    games: [for (final g in games) buildStoryGame(g, pgn: pgn)],
    ordered: [for (final g in games) g.game],
    total: count,
    gameCount: count,
    signature: storySignature(collection),
  );
}

/// A seen document where [caught] circles are caught up as they stand.
String _caughtUp(Map<String, (Collection, StoryBatch)> caught) => jsonEncode({
  'v': 3,
  'c': {
    for (final MapEntry(:key, :value) in caught.entries)
      key: StorySeen(
        ids: [for (final g in value.$2.games) g.id],
        signature: storySignature(value.$1),
        caught: true,
      ).toJson(),
  },
});

class _Harness {
  _Harness(
    this.container,
    this.storage,
    this.rowStore,
    this.opened,
    this.events,
    this.sounds,
  );

  final ProviderContainer container;

  /// The story puzzles' sounds.
  final _Sounds sounds;
  final _MemoryStorage storage;
  final _RowStore rowStore;
  final List<(String, String, int)> opened;

  /// The events opened from a story (Go to event), by tour and round.
  final List<(String?, String?)> events;

  StorySeenNotifier get seen => container.read(storySeenProvider.notifier);
  StoryRowPrefs get prefs => container.read(storyRowPrefsProvider);
}

class _CollectionPage extends StatelessWidget {
  const _CollectionPage(this.collection);

  final Collection collection;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('collection_page'),
    body: Center(child: Text('Page ${collection.slug}')),
  );
}

class _StorySubscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _StorySubscription(bool subscribed)
    : super(SubscriptionState(isSubscribed: subscribed));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_Harness> _pumpRow(
  WidgetTester tester, {
  required List<Collection> collections,
  required Map<String, StoryBatch> batches,
  String? seen,
  _RowStore? rowStore,
  bool light = false,
  bool subscribed = true,
  Completer<void>? openHold,
  List<Override> overrides = const [],
  Widget? below,
}) async {
  tester.view.physicalSize = const Size(393, 852) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final storage = _MemoryStorage(seen);
  final store = rowStore ?? _RowStore();
  final opened = <(String, String, int)>[];
  final events = <(String?, String?)>[];
  final sounds = _Sounds();
  final container = ProviderContainer(
    overrides: [
      subscriptionProvider.overrideWith((_) => _StorySubscription(subscribed)),
      storyCollectionsProvider.overrideWith(
        (ref) async => List.of(collections),
      ),
      storyBatchProvider.overrideWith((ref, slug) async => batches[slug]!),
      ...overrides,
      storySeenStorageProvider.overrideWithValue(storage),
      storyRowPrefsStoreProvider.overrideWithValue(store),
      storyClockProvider.overrideWithValue(() => _now),
      storyCollectionPageProvider.overrideWithValue(_CollectionPage.new),
      storyGameOpenerProvider.overrideWithValue((
        context,
        ref, {
        required collection,
        required batch,
        required story,
        required moveIndex,
      }) async {
        opened.add((collection.slug, story.id, moveIndex));
        await openHold?.future;
      }),
      storyEventOpenerProvider.overrideWithValue(({
        String? tourId,
        String? roundId,
      }) async {
        events.add((tourId, roundId));
        return true;
      }),
      // The eval cache is never asked here: a position the game records
      // nothing for reads as a cache miss.
      feedCachedEvalProvider.overrideWith((ref, fen) async => null),
      boardSettingsProviderNew.overrideWith(_Board.new),
      currentUserProvider.overrideWithValue(null),
      storyPuzzleSoundsProvider.overrideWithValue(sounds),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: ListView(
                padding: const EdgeInsets.only(top: 80),
                children: [
                  const TodayStoryRow(gutter: 16),
                  const SizedBox(key: ValueKey('below'), height: 10),
                  ?below,
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return _Harness(container, storage, store, opened, events, sounds);
}

Finder _circle(String slug) => find.byKey(ValueKey('story_circle_$slug'));

Future<void> _run(WidgetTester tester, Duration duration) async {
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(duration);
}

Future<void> _open(WidgetTester tester, String slug) async {
  await tester.tap(_circle(slug));
  await tester.pump();
  await _run(tester, const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> _settleClose(WidgetTester tester) async {
  await tester.pump();
  await _run(tester, const Duration(milliseconds: 900));
  await tester.pump();
}

Finder _story(String id) => find.byKey(ValueKey('story_game_$id'));

/// Taps the story at a share of its width, between the header and the
/// position: never on a board that takes a move, nor on the header.
Future<void> _tapAside(WidgetTester tester, double share) async {
  final header = tester.getRect(find.byKey(const ValueKey('story_close')));
  final frame = tester.getRect(find.byType(StoryFrameView));
  await tester.tapAt(Offset(393 * share, (header.bottom + frame.top) / 2));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

Color _ringColor(WidgetTester tester, String slug) {
  final ring = tester.widget<DecoratedBox>(
    find.descendant(
      of: _circle(slug),
      matching: find.byKey(const ValueKey('story_ring')),
    ),
  );
  return ((ring.decoration as BoxDecoration).border! as Border).top.color;
}

String _labelText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('story_label'))).data!;

/// The words' headline as drawn: the move, a find or a miss.
String _headline(WidgetTester tester) {
  for (final key in ['story_prompt', 'story_missed', 'story_move']) {
    final found = find.byKey(ValueKey(key));
    if (found.evaluate().isEmpty) continue;
    final text = tester.widget<Text>(found);
    return text.data ?? text.textSpan!.toPlainText();
  }
  return '';
}

/// The Show plate's fill: the actions' quiet plate, or the page's ink once
/// it is the way on.
Color _showFill(WidgetTester tester) {
  final plate = tester.widget<Container>(
    find.byKey(const ValueKey('story_show_plate')),
  );
  return (plate.decoration! as BoxDecoration).color!;
}

/// The Show plate's ink: its label's (the glyph wears the same).
Color _showInk(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('story_show_plate')),
        matching: find.byType(Text),
      ),
    )
    .style!
    .color!;

/// Plays [from] to [to] on a board turned for Black.
Future<void> _playBlack(WidgetTester tester, String from, String to) async {
  Offset at(String name) {
    final rect = tester.getRect(
      find.byKey(const ValueKey('story_puzzle_board')),
    );
    final square = Square.fromName(name);
    final s = rect.width / 8;
    return Offset(
      rect.left + (7 - square.file + 0.5) * s,
      rect.top + (square.rank + 0.5) * s,
    );
  }

  await tester.tapAt(at(from));
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tapAt(at(to));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

/// The center of [square] on the puzzle board, White at the bottom.
Offset _square(WidgetTester tester, String name) {
  final rect = tester.getRect(find.byKey(const ValueKey('story_puzzle_board')));
  final square = Square.fromName(name);
  final s = rect.width / 8;
  return Offset(
    rect.left + (square.file + 0.5) * s,
    rect.top + (7 - square.rank + 0.5) * s,
  );
}

Position _fen(String fen) =>
    Position.setupPosition(Rule.chess, Setup.parseFen(fen));

/// The Scholar's mate, White to find Qxf7#.
const _mateFen =
    'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4';

/// Every string the viewer draws.
List<String> _drawnText(WidgetTester tester) => [
  for (final text in tester.widgetList<RichText>(
    find.descendant(
      of: find.byKey(const ValueKey('story_viewer')),
      matching: find.byType(RichText),
    ),
  ))
    text.text.toPlainText(),
];

/// What the eval bar evaluation in prose looked like: "(−3.3)", "(+0.1)",
/// "mate in one", "is winning here", "It was level".
final _evalProse = RegExp(
  r'\([+−-]?\d+\.\d\)|mate in|winning here|was level|is level|Find it',
);

EvaluationBarWidget _bar(WidgetTester tester) =>
    tester.widget(find.byKey(const ValueKey('story_eval_bar')));

Future<void> _play(WidgetTester tester, String from, String to) async {
  await tester.tapAt(_square(tester, from));
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tapAt(_square(tester, to));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  // ---------------------------------------------------------------- moments
  group('key positions', () {
    test('the annotator\'s words come first, then verdicts, spread over the '
        'game, never more than four', () {
      final story = parseStoryPgn(_operaPgn)!;
      final segments = pickStorySegments(story);
      // Four commented moves; the mate at the end (a verdict of the board)
      // waits behind them.
      expect(segments, hasLength(kStoryMaxSegments));
      expect(
        [for (final s in segments) s.san],
        ['Qb3', 'Nxb5', 'Rxd7', 'Qb8+'],
      );
      expect(segments.every((s) => s.tier == 0), isTrue);
      // In game order, each a readable moment: the move, its number, its
      // glyphs, the book's words with every command gone, the arrows.
      final qb3 = segments.first;
      expect(qb3.number, '7.');
      expect(qb3.comment, 'The queen eyes f7 and b7 at once.');
      expect(qb3.shapes, hasLength(2));
      expect(qb3.shapes.first, isA<Arrow>());
      final queen = segments.last;
      expect(queen.nags, [3]);
      expect(queen.label, 'Brilliant');
      expect(queen.tone, StoryTone.strong);
      expect(queen.moveClass, MoveClass.brilliant);
      // The strong moves ask for the move, at most two: a brilliancy
      // before a good move, then the heavier position.
      expect(
        [for (final s in segments) s.puzzle != null],
        [false, false, true, true],
      );
      expect(queen.puzzle!.kind, StoryPuzzleKind.findPlayed);
      expect(queen.puzzle!.answerSan, 'Qb8+');
      expect(queen.puzzle!.prompt, 'White to move');
      // What there is to find is named on the one action.
      expect(queen.puzzle!.reveal, 'Show the move');
    });

    test('a cluster of notes is spread: the far one is kept, neighbours '
        'only fill what is left', () {
      final moves = [
        '1. e4 { a } 1... e5 { b } 2. Nf3 { c } 2... Nc6 { d } 3. Bb5 { e }',
        '3... a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8',
        '10. d4 Nbd7 11. Nbd2 Bb7 12. Bc2 Re8 13. Nf1 Bf8 14. Ng3 g6',
        '15. a4 c5 16. d5 c4 17. Bg5 h6 { f }',
      ].join(' ');
      final segments = pickStorySegments(
        parseStoryPgn('[Result "*"]\n\n$moves *')!,
      );
      expect(segments, hasLength(4));
      final plies = [for (final s in segments) s.ply];
      // The last note is far from the rest and always makes it.
      expect(plies.last, 34);
      // The first pass keeps notes apart; only then do neighbours fill.
      expect(plies.toSet(), hasLength(4));
      expect(plies, orderedEquals([...plies]..sort()));
    });

    test('a verdict without words still picks a position: mate, a missed '
        'win; a quiet game picks nothing', () {
      final mate = _only(_pgn);
      expect(mate.label, 'Checkmate');
      expect(mate.tier, 1);
      expect(mate.finalPly, isTrue);
      expect(mate.puzzle, isNull);
      expect(pickStorySegments(parseStoryPgn(_quietPgn)!), isEmpty);
      // A game with no position worth a stop is its final position, with
      // no words: the player rows carry its result.
      final still = buildStoryGame(_game('q'), pgn: _quietPgn);
      expect(still.segments.single.isStill, isTrue);
      expect(still.segments.single.label, isNull);
      expect(still.segments.single.evalAfter, isNull);
    });

    test('a missed win asks for the win the PGN gives beside it; the '
        'evaluation is left to the bar, never put in words', () {
      final story = parseStoryPgn(_missedPgn)!;
      expect(story.alternatives[6]!.san, 'Qxf7#');
      final segments = pickMissedChanceSegments(story);
      expect(segments, hasLength(1));
      final miss = segments.single;
      expect(miss.san, 'Qf3');
      expect(miss.label, 'Missed win');
      expect(miss.puzzle!.kind, StoryPuzzleKind.findMissed);
      expect(miss.puzzle!.answerSan, 'Qxf7#');
      expect(miss.puzzle!.solver, Side.white);
      // One line asks; "Find it." is the action's own words now.
      expect(miss.puzzle!.prompt, 'White missed a win here');
      expect(miss.puzzle!.reveal, 'Show the win');
      expect(miss.comment, isNull);
      expect(miss.puzzle!.line, '4. Qxf7#');
      // The bar's numbers: mate in one before the miss, level after it; the
      // answer mates, which the board scores itself.
      expect(miss.evalBefore, (cp: null, mate: 1));
      expect(miss.evalAfter, (cp: 10, mate: null));
      expect(miss.puzzle!.answerEval, isNull);
      // The board opens at the position before the miss while it asks.
      expect(miss.boardMoveIndex(before: true), 5);
      expect(miss.boardMoveIndex(before: false), 6);
    });

    test('a report\'s blunder reads its verdict; what the evaluation did is '
        'the bar\'s, never words', () {
      final segments = pickStorySegments(parseStoryPgn(_missedPgn)!);
      expect([for (final s in segments) s.san], ['Nf6', 'Qf3']);
      final blunder = segments.first;
      expect(blunder.label, 'Blunder');
      expect(blunder.tone, StoryTone.weak);
      expect(blunder.moveClass, MoveClass.blunder);
      expect(blunder.tier, 1);
      expect(blunder.comment, isNull);
      expect(blunder.evalBefore, (cp: 0, mate: null));
      expect(blunder.evalAfter, (cp: null, mate: 1));
      // A blunder is shown, never asked.
      expect(blunder.puzzle, isNull);
    });

    test('a position reads long enough for its words, capped', () {
      final short = storySegmentDuration(_only(_pgn));
      final opera = pickStorySegments(parseStoryPgn(_operaPgn)!);
      final long = storySegmentDuration(opera[2]);
      expect(short, greaterThan(const Duration(seconds: 3)));
      expect(long, greaterThan(short));
      final huge = StorySegment(
        ply: 1,
        fenBefore: '',
        fenAfter: '',
        move: null,
        san: 'e4',
        moveNumber: 1,
        white: true,
        comment: 'x' * 2000,
      );
      expect(storySegmentDuration(huge), const Duration(seconds: 12));
    });
  });

  // ------------------------------------------------------------ selection
  group('which games', () {
    test('the latest game leads; the day\'s picks are random but the same all '
        'day, games with notes first', () {
      final games = [
        for (var i = 0; i < 12; i++)
          _game('g$i', updated: DateTime(2026, 11, 1 + i), annotated: i.isEven),
      ];
      final latest = latestStoryGame(games)!;
      expect(latest.id, 'g11');
      final today = storyDailyCandidates(
        games,
        latest: latest,
        slug: 'a',
        day: '2026-11-21',
      );
      final again = storyDailyCandidates(
        games,
        latest: latest,
        slug: 'a',
        day: '2026-11-21',
      );
      expect([for (final g in today) g.id], [for (final g in again) g.id]);
      expect(today.any((g) => g.id == 'g11'), isFalse);
      expect(today, hasLength(kStoryCandidatePool));
      // Annotated games lead the pool.
      expect(today.take(5).every((g) => g.card.hasAnnotations), isTrue);
      final tomorrow = storyDailyCandidates(
        games,
        latest: latest,
        slug: 'a',
        day: '2026-11-22',
      );
      expect([
        for (final g in tomorrow) g.id,
      ], isNot([for (final g in today) g.id]));
    });

    test('at most three stories, the latest first, each game with at least '
        'two positions', () {
      final latest = _game('latest');
      final candidates = [for (var i = 0; i < 6; i++) _game('c$i')];
      final mate = pickStorySegments(parseStoryPgn(_pgn)!);
      final opera = pickStorySegments(parseStoryPgn(_operaPgn)!);
      final picks = {'c0': mate, 'c1': opera, 'c2': opera, 'c3': opera};
      // The latest with two positions or more leads.
      final stories = chooseCollectionStories(
        latest: latest,
        candidates: candidates,
        segments: {'latest': opera, ...picks},
      );
      expect([for (final s in stories) s.id], ['latest', 'c1', 'c2']);
      expect(stories, hasLength(kStoriesPerCollection));
      // One position is not a story, the latest's included.
      final skipped = chooseCollectionStories(
        latest: latest,
        candidates: candidates,
        segments: {'latest': mate, ...picks},
      );
      expect([for (final s in skipped) s.id], ['c1', 'c2', 'c3']);
      // No game with two: the first with one, the latest first.
      final single = chooseCollectionStories(
        latest: latest,
        candidates: candidates,
        segments: {'c0': mate, 'latest': mate},
      );
      expect(single.single.id, 'latest');
      expect(single.single.segments.single.label, 'Checkmate');
      // Nothing to show at all: the latest game's final position.
      final still = chooseCollectionStories(
        latest: latest,
        candidates: candidates,
        segments: const {},
      );
      expect(still.single.segments.single.isStill, isTrue);
    });

    test('the batch provider reads only the latest and the day\'s pool, and '
        'builds the stories from them', () async {
      final games = [
        for (var i = 0; i < 10; i++)
          _game('g$i', updated: DateTime(2026, 11, 1 + i), annotated: true),
      ];
      final repository = _PgnRepository({
        for (final g in games) g.id: g.id == 'g9' ? _pgn : _operaPgn,
      });
      final container = ProviderContainer(
        overrides: [
          collectionContentsProvider.overrideWith(
            (ref, slug) async =>
                CollectionContents(sections: const [], games: games),
          ),
          collectionDetailProvider.overrideWith(
            (ref, slug) async => _collection(slug, games: 10),
          ),
          collectionsRepositoryProvider.overrideWithValue(repository),
          storyAnalyzerProvider.overrideWithValue(
            (jobs) async => analyzeStoryJobs(jobs),
          ),
          storyClockProvider.overrideWithValue(() => _now),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(storyBatchProvider('a'), (_, _) {});
      addTearDown(sub.close);
      final batch = await container.read(storyBatchProvider('a').future);
      // The latest (g9) is read first, but its one position is no story:
      // the day's picks fill the three.
      expect(batch.games.any((g) => g.id == 'g9'), isFalse);
      expect(batch.games, hasLength(kStoriesPerCollection));
      expect(batch.games.every((g) => g.segments.length == 4), isTrue);
      // The latest and the pool, never the whole collection.
      expect(repository.asked.single, hasLength(1 + kStoryCandidatePool));
      expect(repository.asked.single, contains('g9'));
      // Pages: one per position, a new game opening every fourth.
      expect(batch.storyCount, 4 + 4 + 4);
      expect(batch.frames[4].startsStory, isTrue);
      expect(batch.frames[8].startsStory, isTrue);
      expect(batch.signature, 'v:v-a');
    });

    test('Missed chances: at most three games a day, the ones with the most '
        'wins to find, newest first', () {
      final analysis = <String, StoryAnalysis>{};
      final games = <GamesTourModel>[];
      for (var i = 0; i < 5; i++) {
        final game = _game(
          'm$i',
        ).game.copyWith(lastMoveTime: DateTime(2026, 11, 20, i));
        games.add(game);
        final segments = i == 0
            ? const <StorySegment>[]
            : pickMissedChanceSegments(parseStoryPgn(_missedPgn)!);
        analysis[game.gameId] = StoryAnalysis(segments: segments, event: 'E');
      }
      final stories = chooseMissedChanceStories(
        games,
        analysis,
        day: '2026-11-21',
      );
      expect(stories, hasLength(kMissedChancesPerDay));
      expect(stories.any((s) => s.id == 'm0'), isFalse);
      final times = [for (final s in stories) s.game.lastMoveTime!];
      expect(times, orderedEquals([...times]..sort((a, b) => b.compareTo(a))));
      expect(stories.first.caption, 'E');
    });
  });

  // ------------------------------------------------------------------ seen
  group('seen', () {
    Future<StorySeenNotifier> loaded(_MemoryStorage storage) async {
      final container = ProviderContainer(
        overrides: [
          storySeenProvider.overrideWith((ref) => StorySeenNotifier(storage)),
        ],
      );
      addTearDown(container.dispose);
      container.read(storySeenProvider);
      await Future<void>.delayed(Duration.zero);
      return container.read(storySeenProvider.notifier);
    }

    test('caught up once every story is watched; the next day\'s picks never '
        'light the ring again, a new game does', () async {
      final storage = _MemoryStorage();
      final seen = await loaded(storage);
      final a = _collection('a', games: 3);
      final batch = _batch('a', 3);
      expect(seen.isSeen(a), isFalse);
      seen.markSeen(a, batch, 'a0');
      expect(seen.resumeIndex(a, batch), 1);
      seen.markSeen(a, batch, 'a1');
      seen.markSeen(a, batch, 'a2');
      expect(seen.isSeen(a), isTrue);
      expect(seen.resumeIndex(a, batch), 0);
      // Tomorrow: the latest and two new picks, same collection.
      final tomorrow = StoryBatch(
        games: [
          batch.games[0],
          buildStoryGame(_game('a7'), pgn: _pgn),
          buildStoryGame(_game('a8'), pgn: _pgn),
        ],
        ordered: batch.ordered,
        signature: batch.signature,
      );
      seen.reconcile(a, tomorrow);
      expect(seen.isSeen(a), isTrue);
      // But it opens on what is new to the reader.
      expect(seen.resumeIndex(a, tomorrow), 1);
      // A new game: the signature changes and the ring lights.
      final updated = _collection('a', games: 4, version: 'v-a-2');
      expect(seen.isSeen(updated), isFalse);
      final saved = jsonDecode(storage.value!) as Map;
      expect(saved['v'], 3);
      expect((saved['c'] as Map)['a'], containsPair('k', true));
    });

    test('a circle left part way through a story reopens on that position, '
        'after a relaunch too; a finished story moves it on', () async {
      final storage = _MemoryStorage();
      final seen = await loaded(storage);
      final a = _collection('a');
      final games = [_game('a0'), _game('a1')];
      final batch = StoryBatch(
        games: [for (final g in games) buildStoryGame(g, pgn: _operaPgn)],
        ordered: [for (final g in games) g.game],
        signature: storySignature(a),
      );
      expect(seen.resumeIndex(a, batch), 0);
      seen.markAt(a, batch.frames[2].id);
      expect(seen.resumeIndex(a, batch), 2);
      final again = await loaded(storage);
      expect(again.resumeIndex(a, batch), 2);
      // The story is seen: the place is past, the next story's start.
      again.markSeen(a, batch, 'a0');
      expect(again.resumeIndex(a, batch), 4);
      // A place in a game no longer shown is no place.
      again.markAt(a, 'gone#1');
      expect(again.resumeIndex(a, batch), 4);
    });

    test('a record from 39.1.0 keeps a quiet ring quiet while the collection '
        'holds the same games', () async {
      final a = _collection('a', games: 3);
      final seen = await loaded(
        _MemoryStorage(
          jsonEncode({
            'v': 2,
            'c': {
              'a': {
                'i': ['a0', 'a1', 'a2'],
                'c': 3,
                'f': true,
              },
              'b': {
                'i': ['b0'],
                'c': 3,
                'f': false,
              },
            },
          }),
        ),
      );
      expect(seen.isSeen(a), isTrue);
      expect(seen.isSeen(_collection('a', games: 4)), isFalse);
      expect(seen.isSeen(_collection('b')), isFalse);
    });
  });

  // ------------------------------------------------------------------- row
  group('the row', () {
    test('the eight updated most recently; a collection that changes lands '
        'leftmost, the watched ones after the rest', () {
      final catalog = [
        for (var i = 0; i < 10; i++)
          _collection('c$i', updated: DateTime(2026, 11, 20, 20 - i)),
      ];
      final shown = selectStoryCollections(catalog);
      expect(shown, hasLength(kStoryCollectionCap));
      expect(shown.last.slug, 'c7');
      // c9 gets a new game: its update is the newest of all.
      final updated = [
        ...catalog.take(9),
        _collection('c9', version: 'new', updated: DateTime(2026, 11, 21, 9)),
      ];
      final again = selectStoryCollections(updated);
      expect(again.first.slug, 'c9');
      expect(again.any((c) => c.slug == 'c7'), isFalse);
      final ordered = orderStoryCollections(
        again,
        (c) => c.slug == 'c0' || c.slug == 'c1',
      );
      expect(
        [for (final c in ordered) c.slug],
        ['c9', 'c2', 'c3', 'c4', 'c5', 'c6', 'c0', 'c1'],
      );
    });

    testWidgets('everything seen, the row stays: grey circles, the unseen '
        'ones first in the brand\'s tonal ink', (tester) async {
      final a = _collection('a', updated: DateTime(2026, 11, 21, 8));
      final b = _collection('b', updated: DateTime(2026, 11, 21, 7));
      final c = _collection('c', updated: DateTime(2026, 11, 21, 6));
      final batches = {
        'a': _batch('a', 2),
        'b': _batch('b', 2),
        'c': _batch('c', 2),
      };
      await _pumpRow(
        tester,
        collections: [a, b, c],
        batches: batches,
        seen: _caughtUp({'a': (a, batches['a']!)}),
      );
      final xs = {
        for (final s in ['a', 'b', 'c']) s: tester.getTopLeft(_circle(s)).dx,
      };
      expect(xs['b']!, closeTo(16, 0.01));
      expect(xs['b']! < xs['c']!, isTrue);
      expect(xs['c']! < xs['a']!, isTrue);
      final unseen = StoryRowMetrics.unseenRing(tester.element(_circle('b')));
      expect(_ringColor(tester, 'b'), unseen);
      expect(_ringColor(tester, 'a'), AppColors.dark.dividerStrong);
    });

    testWidgets('a watched circle that gets a new game lands leftmost, lit '
        'again, as soon as the catalog says so', (tester) async {
      final a = _collection('a', updated: DateTime(2026, 11, 21, 8));
      final b = _collection('b', updated: DateTime(2026, 11, 21, 7));
      final c = _collection('c', updated: DateTime(2026, 11, 20));
      final batches = {
        'a': _batch('a', 2),
        'b': _batch('b', 2),
        'c': _batch('c', 2),
      };
      final catalog = [a, b, c];
      final harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: batches,
        seen: _caughtUp({'c': (c, batches['c']!)}),
      );
      double x(String slug) => tester.getTopLeft(_circle(slug)).dx;
      expect(x('a') < x('b') && x('b') < x('c'), isTrue);
      expect(_ringColor(tester, 'c'), AppColors.dark.dividerStrong);
      // c gets a new game: a new version, the newest update.
      catalog[2] = _collection(
        'c',
        games: 4,
        version: 'v-c-2',
        updated: DateTime(2026, 11, 21, 9),
      );
      harness.container.invalidate(storyCollectionsProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(x('c'), closeTo(16, 0.01));
      expect(x('c') < x('a') && x('a') < x('b'), isTrue);
      expect(
        _ringColor(tester, 'c'),
        StoryRowMetrics.unseenRing(tester.element(_circle('c'))),
      );
    });

    testWidgets('all caught up, the row is still there, every circle quiet', (
      tester,
    ) async {
      final a = _collection('a', updated: DateTime(2026, 11, 21, 8));
      final b = _collection('b', updated: DateTime(2026, 11, 21, 7));
      final c = _collection('c', updated: DateTime(2026, 11, 21, 6));
      final batches = {
        'a': _batch('a', 2),
        'b': _batch('b', 2),
        'c': _batch('c', 2),
      };
      await _pumpRow(
        tester,
        collections: [a, b, c],
        batches: batches,
        seen: _caughtUp({
          for (final x in [a, b, c]) x.slug: (x, batches[x.slug]!),
        }),
      );
      await tester.pump(const Duration(seconds: 1));
      final row = find.byType(TodayStoryRow, skipOffstage: false);
      expect(tester.getSize(row).height, greaterThan(50));
      for (final s in ['a', 'b', 'c']) {
        expect(_ringColor(tester, s), AppColors.dark.dividerStrong);
      }
    });

    testWidgets('the Missed chances circle wears its own mark and opens its '
        'day; with no game that day it is not there', (tester) async {
      final a = _collection('a', updated: DateTime(2026, 11, 20));
      final missed = StoryBatch(
        games: [
          StoryGame(
            game: _game('m0').game,
            segments: pickMissedChanceSegments(parseStoryPgn(_missedPgn)!),
            caption: 'Club Championship',
          ),
        ],
        ordered: [_game('m0').game],
        signature: 'v:missed:2026-11-21',
      );
      await _pumpRow(
        tester,
        collections: [a],
        batches: {'a': _batch('a', 2), kMissedChancesSlug: missed},
      );
      expect(_circle(kMissedChancesSlug), findsOneWidget);
      expect(
        find.descendant(
          of: _circle(kMissedChancesSlug),
          matching: find.byType(MissedChancesMark),
        ),
        findsOneWidget,
      );
      expect(find.text('Missed chances'), findsOneWidget);
      // Today's, before yesterday's collection update.
      expect(
        tester.getTopLeft(_circle(kMissedChancesSlug)).dx,
        lessThan(tester.getTopLeft(_circle('a')).dx),
      );
      await _open(tester, kMissedChancesSlug);
      expect(find.byKey(const ValueKey('story_prompt')), findsOneWidget);
      expect(find.text('White missed a win here'), findsOneWidget);
      expect(find.text('Go to event'), findsOneWidget);
      // Free readers see the same stories: the gate is on the game.
      expect(find.byKey(const ValueKey('story_puzzle_board')), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('with no missed chance that day the circle is not there', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {
          'a': _batch('a', 2),
          kMissedChancesSlug: StoryBatch(games: const [], ordered: const []),
        },
      );
      expect(_circle('a'), findsOneWidget);
      expect(_circle(kMissedChancesSlug), findsNothing);
    });

    Future<void> pullPastStart(WidgetTester tester) async {
      final gesture = await tester.startGesture(const Offset(196, 120));
      for (var i = 0; i < 24; i++) {
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();
    }

    /// A second of frames: the row's spring in or out runs its course.
    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    double rowHeight(WidgetTester tester) =>
        tester.getSize(find.byType(TodayStoryRow, skipOffstage: false)).height;

    Finder settingValue(String value) => find.descendant(
      of: find.byKey(const ValueKey('settings_story_row')),
      matching: find.text(value),
    );

    testWidgets('free readers cannot pull Collection stories Off', (
      tester,
    ) async {
      const slugs = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      final harness = await _pumpRow(
        tester,
        collections: [for (final s in slugs) _collection(s)],
        batches: {for (final s in slugs) s: _batch(s, 2)},
        below: const StoryRowSettingsBody(),
        subscribed: false,
      );
      expect(settingValue('On'), findsOneWidget);
      expect(rowHeight(tester), greaterThan(0));
      await pullPastStart(tester);
      await tester.pumpAndSettle();
      expect(harness.prefs.mode, StoryRowMode.on);
      expect(find.text(kStoryRowHiddenMessage), findsNothing);
    });

    testWidgets('a pull past the first circle turns Collection stories Off: '
        'saved, the row gone, Settings saying Off at once; Undo turns it On '
        'and the row is back', (tester) async {
      final slugs = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      final harness = await _pumpRow(
        tester,
        collections: [for (final s in slugs) _collection(s)],
        batches: {for (final s in slugs) s: _batch(s, 2)},
        // Settings' own row on the same screen: one state for both.
        below: const StoryRowSettingsBody(),
      );
      expect(settingValue('On'), findsOneWidget);
      expect(rowHeight(tester), greaterThan(0));
      await pullPastStart(tester);
      // The setting itself, not a hidden-until state beside it.
      expect(harness.prefs.mode, StoryRowMode.off);
      expect(
        StoryRowPrefs.decodeLocal(harness.rowStore.local).mode,
        StoryRowMode.off,
      );
      await tester.pump();
      expect(settingValue('Off'), findsOneWidget);
      expect(find.text(kStoryRowHiddenMessage), findsOneWidget);
      expect(kStoryRowHiddenMessage, contains('Settings'));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(rowHeight(tester), 0);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await _run(tester, const Duration(milliseconds: 1200));
      expect(harness.prefs.mode, StoryRowMode.on);
      expect(settingValue('On'), findsOneWidget);
      expect(rowHeight(tester), greaterThan(0));
      expect(_circle('a'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('signed in, the pull and its Undo write the one choice to '
        'the server, and Settings shows each at once', (tester) async {
      final store = _RowStore(id: 'u1', server: StoryRowMode.on);
      final slugs = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      final harness = await _pumpRow(
        tester,
        collections: [for (final s in slugs) _collection(s)],
        batches: {for (final s in slugs) s: _batch(s, 2)},
        rowStore: store,
        below: const StoryRowSettingsBody(),
      );
      expect(store.reads, greaterThan(0));
      expect(settingValue('On'), findsOneWidget);
      await pullPastStart(tester);
      await tester.pump();
      expect(harness.prefs.mode, StoryRowMode.off);
      expect(store.serverWrites, [('u1', StoryRowMode.off)]);
      expect(settingValue('Off'), findsOneWidget);
      // Written, so the device's copy has nothing left to send.
      expect(harness.prefs.pending, isFalse);
      await frames(tester);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await _run(tester, const Duration(milliseconds: 1200));
      expect(store.serverWrites, [
        ('u1', StoryRowMode.off),
        ('u1', StoryRowMode.on),
      ]);
      expect(store.server, StoryRowMode.on);
      expect(settingValue('On'), findsOneWidget);
      // Never the account's old copy once the server keeps the choice.
      expect(store.legacyWrites, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Settings On shows the row at once, Off hides it at once, '
        'whatever put it away', (tester) async {
      final harness = await _pumpRow(
        tester,
        collections: [_collection('a'), _collection('b')],
        batches: {'a': _batch('a', 2), 'b': _batch('b', 2)},
      );
      final notifier = harness.container.read(storyRowPrefsProvider.notifier);
      expect(rowHeight(tester), greaterThan(0));
      await notifier.setMode(StoryRowMode.off);
      await frames(tester);
      expect(rowHeight(tester), 0);
      await notifier.setMode(StoryRowMode.on);
      await tester.pump();
      await frames(tester);
      expect(rowHeight(tester), greaterThan(0));
      expect(_circle('a'), findsOneWidget);
      // Pulled away, then On from Settings: back, nothing stale held.
      await pullPastStart(tester);
      await frames(tester);
      expect(rowHeight(tester), 0);
      expect(find.text(kStoryRowHiddenMessage), findsOneWidget);
      await notifier.setMode(StoryRowMode.on);
      await tester.pump();
      await frames(tester);
      expect(rowHeight(tester), greaterThan(0));
      // Its "hidden" snack goes too, well before its own time: it would now
      // say the opposite of what Today shows.
      expect(find.text(kStoryRowHiddenMessage), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a row pulled away by 39.2 ("until something new") reads as '
        'Off, in Settings and on Today', (tester) async {
      final store = _RowStore()
        ..local =
            '{"m":"on","u":7,"d":{"t":1763600000000,"f":"abc","g":12,'
            '"s":"k1:3,k2:9"}}';
      final harness = await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
        rowStore: store,
        below: const StoryRowSettingsBody(),
      );
      expect(harness.prefs.mode, StoryRowMode.off);
      expect(settingValue('Off'), findsOneWidget);
      expect(rowHeight(tester), 0);
      expect(find.byKey(const ValueKey('story_row_skeleton')), findsNothing);
      // On from Settings: the row comes, and the old pull-away is gone from
      // what is saved.
      await harness.container
          .read(storyRowPrefsProvider.notifier)
          .setMode(StoryRowMode.on);
      await tester.pump();
      await frames(tester);
      expect(rowHeight(tester), greaterThan(0));
      expect(store.local, isNot(contains('"d"')));
      expect(StoryRowPrefs.decodeLocal(store.local).mode, StoryRowMode.on);
    });

    test('the row is there whenever it is On, everything seen or not; a '
        '39.2 pull-away on the account reads as Off', () {
      expect(storyRowExpected(const StoryRowPrefs()), isTrue);
      expect(
        storyRowExpected(const StoryRowPrefs(mode: StoryRowMode.off)),
        isFalse,
      );
      // A 39.1.0 device copy with its old day fields reads as On.
      final old = StoryRowPrefs.decodeLocal(
        '{"m":"new","u":3,"a":"2026-11-19","r":{"s":"","n":3,"d":"x"}}',
      );
      expect(old.mode, StoryRowMode.on);
      expect(storyRowExpected(old), isTrue);
      // The account's copy of a 39.2 pull-away: Off; one 39.2 cleared
      // (something new came) is On.
      expect(
        StoryRowPrefs.fromAccountJson({
          'm': 'on',
          'd': {'t': 1763600000000, 'f': 'abc', 'g': 12},
          'u': 9,
        }).mode,
        StoryRowMode.off,
      );
      expect(
        StoryRowPrefs.fromAccountJson({'m': 'on', 'd': null, 'u': 10}).mode,
        StoryRowMode.on,
      );
      // What is written carries the choice alone.
      expect(
        const StoryRowPrefs(
          mode: StoryRowMode.off,
          updatedAt: 4,
        ).toAccountJson(),
        {'m': 'off', 'u': 4},
      );
    });
  });

  // ---------------------------------------------------------------- viewer
  group('the viewer', () {
    testWidgets('a tap on the right two thirds is the next position, on the '
        'left third the previous one; each position its own bar, a wider '
        'gap before each game', (tester) async {
      final games = [_game('a0'), _game('a1')];
      final batch = StoryBatch(
        games: [
          buildStoryGame(games[0], pgn: _operaPgn),
          buildStoryGame(games[1], pgn: _pgn),
        ],
        ordered: [for (final g in games) g.game],
      );
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': batch},
      );
      await _open(tester, 'a');
      final bars = tester.widget<StoryProgressBars>(
        find.byType(StoryProgressBars),
      );
      expect(bars.count, 5);
      expect(bars.storyStarts, {4});
      expect(find.byKey(const ValueKey('story_frame_a0#0')), findsOneWidget);
      // The commented move reads at once: its number, SAN, the words.
      expect(find.byKey(const ValueKey('story_move')), findsOneWidget);
      expect(find.text('The queen eyes f7 and b7 at once.'), findsOneWidget);
      expect(find.text('Paris Opera 1858'), findsNothing);
      await _tapAside(tester, 0.8);
      expect(find.byKey(const ValueKey('story_frame_a0#1')), findsOneWidget);
      await _tapAside(tester, 0.15);
      expect(find.byKey(const ValueKey('story_frame_a0#0')), findsOneWidget);
    });

    testWidgets('a position moves on when its bar is full: the move slides '
        'in, the result shows on the game\'s last move', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      await _open(tester, 'a');
      final segment = _batch('a', 1).games.first.segments.single;
      final run = storySegmentDuration(segment);
      // The move slides in a beat after the page shows.
      await tester.pump(run * 0.1);
      final board = tester.widget<GameCardChessboard>(
        find.byKey(const ValueKey('story_board')),
      );
      expect(board.fen, segment.fenAfter);
      expect(find.byKey(const ValueKey('story_result_white')), findsOneWidget);
      expect(_labelText(tester), 'Checkmate');
      await tester.pump(run * 0.9 - const Duration(milliseconds: 300));
      expect(_story('a0'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
      // The new position shows the position before for a beat, then lands.
      expect(
        tester
            .widget<GameCardChessboard>(
              find.byKey(const ValueKey('story_board')),
            )
            .fen,
        segment.fenBefore,
      );
      await tester.pump(run * (kStorySlideAt + 0.02));
      expect(
        tester
            .widget<GameCardChessboard>(
              find.byKey(const ValueKey('story_board')),
            )
            .fen,
        segment.fenAfter,
      );
    });

    testWidgets('holding pauses and hides the chrome; letting go resumes', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      await _open(tester, 'a');
      final hold = await tester.startGesture(
        const Offset(393 * 0.6, 852 * 0.06),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _run(tester, const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 12));
      expect(_story('a0'), findsOneWidget);
      await hold.up();
      await _run(tester, const Duration(milliseconds: 400));
      await tester.pump(storySegmentDuration(_only(_pgn)));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
    });

    testWidgets('a long drag down closes; Today hears it is covered and '
        'uncovered', (tester) async {
      final harness = await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      await _open(tester, 'a');
      await tester.pump(const Duration(seconds: 1));
      expect(harness.container.read(storyViewerCoversProvider), isTrue);
      final drag = await tester.startGesture(const Offset(196, 300));
      for (var i = 0; i < 12; i++) {
        await drag.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(harness.container.read(storyViewerCoversProvider), isFalse);
      await drag.up();
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
      expect(harness.container.read(storyViewerOpenProvider), isFalse);
    });

    testWidgets('after the last circle, with every one watched: "You\'re all '
        'caught up", then out', (tester) async {
      final a = _collection('a', games: 1);
      final b = _collection('b', games: 1);
      final batches = {'a': _batch('a', 1), 'b': _batch('b', 1)};
      final harness = await _pumpRow(
        tester,
        collections: [a, b],
        batches: batches,
        // b already watched; a is the last one left.
        seen: _caughtUp({'b': (b, batches['b']!)}),
      );
      await _open(tester, 'a');
      final run = storySegmentDuration(_only(_pgn));
      await tester.pump(run);
      await tester.pump(const Duration(milliseconds: 16));
      // The cube turns to b (watched before), plays it, then the end.
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(run);
      await tester.pump(const Duration(milliseconds: 16));
      expect(harness.seen.isSeen(a), isTrue);
      expect(find.byKey(const ValueKey('story_caught_up')), findsOneWidget);
      expect(find.text("You're all caught up"), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1900));
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
    });

    testWidgets('with a circle still unwatched the stories just close at the '
        'end, no card', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a', games: 1), _collection('b', games: 1)],
        batches: {'a': _batch('a', 1), 'b': _batch('b', 1)},
      );
      await _open(tester, 'b');
      await tester.pump(storySegmentDuration(_only(_pgn)));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('story_caught_up')), findsNothing);
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
    });

    testWidgets('Open game opens at this position, pausing the story until '
        'the reader is back', (tester) async {
      final hold = Completer<void>();
      final harness = await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 3)},
        openHold: hold,
      );
      await _open(tester, 'a');
      await tester.tap(find.byKey(const ValueKey('story_open_game')));
      await tester.pump();
      // The mate is ply 7: the board's move index 6.
      expect(harness.opened.single, ('a', 'a0', 6));
      await tester.pump(const Duration(seconds: 12));
      expect(_story('a0'), findsOneWidget);
      hold.complete();
      await tester.pump();
      await tester.pump(storySegmentDuration(_only(_pgn)));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
    });

    testWidgets('exposes next, previous, pause and close to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 3)},
      );
      await _open(tester, 'a');
      final node = tester.getSemantics(
        find.byKey(const ValueKey('story_viewer')),
      );
      final labels = [
        for (final id
            in node.getSemanticsData().customSemanticsActionIds ??
                const <int>[])
          CustomSemanticsAction.getAction(id)!.label,
      ];
      expect(
        labels,
        containsAll([
          'Next story',
          'Previous story',
          'Pause stories',
          'Close stories',
        ]),
      );
      expect(node.label, contains('story 1 of 3'));
      handle.dispose();
    });
  });

  // ------------------------------------------------------------- your move
  group('your move', () {
    Future<_Harness> pumpPuzzle(WidgetTester tester, {Completer<void>? hold}) =>
        _pumpRow(
          tester,
          collections: [_collection('a')],
          batches: {'a': _batch('a', 2, pgn: _puzzlePgn)},
          openHold: hold,
        );

    StoryBatch missedBatch() => StoryBatch(
      games: [
        StoryGame(
          game: _game('m0', result: '1-0').game,
          segments: pickMissedChanceSegments(parseStoryPgn(_blackMissPgn)!),
          caption: 'Myvatn OI Open 2026',
        ),
      ],
      ordered: [_game('m0', result: '1-0').game],
      signature: 'v:missed:2026-11-21',
    );

    Future<_Harness> pumpMissed(WidgetTester tester) async {
      final harness = await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 1), kMissedChancesSlug: missedBatch()},
      );
      await _open(tester, kMissedChancesSlug);
      await tester.pump(const Duration(milliseconds: 400));
      return harness;
    }

    ChessboardController board(WidgetTester tester) => tester
        .widget<Chessboard>(find.byKey(const ValueKey('story_puzzle_board')))
        .controller;

    Color? tint(WidgetTester tester) => tester
        .widget<Chessboard>(find.byKey(const ValueKey('story_puzzle_board')))
        .settings
        .colorScheme
        .lastMove
        .solidColor;

    double barProgress(WidgetTester tester) => tester
        .widget<StoryProgressBars>(find.byType(StoryProgressBars))
        .progress
        .value;

    testWidgets('the story waits while the reader thinks; found, the move '
        'lands with the Feed puzzle\'s solve, the found tone and its badge, '
        'says so, and the story holds before it runs on', (tester) async {
      final haptics = _Haptics(tester);
      final harness = await pumpPuzzle(tester);
      await _open(tester, 'a');
      expect(find.text('White to move'), findsOneWidget);
      // The mate is the strongest move, and the question's one action says
      // what there is to find.
      expect(find.text('Show the mate'), findsOneWidget);
      // The classified sounds load while the reader thinks.
      expect(harness.sounds.warmed, greaterThan(0));
      // Paused: a long think never moves the story on.
      await tester.pump(const Duration(seconds: 20));
      expect(_story('a0'), findsOneWidget);
      expect(barProgress(tester), 0);
      final before = haptics.medium;
      await _play(tester, 'h5', 'f7');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('story_prompt')), findsNothing);
      expect(_headline(tester), 'You found it · 4. Qxf7#!!');
      expect(_labelText(tester), 'Brilliant');
      expect(find.byKey(const ValueKey('story_badge')), findsOneWidget);
      // The Feed puzzle's solve: its sound and its haptic.
      expect(harness.sounds.played, [('Qxf7#', MoveClass.brilliant)]);
      expect(haptics.medium, before + 1);
      // The squares in the found tone: the board's own highlight.
      expect(tint(tester), storyTintOf(true));
      expect(board(tester).lastMove?.uci, 'h5f7');
      // Never an instant skip: past its usual reading time it still holds.
      await tester.pump(storySegmentDuration(_only(_puzzlePgn)));
      expect(_story('a0'), findsOneWidget);
      expect(barProgress(tester), greaterThan(0));
      // A beat later the story moves on.
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
    });

    testWidgets('a missed win found: the win\'s line plays on the board, a '
        'move at a time with its sound, the bar holding the winning number', (
      tester,
    ) async {
      final harness = await pumpMissed(tester);
      expect(find.text('Black missed a win here'), findsOneWidget);
      expect(_bar(tester).evaluation, -3.3);
      await _playBlack(tester, 'g5', 'g2');
      await tester.pump(const Duration(milliseconds: 300));
      expect(_headline(tester), 'You found it · 5… Qxg2');
      expect(_labelText(tester), 'd6 was played in the game');
      expect(find.text('Then 6. Rf1 Qxe4+ 7. Be2'), findsOneWidget);
      expect(board(tester).lastMove?.uci, 'g5g2');
      expect(_bar(tester).evaluation, -3.3);
      // The line: White's reply after a beat, then the win going on.
      await tester.pump(const Duration(milliseconds: 800));
      expect(board(tester).lastMove?.uci, 'h1f1');
      // The mark is the answer's: the line plays on the board's own
      // highlight.
      expect(tint(tester), isNot(storyTintOf(true)));
      expect(find.byKey(const ValueKey('story_badge')), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      expect(board(tester).lastMove?.uci, 'g2e4');
      await tester.pump(const Duration(milliseconds: 700));
      expect(board(tester).lastMove?.uci, 'c4e2');
      expect(harness.sounds.played, [
        ('Qxg2', MoveClass.brilliant),
        ('Rf1', null),
        ('Qxe4+', null),
        ('Be2', null),
      ]);
      expect(_bar(tester).evaluation, -3.3);
      expect(_headline(tester), 'You found it · 5… Qxg2');
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a move that was not it lands softly and goes back for '
        'another try; the game\'s own move is named; after two, Show is the '
        'way on, and it reveals as shown', (tester) async {
      final haptics = _Haptics(tester);
      final harness = await pumpMissed(tester);
      final colors = tester.element(find.byType(StoryFrameView)).colors;
      // Quiet while the reader tries: the actions' own plate.
      expect(_showFill(tester), colors.surfaceRecessed);
      // The move the game played.
      await _playBlack(tester, 'd7', 'd6');
      await tester.pump(const Duration(milliseconds: 100));
      expect(_headline(tester), 'Played in the game · try again');
      expect(harness.sounds.played.last, ('d6', MoveClass.mistake));
      expect(haptics.medium, 1);
      expect(tint(tester), storyTintOf(false));
      expect(find.byKey(const ValueKey('story_badge')), findsOneWidget);
      // The bar shows what the game's move gave away.
      expect(_bar(tester).evaluation, 6.0);
      // The story still waits.
      expect(barProgress(tester), 0);
      // It goes back: the board is the reader's again, the bar back on the
      // position asked, the words still saying what it was.
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        board(tester).fen,
        pickMissedChanceSegments(
          parseStoryPgn(_blackMissPgn)!,
        ).single.fenBefore,
      );
      expect(board(tester).game.playerSide, PlayerSide.black);
      expect(find.byKey(const ValueKey('story_badge')), findsNothing);
      expect(_bar(tester).evaluation, -3.3);
      expect(_headline(tester), 'Played in the game · try again');
      expect(_showFill(tester), colors.surfaceRecessed);
      await tester.pump(const Duration(seconds: 10));
      expect(barProgress(tester), 0);
      expect(find.byKey(const ValueKey('story_show_answer')), findsOneWidget);
      // Another move: "either", and Show turns solid, the way on. Its label
      // clears its plate on every frame of the fill's spring, never crossing
      // the fill's own value on the way.
      await _playBlack(tester, 'g8', 'f6');
      var leastContrast = double.infinity;
      for (var i = 0; i < 30; i++) {
        leastContrast = math.min(
          leastContrast,
          wcagContrast(_showInk(tester), _showFill(tester)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(leastContrast, greaterThan(3));
      expect(_headline(tester), 'Not this one either');
      await tester.pump(const Duration(milliseconds: 400));
      expect(_showFill(tester), colors.textPrimary);
      expect(_showInk(tester), colors.background);
      // Show: the answer lands as a find does, as shown.
      await tester.tap(find.byKey(const ValueKey('story_show_answer')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_headline(tester), 'The win · 5… Qxg2');
      expect(_headline(tester), isNot(contains('found')));
      expect(_labelText(tester), 'Missed win · d6 was played');
      expect(board(tester).lastMove?.uci, 'g5g2');
      expect(harness.sounds.played.last, ('Qxg2', null));
      expect(tint(tester), isNot(storyTintOf(true)));
      await tester.pump(const Duration(milliseconds: 800));
      expect(board(tester).lastMove?.uci, 'h1f1');
      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('a first miss says "Not this one · try again"; the next try '
        'can still find it', (tester) async {
      final harness = await pumpPuzzle(tester);
      await _open(tester, 'a');
      await _play(tester, 'h5', 'h7');
      expect(_headline(tester), 'Not this one · try again');
      expect(harness.sounds.played.single, ('Qxh7', MoveClass.mistake));
      // A finger back on the board takes the miss back at once, and never
      // moves the story on.
      await tester.tapAt(_square(tester, 'a3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a0'), findsOneWidget);
      expect(board(tester).game.playerSide, PlayerSide.white);
      await _play(tester, 'h5', 'f7');
      await tester.pump(const Duration(milliseconds: 300));
      expect(_headline(tester), 'You found it · 4. Qxf7#!!');
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a take-back touch on the reader\'s own piece picks it up, '
        'as the board does: the next tap plays it, and the find is seen '
        'through its whole hold', (tester) async {
      final harness = await pumpPuzzle(tester);
      await _open(tester, 'a');
      await _play(tester, 'h5', 'h7');
      expect(_headline(tester), 'Not this one · try again');
      // While the miss stands, the finger comes down on the queen: the miss
      // goes back, and the board picks the queen up in the same touch.
      await tester.tapAt(_square(tester, 'h5'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_story('a0'), findsOneWidget);
      expect(board(tester).game.playerSide, PlayerSide.white);
      // f7 is the queen's move, never a tap that moves the story on.
      await tester.tapAt(_square(tester, 'f7'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_story('a0'), findsOneWidget);
      expect(_headline(tester), 'You found it · 4. Qxf7#!!');
      expect(find.byKey(const ValueKey('story_badge')), findsOneWidget);
      expect(harness.sounds.played, [
        ('Qxh7', MoveClass.mistake),
        ('Qxf7#', MoveClass.brilliant),
      ]);
      // The hold is the find's, as for a first try.
      await tester.pump(storySegmentDuration(_only(_puzzlePgn)));
      expect(_story('a0'), findsOneWidget);
      expect(_headline(tester), 'You found it · 4. Qxf7#!!');
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
    });

    testWidgets('a take-back touch on another piece of the reader\'s picks '
        'that one up: its move is a second try, and the story still waits', (
      tester,
    ) async {
      final harness = await pumpPuzzle(tester);
      await _open(tester, 'a');
      await _play(tester, 'h5', 'h7');
      await tester.tapAt(_square(tester, 'g1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(_square(tester, 'f3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a0'), findsOneWidget);
      expect(board(tester).lastMove?.uci, 'g1f3');
      expect(_headline(tester), 'Not this one either');
      expect(harness.sounds.played, [
        ('Qxh7', MoveClass.mistake),
        ('Nf3', MoveClass.mistake),
      ]);
      // It goes back, and the story waits on the reader as before.
      await tester.pump(const Duration(seconds: 5));
      expect(_story('a0'), findsOneWidget);
      expect(barProgress(tester), 0);
      expect(board(tester).game.playerSide, PlayerSide.white);
    });

    testWidgets('each step is told to a screen reader: announced where the '
        'platform takes it, a live headline elsewhere', (tester) async {
      final announced = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            message,
          ) async {
            if (message is Map && message['type'] == 'announce') {
              announced.add('${(message['data'] as Map)['message']}');
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              null,
            ),
      );
      final handle = tester.ensureSemantics();
      // A platform that takes no announcement: the headline is a live
      // region.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpPuzzle(tester);
      await _open(tester, 'a');
      final live = find.ancestor(
        of: find.byKey(const ValueKey('story_prompt')),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false),
        ),
      );
      expect(live, findsOneWidget);
      // One that does: each step is announced.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(supportsAnnounce: true);
      await tester.pump();
      await _play(tester, 'h5', 'h7');
      await tester.pump(const Duration(milliseconds: 700));
      await _play(tester, 'h5', 'f7');
      await tester.pump(const Duration(milliseconds: 300));
      expect(announced, [
        'Not this one. Try again.',
        'You found it: 4. Qxf7#.',
      ]);
      handle.dispose();
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('Show reveals without a try; a tap on the right skips the '
        'question; Open game opens at the position asked', (tester) async {
      final hold = Completer<void>();
      final harness = await pumpPuzzle(tester, hold: hold);
      await _open(tester, 'a');
      await tester.tap(find.byKey(const ValueKey('story_open_game')));
      await tester.pump();
      // Asked from the position before the move: index 5.
      expect(harness.opened.single, ('a', 'a0', 5));
      hold.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.byKey(const ValueKey('story_show_answer')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_headline(tester), 'The mate · 4. Qxf7#!!');
      expect(_labelText(tester), 'Brilliant');
      // Next story: asked again, and skipped with a tap clear of the board.
      await tester.pump(
        storySegmentDuration(_only(_puzzlePgn)) +
            const Duration(milliseconds: 1300),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
      expect(find.text('White to move'), findsOneWidget);
      // A piece picked up is the reader's, never the story's.
      await tester.tapAt(_square(tester, 'h5'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
      // Put down again, then a tap clear of the board moves on.
      await tester.tapAt(_square(tester, 'h5'));
      await tester.pump(const Duration(milliseconds: 80));
      final words = tester.getRect(find.byKey(const ValueKey('story_words')));
      await tester.tapAt(Offset(words.right - 8, words.bottom - 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // Tapped past, the last story counts as seen: every circle is
      // watched, and the stories end on the quiet card, then go.
      expect(find.byKey(const ValueKey('story_caught_up')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1900));
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
    });

    testWidgets('back on a position found before, it rests on the find', (
      tester,
    ) async {
      await pumpPuzzle(tester);
      await _open(tester, 'a');
      await _play(tester, 'h5', 'f7');
      await tester.pump(const Duration(milliseconds: 300));
      await _tapAside(tester, 0.8);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_story('a1'), findsOneWidget);
      await _tapAside(tester, 0.1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_story('a0'), findsOneWidget);
      expect(_headline(tester), 'You found it · 4. Qxf7#!!');
      expect(find.byKey(const ValueKey('story_show_answer')), findsNothing);
      await tester.pump(const Duration(seconds: 8));
    });
  });

  // ------------------------------------------------- eval bar, board taps
  group('the eval bar\'s numbers', () {
    test('every position carries what its PGN records, read as the Feed '
        'reads a ply; a missed win\'s answer keeps the engine\'s number', () {
      final miss = pickMissedChanceSegments(
        parseStoryPgn(_blackMissPgn)!,
      ).single;
      expect(miss.san, 'd6');
      expect(miss.puzzle!.prompt, 'Black missed a win here');
      expect(miss.puzzle!.reveal, 'Show the win');
      expect(miss.puzzle!.solver, Side.black);
      expect(miss.comment, isNull);
      expect(miss.evalBefore, (cp: -330, mate: null));
      expect(miss.evalAfter, (cp: 600, mate: null));
      // The line beside the miss carries no number: the best move keeps
      // the evaluation it was found with.
      expect(miss.puzzle!.answerEval, (cp: -330, mate: null));
      // What the words add under the revealed win: the line after the
      // move the headline shows, never the move again.
      expect(miss.puzzle!.continuation, '6. Rf1 Qxe4+ 7. Be2');

      // A variation with its own number gives that.
      final own = pickMissedChanceSegments(
        parseStoryPgn(
          _blackMissPgn.replaceFirst(
            '( 5... Qxg2',
            '( 5... Qxg2 { [%eval -4.1] }',
          ),
        )!,
      ).single;
      expect(own.puzzle!.answerEval, (cp: -410, mate: null));

      // A move with no number of its own reads the nearest earlier one.
      final commented = pickStorySegments(
        parseStoryPgn(_commentedEvalPgn)!,
      ).single;
      expect(commented.evalBefore, (cp: 30, mate: null));
      expect(commented.evalAfter, (cp: 20, mate: null));
    });

    test('a mate the solver delivers is one move nearer after the best '
        'move; one in one lands on the board\'s own mate', () {
      expect(storyBestLineEval(null, Side.white), isNull);
      expect(storyBestLineEval((cp: 250, mate: null), Side.white), (
        cp: 250,
        mate: null,
      ));
      expect(storyBestLineEval((cp: null, mate: 3), Side.white), (
        cp: null,
        mate: 2,
      ));
      expect(storyBestLineEval((cp: null, mate: -3), Side.black), (
        cp: null,
        mate: -2,
      ));
      expect(storyBestLineEval((cp: null, mate: 1), Side.white), isNull);
      // Being mated: the number stands.
      expect(storyBestLineEval((cp: null, mate: -2), Side.white), (
        cp: null,
        mate: -2,
      ));
    });

    test('a finished position speaks for itself, then the record; nothing '
        'recorded asks the cache', () {
      final mated = _fen(
        'r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4',
      );
      expect(storyRecordedEval(mated, null), const FeedEval(pawns: 100));
      expect(
        storyRecordedEval(mated, (cp: -50, mate: null)),
        const FeedEval(pawns: 100),
      );
      final open = _fen(_mateFen);
      expect(
        storyRecordedEval(open, (cp: null, mate: 1)),
        const FeedEval(mate: 1),
      );
      expect(
        storyRecordedEval(open, (cp: -330, mate: null)),
        const FeedEval(pawns: -3.3),
      );
      expect(storyRecordedEval(open, null), isNull);
      expect(storyRecordedEval(null, null), FeedEval.none);
      expect(storyBarEvaluation(const FeedEval(mate: -2)), -10);
      expect(storyBarEvaluation(const FeedEval(pawns: 0.4)), 0.4);
    });
  });

  group('a tap on a board that asks for a move', () {
    final position = _fen(_mateFen);
    final legal = makeLegalMoves(position);

    test('nothing picked up: an empty square or an opponent\'s piece is the '
        'story\'s, a piece of the side to move is the board\'s', () {
      expect(storyBoardTap(Square.a3, position: position, validMoves: legal), (
        takes: false,
        selected: null,
        promoting: false,
      ));
      expect(storyBoardTap(Square.c6, position: position, validMoves: legal), (
        takes: false,
        selected: null,
        promoting: false,
      ));
      expect(storyBoardTap(Square.h5, position: position, validMoves: legal), (
        takes: true,
        selected: Square.h5,
        promoting: false,
      ));
    });

    test('a piece picked up: every touch is the board\'s (play it, put it '
        'down, pick up another)', () {
      Square? tapFrom(Square square) => storyBoardTap(
        square,
        position: position,
        validMoves: legal,
        selected: Square.h5,
      ).selected;
      final play = storyBoardTap(
        Square.f7,
        position: position,
        validMoves: legal,
        selected: Square.h5,
      );
      expect(play, (takes: true, selected: null, promoting: false));
      expect(
        storyBoardTap(
          Square.a3,
          position: position,
          validMoves: legal,
          selected: Square.h5,
        ).takes,
        isTrue,
      );
      expect(tapFrom(Square.a3), isNull);
      expect(tapFrom(Square.h5), isNull);
      expect(tapFrom(Square.c4), Square.c4);
    });

    test('a promotion\'s choice is the board\'s too', () {
      final pawn = _fen('8/P7/8/8/8/8/8/k6K w - - 0 1');
      final moves = makeLegalMoves(pawn);
      final promote = storyBoardTap(
        Square.a8,
        position: pawn,
        validMoves: moves,
        selected: Square.a7,
      );
      expect(promote, (takes: true, selected: null, promoting: true));
      expect(
        storyBoardTap(
          Square.d4,
          position: pawn,
          validMoves: moves,
          promoting: true,
        ),
        (takes: true, selected: null, promoting: false),
      );
    });
  });

  group('polish', () {
    StoryBatch missedBatch(String pgn) => StoryBatch(
      games: [
        StoryGame(
          game: _game('m0', result: '1-0').game,
          segments: pickMissedChanceSegments(parseStoryPgn(pgn)!),
          caption: 'Myvatn OI Open 2026',
        ),
      ],
      ordered: [_game('m0', result: '1-0').game],
      signature: 'v:missed:2026-11-21',
    );

    testWidgets('no evaluation is put in words, on any page', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {
          'a': _batch('a', 1, pgn: _missedPgn),
          kMissedChancesSlug: missedBatch(_blackMissPgn),
        },
      );
      await _open(tester, kMissedChancesSlug);
      await tester.pump(const Duration(milliseconds: 400));
      // The screenshot's page: the headline and the action, no number.
      expect(find.text('Black missed a win here'), findsOneWidget);
      expect(find.text('Show the win'), findsOneWidget);
      expect(_drawnText(tester).where(_evalProse.hasMatch), isEmpty);
      await tester.tap(find.byKey(const ValueKey('story_show_answer')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Then 6. Rf1 Qxe4+ 7. Be2'), findsOneWidget);
      expect(_drawnText(tester).where(_evalProse.hasMatch), isEmpty);
      // On to the collection: the report's blunder, then its missed win.
      await _tapAside(tester, 0.8);
      await tester.pump(const Duration(milliseconds: 1200));
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 400));
        expect(_drawnText(tester).where(_evalProse.hasMatch), isEmpty);
        await _tapAside(tester, 0.8);
      }
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the eval bar stands left of the board, as tall, flush with '
        'it, and moves with the move as it lands', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 1, pgn: _commentedEvalPgn)},
      );
      await _open(tester, 'a');
      final bar = tester.getRect(find.byKey(const ValueKey('story_eval_bar')));
      final board = tester.getRect(find.byKey(const ValueKey('story_board')));
      expect(bar.right, moreOrLessEquals(board.left));
      expect(bar.top, moreOrLessEquals(board.top));
      expect(bar.height, moreOrLessEquals(board.height));
      // The Feed's own width on a phone upright.
      expect(bar.width, 20);
      // The rows and the words start on the bar's edge.
      final words = tester.getRect(find.byKey(const ValueKey('story_words')));
      expect(words.left, moreOrLessEquals(bar.left));
      expect(words.right, moreOrLessEquals(board.right));
      final run = storySegmentDuration(
        pickStorySegments(parseStoryPgn(_commentedEvalPgn)!).single,
      );
      await tester.pump(run * 0.2);
      expect(_bar(tester).evaluation, 0.2);
      expect(_bar(tester).isFlipped, isFalse);
      expect(find.text('The knight hits e5 at once.'), findsOneWidget);
    });

    testWidgets('a missed chance asks with the bar on the position asked, '
        'turned with the board; Show reveals the win, the bar keeps the '
        'engine\'s number', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {
          'a': _batch('a', 1),
          kMissedChancesSlug: missedBatch(_blackMissPgn),
        },
      );
      await _open(tester, kMissedChancesSlug);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_bar(tester).evaluation, -3.3);
      expect(_bar(tester).isFlipped, isTrue);
      await tester.tap(find.byKey(const ValueKey('story_show_answer')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('story_prompt')), findsNothing);
      expect(_bar(tester).evaluation, -3.3);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a mate revealed reads "#" on the bar, filled for the side '
        'that mates', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {
          'a': _batch('a', 1),
          kMissedChancesSlug: missedBatch(_missedPgn),
        },
      );
      await _open(tester, kMissedChancesSlug);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_bar(tester).mate, 1);
      await tester.tap(find.byKey(const ValueKey('story_show_answer')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_bar(tester).isCheckmate, isTrue);
      expect(_bar(tester).evaluation, 100);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the actions are buttons: Show reveals, Open game opens the '
        'board at the position, Go to event opens the game\'s event', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {
          'a': _batch('a', 1),
          kMissedChancesSlug: missedBatch(_blackMissPgn),
        },
      );
      await _open(tester, kMissedChancesSlug);
      await tester.pump(const Duration(milliseconds: 400));
      for (final (key, label) in [
        ('story_show_answer', 'Show the win'),
        ('story_open_game', 'Open game'),
        ('story_view_collection', 'Go to event'),
      ]) {
        expect(
          tester.getSemantics(find.byKey(ValueKey(key))),
          isSemantics(label: label, isButton: true, hasTapAction: true),
        );
      }
      // Open game, at the position asked (before Black's 5th move).
      await tester.tap(find.byKey(const ValueKey('story_open_game')));
      await tester.pump();
      expect(harness.opened.single, (kMissedChancesSlug, 'm0', 8));
      await tester.pump(const Duration(milliseconds: 100));
      // Show: the win on the board.
      await tester.tap(find.byKey(const ValueKey('story_show_answer')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('story_label')), findsOneWidget);
      expect(find.textContaining('d6 was played'), findsOneWidget);
      // Go to event: the game's own.
      await tester.tap(find.byKey(const ValueKey('story_view_collection')));
      await tester.pump();
      final game = _game('m0', result: '1-0').game;
      expect(harness.events.single, (game.tourId, game.roundId));
      handle.dispose();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('View collection is a button that opens the collection', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        collections: [_collection('a', kind: CollectionKind.analysis)],
        batches: {'a': _batch('a', 2)},
      );
      await _open(tester, 'a');
      expect(find.text('View collection'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story_view_collection')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('collection_page')), findsOneWidget);
    });

    testWidgets('a tap on a still board moves the story on like a tap '
        'anywhere: right part next, left part back', (tester) async {
      final games = [_game('a0'), _game('a1')];
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {
          'a': StoryBatch(
            games: [
              buildStoryGame(games[0], pgn: _operaPgn),
              buildStoryGame(games[1], pgn: _pgn),
            ],
            ordered: [for (final g in games) g.game],
          ),
        },
      );
      await _open(tester, 'a');
      expect(find.byKey(const ValueKey('story_frame_a0#0')), findsOneWidget);
      final board = tester.getRect(find.byKey(const ValueKey('story_board')));
      await tester.tapAt(
        Offset(board.left + board.width * 0.75, board.center.dy),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('story_frame_a0#1')), findsOneWidget);
      await tester.tapAt(Offset(board.left + 20, board.center.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('story_frame_a0#0')), findsOneWidget);
    });

    testWidgets('on a board asking for a move, an empty square skips; a '
        'piece and its square play the puzzle, never a skip', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 3, pgn: _puzzlePgn)},
      );
      await _open(tester, 'a');
      expect(_story('a0'), findsOneWidget);
      expect(find.byKey(const ValueKey('story_prompt')), findsOneWidget);
      // An empty square on the right: the next story.
      await tester.tapAt(_square(tester, 'f3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
      // An empty square on the left: back.
      await tester.tapAt(_square(tester, 'a3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a0'), findsOneWidget);
      // An opponent's piece with nothing picked up: the story's too.
      await tester.tapAt(_square(tester, 'f6'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
      await tester.tapAt(_square(tester, 'a3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a0'), findsOneWidget);
      // The queen picked up, then an empty square: the board's (it puts
      // the queen down), not a skip.
      await tester.tapAt(_square(tester, 'h5'));
      await tester.pump(const Duration(milliseconds: 80));
      expect(_story('a0'), findsOneWidget);
      // d3: no square the queen reaches.
      await tester.tapAt(_square(tester, 'd3'));
      await tester.pump(const Duration(milliseconds: 80));
      expect(_story('a0'), findsOneWidget);
      expect(find.byKey(const ValueKey('story_prompt')), findsOneWidget);
      // Picked up and played: the puzzle's move.
      await _play(tester, 'h5', 'f7');
      await tester.pump(const Duration(milliseconds: 300));
      expect(_story('a0'), findsOneWidget);
      expect(_headline(tester), 'You found it · 4. Qxf7#!!');
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('polish, over the board', () {
    testWidgets('a hold on an empty square of an asking board pauses, and a '
        'drag down from it closes the stories', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2, pgn: _puzzlePgn)},
      );
      await _open(tester, 'a');
      expect(find.byKey(const ValueKey('story_prompt')), findsOneWidget);
      // The header, bars and actions fade while a story is held.
      double chrome() => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byType(StoryHeader),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      expect(chrome(), 1);
      final hold = await tester.startGesture(_square(tester, 'f3'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(chrome(), lessThan(0.05));
      // The hold turns into a drag down: the stories close.
      for (var i = 0; i < 14; i++) {
        await hold.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await hold.up();
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
    });
  });

  // -------------------------------------------------------------- sanity
  group('robustness', () {
    test('a castling answer is found however it is entered', () {
      const pgn = '''[Result "*"]

1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O!! *''';
      final segment = _only(pgn);
      final answer = segment.puzzle!.answer as NormalMove;
      expect(answer.from, Square.e1);
    });

    test('lichess\'s computer verdicts are never taken for a person\'s '
        'words; a person\'s own "Blunder." is', () {
      expect(pgnCommentProse(['(0.25 → 1.20) Mistake. Nf3 was best.']), isNull);
      expect(
        pgnCommentProse([
          '(Mate in 3 → 0.15) Lost forced checkmate sequence. Qxf7# was best. '
              '[%eval 0.15]',
        ]),
        isNull,
      );
      expect(
        pgnCommentProse(['Inaccuracy. d4 was best. A quiet move.']),
        'A quiet move.',
      );
      expect(
        pgnCommentProse(['Blunder. The king walks into it.']),
        'Blunder. The king walks into it.',
      );
      // An export with lichess's analysis: its glyphs pick, never as words.
      const pgn = '''[Result "1-0"]

1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6?? { (0.0 → Mate in 1) Checkmate is now unavoidable. g6 was best. } 4. Qxf7# 1-0''';
      final segments = pickStorySegments(parseStoryPgn(pgn)!);
      expect([for (final s in segments) s.san], ['Nf6', 'Qxf7#']);
      expect(segments.every((s) => s.tier == 1 && s.comment == null), isTrue);
    });

    test('a damaged PGN gives no story, never a throw', () {
      expect(parseStoryPgn('1. e4 e5 2. Qxx9'), isNotNull);
      expect(parseStoryPgn('not a game'), isNull);
      expect(
        analyzeStoryJobs([
          const StoryAnalysisJob(id: 'x', pgn: '{{{'),
        ])['x']!.segments,
        isEmpty,
      );
    });

    testWidgets('light theme: the label reads in its verdict\'s colour, '
        'legible on paper', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 1, pgn: _operaPgn)},
        light: true,
      );
      await _open(tester, 'a');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

/// Hands back PGNs for the ids asked, recording each ask.
class _PgnRepository implements CollectionsRepository {
  _PgnRepository(this.pgns);

  final Map<String, String> pgns;
  final List<Set<String>> asked = [];

  @override
  Future<Map<String, String>> fetchPgnsOf(
    String slug,
    Set<String> ids, {
    List<String>? order,
  }) async {
    asked.add(ids);
    return {
      for (final id in ids)
        if (pgns[id] case final pgn?) id: pgn,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

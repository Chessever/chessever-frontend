import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_playback.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feed opens a post on the position after the game's last book move and
/// plays on from there.

class _RecordingOutput implements ClassificationSfxOutput {
  final List<String> calls = [];

  @override
  void playOrdinary(SfxType type) => calls.add('ordinary:${type.name}');

  @override
  void playClassification(SfxType type, {SfxType? fallback}) =>
      calls.add('class:${type.name}/${fallback?.name}');

  @override
  Future<void> warmUp() async {}
}

class _FakeGame extends Fake implements GamesTourModel {}

FeedPly _ply(String san, {MoveClass? verdict, FeedMomentType? moment}) =>
    FeedPly(
      fen: kInitialFEN,
      san: san,
      moveClass: verdict,
      moment: moment == null
          ? null
          : FeedMoment(type: moment, label: moment.name),
    );

FeedPly _book(String san) => _ply(san, verdict: MoveClass.book);

FeedItem _item(List<FeedPly> moves, {String? result}) => FeedItem(
  game: _FakeGame(),
  plies: [
    const FeedPly(fen: kInitialFEN),
    ...moves,
  ],
  reason: 'test',
  result: result,
);

FeedPlayback _playback(FeedItem item) {
  final sfx = FeedSfx.forTesting();
  return FeedPlayback(item: item, sfx: sfx, moveSound: FeedMoveSound(sfx));
}

/// Theory, a quiet ply out of the database, a transposition straight back
/// into theory, then the game: the clip opens on ply 4.
List<FeedPly> get _transposed => [
  _book('Nf3'),
  _book('d5'),
  _ply('c4'),
  _book('e6'),
  _ply('Nc3'),
  _ply('a3', moment: FeedMomentType.inaccuracy),
];

void main() {
  group('FeedItem.startPly', () {
    test('a game with no book move opens on its starting position', () {
      expect(_item([_ply('e4'), _ply('e5')]).startPly, 0);
    });

    test('opens after the last book move, past a gap in theory', () {
      expect(_item(_transposed).startPly, 4);
    });

    test('a game that was theory to the end still plays its last move', () {
      expect(_item([_book('e4'), _book('e5'), _book('Nf3')]).startPly, 2);
      expect(_item([_book('e4')]).startPly, 0);
    });

    test('an empty clip opens at zero', () {
      expect(
        FeedItem(
          game: _FakeGame(),
          plies: const [FeedPly(fen: kInitialFEN)],
          reason: 'test',
        ).startPly,
        0,
      );
    });
  });

  group('FeedPlayback opens after the book', () {
    late _RecordingOutput output;

    setUp(() => ClassificationSfx.output = output = _RecordingOutput());
    tearDown(() => ClassificationSfx.output = null);

    testWidgets('a page shows the position before it is swiped onto, then '
        'plays on from it without sounding the book', (tester) async {
      final playback = _playback(_item(_transposed, result: '½-½'));
      addTearDown(playback.dispose);

      // Not yet the current page: a neighbour already shows where it opens.
      expect(playback.startPly, 4);
      expect(playback.shownPly, 4);

      playback
        ..restart()
        ..setSuspended(false);
      expect(playback.shownPly, 4);
      expect(output.calls, isEmpty);

      await tester.pump(const Duration(seconds: 5));

      expect(playback.isEnded, isTrue);
      expect(output.calls, [
        'ordinary:move', // Nc3, the first move after the book
        'class:nagInaccuracy/move',
        'ordinary:draw',
      ]);
    });

    testWidgets('the first beat off the opening position is the short one', (
      tester,
    ) async {
      final playback = _playback(_item(_transposed, result: '½-½'));
      addTearDown(playback.dispose);

      playback
        ..restart()
        ..setSuspended(false);
      await tester.pump(FeedPlayback.firstStep);

      expect(playback.ply, 5);
      // Off screen: the next beat's timer goes with it.
      playback.setSuspended(true);
    });

    test('a replay starts after the book again; stepping still reaches move '
        'one', () {
      final playback = _playback(_item(_transposed, result: '½-½'));
      addTearDown(playback.dispose);

      playback.stepTo(0);
      expect(playback.shownPly, 0);

      playback.stepTo(playback.lastPly);
      playback.restart();
      expect(playback.shownPly, 4);
      expect(playback.isManual, isFalse);
      expect(playback.isEnded, isFalse);
    });
  });
}

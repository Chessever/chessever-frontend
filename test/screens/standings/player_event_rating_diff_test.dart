import 'package:chessever2/screens/standings/utils/fide_rating_change.dart';
import 'package:chessever2/screens/standings/utils/player_event_share_utils.dart';
import 'package:chessever2/screens/standings/widgets/player_event_share_image_card.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerEventShareGameRow _row({
  double? change,
  PlayerEventGameOutcome outcome = PlayerEventGameOutcome.win,
  int rating = 2676,
  String? pool,
}) => PlayerEventShareGameRow(
  roundLabel: null,
  countryCode: '',
  title: 'GM',
  name: 'Opponent',
  rating: rating,
  ratingChange: change,
  ratingPool: pool,
  result: outcome == PlayerEventGameOutcome.draw ? '½' : '1',
  outcome: outcome,
  isWhite: true,
);

void main() {
  test('Lazavik report includes the latest win despite stale standings +7', () {
    // The nine opponents and scores shown in the reported share image.
    const ratings = [2344, 2665, 2453, 2469, 2743, 2644, 2642, 2391, 2676];
    const scores = [1.0, 0.5, 1.0, 0.5, 1.0, 0.5, 0.5, 0.5, 1.0];
    final rows = [
      for (var i = 0; i < ratings.length; i++)
        _row(
          rating: ratings[i],
          outcome: scores[i] == 1
              ? PlayerEventGameOutcome.win
              : PlayerEventGameOutcome.draw,
          change: calculateFideRatingChange(
            playerRating: 2621,
            opponentRating: ratings[i],
            actualScore: scores[i],
            kFactor: 10,
          ),
        ),
    ];

    expect(resolvePlayerEventRatingDiff(rows: rows.sublist(0, 8)), 7);
    expect(rows.last.ratingChange, closeTo(5.785, 0.001));
    for (final sourcePlayed in [8, 9]) {
      expect(
        resolvePlayerEventRatingDiff(
          rows: rows,
          sourcePlayed: sourcePlayed,
          fallbackRatingDiff: 7,
        ),
        13,
      );
    }
  });

  test('latest loss can turn a stale positive total negative', () {
    expect(
      resolvePlayerEventRatingDiff(
        rows: [
          _row(change: 2.2),
          _row(change: -7.1, outcome: PlayerEventGameOutcome.loss),
        ],
        fallbackRatingDiff: 2,
      ),
      -5,
    );
  });

  test('rounds the full sum rather than adding rounded row labels', () {
    expect(
      resolvePlayerEventRatingDiff(
        rows: [_row(change: 0.4), _row(change: 0.4)],
      ),
      1,
    );
  });

  test('zero change is a valid calculated total, not missing data', () {
    expect(
      resolvePlayerEventRatingDiff(
        rows: [_row(change: 0, outcome: PlayerEventGameOutcome.draw)],
        fallbackRatingDiff: 7,
      ),
      0,
    );
    expect(
      resolvePlayerEventRatingDiff(rows: [_row(change: 2), _row(change: -2)]),
      0,
    );
  });

  test('ongoing or unknown games do not change a completed-game total', () {
    expect(
      resolvePlayerEventRatingDiff(
        rows: [
          _row(change: 5.8),
          _row(outcome: PlayerEventGameOutcome.other),
        ],
        fallbackRatingDiff: 7,
      ),
      6,
    );
  });

  test('keeps source total while finished game ratings are missing', () {
    final rows = [_row(change: 5.8), _row()];
    expect(resolvePlayerEventRatingDiff(rows: rows, fallbackRatingDiff: 7), 7);
    expect(resolvePlayerEventRatingDiff(rows: rows), isNull);
  });

  test('keeps source total while only part of the event history is loaded', () {
    expect(
      resolvePlayerEventRatingDiff(
        rows: [_row(change: 5.8)],
        sourcePlayed: 9,
        fallbackRatingDiff: 7,
      ),
      7,
    );
  });

  test(
    'mixed rating pools retain a source total instead of adding separate lists',
    () {
      expect(
        resolvePlayerEventRatingDiff(
          rows: [
            _row(change: 5, pool: 'standard'),
            _row(change: 7, pool: 'blitz'),
          ],
        ),
        isNull,
      );
      expect(
        resolvePlayerEventRatingDiff(
          rows: [
            _row(change: 5, pool: 'standard'),
            _row(change: 7, pool: 'blitz'),
          ],
          fallbackRatingDiff: 5,
        ),
        5,
      );
    },
  );

  test('custom scoring preserves source Elo including a real zero', () {
    expect(
      resolvePlayerEventRatingDiff(
        rows: [_row(change: 5)],
        preferSource: true,
        fallbackRatingDiff: 0,
      ),
      0,
    );
  });

  test('does not invent a zero total before any games have finished', () {
    expect(resolvePlayerEventRatingDiff(rows: []), isNull);
    expect(
      resolvePlayerEventRatingDiff(
        rows: [_row(outcome: PlayerEventGameOutcome.other)],
        fallbackRatingDiff: 7,
      ),
      7,
    );
  });
}

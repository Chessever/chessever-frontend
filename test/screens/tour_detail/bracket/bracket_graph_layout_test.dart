import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_graph_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('layout is finite, ordered, and non-overlapping', () {
    final firstMatches = [
      _match('a', 'first', 'A', 'B', board: 1),
      _match('b', 'first', 'C', 'D', board: 2),
      _match('c', 'first', 'E', 'F', board: 3),
      _match('d', 'first', 'G', 'H', board: 4),
    ];
    final secondMatches = [
      _match('e', 'second', 'A', 'C', board: 1),
      _match('f', 'second', 'E', 'G', board: 2),
    ];
    final bracket = KnockoutBracket(
      stages: [
        _stage('first', 0, firstMatches),
        _stage('second', 1, secondMatches),
      ],
      edges: const [
        KnockoutEdge(
          sourceMatchKey: 'a',
          destinationMatchKey: 'e',
          participantId: 'A',
        ),
        KnockoutEdge(
          sourceMatchKey: 'b',
          destinationMatchKey: 'e',
          participantId: 'C',
        ),
        KnockoutEdge(
          sourceMatchKey: 'c',
          destinationMatchKey: 'f',
          participantId: 'E',
        ),
        KnockoutEdge(
          sourceMatchKey: 'd',
          destinationMatchKey: 'f',
          participantId: 'G',
        ),
      ],
      selectedStageKey: 'first',
      currentStageKey: 'second',
      isPartial: false,
    );

    final layout = buildBracketGraphLayout(bracket);

    expect(layout.size.width.isFinite, isTrue);
    expect(layout.size.height.isFinite, isTrue);
    expect(layout.size.width, greaterThan(BracketGraphMetrics.matchWidth * 2));
    expect(layout.matchRects, hasLength(6));

    final firstX = layout.matchRects['a']!.left;
    final secondX = layout.matchRects['e']!.left;
    expect(secondX, greaterThan(firstX));

    for (final stage in bracket.stages) {
      final rects =
          stage.matches.map((match) => layout.matchRects[match.key]!).toList();
      for (var index = 1; index < rects.length; index += 1) {
        expect(rects[index].top, greaterThan(rects[index - 1].bottom));
      }
    }

    final expectedFirstDestinationCenter =
        (layout.matchRects['a']!.center.dy +
            layout.matchRects['b']!.center.dy) /
        2;
    expect(
      layout.matchRects['e']!.center.dy,
      closeTo(expectedFirstDestinationCenter, 0.001),
    );
  });

  test('large first round keeps a truthful overview-scale canvas', () {
    final matches = [
      for (var index = 0; index < 78; index += 1)
        _match(
          'm$index',
          'round-1',
          'P${index * 2}',
          'P${index * 2 + 1}',
          board: index + 1,
        ),
    ];
    final bracket = KnockoutBracket(
      stages: [_stage('round-1', 0, matches)],
      edges: const [],
      selectedStageKey: 'round-1',
      currentStageKey: 'round-1',
      isPartial: true,
    );

    final layout = buildBracketGraphLayout(bracket);
    const portraitCanvasHeight = 560.0;
    final fitScale = portraitCanvasHeight / layout.size.height;

    expect(layout.size.height, greaterThan(8000));
    expect(fitScale, greaterThan(0.04));
    expect(fitScale, lessThan(0.08));
  });
}

KnockoutStage _stage(String key, int order, List<KnockoutMatch> matches) =>
    KnockoutStage(
      key: key,
      label: key,
      sourceTourIds: ['tour'],
      sourceRoundIds: ['$key-round'],
      order: order,
      state: KnockoutStageState.inProgress,
      isLive: false,
      matches: matches,
    );

KnockoutMatch _match(
  String key,
  String stage,
  String first,
  String second, {
  required int board,
}) => KnockoutMatch(
  key: key,
  stageKey: stage,
  participant1: BracketParticipant(id: first, name: first),
  participant2: BracketParticipant(id: second, name: second),
  games: const [],
  participant1Score: 0,
  participant2Score: 0,
  leader: null,
  winner: null,
  minimumBoardOrder: board,
  isComplete: false,
  isLive: false,
);

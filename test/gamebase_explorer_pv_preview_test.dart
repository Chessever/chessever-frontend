import 'package:chessever2/screens/chessboard/utils/engine_pv_palette.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_eval_provider.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _initialFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _line = ExplorerPvLine(
  evaluation: 0.3,
  sanMoves: ['e4', 'e5', 'Nf3'],
  uciMoves: ['e2e4', 'e7e5', 'g1f3'],
);

class _SeededExplorerEvalNotifier extends ExplorerEvalNotifier {
  _SeededExplorerEvalNotifier(super.ref) {
    state = const ExplorerEvalState(
      evaluation: 0.3,
      depth: 18,
      isEvaluating: true,
      fen: _initialFen,
      pvLines: [_line],
    );
  }
}

Position _replay(List<String> uciMoves) {
  var position = Position.setupPosition(
    Rule.chess,
    Setup.parseFen(_initialFen),
  );
  for (final uci in uciMoves) {
    position = position.play(NormalMove.fromUci(uci));
  }
  return position;
}

void main() {
  group('ExplorerPvPreview', () {
    test('starts at the tapped move and precomputes the locked line', () {
      final preview = ExplorerPvPreview.tryCreate(
        baseFen: _initialFen,
        line: _line,
        variantIndex: 1,
        targetMoveIndex: 1,
      );

      expect(preview, isNotNull);
      expect(preview!.variantIndex, 1);
      expect(preview.moveIndex, 1);
      expect(preview.currentFen, _replay(['e2e4', 'e7e5']).fen);
      expect(preview.currentMove.uci, 'e7e5');
      expect(preview.positions, hasLength(preview.moves.length + 1));
      expect(preview.positions.first.fen, _initialFen);
      expect(preview.canMoveBackward, isTrue);
      expect(preview.canMoveForward, isTrue);
    });

    test('forward and backward stay inside the locked PV boundaries', () {
      final first =
          ExplorerPvPreview.tryCreate(
            baseFen: _initialFen,
            line: _line,
            variantIndex: 0,
            targetMoveIndex: 0,
          )!;

      expect(first.canMoveBackward, isFalse);
      expect(first.navigateTo(-20), same(first));

      final last = first.navigateTo(99);
      expect(last.moveIndex, 2);
      expect(last.currentFen, _replay(['e2e4', 'e7e5', 'g1f3']).fen);
      expect(last.canMoveForward, isFalse);
      expect(last.navigateTo(99), same(last));

      final middle = last.navigateTo(1);
      expect(middle.moveIndex, 1);
      expect(middle.currentFen, _replay(['e2e4', 'e7e5']).fen);
    });

    test('rejects an illegal first move and truncates an illegal tail', () {
      final rejected = ExplorerPvPreview.tryCreate(
        baseFen: _initialFen,
        line: const ExplorerPvLine(sanMoves: ['e5'], uciMoves: ['e2e5']),
        variantIndex: 0,
        targetMoveIndex: 0,
      );
      expect(rejected, isNull);

      final truncated =
          ExplorerPvPreview.tryCreate(
            baseFen: _initialFen,
            line: const ExplorerPvLine(
              sanMoves: ['e4', 'e5', 'Ke3'],
              uciMoves: ['e2e4', 'e7e5', 'e1e3'],
            ),
            variantIndex: 0,
            targetMoveIndex: 20,
          )!;
      expect(truncated.moves, hasLength(2));
      expect(truncated.line.sanMoves, ['e4', 'e5']);
      expect(truncated.moveIndex, 1);
      expect(truncated.currentFen, _replay(['e2e4', 'e7e5']).fen);
    });

    test('notifier freezes, traverses, and restores the base engine state', () {
      final container = ProviderContainer(
        overrides: [
          explorerEvalProvider.overrideWith(
            (ref) => _SeededExplorerEvalNotifier(ref),
          ),
        ],
      );
      final subscription = container.listen<ExplorerEvalState>(
        explorerEvalProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });

      final notifier = container.read(explorerEvalProvider.notifier);
      final started = notifier.previewPrincipalVariationMoveAt(
        _line,
        0,
        1,
        baseFen: _initialFen,
      );

      expect(started, isTrue);
      expect(container.read(explorerEvalProvider).fen, _initialFen);
      expect(container.read(explorerEvalProvider).pvLines, [_line]);
      expect(container.read(explorerEvalProvider).isEvaluating, isFalse);
      expect(
        container.read(explorerEvalProvider).pvPreview?.currentFen,
        _replay(['e2e4', 'e7e5']).fen,
      );

      notifier.navigateLockedPvForward();
      expect(
        container.read(explorerEvalProvider).pvPreview?.currentFen,
        _replay(['e2e4', 'e7e5', 'g1f3']).fen,
      );
      notifier.navigateLockedPvForward();
      expect(container.read(explorerEvalProvider).pvPreview?.moveIndex, 2);

      notifier.navigateLockedPvBackward();
      expect(container.read(explorerEvalProvider).pvPreview?.moveIndex, 1);

      notifier.clearPvPreview(resumeEvaluation: false);
      final restored = container.read(explorerEvalProvider);
      expect(restored.pvPreview, isNull);
      expect(restored.fen, _initialFen);
      expect(restored.pvLines, [_line]);
      expect(restored.evaluation, 0.3);
      expect(restored.depth, 18);
    });

    test('notifier rejects a line generated for a different position', () {
      final container = ProviderContainer(
        overrides: [
          explorerEvalProvider.overrideWith(
            (ref) => _SeededExplorerEvalNotifier(ref),
          ),
        ],
      );
      final subscription = container.listen<ExplorerEvalState>(
        explorerEvalProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });

      final staleFen = _replay(['e2e4']).fen;
      final started = container
          .read(explorerEvalProvider.notifier)
          .previewPrincipalVariationMoveAt(_line, 0, 0, baseFen: staleFen);

      expect(started, isFalse);
      expect(container.read(explorerEvalProvider).pvPreview, isNull);
      expect(container.read(explorerEvalProvider).isEvaluating, isTrue);
    });
  });

  test('engine PV ranks share five distinct colors and cycle predictably', () {
    final colors = <int>[
      for (var index = 0; index < 5; index++)
        enginePvVariantColor(index, isSelected: true).toARGB32(),
    ];

    expect(colors.toSet(), hasLength(5));
    expect(
      enginePvVariantColor(5, isSelected: true),
      enginePvVariantColor(0, isSelected: true),
    );
    expect(
      enginePvVariantColor(0, isSelected: false).a,
      lessThan(enginePvVariantColor(0, isSelected: true).a),
    );
  });
}

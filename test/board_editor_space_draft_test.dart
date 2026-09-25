import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/board_editor/board_editor_space_draft.dart';
import 'package:chessever2/screens/board_editor/board_editor_state.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/my_space/defaults/space_defaults.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart' show ChessboardEditor;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The board editor's "Add to My Space": it saves the position keyed by its
/// FEN, the same shortcut the seeded defaults, the + picker and search save
/// for a line, named and lined by the catalogue when the position is in it;
/// and an editor opened on a position shows it from the first frame.
void main() {
  final index = buildEcoPositionIndex();

  String fenAfter(List<String> sans) {
    Position position = Chess.initial;
    for (final san in sans) {
      position = position.play(position.parseSan(san)!);
    }
    return position.fen;
  }

  /// What the editor's FEN reads once it is opened on [fen].
  String editorFen(String fen) => BoardEditorNotifier(fen).state.fullFen;

  group('boardEditorSpaceDraft', () {
    test('a catalogue position saves as that position, named by the line', () {
      final fen = fenAfter(['e4', 'e5']);
      final record = index[ecoPositionKey(fen)]!;
      final draft = boardEditorSpaceDraft(fen, index)!;
      expect(draft.kind, SpaceShortcutKind.position);
      expect(draft.targetId, fen);
      expect(draft.title, record.name);
      expect(draft.subtitle, 'C20 · Move 1');
      expect(draft.params['eco'], 'C20');
      expect(draft.params['moves'], ['e2e4', 'e7e5']);
    });

    test('every seeded opening reads as the same shortcut in the editor', () {
      for (final o in [...kSpaceDefaultOpenings, ...kSpacePopularOpenings]) {
        final seeded = spaceEliteOpeningDraft(o)!;
        final fen = editorFen(seeded.targetId);
        expect(
          boardEditorSpaceDraft(fen, index)!.key,
          seeded.key,
          reason: o.tileName,
        );
        expect(
          boardEditorSpaceDraft(fen, null)!.key,
          seeded.key,
          reason: o.tileName,
        );
      }
    });

    test('two positions under one ECO code stay two shortcuts', () {
      final a = boardEditorSpaceDraft(fenAfter(['e4', 'e5']), index)!;
      final b = boardEditorSpaceDraft(fenAfter(['e4', 'e5', 'Qh5']), index)!;
      expect(b.params['eco'], a.params['eco']);
      expect(a.key, isNot(b.key));
    });

    test('a transposed move order still finds the line', () {
      // 1.Nf3 d5 2.d4 and 1.d4 d5 2.Nf3 reach the same position.
      final a = boardEditorSpaceDraft(fenAfter(['Nf3', 'd5', 'd4']), index)!;
      final b = boardEditorSpaceDraft(fenAfter(['d4', 'd5', 'Nf3']), index)!;
      expect(a.title, b.title);
      expect(a.title, isNot('Custom position'));
      expect(a.params['moves'], b.params['moves']);
      expect(a.params['moves'], hasLength(3));
    });

    test('move counters do not change what the position is', () {
      final fen = fenAfter(['e4', 'e5']).split(' ');
      fen[4] = '7';
      fen[5] = '31';
      final draft = boardEditorSpaceDraft(fen.join(' '), index)!;
      expect(draft.params['eco'], 'C20');
      expect(draft.params['moves'], ['e2e4', 'e7e5']);
    });

    test('an en passant square nobody can use does not split a position', () {
      final fen = fenAfter(['e4']);
      final withEp = fen.replaceFirst(' - ', ' e3 ');
      expect(withEp, isNot(fen));
      expect(
        boardEditorSpaceDraft(withEp, index)!.key,
        boardEditorSpaceDraft(fen, index)!.key,
      );
    });

    test('a custom position saves as a position, keyed by its FEN', () {
      const fen = '8/8/4k3/8/3K4/8/5Q2/8 w - - 0 1';
      final draft = boardEditorSpaceDraft(fen, index)!;
      expect(draft.kind, SpaceShortcutKind.position);
      expect(draft.targetId, fen);
      expect(draft.title, 'Custom position');
    });

    test('while the catalogue is still loading the key is already final', () {
      final fen = fenAfter(['e4', 'e5']);
      final loading = boardEditorSpaceDraft(fen, null)!;
      expect(loading.kind, SpaceShortcutKind.position);
      expect(loading.key, boardEditorSpaceDraft(fen, index)!.key);
    });
  });

  group('boardEditorAt', () {
    testWidgets('shows the position on the first frame', (tester) async {
      final fen = fenAfter(['e4', 'e5', 'Nf3']);
      final space = _MemorySpace();
      await _pumpEditor(tester, boardEditorAt(fen), space);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BoardEditorScreen)),
      );
      expect(
        container.read(boardEditorProvider).fullFen.split(' ').take(4),
        fen.split(' ').take(4),
      );
      await _tearDown(tester);
    });

    testWidgets('Add to My Space saves the position', (tester) async {
      final fen = fenAfter(['e4', 'e5']);
      final space = _MemorySpace();
      await _pumpEditor(tester, boardEditorAt(fen), space);
      expect(find.bySemanticsLabel('Add position to My Space'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('board_editor_space_button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(space.saved.single.kind, SpaceShortcutKind.position);
      expect(space.saved.single.targetId, fen);
      expect(space.saved.single.params['eco'], 'C20');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Remove from My Space'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('a seeded opening opened from the + picker reads as saved', (
      tester,
    ) async {
      final berlin = spaceEliteOpeningDraft(
        kSpacePopularOpenings.firstWhere((o) => o.eco == 'C65'),
      )!;
      final space = _MemorySpace([berlin]);
      await _pumpEditor(tester, boardEditorAt(berlin.targetId), space);
      expect(find.bySemanticsLabel('Remove from My Space'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('an illegal setup explains itself instead of saving', (
      tester,
    ) async {
      final space = _MemorySpace();
      // No black king.
      await _pumpEditor(
        tester,
        boardEditorAt('8/8/8/8/3K4/8/5Q2/8 w - - 0 1'),
        space,
      );
      await tester.tap(find.byKey(const ValueKey('board_editor_space_button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(space.saved, isEmpty);
      expect(
        find.text('Position must include both kings before analysis.'),
        findsOneWidget,
      );
      await _tearDown(tester);
    });
  });

  // The app bar gained a 44pt My Space button beside Analyze; the title must
  // still read whole on the narrowest phone at a large text size.
  group('the app bar keeps its words whole', () {
    for (final (width, height, scale) in [
      (360.0, 640.0, 1.3),
      (360.0, 640.0, 1.0),
      (393.0, 852.0, 1.3),
    ]) {
      testWidgets('${width.toInt()}pt at ${scale}x', (tester) async {
        await _pumpEditor(
          tester,
          boardEditorAt(Chess.initial.fen),
          _MemorySpace(),
          size: Size(width, height),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        for (final label in ['Board Editor', 'Analyze']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '"$label" is cut',
          );
          final natural = TextPainter(
            text: TextSpan(text: label, style: paragraph.text.style),
            textDirection: TextDirection.ltr,
            textScaler: paragraph.textScaler,
            maxLines: 1,
          )..layout();
          expect(
            paragraph.size.width,
            greaterThanOrEqualTo(natural.width - 0.5),
            reason: '"$label" is ellipsized',
          );
          natural.dispose();
        }
        expect(
          tester.getSize(
            find.byKey(const ValueKey('board_editor_space_button')),
          ),
          const Size(44, 44),
        );
        await _tearDown(tester);
      });
    }

    // A short phone shrinks the board to keep the paste actions on screen;
    // a phone with room keeps the full-width board it always had.
    testWidgets('a tall phone keeps the full-width board', (tester) async {
      await _pumpEditor(
        tester,
        boardEditorAt(Chess.initial.fen),
        _MemorySpace(),
      );
      final board = tester.getRect(find.byType(ChessboardEditor));
      expect(board.right, moreOrLessEquals(393, epsilon: 0.5));
      expect(board.width, moreOrLessEquals(board.height, epsilon: 0.5));
      await _tearDown(tester);
    });
  });
}

Future<void> _pumpEditor(
  WidgetTester tester,
  Widget editor,
  _MemorySpace space, {
  Size size = const Size(393, 852),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        boardSettingsProviderNew.overrideWith(_BoardSettings.new),
        spaceShortcutsProvider.overrideWith(() => space),
        ecoPositionIndexProvider.overrideWith(
          (ref) async => buildEcoPositionIndex(),
        ),
        gameCardEvalWithStockfishFallbackProvider.overrideWith(
          (ref, fen) async => CloudEval(
            fen: fen,
            knodes: 1,
            depth: 20,
            pvs: [Pv(moves: 'e2e4', cp: 20)],
          ),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: editor,
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

/// My Space in memory: never touches SQLite or Supabase.
class _MemorySpace extends SpaceShortcutsNotifier {
  _MemorySpace([this._initial = const []]);

  final List<SpaceShortcut> _initial;

  List<SpaceShortcut> get saved => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => _initial;

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (saved.any((s) => s.key == draft.key)) return false;
    state = AsyncData([draft, ...saved]);
    return true;
  }

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final key = SpaceShortcut.keyFor(kind, targetId);
    SpaceShortcut? hit;
    for (final s in saved) {
      if (s.key == key) hit = s;
    }
    state = AsyncData([
      for (final s in saved)
        if (s.key != key) s,
    ]);
    return hit;
  }
}

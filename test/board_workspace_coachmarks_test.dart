import 'package:chessever2/screens/gamebase/utils/board_workspace_coachmarks.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements BoardWorkspaceCoachmarkStore {
  bool seen = false;

  @override
  Future<bool> hasSeen() async => seen;

  @override
  Future<void> markSeen() async => seen = true;
}

void main() {
  test('coachmarks teach views then editor exactly once', () async {
    final viewsStore = _MemoryStore();
    final editorStore = _MemoryStore();
    final shown = <String>[];

    await showBoardWorkspaceCoachmarks(
      viewsTracker: BoardWorkspaceCoachmarkTracker(viewsStore),
      editorTracker: BoardWorkspaceCoachmarkTracker(editorStore),
      isEligible: () => true,
      showViews: () {
        shown.add('views');
        return true;
      },
      showEditor: () {
        shown.add('editor');
        return true;
      },
      pauseBetween: Duration.zero,
    );

    expect(shown, ['views', 'editor']);
    expect(viewsStore.seen, isTrue);
    expect(editorStore.seen, isTrue);

    shown.clear();
    await showBoardWorkspaceCoachmarks(
      viewsTracker: BoardWorkspaceCoachmarkTracker(viewsStore),
      editorTracker: BoardWorkspaceCoachmarkTracker(editorStore),
      isEligible: () => true,
      showViews: () {
        shown.add('views');
        return true;
      },
      showEditor: () {
        shown.add('editor');
        return true;
      },
      pauseBetween: Duration.zero,
    );

    expect(shown, isEmpty);
  });

  test('an unavailable first target does not consume its coachmark', () async {
    final viewsStore = _MemoryStore();
    final editorStore = _MemoryStore();

    await showBoardWorkspaceCoachmarks(
      viewsTracker: BoardWorkspaceCoachmarkTracker(viewsStore),
      editorTracker: BoardWorkspaceCoachmarkTracker(editorStore),
      isEligible: () => true,
      showViews: () => false,
      showEditor: () => true,
      pauseBetween: Duration.zero,
    );

    expect(viewsStore.seen, isFalse);
    expect(editorStore.seen, isTrue);
  });
}

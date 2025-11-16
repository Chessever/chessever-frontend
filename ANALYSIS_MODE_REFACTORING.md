# Analysis Mode Refactoring - Implementation Guide

## Critical Bugs (Priority 1 - Must Fix First)

### Bug 1: State Management Crash (parentDataDirty)
**Issue**: When tapping moves in PV cards or main notation, app crashes with rendering assertion errors.
**Root Cause**: State updates happening during widget build/layout phase.
**Fix**: Wrap all state-changing tap handlers with `WidgetsBinding.instance.addPostFrameCallback()`

**Files to Fix**:
- `lib/screens/chessboard/chess_board_screen_new.dart`
  - All `GestureRecognizer.onTap` callbacks in moves display
  - All PV card move tap handlers
  - Parenthesis tap handlers

### Bug 2: Navigation Broken in Nested Variants
**Issue**: Can't navigate back with arrow buttons once inside subvariants.
**Root Cause**: Navigator pointer logic not handling deep nesting correctly.
**Status**: Navigation logic in ChessGameNavigator appears correct, issue likely in UI state sync.

### Bug 3: Preview Mode PageView Interference
**Issue**: During preview mode, PageView gets activated when using navigation arrows.
**Fix**: Block horizontal gestures when preview mode is active.

### Bug 4: Long-Press Navigation Not Working in Preview Mode
**Issue**: Fast forward/backward (long press) doesn't work in preview mode.
**Fix**: Add long-press handlers for preview navigation.

---

## Phase 1: Core Fixes (Start Here)

### Step 1.1: Fix State Management Crashes
```dart
// Pattern to fix in chess_board_screen_new.dart:

// BAD (causes crashes):
onTap: () {
  ref.read(provider).someMethod();
}

// GOOD:
onTap: () {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      ref.read(provider).someMethod();
    }
  });
}
```

### Step 1.2: Add Gesture Blocking for Preview Mode
```dart
// Wrap moves display area with:
AbsorbPointer(
  absorbing: state.isPvPreviewActive, // Block taps when in preview
  child: // ... moves display
)

// Wrap PageView with custom gesture detector to block horizontal drags
GestureDetector(
  onHorizontalDragUpdate: state.isPvPreviewActive
    ? (_) {} // Absorb gesture
    : null, // Allow normal PageView
  child: PageView(...)
)
```

---

## Phase 2: Navigation System Improvements

### Step 2.1: Fix Deep Nested Navigation
- Test navigation at 3+ nesting levels
- Ensure forward/backward correctly enter/exit parentheses
- Verify pointer arithmetic

### Step 2.2: Add Long-Press for Preview Mode
```dart
// In _BottomNavBar:
onLongPressForwardStart: effectiveCanMoveForward
  ? () => notifier.startLongPressForwardPreview()
  : null,
onLongPressBackwardStart: effectiveCanMoveBackward
  ? () => notifier.startLongPressBackwardPreview()
  : null,
```

### Step 2.3: Fix Navigation State Synchronization
- Ensure bottom navbar reflects correct state in all modes
- Fix canMoveForward/Backward for preview mode
- Handle transitions between modes smoothly

---

## Phase 3: Preview Mode Redesign

### Step 3.1: UI Changes
```dart
// Hide when in preview mode:
- if (!state.isPvPreviewActive) PrincipalVariationList(...)
- if (!state.isPvPreviewActive) DotIndicator(...)

// Show instead:
if (state.isPvPreviewActive)
  PreviewModeOverlay(
    onPromote: () => notifier.promotePreviewToMainVariant(),
    onExit: () => notifier.clearPvPreview(),
  )
```

### Step 3.2: Enable PGN Editing in Preview Mode
- Allow board moves during preview
- Create subvariants within preview card
- Maintain full hierarchy support

### Step 3.3: Fix Eval Bar in Preview Mode
- Ensure `_evaluatePosition()` uses preview position when active
- Update eval bar with preview FEN

---

## Phase 4: PV Card Redesign

### Step 4.1: New Layout
```dart
// Compact evaluation badge (top-right corner):
Positioned(
  top: 8,
  right: 8,
  child: EvalBadge(eval: line.eval, mate: line.mate),
)

// Tappable right area for quick insertion:
GestureDetector(
  onTap: () => insertPvMove(line.moves.first),
  child: Container(
    width: 60,
    alignment: Alignment.centerRight,
    child: Icon(Icons.add),
  ),
)
```

### Step 4.2: New Tap Behaviors
```dart
// Single tap on notation text:
onTap: (moveIndex) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    notifier.enterPreviewModeAt(line, variantIndex, moveIndex);
  });
}

// Tap outside notation (anywhere on card background):
onTap: () {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    notifier.insertCurrentPvMove();
  });
}
```

### Step 4.3: Replace Long-Tap Loading with Action Buttons
```dart
// Show hero card with buttons:
HeroineActionSheet(
  actions: [
    ActionButton(
      label: 'Promote to main variant',
      onTap: () => notifier.promoteToMainVariant(),
    ),
    ActionButton(
      label: 'Insert into variant',
      onTap: () => notifier.insertIntoVariant(),
    ),
    ActionButton(
      label: 'Preview',
      onTap: () => notifier.enterPreviewMode(),
    ),
  ],
)
```

---

## Phase 5: Subvariant Long-Tap Experience

### Step 5.1: Add Heroine to Parentheses
```dart
// Wrap each parenthesis with Heroine widget:
Heroine(
  tag: 'subvariant_${variationNode.id}',
  child: GestureDetector(
    onLongPress: () => showVariationActions(variationNode),
    child: Text('('),
  ),
)
```

### Step 5.2: Variation Action Sheet
```dart
Future<void> showVariationActions(NotationVariationNode node) async {
  await showHeroineBottomSheet(
    context: context,
    builder: (context) => VariationActionSheet(
      onCopyPgn: () => copyVariationPgn(node),
      onPromote: () => promoteVariation(node),
      onDelete: () => deleteVariation(node),
    ),
  );
}
```

### Step 5.3: Implement Promote to Main Variant
```dart
Future<void> promoteVariationToMainVariant(NotationVariationNode node) async {
  // 1. Exit preview mode if active
  if (state.isPvPreviewActive) {
    clearPvPreview();
  }

  // 2. Extract parent moves + variation moves
  final parentMoves = _getMovesBeforeVariation(node.parentPointer);
  final variationMoves = _getVariationMoves(node);

  // 3. Create new game with merged mainline
  final newGame = ChessGame(
    gameId: game.gameId,
    startingFen: game.startingFen,
    mainline: [...parentMoves, ...variationMoves],
  );

  // 4. Update state
  _analysisGame = newGame;
  _analysisNavigator = ChessGameNavigator(newGame);
  _syncAnalysisFromNavigator(_analysisNavigator!.state);
}
```

---

## Phase 6: Animation Rewrite

### Step 6.1: Install Dependencies
```yaml
dependencies:
  heroine: ^latest
  sprung: ^latest
```

### Step 6.2: Define Animation Patterns
```dart
// Use Sprung curves:
final bouncyCurve = Sprung(damping: 20);
final smoothCurve = Sprung.overDamped;

// Use Heroine for transitions:
Heroine(
  tag: 'move_$index',
  motion: Motion.spring(Spring.withDurationAndBounce(
    duration: Duration(milliseconds: 400),
    bounce: 0.3,
  )),
  child: moveWidget,
)
```

### Step 6.3: Rewrite Preview Transition
```dart
// Replace linear progress indicator with spring-based transition
// Orchestrate: move tap → hero flight → card appearance → buttons slide in
```

---

## Phase 7: Floating Action Buttons

### Step 7.1: Add Undo Button
```dart
class UndoStack {
  final List<ChessGame> _history = [];
  final List<ChessMovePointer> _pointers = [];

  void push(ChessGame game, ChessMovePointer pointer) {
    _history.add(game);
    _pointers.add(pointer);
    if (_history.length > 50) {
      _history.removeAt(0);
      _pointers.removeAt(0);
    }
  }

  (ChessGame?, ChessMovePointer?) pop() {
    if (_history.isEmpty) return (null, null);
    final game = _history.removeLast();
    final pointer = _pointers.removeLast();
    return (game, pointer);
  }
}
```

### Step 7.2: Implement Undo Logic
```dart
Future<void> undo() async {
  final (game, pointer) = _undoStack.pop();
  if (game == null || pointer == null) return;

  _analysisGame = game;
  _analysisNavigator = ChessGameNavigator(game);
  _analysisNavigator!.goToMovePointerUnchecked(pointer);
  await _syncAnalysisFromNavigator(_analysisNavigator!.state);
}
```

### Step 7.3: Relocate FABs
```dart
// Position FABs beside main notation area (bottom)
Positioned(
  right: 16,
  bottom: 16, // Above main notation area
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FloatingActionButton(
        heroTag: 'undo',
        onPressed: undo,
        child: Icon(Icons.undo),
      ),
      SizedBox(height: 8),
      FloatingActionButton(
        heroTag: 'delete',
        onPressed: deleteFromHere,
        child: Icon(Icons.delete),
      ),
      SizedBox(height: 8),
      FloatingActionButton(
        heroTag: 'reset',
        onPressed: resetAnalysis,
        child: Icon(Icons.refresh),
      ),
    ],
  ),
)
```

---

## Phase 8: Additional Features

### Step 8.1: Null Move Support
```dart
// Add button to insert null move:
IconButton(
  icon: Icon(Icons.fast_forward),
  onPressed: () => _analysisNavigator?.insertNullMoveAtPointer(),
)

// Null move is already implemented in ChessGameNavigator (line 845)
```

### Step 8.2: Auto-Play Feature
```dart
Timer? _autoPlayTimer;

void startAutoPlay() {
  _autoPlayTimer = Timer.periodic(Duration(seconds: 1), (_) {
    if (state.value?.analysisState.canMoveForward ?? false) {
      moveForward();
    } else {
      stopAutoPlay();
    }
  });
}

void stopAutoPlay() {
  _autoPlayTimer?.cancel();
  _autoPlayTimer = null;
}
```

---

## Implementation Order

1. ✅ Fix state management crashes (CRITICAL)
2. ✅ Fix navigation bugs (CRITICAL)
3. ✅ Fix preview mode PageView interference
4. Preview mode UI redesign
5. PV card redesign
6. Subvariant long-tap
7. Animation rewrite
8. FABs (undo, delete, reset)
9. Additional features (null move, auto-play)
10. Testing and polish

---

## Testing Checklist

- [ ] Can create nested subvariants 5+ levels deep
- [ ] Navigation works at all depths (forward/back/fast-forward/fast-back)
- [ ] Preview mode: single tap enters, displays correctly
- [ ] Preview mode: can make moves, create subvariants
- [ ] Preview mode: eval bar updates
- [ ] Preview mode: promote to main variant works
- [ ] PV card: single tap enters preview
- [ ] PV card: tap outside adds move
- [ ] PV card: long-tap shows actions
- [ ] Subvariant: long-tap shows actions
- [ ] Subvariant: promote merges correctly
- [ ] Subvariant: delete removes branch
- [ ] Undo works for all actions
- [ ] Delete focuses on latest move
- [ ] Null move can be inserted
- [ ] Auto-play works
- [ ] No crashes when tapping moves rapidly
- [ ] PageView doesn't interfere in preview mode
- [ ] All animations feel smooth
- [ ] PGN export is correct

---

## Known Risks

1. **Performance**: Deep nesting may cause slow notation rendering
   - Solution: Implement virtualized rendering for long games

2. **State Synchronization**: Multiple sources of truth (navigator, state, preview)
   - Solution: Make navigator the single source of truth

3. **Animation Complexity**: Orchestrating multiple animations
   - Solution: Use Heroine's built-in sequencing

---

## Notes

- Always use `WidgetsBinding.instance.addPostFrameCallback()` for state updates from tap handlers
- Test with real games that have 10+ variations at 3+ nesting levels
- Ensure PGN export/import maintains full variation structure
- Consider adding keyboard shortcuts for power users

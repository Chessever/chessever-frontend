import 'package:chessever2/screens/gamebase/providers/explorer_game_focus_provider.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test(
    'Build Tree scope can read focused-game state beside overridden explorer',
    () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final scoped = ProviderContainer(
        parent: root,
        overrides: [
          gamebaseExplorerProvider.overrideWith(
            (ref) => GamebaseExplorerNotifier(ref),
          ),
        ],
      );
      addTearDown(scoped.dispose);

      expect(() => scoped.read(explorerFocusedGameProvider), returnsNormally);
      expect(scoped.read(explorerFocusedGameProvider), isNull);
    },
  );
}

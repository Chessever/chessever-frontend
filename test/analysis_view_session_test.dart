import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/screens/chessboard/provider/analysis_view_session.dart';

void main() {
  test(
    'raw mode hides reports until explicit request; clear wins again',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = analysisViewSessionProvider('game-a');
      final subscription = container.listen(provider, (_, __) {});
      addTearDown(subscription.close);
      final controller = container.read(provider.notifier);
      expect(container.read(provider).showReport(rawPgn: true), isFalse);
      final request = controller.requestReport();
      expect(container.read(provider).showReport(rawPgn: true), isTrue);
      expect(
        container.read(provider).showSourceAnnotations(rawPgn: true),
        isFalse,
      );
      controller.clear(hiddenVariationIds: const {'1-0'});
      expect(container.read(provider).showReport(rawPgn: false), isFalse);
      expect(container.read(provider).sourceHidden, isTrue);
      expect(container.read(provider).hiddenVariationIds, {'1-0'});
      expect(controller.isCurrentRequest(request), isFalse);
      expect(
        container.read(provider).showSourceAnnotations(rawPgn: false),
        isFalse,
      );
      controller.requestReport();
      expect(container.read(provider).showReport(rawPgn: true), isTrue);
      // Generate after Clear reveals the report but never restores the branches
      // or source glyphs that Clear hid.
      expect(container.read(provider).sourceHidden, isTrue);
      expect(container.read(provider).hiddenVariationIds, {'1-0'});
    },
  );

  test(
    'leaving disposes override; reopen follows settings, other game isolated',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = analysisViewSessionProvider('game-a');
      final subscription = container.listen(provider, (_, __) {});
      container.read(provider.notifier).clear();
      expect(
        container
            .read(analysisViewSessionProvider('game-b'))
            .showReport(rawPgn: false),
        isTrue,
      );
      subscription.close();
      await container.pump();
      expect(container.read(provider).showReport(rawPgn: false), isTrue);
      expect(container.read(provider).showReport(rawPgn: true), isFalse);
      expect(container.read(provider).sourceHidden, isFalse);
      expect(container.read(provider).hiddenVariationIds, isEmpty);
    },
  );
}

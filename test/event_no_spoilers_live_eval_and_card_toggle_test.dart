import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('No Spoilers evaluation visibility', () {
    test('hides evaluation for an enabled live broadcast event', () {
      expect(
        shouldHideEventEvaluation(
          isBroadcastGame: true,
          spoilerState: const EventNoSpoilersState(
            enabled: true,
            isLoading: false,
          ),
        ),
        isTrue,
      );
    });

    test('keeps evaluation for an archive game and a disabled event', () {
      const enabled = EventNoSpoilersState(enabled: true, isLoading: false);
      const disabled = EventNoSpoilersState(enabled: false, isLoading: false);

      expect(
        shouldHideEventEvaluation(
          isBroadcastGame: false,
          spoilerState: enabled,
        ),
        isFalse,
      );
      expect(
        shouldHideEventEvaluation(
          isBroadcastGame: true,
          spoilerState: disabled,
        ),
        isFalse,
      );
    });

    test('fails closed while the saved event preference loads', () {
      expect(
        shouldHideEventEvaluation(
          isBroadcastGame: true,
          spoilerState: const EventNoSpoilersState(),
        ),
        isTrue,
      );
    });
  });

  group('event-card No Spoilers action', () {
    test('turns off only when every child tour is already enabled', () {
      const enabled = EventNoSpoilersState(enabled: true, isLoading: false);
      const disabled = EventNoSpoilersState(enabled: false, isLoading: false);

      expect(eventNoSpoilersNextEnabled([enabled, enabled]), isFalse);
      expect(eventNoSpoilersNextEnabled([enabled, disabled]), isTrue);
      expect(eventNoSpoilersNextEnabled([disabled, disabled]), isTrue);
    });

    test('uses explicit turn-on and turn-off labels', () {
      expect(eventNoSpoilersMenuLabel(false), 'Turn on No Spoilers');
      expect(eventNoSpoilersMenuLabel(true), 'Turn off No Spoilers');
    });
  });
}

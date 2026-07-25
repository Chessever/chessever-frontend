import 'package:chessever2/providers/guest_session_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// The guest window policy: silent for a week, weekly nag after that, account
/// required at four weeks. Pure date math, so it is tested directly.
void main() {
  final now = DateTime(2026, 7, 25, 12);

  GuestSessionState guestFor({required int daysAgo, int? promptedDaysAgo}) {
    return GuestSessionState(
      startedAt: now.subtract(Duration(days: daysAgo)),
      lastPromptAt:
          promptedDaysAgo == null
              ? null
              : now.subtract(Duration(days: promptedDaysAgo)),
    );
  }

  group('GuestSessionState.gateAt', () {
    test('no guest clock is never gated', () {
      expect(const GuestSessionState.unknown().gateAt(now), GuestGate.none);
    });

    test('stays silent for the first week', () {
      for (final day in [0, 1, 3, 6]) {
        expect(
          guestFor(daysAgo: day).gateAt(now),
          GuestGate.none,
          reason: 'day $day should not prompt',
        );
      }
    });

    test('prompts on day 7 when never prompted before', () {
      expect(guestFor(daysAgo: 7).gateAt(now), GuestGate.softPrompt);
    });

    test('does not re-prompt within the weekly interval', () {
      expect(
        guestFor(daysAgo: 10, promptedDaysAgo: 3).gateAt(now),
        GuestGate.none,
      );
    });

    test('re-prompts once a week has passed since the last prompt', () {
      expect(
        guestFor(daysAgo: 14, promptedDaysAgo: 7).gateAt(now),
        GuestGate.softPrompt,
      );
      expect(
        guestFor(daysAgo: 21, promptedDaysAgo: 7).gateAt(now),
        GuestGate.softPrompt,
      );
    });

    test('forces sign up at four weeks regardless of recent prompts', () {
      expect(guestFor(daysAgo: 28).gateAt(now), GuestGate.forcedSignUp);
      expect(
        guestFor(daysAgo: 28, promptedDaysAgo: 0).gateAt(now),
        GuestGate.forcedSignUp,
      );
      expect(guestFor(daysAgo: 90).gateAt(now), GuestGate.forcedSignUp);
    });

    test('a start stamp in the future is treated as brand new', () {
      // Device clock moved backwards — never lock the user out over it.
      final skewed = GuestSessionState(startedAt: now.add(Duration(days: 5)));
      expect(skewed.gateAt(now), GuestGate.none);
    });

    test('a prompt stamp in the future still allows the next prompt', () {
      final skewed = GuestSessionState(
        startedAt: now.subtract(const Duration(days: 9)),
        lastPromptAt: now.add(const Duration(days: 2)),
      );
      expect(skewed.gateAt(now), GuestGate.softPrompt);
    });

    test('thresholds match the ticket: 7 days, then 28 days', () {
      expect(kGuestSoftPromptAfter, const Duration(days: 7));
      expect(kGuestSoftPromptInterval, const Duration(days: 7));
      expect(kGuestForcedSignUpAfter, const Duration(days: 28));
    });
  });
}

import 'package:chessever2/repository/local_storage/guest_session/guest_session_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How long a guest can use the app before we ask them to create an account.
const kGuestSoftPromptAfter = Duration(days: 7);

/// Minimum gap between two soft prompts, so a guest who taps "Not now" on
/// day 7 is asked again on day 14 and day 21 — not on every single open.
const kGuestSoftPromptInterval = Duration(days: 7);

/// After four weeks a guest must create an account to keep using the app.
const kGuestForcedSignUpAfter = Duration(days: 28);

/// What the app should do about the current guest session, if anything.
enum GuestGate {
  /// Leave the guest alone.
  none,

  /// Ask them to sign up, with a "Not now" escape hatch.
  softPrompt,

  /// Guest window is over — route them to the auth screen.
  forcedSignUp,
}

@immutable
class GuestSessionState {
  const GuestSessionState({this.startedAt, this.lastPromptAt});

  const GuestSessionState.unknown() : startedAt = null, lastPromptAt = null;

  final DateTime? startedAt;
  final DateTime? lastPromptAt;

  bool get hasGuestClock => startedAt != null;

  /// Age of the guest session, or null when the clock was never started.
  Duration? ageAt(DateTime now) {
    final startedAt = this.startedAt;
    if (startedAt == null) return null;
    return now.difference(startedAt);
  }

  /// Resolves the gate for [now]. Pure so it can be unit tested without
  /// SharedPreferences or a Supabase session.
  GuestGate gateAt(DateTime now) {
    final age = ageAt(now);
    // A negative age means the stored stamp is in the future (device clock was
    // moved back). Treat it as a brand-new guest rather than locking them out.
    if (age == null || age.isNegative) return GuestGate.none;

    if (age >= kGuestForcedSignUpAfter) return GuestGate.forcedSignUp;
    if (age < kGuestSoftPromptAfter) return GuestGate.none;

    final lastPromptAt = this.lastPromptAt;
    if (lastPromptAt == null) return GuestGate.softPrompt;

    final sincePrompt = now.difference(lastPromptAt);
    if (sincePrompt.isNegative) return GuestGate.softPrompt;

    return sincePrompt >= kGuestSoftPromptInterval
        ? GuestGate.softPrompt
        : GuestGate.none;
  }

  GuestSessionState copyWith({DateTime? startedAt, DateTime? lastPromptAt}) {
    return GuestSessionState(
      startedAt: startedAt ?? this.startedAt,
      lastPromptAt: lastPromptAt ?? this.lastPromptAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GuestSessionState &&
      other.startedAt == startedAt &&
      other.lastPromptAt == lastPromptAt;

  @override
  int get hashCode => Object.hash(startedAt, lastPromptAt);
}

final guestSessionProvider =
    AsyncNotifierProvider<GuestSessionNotifier, GuestSessionState>(
      GuestSessionNotifier.new,
    );

class GuestSessionNotifier extends AsyncNotifier<GuestSessionState> {
  GuestSessionRepository get _repository =>
      ref.read(guestSessionRepositoryProvider);

  @override
  Future<GuestSessionState> build() async {
    final stamps = await _repository.read();
    return GuestSessionState(
      startedAt: stamps.startedAt,
      lastPromptAt: stamps.lastPromptAt,
    );
  }

  /// Re-reads the stored clock (e.g. on app resume so a guest who crossed a
  /// threshold while backgrounded is evaluated against fresh values).
  Future<void> refresh() async {
    final stamps = await _repository.read();
    final next = GuestSessionState(
      startedAt: stamps.startedAt,
      lastPromptAt: stamps.lastPromptAt,
    );
    if (state.valueOrNull != next) {
      state = AsyncValue.data(next);
    }
  }

  /// Starts the guest clock if it isn't running yet. Idempotent — replays of
  /// onboarding or a legacy anonymous install never extend the window.
  Future<void> startGuestSession({DateTime? now}) async {
    final startedAt = await _repository.startIfMissing(now ?? DateTime.now());
    if (startedAt == null) return;
    final current = state.valueOrNull ?? const GuestSessionState.unknown();
    if (current.startedAt == startedAt) return;
    state = AsyncValue.data(current.copyWith(startedAt: startedAt));
  }

  Future<void> markPromptShown({DateTime? now}) async {
    final shownAt = now ?? DateTime.now();
    await _repository.markPromptShown(shownAt);
    final current = state.valueOrNull ?? const GuestSessionState.unknown();
    state = AsyncValue.data(current.copyWith(lastPromptAt: shownAt));
  }

  /// Called once the guest upgrades to a real account — the clock is gone and
  /// they are treated as any other signed-in user.
  Future<void> clearGuestSession() async {
    final current = state.valueOrNull;
    if (current != null && !current.hasGuestClock) return;
    await _repository.clear();
    state = const AsyncValue.data(GuestSessionState.unknown());
  }
}

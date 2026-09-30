import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/feed/race/puzzle_rating_range.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_copy.dart';
import 'package:chessever2/screens/feed/race/race_flames.dart';
import 'package:chessever2/screens/feed/race/race_results.dart';
import 'package:chessever2/screens/feed/race/race_screen.dart';
import 'package:chessever2/screens/feed/race/race_stats_store.dart';
import 'package:chessever2/screens/feed/race/race_widgets.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:share_plus/share_plus.dart';

/// Puzzle Race, pushed full-screen from the Feed (or My Profile), in the
/// app's own theme.
///
/// One route for the whole race: choosing a mode (Survival or Infinite, Solo
/// or Multiplayer) and a difficulty, a multiplayer room's lobby, the race
/// ([RaceScreen]) and the results ([RaceResults]). Leaving the route leaves
/// the room.
///
/// Every view names its way out in the top-left corner, and the system back
/// (Android's gesture, the iOS swipe where it is allowed) does exactly what
/// that control does: the setup and the results leave, a room is left for
/// the setup, a run asks before it ends.
class RaceLobbyScreen extends ConsumerStatefulWidget {
  const RaceLobbyScreen({super.key, this.from = 'Feed'});

  static const String routeName = '/feed/race';

  /// Where the race was opened from, named on the way back ("Feed").
  final String from;

  static Future<void> open(BuildContext context, {String from = 'Feed'}) {
    unawaited(HapticFeedbackService.navigation());
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: routeName),
        builder: (_) => RaceLobbyScreen(from: from),
      ),
    );
  }

  @override
  ConsumerState<RaceLobbyScreen> createState() => _RaceLobbyScreenState();
}

class _RaceLobbyScreenState extends ConsumerState<RaceLobbyScreen> {
  RaceController get _race => ref.read(raceControllerProvider.notifier);

  /// Running while a run that ended on a verdict keeps its board up for
  /// that verdict ([RaceState.endedOnVerdict]); the results follow.
  Timer? _resultsHold;

  /// The results as spoken, where the platform only speaks live regions
  /// (Android). Empty until results show.
  String _resultsAnnouncement = '';

  @override
  void dispose() {
    _resultsHold?.cancel();
    super.dispose();
  }

  void _onPhase(RacePhase? previous, RacePhase next) {
    if (previous == RacePhase.finished && next != RacePhase.finished) {
      // A race was just counted: its flames and bests read in fresh.
      ref.invalidate(raceServerStatsProvider);
      ref.invalidate(raceBestsProvider);
    }
    if (next != RacePhase.finished) {
      _resultsHold?.cancel();
      _resultsHold = null;
      _resultsAnnouncement = '';
      return;
    }
    if (previous == RacePhase.finished) return;
    final state = ref.read(raceControllerProvider);
    // Reduced motion skips the pause and goes straight to the results.
    if (!state.endedOnVerdict || MediaQuery.disableAnimationsOf(context)) {
      _announceResultsAfterFrame();
      return;
    }
    _resultsHold?.cancel();
    _resultsHold = Timer(RaceScreen.verdictHold, () {
      _resultsHold = null;
      if (!mounted) return;
      setState(() {});
      _announceResultsAfterFrame();
    });
  }

  /// The results replace the run in place, so a screen reader is told
  /// what they say once they are on screen (WCAG 4.1.3).
  void _announceResultsAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(raceControllerProvider);
      if (state.phase != RacePhase.finished || _resultsHold != null) return;
      final earned = state.flamesEarned ?? 0;
      final flames = earned == 1 ? '1 flame' : '$earned flames';
      final message =
          '${state.score} solved. ${raceFinishLine(state.finishReason)}.'
          '${earned > 0 ? ' $flames earned.' : ''}';
      if (MediaQuery.maybeSupportsAnnounceOf(context) ?? false) {
        unawaited(
          SemanticsService.sendAnnouncement(
            View.of(context),
            message,
            Directionality.of(context),
          ).catchError((Object _) {}),
        );
      } else {
        setState(() => _resultsAnnouncement = message);
      }
    });
  }

  void _close() {
    unawaited(HapticFeedbackService.navigation());
    Navigator.of(context).maybePop();
  }

  Future<void> _signIn({
    String title = 'Sign in to race friends',
    String message =
        'Multiplayer races need an account. Solo races work without one.',
    String done = 'Signed in. Create a room or join one.',
  }) async {
    final signedIn = await showAuthUpgradeSheet(
      context: context,
      title: title,
      message: message,
      dismissLabel: 'Not now',
    );
    if (!mounted) return;
    setState(() {});
    if (signedIn) {
      ref.invalidate(raceServerStatsProvider);
      ref.invalidate(raceBestsProvider);
      showAppSnack(context, done);
    }
  }

  Future<void> _signInForFlames() => _signIn(
    title: 'Keep your flames',
    message: 'Flames you earn signed in are saved to your account.',
    done: 'Signed in. Your flames are kept from now on.',
  );

  void _onNotice(RaceNotice? previous, RaceNotice? next) {
    if (next == null || next.seq == previous?.seq) return;
    final needsAccount = next.code == 'authentication_required';
    showAppSnack(
      context,
      raceErrorMessage(next.code),
      actionLabel: needsAccount ? 'Sign in' : null,
      onAction: needsAccount ? _signIn : null,
    );
  }

  /// A run under way: leaving asks first.
  bool _guarded(RaceState state) =>
      state.phase == RacePhase.running ||
      (state.phase == RacePhase.countdown && state.multiplayer);

  /// The setup, a failure and the results leave the route on back; anything
  /// in between steps back inside it (see [_onBack]).
  bool _canPop(RaceState state, bool configured) =>
      !configured ||
      state.phase == RacePhase.setup ||
      state.phase == RacePhase.failed ||
      state.phase == RacePhase.finished;

  /// Back where the route stays: a run asks before it ends; a room, a
  /// countdown or a race still opening goes back to the setup.
  Future<void> _onBack() async {
    final state = ref.read(raceControllerProvider);
    if (_guarded(state)) {
      final end = await confirmRaceStop(
        context,
        others: state.multiplayer && state.opponents.isNotEmpty,
      );
      if (!mounted || !end) return;
      _race.stop();
      return;
    }
    unawaited(HapticFeedbackService.navigation());
    _race.stop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RacePhase>(
      raceControllerProvider.select((s) => s.phase),
      _onPhase,
    );
    ref.listen<RaceNotice?>(
      raceControllerProvider.select((s) => s.notice),
      _onNotice,
    );
    final state = ref.watch(raceControllerProvider);
    final configured = _race.isConfigured;
    final colors = context.colors;
    final light = context.isLightTheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
        statusBarBrightness: light ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: colors.background,
        systemNavigationBarIconBrightness: light
            ? Brightness.dark
            : Brightness.light,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.4,
        child: PopScope(
          canPop: _canPop(state, configured),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_onBack());
          },
          child: Scaffold(
            backgroundColor: colors.background,
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              bottom: false,
              child: KeyedSubtree(
                key: const ValueKey('race_root'),
                child: _body(state, configured),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(RaceState state, bool configured) {
    final from = widget.from;
    if (!configured) return _ComingSoon(from: from, onBack: _close);
    switch (state.phase) {
      case RacePhase.finished:
        // The same RaceScreen stays mounted through the hold, so the
        // verdict's own motion plays out; it takes no moves once finished.
        if (_resultsHold != null) return const RaceScreen();
        // Where announcements are not spoken, the results carry what they
        // say as a live region: inert until then, and never a focus stop.
        final live = _resultsAnnouncement.isNotEmpty;
        return Semantics(
          container: live,
          explicitChildNodes: live,
          liveRegion: live,
          label: live ? _resultsAnnouncement : null,
          accessibilityFocusBlockType: live
              ? AccessibilityFocusBlockType.blockNode
              : AccessibilityFocusBlockType.none,
          child: RaceResults(
            onBack: _close,
            backLabel: from,
            onSignIn: _race.signedIn ? null : _signInForFlames,
          ),
        );
      case RacePhase.running || RacePhase.countdown:
        return const RaceScreen();
      case RacePhase.creating || RacePhase.connecting || RacePhase.lobby:
        if (!state.multiplayer) return const RaceScreen();
        if (state.phase == RacePhase.lobby || state.code != null) {
          return _RoomView(state: state, onShareFailed: _shareFailed);
        }
        return _SetupView(
          state: state,
          from: from,
          onBack: _close,
          onSignIn: _signIn,
          onSignInForFlames: _signInForFlames,
        );
      case RacePhase.setup || RacePhase.failed:
        return _SetupView(
          state: state,
          from: from,
          onBack: _close,
          onSignIn: _signIn,
          onSignInForFlames: _signInForFlames,
        );
    }
  }

  void _shareFailed() {
    showAppSnack(context, "Couldn't open sharing.", tone: AppSnackTone.danger);
  }
}

// ---------------------------------------------------------------- pieces

/// The lobby's way out: back to wherever the race was opened from.
class _BackTo extends StatelessWidget {
  const _BackTo({required this.from, required this.onBack});

  final String from;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return RaceBackControl(
      key: const ValueKey('race_back'),
      glyph: RaceGlyphs.back,
      label: from,
      semanticsLabel: 'Back to $from',
      onTap: onBack,
    );
  }
}

/// No race service in this build: a calm promise, one way back, and the
/// race's own frame around a clock that has not started.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.from, required this.onBack});

  final String from;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        RaceHeader(back: _BackTo(from: from, onBack: onBack)),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 232,
                    height: 112,
                    child: CustomPaint(
                      painter: RaceFramePainter(
                        reach: 0.34,
                        color: colors.textTertiary,
                      ),
                      child: Center(
                        child: Text(
                          formatRaceClock(0),
                          style: AppTypography.displayMdBold.copyWith(
                            fontSize: 40,
                            height: 48 / 40,
                            color: raceQuietInk(colors),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Puzzle Race is almost here',
                    key: const ValueKey('race_coming_soon'),
                    textAlign: TextAlign.center,
                    style: AppTypography.textXlBold.copyWith(
                      fontSize: 22,
                      height: 28 / 22,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Race the clock through puzzles that climb in rating, '
                    'alone or against friends.',
                    textAlign: TextAlign.center,
                    style: AppTypography.textMdRegular.copyWith(
                      fontSize: 15,
                      height: 22 / 15,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, math.max(16, bottom)),
          child: RaceButton(
            label: 'Back to $from',
            tone: RaceButtonTone.primary,
            onTap: onBack,
          ),
        ),
      ],
    );
  }
}

/// Choosing a race: mode by format, two by two, then the difficulty, with
/// the one action that fits the choice pinned under it all.
class _SetupView extends ConsumerStatefulWidget {
  const _SetupView({
    required this.state,
    required this.from,
    required this.onBack,
    required this.onSignIn,
    required this.onSignInForFlames,
  });

  final RaceState state;
  final String from;
  final VoidCallback onBack;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignInForFlames;

  @override
  ConsumerState<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends ConsumerState<_SetupView> {
  final TextEditingController _code = TextEditingController();

  /// Custom was tapped while a preset still matched, or its handle saved a
  /// preset's range: the slider shows until another preset is picked.
  bool _customOpen = false;

  void _keepCustom() {
    if (!_customOpen) setState(() => _customOpen = true);
  }

  RaceController get _race => ref.read(raceControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    // The setup is rebuilt fresh after a failed join. A code no room has is
    // most likely a typo, so it comes back in the field to be corrected.
    final failed = widget.state;
    if (failed.phase == RacePhase.failed &&
        failed.errorCode == 'room_not_found' &&
        failed.code != null) {
      _code.text = failed.code!;
    }
    _code.addListener(_onCode);
  }

  @override
  void dispose() {
    _code
      ..removeListener(_onCode)
      ..dispose();
    super.dispose();
  }

  void _onCode() => setState(() {});

  void _join() {
    FocusScope.of(context).unfocus();
    unawaited(HapticFeedbackService.buttonPress());
    unawaited(_race.joinRoom(_code.text));
  }

  void _choose(PuzzleRatingPreset? preset) {
    // Choosing again after a failure starts over from the setup.
    if (widget.state.phase == RacePhase.failed) _race.backToSetup();
    setState(() => _customOpen = preset == null);
    if (preset != null) {
      unawaited(ref.read(puzzleRatingRangeProvider.notifier).choose(preset));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = widget.state;
    final bests = ref.watch(raceBestsProvider).valueOrNull ?? RaceBests.empty;
    final range = ref.watch(puzzleRatingRangeProvider);
    final busy =
        state.phase == RacePhase.creating ||
        state.phase == RacePhase.connecting;
    final failed = state.phase == RacePhase.failed;
    final signedIn = _race.signedIn;
    final server = signedIn
        ? ref.watch(raceServerStatsProvider).valueOrNull
        : null;
    final flames = raceFlameTotal(server: server, local: bests.flames);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final custom = range.preset == null || _customOpen;

    String bestLine(RaceMode mode) {
      final best = math.max(
        bests.bestFor(mode),
        switch (mode) {
          RaceMode.survival => server?.survivalBest ?? 0,
          RaceMode.infinite => server?.infiniteBest ?? 0,
        },
      );
      return best > 0 ? 'Best $best' : 'No best yet';
    }

    final Widget primary;
    if (failed && !_roomOutOfReach(state.errorCode)) {
      // A room that is gone, full or already racing will refuse the same
      // code again, so "Try again" stays for failures that may pass.
      primary = RaceButton(
        key: const ValueKey('race_retry'),
        label: 'Try again',
        tone: RaceButtonTone.primary,
        onTap: () {
          unawaited(HapticFeedbackService.buttonPress());
          unawaited(_race.retry());
        },
      );
    } else if (!state.multiplayer) {
      primary = RaceButton(
        key: const ValueKey('race_start_solo'),
        label: busy ? 'Starting' : 'Start race',
        tone: RaceButtonTone.primary,
        onTap: busy
            ? null
            : () {
                unawaited(HapticFeedbackService.buttonPress());
                unawaited(_race.startSolo());
              },
      );
    } else if (!signedIn) {
      primary = RaceButton(
        key: const ValueKey('race_sign_in'),
        label: 'Sign in',
        tone: RaceButtonTone.primary,
        onTap: () => unawaited(widget.onSignIn()),
      );
    } else {
      primary = RaceButton(
        key: const ValueKey('race_create_room'),
        label: busy ? 'Opening the room' : 'Create a room',
        tone: RaceButtonTone.primary,
        onTap: busy
            ? null
            : () {
                unawaited(HapticFeedbackService.buttonPress());
                unawaited(_race.createRoom());
              },
      );
    }

    final validCode = normalizeRaceCode(_code.text) != null;
    final quiet = AppTypography.textSmRegular.copyWith(
      fontSize: 14,
      height: 20 / 14,
      color: colors.textSecondary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RaceHeader(
          back: _BackTo(from: widget.from, onBack: widget.onBack),
          title: const RaceTitle('Puzzle Race'),
        ),
        Expanded(
          child: _ScrollEdgeFade(
            child: SingleChildScrollView(
              key: const ValueKey('race_setup'),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (flames > 0) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: RaceFlameMark(
                        key: const ValueKey('race_lobby_flames'),
                        flames: flames,
                        size: 20,
                      ),
                    ),
                    if (!signedIn)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: RaceTextLink(
                          key: const ValueKey('race_keep_flames'),
                          label: 'Sign in to keep your flames',
                          onTap: () => unawaited(widget.onSignInForFlames()),
                        ),
                      )
                    else
                      const SizedBox(height: 10),
                  ],
                  Text(
                    'Puzzles climb from where you start. Solves earn flames, '
                    'harder ones more.',
                    style: AppTypography.textMdRegular.copyWith(
                      fontSize: 15,
                      height: 22 / 15,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ChoiceRow(
                    children: [
                      _ChoiceTile(
                        key: const ValueKey('race_mode_survival'),
                        title: 'Survival',
                        body: 'Three mistakes and the run ends',
                        footnote: bestLine(RaceMode.survival),
                        selected: state.mode == RaceMode.survival,
                        onTap: busy
                            ? null
                            : () => _race.selectMode(RaceMode.survival),
                      ),
                      _ChoiceTile(
                        key: const ValueKey('race_mode_infinite'),
                        title: 'Infinite',
                        body: 'No lives. Race until you stop',
                        footnote: bestLine(RaceMode.infinite),
                        selected: state.mode == RaceMode.infinite,
                        onTap: busy
                            ? null
                            : () => _race.selectMode(RaceMode.infinite),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _ChoiceRow(
                    children: [
                      _ChoiceTile(
                        key: const ValueKey('race_solo'),
                        title: 'Solo',
                        body: 'Just you and the clock',
                        selected: !state.multiplayer,
                        onTap: busy
                            ? null
                            : () => _race.selectMultiplayer(false),
                      ),
                      _ChoiceTile(
                        key: const ValueKey('race_multiplayer'),
                        title: 'Multiplayer',
                        body: 'The same puzzles, up to 8 players',
                        selected: state.multiplayer,
                        onTap: busy
                            ? null
                            : () => _race.selectMultiplayer(true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _Difficulty(
                    range: range,
                    custom: custom,
                    enabled: !busy,
                    multiplayer: state.multiplayer,
                    onChoose: _choose,
                    onCustomSaved: _keepCustom,
                  ),
                  if (state.multiplayer && !signedIn) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Racing friends needs a ChessEver account. Solo races '
                      'work without one.',
                      key: const ValueKey('race_sign_in_hint'),
                      style: quiet.copyWith(fontSize: 15, height: 21 / 15),
                    ),
                  ],
                  if (state.multiplayer && signedIn) ...[
                    const SizedBox(height: 28),
                    Text(
                      'Have a code?',
                      style: AppTypography.textMdBold.copyWith(
                        fontSize: 16,
                        height: 22 / 16,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CodeField(
                            controller: _code,
                            onSubmitted: validCode && !busy ? _join : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 96,
                          child: RaceButton(
                            key: const ValueKey('race_join'),
                            label: 'Join',
                            onTap: validCode && !busy ? _join : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // The action stays in reach however long the choices run. While a
        // code is typed the keyboard sits here instead; Join is by the field.
        if (!keyboard || failed)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, math.max(16, bottom)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (failed) ...[
                  _Failure(code: state.errorCode),
                  const SizedBox(height: 12),
                ],
                primary,
              ],
            ),
          ),
      ],
    );
  }
}

/// Where the ladder starts: five presets and a start of your own, two by
/// two so every label stays whole on a narrow phone at large text.
class _Difficulty extends StatelessWidget {
  const _Difficulty({
    required this.range,
    required this.custom,
    required this.enabled,
    required this.multiplayer,
    required this.onChoose,
    required this.onCustomSaved,
  });

  final PuzzleRatingRange range;
  final bool custom;
  final bool enabled;
  final bool multiplayer;

  /// Null chooses Custom.
  final void Function(PuzzleRatingPreset? preset) onChoose;

  /// The custom handle saved a start.
  final VoidCallback onCustomSaved;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget preset(PuzzleRatingPreset p) => _ChoiceTile(
      key: ValueKey('race_difficulty_${p.name}'),
      title: p.label,
      body: 'Starts at ${p.range.min}',
      tabularBody: true,
      selected: !custom && range.preset == p,
      onTap: enabled ? () => onChoose(p) : null,
    );
    final customTile = _ChoiceTile(
      key: const ValueKey('race_difficulty_custom'),
      title: 'Custom',
      body: custom ? 'Starts at ${range.min}' : 'Your own start',
      tabularBody: custom,
      selected: custom,
      onTap: enabled ? () => onChoose(null) : null,
    );
    const presets = PuzzleRatingPreset.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Difficulty',
            style: AppTypography.textMdBold.copyWith(
              fontSize: 16,
              height: 22 / 16,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _ChoiceRow(children: [preset(presets[0]), preset(presets[1])]),
        const SizedBox(height: 10),
        _ChoiceRow(children: [preset(presets[2]), preset(presets[3])]),
        const SizedBox(height: 10),
        _ChoiceRow(children: [preset(presets[4]), customTile]),
        if (custom) ...[
          const SizedBox(height: 14),
          _CustomStart(enabled: enabled, onSaved: onCustomSaved),
        ],
        if (multiplayer) ...[
          const SizedBox(height: 10),
          Text(
            'Rooms you create start at this rating.',
            style: AppTypography.textSmRegular.copyWith(
              fontSize: 14,
              height: 20 / 14,
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// A start of your own: one handle on the catalogue's 400 up to 3000, in 50
/// point steps. A race climbs from it with no ceiling, so the track is inked
/// from the handle up. The saved band keeps its top (the Feed's casual
/// puzzles draw from it) unless the start climbs past it, when the top is
/// pushed along to stay 200 above, as the old low handle did. A drag saves
/// when the handle lets go; a step with no drag (a screen reader's adjust)
/// saves at once.
class _CustomStart extends ConsumerStatefulWidget {
  const _CustomStart({required this.enabled, required this.onSaved});

  final bool enabled;

  /// A start was saved from here: Custom stays chosen even when it lands on
  /// a preset's range, so the handle never vanishes mid-adjustment.
  final VoidCallback onSaved;

  @override
  ConsumerState<_CustomStart> createState() => _CustomStartState();
}

class _CustomStartState extends ConsumerState<_CustomStart> {
  double? _drag;

  /// A pointer holds the handle: changes wait for the release to save.
  bool _dragging = false;

  static const double _floor = kPuzzleRatingFloor * 1.0;

  /// The highest start that still leaves the band its smallest span.
  static const double _top =
      (kPuzzleRatingCeiling - kPuzzleRatingMinSpan) * 1.0;

  @override
  void didUpdateWidget(covariant _CustomStart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Disabled mid-drag, the slider never reports the release.
    if (!widget.enabled) {
      _dragging = false;
      _drag = null;
    }
  }

  double _current(PuzzleRatingRange range) =>
      _drag ?? range.min.toDouble().clamp(_floor, _top);

  static int _snap(double value) =>
      (value / kPuzzleRatingStep).round() * kPuzzleRatingStep;

  void _onChangeStart(double _) => _dragging = true;

  void _onChanged(double previous, double next) {
    if (_snap(next) != _snap(previous)) {
      unawaited(HapticFeedbackService.selection());
    }
    if (_dragging) {
      setState(() => _drag = next);
    } else {
      // No release follows a step a screen reader takes.
      _save(next);
    }
  }

  void _onChangeEnd(double _) {
    _dragging = false;
    final value = _drag;
    if (value == null) return;
    _save(value);
  }

  void _save(double value) {
    widget.onSaved();
    final start = _snap(value);
    final top = ref.read(puzzleRatingRangeProvider).max;
    unawaited(
      ref
          .read(puzzleRatingRangeProvider.notifier)
          .set(
            PuzzleRatingRange(
              start,
              math.max(top, start + kPuzzleRatingMinSpan),
            ),
          ),
    );
    setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final range = ref.watch(puzzleRatingRangeProvider);
    final value = _current(range);
    final start = _snap(value);
    final rail = raceLegible(
      colors.textTertiary.withValues(alpha: 0.4),
      on: colors.background,
      toward: colors.textPrimary,
      min: 3,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Starts at $start',
          key: const ValueKey('race_custom_range'),
          style: AppTypography.textLgBold.copyWith(
            fontSize: 20,
            height: 26 / 20,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            // The climb (from the handle up) is inked; below it, the rail.
            trackShape: const _ClimbTrackShape(),
            activeTrackColor: colors.textPrimary,
            inactiveTrackColor: rail,
            disabledActiveTrackColor: rail,
            disabledInactiveTrackColor: rail,
            thumbColor: colors.textPrimary,
            disabledThumbColor: rail,
            // A flat disc, no shadow, and no halo on press: the 22 radius
            // only widens the touch target to 44.
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 10,
              elevation: 0,
              pressedElevation: 0,
            ),
            overlayColor: Colors.transparent,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 0),
            activeTickMarkColor: Colors.transparent,
            inactiveTickMarkColor: Colors.transparent,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            key: const ValueKey('race_custom_slider'),
            value: value,
            min: _floor,
            max: _top,
            divisions: (_top - _floor) ~/ kPuzzleRatingStep,
            semanticFormatterCallback: (v) => 'Starting rating ${_snap(v)}',
            onChangeStart: widget.enabled ? _onChangeStart : null,
            onChanged: widget.enabled
                ? (next) => _onChanged(value, next)
                : null,
            onChangeEnd: widget.enabled ? _onChangeEnd : null,
          ),
        ),
      ],
    );
  }
}

/// The stock rounded track with its ink on the other side of the handle:
/// everything from the start up (the ladder's climb) is the active, slightly
/// taller segment, and what lies below the start is the rail.
class _ClimbTrackShape extends RoundedRectSliderTrackShape {
  const _ClimbTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      // The mirrored direction paints the active segment after the handle.
      textDirection: textDirection == TextDirection.ltr
          ? TextDirection.rtl
          : TextDirection.ltr,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
  }
}

/// Failures that belong to the room itself (a mistyped or expired code, a
/// full room, a race already under way or over). Joining it again would get
/// the same answer, so the setup keeps its own actions instead of a retry.
bool _roomOutOfReach(String? code) => switch (code) {
  'room_not_found' ||
  'room_closed' ||
  'race_finished' ||
  'room_full' ||
  'already_started' => true,
  _ => false,
};

/// Softens a scroll's edge where more runs on past it, so a tile half under
/// the header or the pinned action reads as "more this way", not as a cut.
/// Each fade grows with the first [_reach] of travel toward that edge, tied
/// to the scroll itself, so nothing pops; an end the scroll rests against
/// stays crisp, and content that fits is never faded.
class _ScrollEdgeFade extends StatefulWidget {
  const _ScrollEdgeFade({required this.child});

  final Widget child;

  @override
  State<_ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<_ScrollEdgeFade> {
  static const double _reach = 32;

  /// How far each edge has faded, 0 (crisp) to 1 (gone at the rim).
  double _top = 0;
  double _bottom = 0;

  bool _onMetrics(ScrollMetrics metrics, int depth) {
    // Only the wrapped scroll: a text field's own scroll inside it is not.
    if (depth != 0 || metrics.axis != Axis.vertical) return false;
    final top = (metrics.extentBefore / _reach).clamp(0.0, 1.0);
    final bottom = (metrics.extentAfter / _reach).clamp(0.0, 1.0);
    if (top == _top && bottom == _bottom) return false;
    _top = top;
    _bottom = bottom;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      // Metrics that change mid-layout are painted on the next frame.
      scheduler.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final top = _top;
    final bottom = _bottom;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics, n.depth),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.metrics, n.depth),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final span = bounds.height <= 0
                ? 0.0
                : math.min(0.5, _reach / bounds.height);
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 1 - top),
                Colors.black,
                Colors.black,
                Colors.black.withValues(alpha: 1 - bottom),
              ],
              stops: [0, span, 1 - span, 1],
            ).createShader(bounds);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Two choices side by side, always the same height so their lines agree.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatefulWidget {
  const _ChoiceTile({
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
    this.footnote,
    this.tabularBody = false,
    super.key,
  });

  final String title;
  final String body;
  final String? footnote;
  final bool selected;
  final VoidCallback? onTap;

  /// Figures in the body (a starting rating) line up digit for digit.
  final bool tabularBody;

  @override
  State<_ChoiceTile> createState() => _ChoiceTileState();
}

class _ChoiceTileState extends State<_ChoiceTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = widget.selected;
    final enabled = widget.onTap != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final fill = selected ? colors.surfaceRecessed : colors.surface;
    // On paper the tile's own fill barely leaves the page, so an unchosen
    // tile keeps a divider edge; in the dark its fill already reads.
    final edge = selected
        ? colors.textPrimary.withValues(alpha: 0.9)
        : context.isLightTheme
        ? colors.divider
        : fill;
    final secondary = raceLegible(
      colors.textSecondary,
      on: fill,
      toward: colors.textPrimary,
    );
    final face = Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _pressed ? Color.lerp(fill, colors.textPrimary, 0.06) : fill,
        borderRadius: BorderRadius.circular(4),
        // Same width either way, so choosing never shifts the layout.
        border: Border.all(color: edge, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: AppTypography.textLgBold.copyWith(
              fontSize: 17,
              height: 22 / 17,
              color: selected ? colors.textPrimary : colors.textPrimaryMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.body,
            style: AppTypography.textSmRegular.copyWith(
              fontSize: 13,
              height: 18 / 13,
              color: secondary,
              fontFeatures: widget.tabularBody
                  ? const [FontFeature.tabularFigures()]
                  : null,
            ),
          ),
          if (widget.footnote != null) ...[
            const Spacer(),
            const SizedBox(height: 10),
            Text(
              widget.footnote!,
              style: AppTypography.textSmMedium.copyWith(
                fontSize: 13,
                height: 18 / 13,
                color: raceQuietInk(colors, on: fill),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      inMutuallyExclusiveGroup: true,
      label:
          '${widget.title}. ${widget.body}'
          '${widget.footnote == null ? '' : '. ${widget.footnote}'}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTap: enabled
            ? () {
                unawaited(HapticFeedbackService.selection());
                widget.onTap!();
              }
            : null,
        child: reduceMotion
            ? face
            : SingleMotionBuilder(
                value: _pressed ? 0.97 : 1.0,
                motion: const CupertinoMotion.snappy(
                  duration: Duration(milliseconds: 220),
                ),
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: face,
              ),
      ),
    );
  }
}

/// Six Crockford characters, typed however: lower case, spaces and hyphens
/// are fine, and O, I and L read as 0, 1 and 1.
class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.textLgBold.copyWith(
      fontSize: 20,
      height: 24 / 20,
      letterSpacing: 4,
      color: colors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final fieldEdge = raceLegible(
      colors.textTertiary,
      on: colors.background,
      toward: colors.textPrimary,
      min: 3,
    );
    OutlineInputBorder edge(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: color, width: 1.5),
    );
    return TextField(
      key: const ValueKey('race_code_field'),
      controller: controller,
      style: style,
      cursorColor: colors.textPrimary,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.go,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      inputFormatters: const [_RaceCodeFormatter()],
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: colors.surfaceRecessed,
        // At the largest text on a narrow phone the hint scales down
        // rather than lose its last letters.
        hint: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            'Room code',
            maxLines: 1,
            style: style.copyWith(
              letterSpacing: 0,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: raceLegible(
                colors.textSecondary,
                on: colors.surfaceRecessed,
                toward: colors.textPrimary,
              ),
            ),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        // The field's edge clears 3:1 on the page, so it reads as a field.
        border: edge(fieldEdge),
        enabledBorder: edge(fieldEdge),
        focusedBorder: edge(colors.textPrimary.withValues(alpha: 0.9)),
      ),
    );
  }
}

/// Keeps letters and digits only, upper case, at most six.
class _RaceCodeFormatter extends TextInputFormatter {
  const _RaceCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text.toUpperCase().replaceAll(
      RegExp('[^0-9A-Z]'),
      '',
    );
    final text = cleaned.length > kRaceCodeLength
        ? cleaned.substring(0, kRaceCodeLength)
        : cleaned;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.code});

  final String? code;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Couldn't start the race",
            style: AppTypography.textLgBold.copyWith(
              fontSize: 17,
              height: 22 / 17,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            raceErrorMessage(code),
            key: const ValueKey('race_failure'),
            style: AppTypography.textMdRegular.copyWith(
              fontSize: 15,
              height: 21 / 15,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A multiplayer room before the start: its code to share, who is in, and
/// the host's Start (or everyone else's Ready).
class _RoomView extends ConsumerWidget {
  const _RoomView({required this.state, required this.onShareFailed});

  final RaceState state;
  final VoidCallback onShareFailed;

  Future<void> _share(BuildContext context, String code) async {
    unawaited(HapticFeedbackService.buttonPress());
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    try {
      await Share.share(raceInviteText(code), sharePositionOrigin: origin);
    } catch (error) {
      debugPrint('[Race] invite share failed: ${error.runtimeType}');
      onShareFailed();
    }
  }

  Future<void> _copy(BuildContext context, String code) async {
    unawaited(HapticFeedbackService.buttonPress());
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: code));
    if (messenger != null) showAppSnackOn(messenger, 'Code copied');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final race = ref.read(raceControllerProvider.notifier);
    final code = state.code ?? '';
    final joined = state.me != null;
    final open = state.link == RaceLinkStatus.open;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final players = state.players;
    final label = AppTypography.textSmMedium.copyWith(
      fontSize: 14,
      height: 19 / 14,
      color: colors.textSecondary,
    );

    final Widget footer;
    if (!joined) {
      footer = Text(
        state.link == RaceLinkStatus.reconnecting && state.you != null
            ? 'Reconnecting'
            : 'Joining the room',
        textAlign: TextAlign.center,
        style: label,
      );
    } else if (state.isHost) {
      footer = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            players.length < 2
                ? 'You can start alone, or wait for friends.'
                : 'Everyone gets the same puzzles.',
            textAlign: TextAlign.center,
            style: label,
          ),
          const SizedBox(height: 10),
          RaceButton(
            key: const ValueKey('race_host_start'),
            label: 'Start race',
            tone: RaceButtonTone.primary,
            onTap: open
                ? () {
                    unawaited(HapticFeedbackService.buttonPress());
                    race.startRace();
                  }
                : null,
          ),
        ],
      );
    } else {
      footer = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'The host starts the race.',
            textAlign: TextAlign.center,
            style: label,
          ),
          const SizedBox(height: 10),
          RaceButton(
            key: const ValueKey('race_ready'),
            label: state.ready ? "I'm ready" : 'Mark me ready',
            tone: state.ready ? RaceButtonTone.tonal : RaceButtonTone.primary,
            semanticsLabel: state.ready
                ? 'Ready. Tap to undo'
                : 'Mark me ready',
            onTap: open
                ? () {
                    unawaited(HapticFeedbackService.toggle());
                    race.setReady(!state.ready);
                  }
                : null,
          ),
        ],
      );
    }

    final details = [
      raceModeName(state.mode),
      ?raceStartLine(state.startRating),
      'up to 8 players',
    ].join(' · ');

    return Column(
      children: [
        RaceHeader(
          back: RaceBackControl(
            key: const ValueKey('race_leave_room'),
            glyph: RaceGlyphs.back,
            label: 'Leave',
            semanticsLabel: 'Leave the room',
            onTap: () {
              unawaited(HapticFeedbackService.navigation());
              race.leave();
            },
          ),
          title: const RaceTitle('Race room'),
        ),
        Expanded(
          child: _ScrollEdgeFade(
            child: ListView(
              key: const ValueKey('race_room'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                Semantics(
                  label: 'Room code ${code.split('').join(' ')}',
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      code,
                      key: const ValueKey('race_room_code'),
                      maxLines: 1,
                      style: AppTypography.displayMdBold.copyWith(
                        fontSize: 48,
                        height: 56 / 48,
                        letterSpacing: 8,
                        color: colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  details,
                  key: const ValueKey('race_room_details'),
                  style: label.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Builder(
                        builder: (buttonContext) => RaceButton(
                          key: const ValueKey('race_share_invite'),
                          label: 'Share invite',
                          onTap: code.isEmpty
                              ? null
                              : () => unawaited(_share(buttonContext, code)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RaceButton(
                        label: 'Copy code',
                        onTap: code.isEmpty
                            ? null
                            : () => unawaited(_copy(context, code)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Semantics(
                  header: true,
                  child: Text(
                    players.isEmpty ? 'Players' : 'Players ${players.length}',
                    style: AppTypography.textLgBold.copyWith(
                      fontSize: 17,
                      height: 22 / 17,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                for (final p in players)
                  _PlayerRow(
                    player: p,
                    isMe: p.id == state.you,
                    isHost: p.id == state.hostId,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, math.max(16, bottom)),
          child: footer,
        ),
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.isMe,
    required this.isHost,
  });

  final RacePlayer player;
  final bool isMe;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = !player.connected
        ? 'Away'
        : isHost
        ? 'Host'
        : player.ready
        ? 'Ready'
        : 'Not ready';
    final nameStyle = AppTypography.textMdMedium.copyWith(
      fontSize: 16,
      height: 22 / 16,
      fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
      color: player.connected ? colors.textPrimary : raceQuietInk(colors),
    );
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: RaceNameLine(
              name: player.name,
              isMe: isMe,
              style: nameStyle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            status,
            style: AppTypography.textSmMedium.copyWith(
              fontSize: 14,
              color: status == 'Ready' || status == 'Host'
                  ? colors.textSecondary
                  : raceQuietInk(colors),
            ),
          ),
        ],
      ),
    );
  }
}

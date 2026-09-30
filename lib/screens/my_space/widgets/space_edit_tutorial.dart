import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/chessboard/widgets/switch_views_tutorial_overlay.dart'
    show TutorialBorderProgressPainter, TutorialStepIndicator;
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_grid.dart'
    show SpaceEditCheck, kSpaceEditCheck;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

// Edit's tips: the first time a reader opens Edit on a My Space page (a See
// all, My Prep's Openings), one card walks them through it a step at a time,
// in the chess board's teaching look and with its memory of what was seen.

/// Device-local memory of Edit's tips, shaped as the board tips' keys are:
/// when they were shown, and whether they were skipped.
const String kSpaceEditWalkthroughShownDateKey =
    'my_space_edit_walkthrough_shown_date';
const String kSpaceEditWalkthroughDontShowKey =
    'my_space_edit_walkthrough_dont_show';

/// When the Players' tips were shown. They leave out holding to reorder
/// (the Players order themselves), so they do not retire the whole tips: a
/// page that reorders still teaches that one step, once.
const String kSpaceEditWalkthroughPlayersShownDateKey =
    'my_space_edit_walkthrough_players_shown_date';

SharedPreferences? _loadedPrefs() =>
    SharedPreferencesService.instance.prefsOrNull;

/// Every fade and glide on the tips. Under reduced motion each is set, not
/// eased (`active: false`): `Motion.none()` would hold the value it started
/// at, and leave the tips invisible.
const Motion _kTipsSpring = CupertinoMotion.snappy();

/// Whether Edit's tips are due, and the marks that retire them.
///
/// Read synchronously from the preferences loaded at startup. With none
/// loaded (a failed read, a test) the tips are never due: they never stand
/// between a reader and Edit on a guess.
class SpaceEditTutorialStore {
  const SpaceEditTutorialStore([this._prefs = _loadedPrefs]);

  final SharedPreferences? Function() _prefs;

  /// The whole tips (holding to reorder among them) were never shown on this
  /// device, and never skipped.
  bool due() {
    final prefs = _prefs();
    if (prefs == null) return false;
    return prefs.getBool(kSpaceEditWalkthroughDontShowKey) != true &&
        prefs.getInt(kSpaceEditWalkthroughShownDateKey) == null;
  }

  /// The Players' tips (select, Remove, Done) were shown.
  bool playersShown() =>
      _prefs()?.getInt(kSpaceEditWalkthroughPlayersShownDateKey) != null;

  /// Seen once is seen: marked the moment the tips show, as the board's are.
  void markShown() => _write(
    (prefs) => prefs.setInt(
      kSpaceEditWalkthroughShownDateKey,
      DateTime.now().millisecondsSinceEpoch,
    ),
  );

  /// The Players' tips showed; holding to reorder is still to teach.
  void markPlayersShown() => _write(
    (prefs) => prefs.setInt(
      kSpaceEditWalkthroughPlayersShownDateKey,
      DateTime.now().millisecondsSinceEpoch,
    ),
  );

  /// The reader skipped them.
  void markSkipped() =>
      _write((prefs) => prefs.setBool(kSpaceEditWalkthroughDontShowKey, true));

  /// The value is in memory at once; only the disk write is awaited.
  void _write(Future<bool> Function(SharedPreferences prefs) write) {
    final prefs = _prefs();
    if (prefs == null) return;
    unawaited(
      write(prefs).then<void>(
        (_) {},
        onError: (Object e) => debugPrint('[MySpace] Edit tips not saved: $e'),
      ),
    );
  }
}

final spaceEditTutorialStoreProvider = Provider<SpaceEditTutorialStore>(
  (ref) => const SpaceEditTutorialStore(),
);

/// The steps [section]'s Edit still has to teach, none once taught: every
/// step the first time; on the Players, all but holding (they order
/// themselves); on a page that reorders after the Players' tips, holding
/// alone, the one step those left out.
List<SpaceEditTutorialStep> spaceEditTutorialStepsDue(
  SpaceEditTutorialStore store,
  SpaceSection section,
) {
  if (!store.due()) return const [];
  final steps = spaceEditTutorialSteps(section);
  if (!store.playersShown()) return steps;
  if (section == SpaceSection.players) return const [];
  return [
    for (final s in steps)
      if (s.demo == SpaceEditTutorialDemo.hold) s,
  ];
}

/// Shows Edit's tips over [context]'s page once a frame has drawn Edit
/// under them, if any are due; marks them seen as they show. Call as Edit
/// opens.
void maybeShowSpaceEditTutorial(
  BuildContext context,
  WidgetRef ref,
  SpaceSection section,
) {
  final store = ref.read(spaceEditTutorialStoreProvider);
  if (spaceEditTutorialStepsDue(store, section).isEmpty) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final steps = spaceEditTutorialStepsDue(store, section);
    if (steps.isEmpty) return;
    if (section == SpaceSection.players) {
      store.markPlayersShown();
    } else {
      store.markShown();
    }
    unawaited(
      showSpaceEditTutorial(
        context,
        section: section,
        steps: steps,
        onSkip: store.markSkipped,
      ),
    );
  });
}

/// Edit's tips for [section] ([steps], or all of them), over everything,
/// until the reader is through them, skips them, or goes back.
Future<void> showSpaceEditTutorial(
  BuildContext context, {
  required SpaceSection section,
  List<SpaceEditTutorialStep>? steps,
  VoidCallback? onSkip,
}) {
  late final RawDialogRoute<void> route;
  route = RawDialogRoute<void>(
    barrierDismissible: false,
    // The tips draw their own scrim, and fade it in and out themselves.
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    settings: const RouteSettings(name: 'space_edit_tips'),
    pageBuilder: (_, _, _) => SpaceEditTutorial(
      steps: steps ?? spaceEditTutorialSteps(section),
      onSkip: onSkip,
      // Takes away the tips' own route: never a page a notification or a
      // link pushed over them while they faded.
      onClosed: () {
        final navigator = route.navigator;
        if (navigator == null || !route.isActive) return;
        if (route.isCurrent) {
          navigator.pop();
        } else {
          navigator.removeRoute(route);
        }
      },
    ),
  );
  return Navigator.of(context, rootNavigator: true).push(route);
}

/// What a step's hand shows.
enum SpaceEditTutorialDemo {
  /// Holds a card until it lifts, then drags it along.
  hold,

  /// Taps a card, and its circle fills; taps again, and it empties.
  tap,

  /// Taps Remove.
  remove,

  /// Taps Done.
  done,
}

@immutable
class SpaceEditTutorialStep {
  const SpaceEditTutorialStep({
    required this.demo,
    required this.icon,
    required this.title,
    required this.body,
    this.faces = false,
  });

  final SpaceEditTutorialDemo demo;
  final IconData icon;
  final String title;
  final String body;

  /// The group is faces (the Players): the hand taps a face, not a card.
  final bool faces;
}

/// Edit's steps for [section]: hold to reorder, tap to select, Remove (with
/// Undo), Done. The Players order themselves, so theirs start at selecting.
List<SpaceEditTutorialStep> spaceEditTutorialSteps(SpaceSection section) {
  final players = section == SpaceSection.players;
  final one = players ? 'player' : 'card';
  final its = players ? 'their' : 'its';
  return [
    if (!players)
      const SpaceEditTutorialStep(
        demo: SpaceEditTutorialDemo.hold,
        icon: Icons.open_with_rounded,
        title: 'Hold to Reorder',
        body: 'Hold a card until it lifts, then drag it where you want it.',
      ),
    SpaceEditTutorialStep(
      demo: SpaceEditTutorialDemo.tap,
      icon: Icons.check_circle_rounded,
      title: 'Tap to Select',
      body: 'Tap a $one to fill $its circle. Tap again to unselect.',
      faces: players,
    ),
    SpaceEditTutorialStep(
      demo: SpaceEditTutorialDemo.remove,
      icon: Icons.remove_circle_rounded,
      title: 'Remove the Selected',
      body: players
          ? 'Remove hides them here, still followed. Undo puts them back.'
          : 'Remove takes them out of My Space. Undo puts them back.',
    ),
    SpaceEditTutorialStep(
      demo: SpaceEditTutorialDemo.done,
      icon: Icons.done_all_rounded,
      title: 'Done to Finish',
      body: players
          ? 'Tap Done to leave Edit.'
          : 'Tap Done to leave Edit. Your new order is already saved.',
    ),
  ];
}

/// Edit's tips: the chess board's teaching card (white on the dim scrim,
/// its timer border, the step dots, the floating badge, the hand under it),
/// holding every step of Edit in turn. Next (or a tap anywhere) moves on,
/// as a tap moves the board's tips on; Back returns; Skip ends them for
/// good. Each step stands [stepTime] and then gives way, the border drawing
/// its time. Under reduced motion nothing fades, loops or runs a clock, and
/// with a screen reader the reader sets the pace.
class SpaceEditTutorial extends StatefulWidget {
  const SpaceEditTutorial({
    super.key,
    required this.steps,
    required this.onClosed,
    this.onSkip,
  });

  final List<SpaceEditTutorialStep> steps;

  /// The tips have faded out: take them away.
  final VoidCallback onClosed;

  /// Skip was tapped, before the tips fade.
  final VoidCallback? onSkip;

  /// How long a step stands, as long as each board tip stands.
  static const Duration stepTime = Duration(seconds: 8);

  /// The fade out before [onClosed], the board tips' own.
  static const Duration fadeOut = Duration(milliseconds: 500);

  @override
  State<SpaceEditTutorial> createState() => _SpaceEditTutorialState();
}

class _SpaceEditTutorialState extends State<SpaceEditTutorial>
    with TickerProviderStateMixin {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: SpaceEditTutorial.stepTime)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _next();
        });

  /// The hand's loop.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  int _index = 0;
  bool _leaving = false;
  Timer? _exit;

  /// Reduced motion: no fade, no loop, no border, no clock.
  bool _still = false;

  /// A clock moves the steps on: not under reduced motion (nothing would
  /// show it running), nor for a screen reader.
  bool _timed = false;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final timed =
        !still && !(MediaQuery.maybeAccessibleNavigationOf(context) ?? false);
    if (_ready && still == _still && timed == _timed) return;
    _ready = true;
    _still = still;
    _timed = timed;
    if (_leaving) return;
    if (_still) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
    if (_timed) {
      _clock.forward(from: 0);
    } else {
      _clock
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _exit?.cancel();
    _clock.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (_leaving) return;
    setState(() => _index = index);
    if (_timed) _clock.forward(from: 0);
  }

  void _next() {
    if (_leaving) return;
    if (_index >= widget.steps.length - 1) return _leave();
    _go(_index + 1);
  }

  void _back() {
    if (_index > 0) _go(_index - 1);
  }

  void _skip() {
    if (_leaving) return;
    widget.onSkip?.call();
    _leave();
  }

  void _leave() {
    if (_leaving) return;
    _clock.stop();
    setState(() => _leaving = true);
    // Nothing to fade under reduced motion: gone at once.
    if (_still) return widget.onClosed();
    _exit = Timer(SpaceEditTutorial.fadeOut, () {
      if (mounted) widget.onClosed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    return PopScope(
      canPop: false,
      // Back leaves the tips, as Got it does.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: SingleMotionBuilder(
        motion: _kTipsSpring,
        // Under reduced motion there, and gone, at once.
        active: !_still,
        from: _still ? null : 0,
        value: _leaving ? 0 : 1,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: 'How Edit works',
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Next and Skip carry these for a screen reader.
              excludeFromSemantics: true,
              onTap: _next,
              child: ColoredBox(
                color: kBlackColor.withValues(alpha: 0.8),
                child: SafeArea(
                  child: CustomMultiChildLayout(
                    delegate: _TipsLayout(
                      top: 80.h,
                      // The badge rides 20.h over the card: it stays on.
                      minTop: 28.h,
                      gap: 24.h,
                      bottom: 32.h,
                      demo: _SpaceEditDemo.height,
                    ),
                    children: [
                      LayoutId(id: _TipsPart.card, child: _card(context)),
                      // A picture, not controls: a tap on it is a tap on
                      // the scrim, and moves the tips on.
                      LayoutId(
                        id: _TipsPart.demo,
                        child: _WholeOrNone(
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: AnimatedBuilder(
                                animation: _loop,
                                builder: (context, _) => _SpaceEditDemo(
                                  demo: step.demo,
                                  faces: step.faces,
                                  t: _loop.value,
                                  still: _still,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      LayoutId(id: _TipsPart.controls, child: _controls()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [child] for step [i]: shown while it is the step, faded otherwise, and
  /// read out only while it is.
  Widget _fading(int i, Widget child) {
    final on = i == _index;
    return ExcludeSemantics(
      excluding: !on,
      child: SingleMotionBuilder(
        motion: _kTipsSpring,
        active: !_still,
        value: on ? 1 : 0,
        builder: (context, t, child) =>
            Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        child: child,
      ),
    );
  }

  Widget _card(BuildContext context) {
    final steps = widget.steps;
    return SizedBox(
      width: 280.w,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          AnimatedBuilder(
            animation: _clock,
            builder: (context, card) => CustomPaint(
              foregroundPainter: TutorialBorderProgressPainter(
                progress: _timed ? _clock.value : 0,
                color: kPrimaryColor,
                strokeWidth: 3.0,
                borderRadius: 28.br,
              ),
              child: card,
            ),
            child: Container(
              padding: EdgeInsets.fromLTRB(24.w, 36.h, 24.w, 24.h),
              decoration: BoxDecoration(
                // White with black text on the dim scrim in both themes,
                // as every teaching card.
                color: Colors.white,
                borderRadius: BorderRadius.circular(28.br),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // One step alone (holding, after the Players' tips) has
                  // no place to show among others; its room stays, so the
                  // title sits where it does on every other card.
                  if (steps.length > 1)
                    ExcludeSemantics(
                      child: TutorialStepIndicator(
                        currentStep: _index + 1,
                        totalSteps: steps.length,
                        duration: _still
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                      ),
                    )
                  else
                    SizedBox(height: 6.h),
                  SizedBox(height: 10.h),
                  // Every step laid out at once: the card keeps the height
                  // of its longest, so nothing moves as the steps change.
                  // At the largest text on a small phone, when nothing
                  // else is left to give way, the words scroll inside the
                  // card, which stays whole.
                  Flexible(child: _ScrollFade(child: _steps())),
                ],
              ),
            ),
          ),
          Positioned(top: -20.h, child: _badge(context)),
        ],
      ),
    );
  }

  Widget _steps() {
    final steps = widget.steps;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        for (final (i, s) in steps.indexed)
          _fading(
            i,
            Semantics(
              container: true,
              liveRegion: i == _index,
              label: steps.length > 1
                  ? 'Step ${i + 1} of ${steps.length}'
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.title,
                    style: AppTypography.textLgBold.copyWith(
                      color: kBlackColor,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    s.body,
                    style: AppTypography.textSmMedium.copyWith(
                      color: kBlackColor.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _badge(BuildContext context) {
    final light = context.isLightTheme;
    return Container(
      padding: EdgeInsets.all(10.sp),
      decoration: BoxDecoration(
        color: kPrimaryColor,
        shape: BoxShape.circle,
        boxShadow: light
            ? null
            : [
                BoxShadow(
                  color: kPrimaryColor.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: SizedBox.square(
        dimension: 22.sp,
        child: Stack(
          children: [
            for (final (i, s) in widget.steps.indexed)
              _fading(
                i,
                Icon(
                  s.icon,
                  // Paper: accent ink (white on cyan is 2.4:1).
                  color: light ? context.colors.inkOnAccent : Colors.white,
                  size: 22.sp,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    final first = _index == 0;
    final last = _index == widget.steps.length - 1;
    // One step alone has no step to go back to: Skip and Got it, spaced as
    // on the board.
    final alone = widget.steps.length == 1;
    // A tap that misses a button here (the first step's empty Back) is
    // not a tap on the scrim: it moves nothing on.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () {},
      child: Padding(
        // Never against the screen's edges: at the largest text on a
        // narrow phone the row shrinks to fit rather than run off.
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Center(
          heightFactor: 1,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  key: const ValueKey<String>('space_edit_tips_skip'),
                  onPressed: _skip,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.6),
                  ),
                  child: Text('Skip', style: AppTypography.textSmMedium),
                ),
                if (alone)
                  SizedBox(width: 24.w)
                else ...[
                  SizedBox(width: 16.w),
                  // Back keeps its place on the first step, so Next never
                  // moves under a finger tapping through; there it takes
                  // no tap at all.
                  AbsorbPointer(
                    absorbing: first,
                    child: ExcludeSemantics(
                      excluding: first,
                      child: SingleMotionBuilder(
                        motion: _kTipsSpring,
                        active: !_still,
                        value: first ? 0 : 1,
                        builder: (context, t, child) =>
                            Opacity(opacity: t.clamp(0.0, 1.0), child: child),
                        child: TextButton(
                          key: const ValueKey<String>('space_edit_tips_back'),
                          onPressed: _back,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: Text('Back', style: AppTypography.textSmBold),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                ],
                TextButton(
                  key: const ValueKey<String>('space_edit_tips_next'),
                  onPressed: _next,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    padding: EdgeInsets.symmetric(
                      horizontal: 24.w,
                      vertical: 12.h,
                    ),
                    // Next and Got it take the same room.
                    minimumSize: Size(96.w, 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30.br),
                    ),
                  ),
                  child: Text(
                    last ? 'Got it' : 'Next',
                    style: AppTypography.textSmBold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's words, scrolling only when the card cannot hold them (the
/// largest text on a small phone). Then they fade out at an edge with more
/// beyond it, rather than being sliced by it. Words that fit draw as they
/// are, with no mask.
class _ScrollFade extends StatefulWidget {
  const _ScrollFade({required this.child});

  final Widget child;

  @override
  State<_ScrollFade> createState() => _ScrollFadeState();
}

class _ScrollFadeState extends State<_ScrollFade> {
  /// Keeps the list, and where it stands, as the mask comes and goes.
  final GlobalKey _list = GlobalKey();
  bool _before = false;
  bool _after = false;

  bool _read(ScrollMetrics metrics) {
    final before = metrics.extentBefore > 0.5;
    final after = metrics.extentAfter > 0.5;
    if (before != _before || after != _after) {
      setState(() {
        _before = before;
        _after = after;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    Widget list = SingleChildScrollView(
      key: _list,
      physics: const ClampingScrollPhysics(),
      child: widget.child,
    );
    if (_before || _after) {
      final fade = 40.h;
      list = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) {
          final f = (fade / rect.height).clamp(0.0, 0.5);
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _before ? Colors.transparent : Colors.black,
              Colors.black,
              Colors.black,
              _after ? Colors.transparent : Colors.black,
            ],
            stops: [0, f, 1 - f, 1],
          ).createShader(rect);
        },
        child: list,
      );
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _read(n.metrics),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) => _read(n.metrics),
        child: list,
      ),
    );
  }
}

/// The tips' parts, as [_TipsLayout] places them.
enum _TipsPart { card, demo, controls }

/// Places the tips as the board's stand: the card [top] under the top, the
/// buttons [bottom] over the foot, the hand [gap] above the buttons. When
/// the room runs short (the largest text on a small phone) the parts give
/// way in turn: first the air over the card, down to [minTop]; then the
/// hand, which goes whole rather than cut; last the card's own words
/// scroll inside it. The buttons always stand on the screen.
class _TipsLayout extends MultiChildLayoutDelegate {
  _TipsLayout({
    required this.top,
    required this.minTop,
    required this.gap,
    required this.bottom,
    required this.demo,
  });

  final double top;
  final double minTop;
  final double gap;
  final double bottom;

  /// The hand's height, standing whole.
  final double demo;

  @override
  void performLayout(Size size) {
    final controls = layoutChild(
      _TipsPart.controls,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    );
    final controlsTop = math.max(0.0, size.height - bottom - controls.height);
    positionChild(_TipsPart.controls, Offset(0, controlsTop));

    // Over the buttons and the air above them.
    final room = math.max(0.0, controlsTop - gap);
    final card = layoutChild(
      _TipsPart.card,
      BoxConstraints(
        maxWidth: size.width,
        maxHeight: math.max(0.0, room - minTop),
      ),
    );
    final spare = room - card.height;
    final hand = spare - demo >= minTop;
    final cardTop = math.min(top, hand ? spare - demo : spare);
    positionChild(
      _TipsPart.card,
      Offset((size.width - card.width) / 2, math.max(0.0, cardTop)),
    );

    final demoHeight = hand ? demo : 0.0;
    layoutChild(
      _TipsPart.demo,
      BoxConstraints.tightFor(width: size.width, height: demoHeight),
    );
    positionChild(_TipsPart.demo, Offset(0, room - demoHeight));
  }

  @override
  bool shouldRelayout(_TipsLayout old) =>
      top != old.top ||
      minTop != old.minTop ||
      gap != old.gap ||
      bottom != old.bottom ||
      demo != old.demo;
}

/// Paints [child] only when given room to stand whole: with none (the
/// tips short of room) the hand is not drawn at all, rather than cut.
class _WholeOrNone extends SingleChildRenderObjectWidget {
  const _WholeOrNone({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWholeOrNone();
}

class _RenderWholeOrNone extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    super.paint(context, offset);
  }
}

/// The hand under the card, as on the board's tips, showing its step on
/// what Edit itself draws: a card with its circle (held and dragged, or
/// tapped till the circle fills), then Remove and Done. The hand glides
/// from one step's place to the next. Drawn in the dark theme, on the
/// scrim, whatever the app's theme.
class _SpaceEditDemo extends StatelessWidget {
  const _SpaceEditDemo({
    required this.demo,
    required this.faces,
    required this.t,
    required this.still,
  });

  final SpaceEditTutorialDemo demo;
  final bool faces;

  /// Where the loop stands, 0 to 1.
  final double t;
  final bool still;

  /// The hand's disc: the glyph and its air, as on the board's tips.
  static double get _hand => 52.sp + 2 * 24.sp;

  /// The whole picture's height: the row the hand points at, and the hand.
  static double get height => _target + _gap + _hand;

  /// The row the hand points up at.
  static double get _target => 44.sp;
  static double get _gap => 6.sp;

  /// How far a held card travels.
  static double get _drag => 44.w;

  /// Remove's and Done's widths, and the air between them.
  static double get _label => 96.w;
  static double get _labelGap => 8.w;

  /// The hand's place for [demo], from the middle.
  static double _base(SpaceEditTutorialDemo demo) => switch (demo) {
    SpaceEditTutorialDemo.hold => -_drag / 2,
    SpaceEditTutorialDemo.tap => 0,
    SpaceEditTutorialDemo.remove => -(_label + _labelGap) / 2,
    SpaceEditTutorialDemo.done => (_label + _labelGap) / 2,
  };

  /// 0 to 1 as the loop runs from [from] to [to].
  double _ramp(double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  /// A tap's press around [at]: 1 at [at], 0 a little either side.
  double _press(double at) => (1 - (t - at).abs() / 0.06).clamp(0.0, 1.0);

  static double _smooth(double x) => x * x * (3 - 2 * x);

  @override
  Widget build(BuildContext context) {
    final hold = demo == SpaceEditTutorialDemo.hold;
    final tap = demo == SpaceEditTutorialDemo.tap;
    final labels = !hold && !tap;

    // Hold: down, a beat for the lift, across, up, then gone and back to
    // the start for the next go.
    final held = still ? 1.0 : _ramp(0.10, 0.20) - _ramp(0.62, 0.70);
    final dragged = still
        ? _drag / 2
        : t < 0.80
        ? _smooth(_ramp(0.28, 0.58)) * _drag
        : 0.0;
    final shown = still
        ? 1.0
        : (1 - _ramp(0.72, 0.80) + _ramp(0.88, 1.0)).clamp(0.0, 1.0);

    // Tap: in, then out again.
    final tapped = still ? 0.0 : _press(0.25) + _press(0.70);
    final selected = still || (t >= 0.25 && t < 0.70);

    // Remove or Done: one tap.
    final pressed = still ? 0.0 : _press(0.35);

    final handScale = switch (demo) {
      SpaceEditTutorialDemo.hold => 1 - 0.14 * held,
      SpaceEditTutorialDemo.tap => 1 - 0.18 * tapped,
      _ => 1 - 0.18 * pressed,
    };
    final dx = hold ? dragged : 0.0;
    final fade = hold ? shown : 1.0;

    return Theme(
      data: AppTheme.darkTheme,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: SingleMotionBuilder(
          motion: _kTipsSpring,
          active: !still,
          value: _base(demo),
          builder: (context, x, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: _target,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    _Shown(
                      on: !labels,
                      still: still,
                      child: Transform.translate(
                        offset: Offset(x + dx, 0),
                        child: Opacity(
                          opacity: fade,
                          child: _DemoCard(
                            face: faces,
                            lift: hold ? held : 0,
                            selected: tap && selected,
                          ),
                        ),
                      ),
                    ),
                    _Shown(
                      on: labels,
                      still: still,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _action(
                            'Remove 2',
                            on: demo == SpaceEditTutorialDemo.remove,
                            pressed: pressed,
                          ),
                          SizedBox(width: _labelGap),
                          _action(
                            'Done',
                            on: demo == SpaceEditTutorialDemo.done,
                            pressed: pressed,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: _target + _gap,
                child: Center(
                  child: Transform.translate(
                    offset: Offset(x + dx, 0),
                    child: Opacity(
                      opacity: fade,
                      child: Transform.scale(
                        scale: handScale,
                        child: const _Hand(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Remove or Done as Edit draws them; the one the hand is on stands out,
  /// and dips as it is pressed.
  Widget _action(String text, {required bool on, required double pressed}) {
    return SizedBox(
      width: _label,
      child: Center(
        child: Opacity(
          opacity: on ? 1 - 0.4 * pressed : 0.35,
          // A large text size shrinks the word to its place, never past it.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: DiscoveryAction(label: text, onTap: () {}),
          ),
        ),
      ),
    );
  }
}

/// Fades [child] in while [on], out otherwise.
class _Shown extends StatelessWidget {
  const _Shown({required this.on, required this.still, required this.child});

  final bool on;
  final bool still;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: _kTipsSpring,
      active: !still,
      value: on ? 1 : 0,
      builder: (context, t, child) =>
          Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      child: child,
    );
  }
}

/// A card in Edit, as a sketch: its outline and its circle in the corner;
/// or for the Players a face, its circle on the rim, top left, as Edit
/// draws them. A held card lifts (a touch larger, a touch brighter).
class _DemoCard extends StatelessWidget {
  const _DemoCard({
    required this.face,
    required this.lift,
    required this.selected,
  });

  final bool face;
  final double lift;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fill = Colors.white.withValues(alpha: 0.08 + 0.10 * lift);
    final edge = Border.all(
      color: Colors.white.withValues(alpha: 0.45 + 0.25 * lift),
      width: 1.5,
    );
    final check = SpaceEditCheck(selected: selected);
    if (face) {
      final size = 44.sp;
      return SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: edge,
              ),
              child: const SizedBox.expand(),
            ),
            // On the rim at ten past ten, as on a face in Edit.
            Positioned(
              left: size * 0.146 - kSpaceEditCheck / 2,
              top: size * 0.146 - kSpaceEditCheck / 2,
              child: check,
            ),
          ],
        ),
      );
    }
    final inset = 6.sp;
    return Transform.scale(
      scale: 1 + 0.06 * lift,
      child: Container(
        width: 88.w,
        height: kSpaceEditCheck + 2 * inset + 8.sp,
        padding: EdgeInsets.all(inset),
        alignment: Alignment.topLeft,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10.br),
          border: edge,
        ),
        child: check,
      ),
    );
  }
}

/// The board tips' hand.
class _Hand extends StatelessWidget {
  const _Hand();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      padding: EdgeInsets.all(24.sp),
      child: Icon(
        Icons.touch_app_rounded,
        size: 52.sp,
        color: Colors.white,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }
}

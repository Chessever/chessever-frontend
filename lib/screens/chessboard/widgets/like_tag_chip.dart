import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/models/like_tag.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_offer.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_anchored_route.dart'
    show
        GlassAnchoredMotion,
        GlassFold,
        GlassFoldIgnorePointer,
        GlassFoldTransition,
        GlassScrimPainter;
import 'package:chessever2/utils/text_scale.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:chessever2/screens/chessboard/utils/legible_ink.dart';

/// The shared post-like tag picker for the board toolbar and Feed actions.
///
/// Replaces the roulette wheel: instead of a full-screen casino spinner sliding
/// in from the right, the toolbar's action icons quietly hand over to a single
/// pill — a "Tag this game" chip whose border drains as a countdown. Tapping it
/// drops a small menu of the [kLikeTags] (each with an explanatory icon);
/// checking one or more tags writes the full tag list, letting the countdown
/// elapse leaves the like untagged.
class LikeTagChip extends ConsumerStatefulWidget {
  const LikeTagChip({super.key, required this.offer, this.onDismiss});

  final TagOffer offer;

  /// Feed owns its offer locally; the board uses [tagChipOfferProvider].
  final VoidCallback? onDismiss;

  @override
  ConsumerState<LikeTagChip> createState() => _LikeTagChipState();
}

class _LikeTagChipState extends ConsumerState<LikeTagChip>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// How long the chip lingers before self-dismissing untagged. Long enough to
  /// notice and reach for, short enough not to squat on the toolbar.
  static const Duration _countdownDuration = Duration(milliseconds: 5200);

  final GlobalKey _chipKey = GlobalKey();

  late final AnimationController _countdown;

  /// The menu's open and close, on the anchored glass springs
  /// ([GlassAnchoredMotion]): 0 shut, 1 open.
  late final AnimationController _menu;

  /// The open menu's grow and fold; a new one for every open.
  GlassFold? _fold;
  OverlayEntry? _menuEntry;
  Timer? _confirmationTimer;

  bool _pressed = false;
  bool _menuOpen = false;

  // After a pick the chip flips to a confirmation face and the countdown stops;
  // the offer is closed after a short beat so the confirmation is seen.
  bool _committed = false;
  bool _draftTouched = false;
  List<String> _draftLabels = const <String>[];
  List<String> _committedLabels = const <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draftLabels = _initialLabels;
    _countdown = AnimationController(
      vsync: this,
      duration: _countdownDuration,
      // This is time to act, not decorative motion.
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_onCountdownStatus);
    _menu = AnimationController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _countdown.forward();
    });
  }

  @override
  void dispose() {
    // Synchronous teardown — no setState — so a chip swapped out mid-menu by
    // the AppBar's AnimatedSwitcher can't leak its overlay entry.
    WidgetsBinding.instance.removeObserver(this);
    _menuEntry?.remove();
    _menuEntry?.dispose();
    _menuEntry = null;
    _confirmationTimer?.cancel();
    _countdown.dispose();
    _menu.dispose();
    super.dispose();
  }

  void _onCountdownStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_committed && !_menuOpen) {
      // Elapsed without a Save tap -> leave the like untagged regardless of
      // any in-flight draft picks. Tags only persist via the explicit Save
      // button in the dropdown. Token-guarded close in case a newer offer
      // already replaced us.
      _dismiss();
    }
  }

  void _dismiss() {
    final onDismiss = widget.onDismiss;
    if (onDismiss != null) {
      onDismiss();
    } else {
      ref.read(tagChipOfferProvider).close(widget.offer.token);
    }
  }

  List<String> get _initialLabels =>
      normalizeLikeTagLabels(widget.offer.initialTags);

  @override
  void didUpdateWidget(covariant LikeTagChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer.token == widget.offer.token) return;
    _draftTouched = false;
    _draftLabels = _initialLabels;
    _committed = false;
    _committedLabels = const <String>[];
  }

  // --- menu lifecycle ------------------------------------------------------

  Rect? _chipOverlayRect(RenderBox overlayBox) {
    final box = _chipKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return overlayBox.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
  }

  @override
  void didChangeMetrics() {
    // A fold moves the toolbar. Close this transient surface, keeping its
    // draft on the chip so reopening continues from the same choices.
    if (_menuOpen) _closeMenu();
  }

  void _toggleMenu() {
    if (_committed) return;
    if (_menuOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    if (_chipOverlayRect(overlayBox) == null) return;
    HapticFeedback.selectionClick();
    // A menu still folding from the last close gives way to the new one.
    _dropMenuEntry();
    _countdown.stop(); // pause: never time out with the menu open.
    setState(() => _menuOpen = true);
    _fold = GlassFold(_menu);
    _menuEntry = OverlayEntry(
      builder: (ctx) {
        final rect = _chipOverlayRect(overlayBox);
        return rect == null ? const SizedBox.shrink() : _buildMenu(ctx, rect);
      },
    );
    overlay.insert(_menuEntry!);
    if (MediaQuery.disableAnimationsOf(context)) {
      _menu.value = 1;
    } else {
      _menu.value = 0;
      _menu.animateWith(GlassAnchoredMotion.simulation(from: 0));
    }
  }

  void _dropMenuEntry() {
    _menuEntry?.remove();
    _menuEntry?.dispose();
    _menuEntry = null;
  }

  /// Folds the menu shut into the chip, like every anchored glass surface
  /// ([GlassFold]): the chip turns closed at once, the page under the
  /// folding menu already takes taps, and the entry goes once the fold
  /// holds nothing (at once under reduced motion).
  void _closeMenu() {
    if (!_menuOpen) return;
    final entry = _menuEntry;
    _fold?.close();
    setState(() => _menuOpen = false);
    // Closing the menu without Save never persists. Resume the countdown
    // from where it paused so the chip still self-dismisses if ignored.
    if (!_committed && _countdown.status != AnimationStatus.completed) {
      _countdown.forward();
    }
    void finish() {
      if (identical(_menuEntry, entry)) _dropMenuEntry();
    }

    if (MediaQuery.disableAnimationsOf(context) || _menu.value <= 0) {
      _menu.value = 0;
      finish();
      return;
    }
    _menu
        .animateBackWith(GlassAnchoredMotion.closeSimulation(from: _menu.value))
        .orCancel
        .then((_) {
          if (mounted) finish();
        }, onError: (Object _) {});
  }

  void _commit(List<String> labels, {bool haptic = true}) {
    if (_committed) return;
    final normalized = _normalizeLabels(labels);
    if (haptic) HapticFeedback.mediumImpact();
    setState(() {
      _committed = true;
      _draftLabels = normalized;
      _committedLabels = normalized;
    });
    _countdown.stop();
    _closeMenu();

    // Persist (or clear). Fire-and-forget — the chip's job is the gesture; the
    // notifier owns optimistic state + rollback.
    unawaited(
      ref
          .read(likedGamesProvider.notifier)
          .setTagsForLikeId(widget.offer.likeId, normalized),
    );

    _confirmationTimer = Timer(const Duration(milliseconds: 640), () {
      if (mounted) _dismiss();
    });
  }

  List<String> _normalizeLabels(Iterable<String> labels) {
    return normalizeLikeTagLabels(labels);
  }

  // --- chip ----------------------------------------------------------------

  _ChipFace _faceFor(AppColors colors) {
    if (_committed) {
      return _faceForLabels(colors, _committedLabels, showCheck: true);
    }
    if (_draftTouched) {
      return _faceForLabels(colors, _draftLabels);
    }
    if (_draftLabels.isNotEmpty) {
      return _faceForLabels(colors, _draftLabels);
    }
    return _ChipFace(
      icon: Icons.sell_rounded,
      label: 'Tag this game',
      accent: colors.brand,
    );
  }

  _ChipFace _faceForLabels(
    AppColors colors,
    List<String> labels, {
    bool showCheck = false,
  }) {
    if (labels.isEmpty) {
      return _ChipFace(
        icon: Icons.label_off_rounded,
        label: 'No tags',
        accent: colors.textSecondary,
        showCheck: showCheck,
      );
    }

    final firstTag = likeTagByLabel(labels.first);
    if (labels.length == 1) {
      return _ChipFace(
        icon: firstTag?.icon ?? Icons.sell_rounded,
        label: labels.first,
        accent: firstTag?.color ?? colors.brand,
        showCheck: showCheck,
      );
    }

    return _ChipFace(
      icon: firstTag?.icon ?? Icons.sell_rounded,
      label: '${labels.length} tags',
      accent: firstTag?.color ?? colors.brand,
      showCheck: showCheck,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleMenu,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
      },
      child: SingleMotionBuilder(
        // Bouncy press feedback — spring beats AnimatedScale's linear ease.
        motion: const CupertinoMotion.bouncy(),
        value: _pressed ? 1.0 : 0.0,
        builder: (context, pressT, _) {
          return Transform.scale(
            scale: reduceMotion ? 1 : 1.0 - 0.05 * pressT,
            child: AnimatedBuilder(
              animation: _countdown,
              builder: (context, _) {
                final remaining = _committed
                    ? 1.0
                    : (1 - _countdown.value).clamp(0.0, 1.0);
                return _chipBody(colors, _faceFor(colors), remaining);
              },
            ),
          );
        },
      ),
    );
    if (reduceMotion) return chip;
    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      from: 0,
      value: 1,
      child: chip,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, 6 * (1 - t)),
        child: Transform.scale(
          scale: 0.92 + 0.08 * t,
          alignment: Alignment.centerRight,
          child: child,
        ),
      ),
    );
  }

  Widget _chipBody(AppColors colors, _ChipFace face, double remaining) {
    final radius = 17.br;
    // Subtle accent glow under the chip, brightest while the countdown is
    // still draining, faded once the user commits.
    // Paper gets no bloom at all.
    final glowAlpha = _committed || context.isLightTheme
        ? 0.0
        : 0.22 * remaining;
    // Tag hues are tuned on black; on paper the glyph, check and countdown
    // take the same hue darkened to 3:1 against the chip's recessed well.
    final ink = legibleHueInk(
      context,
      face.accent,
      minContrast: 3,
      on: colors.surfaceRecessed,
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerRight,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            if (glowAlpha > 0.01)
              BoxShadow(
                color: face.accent.withValues(alpha: glowAlpha),
                blurRadius: 14,
                spreadRadius: -2,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: CustomPaint(
          foregroundPainter: _CountdownBorderPainter(
            remaining: remaining,
            radius: radius,
            accent: ink,
            track: colors.dividerStrong.withValues(alpha: 0.45),
          ),
          child: Container(
            key: _chipKey,
            height: 34.h,
            constraints: BoxConstraints(maxWidth: 196.w),
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            decoration: BoxDecoration(
              color: colors.surfaceRecessed,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconBubble(icon: face.icon, accent: face.accent, ink: ink),
                SizedBox(width: 7.w),
                Flexible(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) {
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.15),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      face.label,
                      key: ValueKey<String>(face.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textSmMedium.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 4.w),
                face.showCheck
                    ? Icon(
                        Icons.check_rounded,
                        size: 17.sp,
                        color: ink,
                      ).animate().scale(
                        duration: 240.ms,
                        curve: Curves.elasticOut,
                        begin: const Offset(0.4, 0.4),
                        end: const Offset(1.0, 1.0),
                      )
                    : AnimatedRotation(
                        turns: _menuOpen ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18.sp,
                          color: colors.textSecondary,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- dropdown ------------------------------------------------------------

  Widget _buildMenu(BuildContext overlayContext, Rect chipRect) {
    final media = MediaQuery.of(overlayContext);
    final screenW = media.size.width;
    final gutter = math.max(12.0, 8.w);
    final leftEdge = media.padding.left + gutter;
    final rightEdge = media.padding.right + gutter;
    final panelWidth = math.min(332.w, screenW - leftEdge - rightEdge);
    // The board toolbar opens down; Feed's action row opens up. Keep the
    // same panel inside the safe area, with a scrollable grid on short screens.
    final right = (screenW - chipRect.right).clamp(
      rightEdge,
      math.max(rightEdge, screenW - panelWidth - leftEdge),
    );
    final below = math.max(
      0.0,
      media.size.height -
          math.max(media.padding.bottom, media.viewInsets.bottom) -
          chipRect.bottom -
          16.h,
    );
    final above = math.max(0.0, chipRect.top - media.padding.top - 16.h);
    final opensUp = above > below;
    final maxHeight = math.min(opensUp ? above : below, 540.h);

    return _TagDropdown(
      animation: _menu,
      fold: _fold!,
      chip: RRect.fromRectAndRadius(chipRect, Radius.circular(17.br)),
      top: opensUp ? null : chipRect.bottom + 8.h,
      bottom: opensUp ? media.size.height - chipRect.top + 8.h : null,
      right: right.toDouble(),
      width: panelWidth,
      maxHeight: maxHeight,
      initialLabels: _draftLabels,
      onChanged: (labels) {
        setState(() {
          _draftTouched = true;
          _draftLabels = _normalizeLabels(labels);
        });
      },
      onCommit: _commit,
      onDismiss: _closeMenu,
    );
  }
}

/// Resolved visual state of the chip for one frame.
class _ChipFace {
  const _ChipFace({
    required this.icon,
    required this.label,
    required this.accent,
    this.showCheck = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool showCheck;
}

/// Small tinted glyph bubble on the AppBar chip face.
class _IconBubble extends StatelessWidget {
  const _IconBubble({
    required this.icon,
    required this.accent,
    required this.ink,
  });

  final IconData icon;
  final Color accent;

  /// Glyph colour: [accent] in dark, its legible paper ink in light.
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final dim = 22.w;
    return Container(
      width: dim,
      height: dim,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(dim * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: dim * 0.62, color: ink),
    );
  }
}

/// Strokes the chip's rounded-rect perimeter: a faint full-loop track plus a
/// bright segment whose length is [remaining] of the perimeter — the visible
/// countdown. Drains by shortening the bright segment.
class _CountdownBorderPainter extends CustomPainter {
  _CountdownBorderPainter({
    required this.remaining,
    required this.radius,
    required this.accent,
    required this.track,
  });

  final double remaining;
  final double radius;
  final Color accent;
  final Color track;

  static const double _stroke = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(_stroke / 2),
      Radius.circular(radius - _stroke / 2),
    );
    final path = Path()..addRRect(rrect);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = track,
    );

    final frac = remaining.clamp(0.0, 1.0);
    if (frac <= 0) return;
    final metric = path.computeMetrics().first;
    final segment = metric.extractPath(0, metric.length * frac);
    // Thin, crisp, no glow — a quiet hairline that drains, not a bright halo.
    canvas.drawPath(
      segment,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_CountdownBorderPainter old) =>
      old.remaining != remaining ||
      old.accent != accent ||
      old.radius != radius;
}

/// The dropping menu: a dimming dismiss barrier plus an anchored panel of
/// frosted glass ([PopupGlass]) that grows out of the chip on the anchored
/// glass spring (scaled, never faded: glass under an opacity loses its
/// frost) as [animation] runs forward, and folds shut back into it as it
/// closes ([fold]), its contents fading.
class _TagDropdown extends StatefulWidget {
  const _TagDropdown({
    required this.animation,
    required this.fold,
    required this.chip,
    required this.top,
    required this.bottom,
    required this.right,
    required this.width,
    required this.maxHeight,
    required this.initialLabels,
    required this.onChanged,
    required this.onCommit,
    required this.onDismiss,
  });

  final Animation<double> animation;
  final GlassFold fold;

  /// The chip that opened the menu: left lit under the dim.
  final RRect chip;
  final double? top;
  final double? bottom;
  final double right;
  final double width;
  final double maxHeight;
  final List<String> initialLabels;
  final void Function(List<String>) onChanged;
  final void Function(List<String>) onCommit;
  final VoidCallback onDismiss;

  @override
  State<_TagDropdown> createState() => _TagDropdownState();
}

class _TagDropdownState extends State<_TagDropdown> {
  /// The tag grid is capped at [_visibleRows] rows and scrolls past that, so
  /// the panel keeps a stable footprint if the vocabulary grows past the
  /// current fourteen tags (seven 2-up rows). The cap is the full set so
  /// nothing starts clipped behind a scroll.
  static const int _columns = 2;
  static const int _visibleRows = 7;
  static const int _pageSize = _columns * _visibleRows;

  late final Set<String> _selected;
  final ScrollController _grid = ScrollController();

  /// Whether content runs off the top / bottom of the capped viewport. Drives
  /// the edge fades — the only hint that the list continues.
  bool _moreAbove = false;
  bool _moreBelow = kLikeTags.length > _pageSize;

  @override
  void initState() {
    super.initState();
    _selected = <String>{...normalizeLikeTagLabels(widget.initialLabels)};
    _grid.addListener(_syncEdges);
    // First frame has no scroll metrics yet; read them once laid out so a
    // short screen (which shrinks the panel further) also gets its fades.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
  }

  @override
  void dispose() {
    _grid.removeListener(_syncEdges);
    _grid.dispose();
    super.dispose();
  }

  void _syncEdges() {
    if (!mounted || !_grid.hasClients) return;
    final position = _grid.position;
    final above = position.extentBefore > 1;
    final below = position.extentAfter > 1;
    if (above == _moreAbove && below == _moreBelow) return;
    setState(() {
      _moreAbove = above;
      _moreBelow = below;
    });
  }

  void _toggle(String label) {
    final isSelected = _selected.contains(label);

    HapticFeedback.selectionClick();
    setState(() {
      if (isSelected) {
        _selected.remove(label);
      } else {
        _selected.add(label);
      }
    });
    widget.onChanged(_selected.toList(growable: false));
  }

  void _commit() {
    widget.onCommit(_selected.toList(growable: false));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final opensUp = widget.bottom != null;
    return GlassFoldIgnorePointer(
      fold: widget.fold,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
              // The anchored menus' dim, riding the menu's spring (repainted,
              // never rebuilt); never a blur. The chip stays lit.
              child: CustomPaint(
                size: Size.infinite,
                painter: GlassScrimPainter(
                  color: AnchoredGlassDim.colorOf(context),
                  hole: widget.chip,
                  progress: widget.animation,
                ),
              ),
            ),
          ),
          Positioned(
            top: widget.top,
            bottom: widget.bottom,
            right: widget.right,
            width: widget.width,
            // Grown out of the chip's corner and folded shut back into it.
            // Content is readable even at the first frame; an entrance never
            // gates visibility. Under reduced motion it opens at full size and
            // goes at once.
            child: GlassFoldTransition(
              fold: widget.fold,
              alignment: opensUp ? Alignment.bottomRight : Alignment.topRight,
              includeOpen: !MediaQuery.disableAnimationsOf(context),
              child: RepaintBoundary(child: _panel(colors)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(AppColors colors) {
    final tags = kLikeTags;
    // Two-line tag labels need taller rows at larger text sizes.
    final rowExtent = context.textExtent(48.h);
    final rowGap = 8.h;
    final padTop = 8.h;
    final padBottom = 10.h;
    // Exactly [_visibleRows] rows — the full current vocabulary. Anything
    // past that scrolls instead of stretching the panel.
    final gridHeight =
        rowExtent * _visibleRows +
        rowGap * (_visibleRows - 1) +
        padTop +
        padBottom;
    // The popups' frosted glass, averaging to the raised surface the opaque
    // panel was. Its lit rim is the edge, in the pixel the border held, so
    // the contents keep their exact place.
    return PopupGlass(
      tone: colors.surfaceElevated,
      // Solved over the page as the anchored dim leaves it.
      page: AnchoredGlassDim.pageOf(context),
      cover: AnchoredGlassDim.cover,
      borderRadius: BorderRadius.circular(16.br),
      padding: const EdgeInsets.all(1),
      // The contents fade as the menu folds; the glass itself never does.
      child: FadeTransition(
        opacity: widget.fold,
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(14.w, 11.h, 14.w, 7.h),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sell_rounded,
                        size: 14.sp,
                        color: colors.textSecondary,
                      ),
                      SizedBox(width: 7.w),
                      Expanded(
                        child: Text(
                          _selected.isEmpty
                              ? 'Tag this game'
                              : '${_selected.length} selected',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.textXsMedium.copyWith(
                            color: colors.textSecondary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _commit,
                          borderRadius: BorderRadius.circular(8.br),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10.w,
                              vertical: 5.h,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_rounded,
                                  size: 15.sp,
                                  color: context.colors.accentText,
                                ),
                                SizedBox(width: 4.w),
                                Text(
                                  'Save',
                                  style: AppTypography.textXsMedium.copyWith(
                                    color: context.colors.accentText,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.dividerStrong.withValues(alpha: 0.4),
                ),
                Flexible(
                  // Rows now scroll under the panel's bottom corners, so clip
                  // them to the border's inner radius — otherwise a square's
                  // corner paints outside the rounded edge on the way past.
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(16.br - 1),
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: gridHeight),
                      // A half-row at a scrolling edge melts into the glass:
                      // the list's own alpha fades there (a mask, only while
                      // rows run past that edge), so the frost under it is
                      // never covered by an opaque band.
                      child: _ScrollEdgeFade(
                        top: _moreAbove,
                        bottom: _moreBelow,
                        topExtent: padTop + rowExtent * 0.34,
                        bottomExtent: padBottom + rowExtent * 0.34,
                        child: GridView.builder(
                          controller: _grid,
                          padding: EdgeInsets.fromLTRB(
                            10.w,
                            padTop,
                            10.w,
                            padBottom,
                          ),
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          itemCount: tags.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _columns,
                                mainAxisSpacing: rowGap,
                                crossAxisSpacing: 8.w,
                                mainAxisExtent: rowExtent,
                              ),
                          itemBuilder: (_, i) {
                            final t = tags[i];
                            final square = _TagSquare(
                              label: t.label,
                              accent: t.color,
                              selected: _selected.contains(t.label),
                              onTap: () => _toggle(t.label),
                            );
                            // Only the first screenful joins the opening
                            // stagger. Rows below the fold are built as the user
                            // scrolls, and a delayed fade there would pop in
                            // under the thumb.
                            if (i >= _pageSize ||
                                MediaQuery.disableAnimationsOf(context)) {
                              return square;
                            }
                            final delay = Duration(milliseconds: 60 + i * 22);
                            return square
                                // Stagger reveal — each chip arrives ~22ms after
                                // the previous so the grid feels assembled, not
                                // slammed.
                                .animate()
                                .moveY(
                                  begin: 6,
                                  end: 0,
                                  delay: delay,
                                  duration: 220.ms,
                                  curve: Curves.easeOutCubic,
                                )
                                .scaleXY(
                                  begin: 0.94,
                                  end: 1.0,
                                  delay: delay,
                                  duration: 240.ms,
                                  curve: Curves.easeOutBack,
                                );
                          },
                        ),
                      ),
                    ),
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

/// Softens the rows at a scrolling edge, so a clipped half-row reads as
/// "there is more" instead of as a botched cut, and only while content runs
/// past that edge.
///
/// It fades the list's own alpha ([BlendMode.dstIn] over a gradient), so
/// the glass behind shows through the fade as it does everywhere else on
/// the panel: an opaque band of the panel's tone laid over translucent
/// glass would read as a strip of a different material. Each edge eases in
/// and out on a spring; with neither edge showing, the list is painted as
/// is, with no mask layer.
class _ScrollEdgeFade extends StatelessWidget {
  const _ScrollEdgeFade({
    required this.top,
    required this.bottom,
    required this.topExtent,
    required this.bottomExtent,
    required this.child,
  });

  final bool top;
  final bool bottom;
  final double topExtent;
  final double bottomExtent;
  final Widget child;

  static const _motion = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 160),
    snapToEnd: true,
  );

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return SingleMotionBuilder(
      motion: _motion,
      value: top ? 1.0 : 0.0,
      active: !still,
      child: child,
      builder: (context, topShown, child) => SingleMotionBuilder(
        motion: _motion,
        value: bottom ? 1.0 : 0.0,
        active: !still,
        child: child,
        builder: (context, bottomShown, child) => _EdgeFadeMask(
          top: topShown.clamp(0.0, 1.0),
          bottom: bottomShown.clamp(0.0, 1.0),
          topExtent: topExtent,
          bottomExtent: bottomExtent,
          child: child,
        ),
      ),
    );
  }
}

class _EdgeFadeMask extends SingleChildRenderObjectWidget {
  const _EdgeFadeMask({
    required this.top,
    required this.bottom,
    required this.topExtent,
    required this.bottomExtent,
    super.child,
  });

  final double top;
  final double bottom;
  final double topExtent;
  final double bottomExtent;

  @override
  _RenderEdgeFadeMask createRenderObject(BuildContext context) =>
      _RenderEdgeFadeMask()
        ..top = top
        ..bottom = bottom
        ..topExtent = topExtent
        ..bottomExtent = bottomExtent;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEdgeFadeMask renderObject,
  ) {
    renderObject
      ..top = top
      ..bottom = bottom
      ..topExtent = topExtent
      ..bottomExtent = bottomExtent;
  }
}

/// Paints its child through a vertical alpha mask: [top] and [bottom] (0
/// none, 1 full) fade the child out over [topExtent] / [bottomExtent] at
/// that edge (its first 15% fully gone, as the old fade's solid lip was).
class _RenderEdgeFadeMask extends RenderProxyBox {
  double _top = 0;
  double _bottom = 0;
  double _topExtent = 0;
  double _bottomExtent = 0;

  bool get _masking => _top > 0.001 || _bottom > 0.001;

  set top(double value) => _set(value, _top, (v) => _top = v);
  set bottom(double value) => _set(value, _bottom, (v) => _bottom = v);
  set topExtent(double value) => _set(value, _topExtent, (v) => _topExtent = v);
  set bottomExtent(double value) =>
      _set(value, _bottomExtent, (v) => _bottomExtent = v);

  void _set(double value, double old, void Function(double) write) {
    if (value == old) return;
    final masking = _masking;
    write(value);
    if (masking != _masking) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _masking;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || !_masking || size.isEmpty) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final height = size.height;
    double at(double extent) => (extent / height).clamp(0.0, 0.5);
    final top = at(_topExtent);
    final bottom = at(_bottomExtent);
    final topEdge = Colors.white.withValues(alpha: 1 - _top);
    final bottomEdge = Colors.white.withValues(alpha: 1 - _bottom);
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        topEdge,
        topEdge,
        Colors.white,
        Colors.white,
        bottomEdge,
        bottomEdge,
      ],
      stops: [0, top * 0.15, top, 1 - bottom, 1 - bottom * 0.15, 1],
    ).createShader(Offset.zero & size);
    final mask = (layer as ShaderMaskLayer?) ?? ShaderMaskLayer();
    mask
      ..shader = shader
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    layer = mask;
    context.pushLayer(mask, super.paint, offset);
  }
}

/// One selectable tag in the dropdown: text-only clickable square laid out
/// two-up in a scrolling grid. Tag colour survives as the selected-state accent
/// (border + tinted fill) so the curated palette still distinguishes tags
/// without per-tag glyphs.
class _TagSquare extends StatelessWidget {
  const _TagSquare({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = 10.br;
    final Color fill;
    final Color border;
    final Color textColor;
    if (selected) {
      fill = accent.withValues(alpha: 0.18);
      border = context.isLightTheme
          ? legibleHueInk(
              context,
              accent,
              minContrast: 3,
              on: Color.alphaBlend(fill, colors.surfaceElevated),
            )
          : accent.withValues(alpha: 0.9);
      textColor = colors.textPrimary;
    } else {
      fill = colors.surfaceRecessed;
      border = colors.dividerStrong.withValues(alpha: 0.55);
      textColor = colors.textPrimary;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: accent.withValues(alpha: 0.12),
        highlightColor: accent.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: selected ? 1.2 : 1.0),
          ),
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            textAlign: TextAlign.center,
            style: AppTypography.textXsMedium.copyWith(
              color: textColor,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.1,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}

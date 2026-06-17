import 'dart:async';

import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/models/like_tag.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_offer.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// The post-like tag picker that lives *in the AppBar*.
///
/// Replaces the roulette wheel: instead of a full-screen casino spinner sliding
/// in from the right, the toolbar's action icons quietly hand over to a single
/// pill — a "Tag this game" chip whose border drains as a countdown. Tapping it
/// drops a small menu of the ten [kLikeTags] (each with an explanatory icon);
/// checking one or more tags writes the full tag list, letting the countdown
/// elapse leaves the like untagged.
class LikeTagChip extends ConsumerStatefulWidget {
  const LikeTagChip({super.key, required this.offer});

  final TagOffer offer;

  @override
  ConsumerState<LikeTagChip> createState() => _LikeTagChipState();
}

class _LikeTagChipState extends ConsumerState<LikeTagChip>
    with TickerProviderStateMixin {
  /// How long the chip lingers before self-dismissing untagged. Long enough to
  /// notice and reach for, short enough not to squat on the toolbar.
  static const Duration _countdownDuration = Duration(milliseconds: 5200);
  static const Duration _menuDuration = Duration(milliseconds: 240);

  final GlobalKey _chipKey = GlobalKey();

  late final AnimationController _countdown;
  late final AnimationController _menu;
  OverlayEntry? _menuEntry;

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
    _draftLabels = _initialLabels;
    _countdown = AnimationController(vsync: this, duration: _countdownDuration)
      ..addStatusListener(_onCountdownStatus);
    _menu = AnimationController(vsync: this, duration: _menuDuration);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _countdown.forward();
    });
  }

  @override
  void dispose() {
    // Synchronous teardown — no setState — so a chip swapped out mid-menu by
    // the AppBar's AnimatedSwitcher can't leak its overlay entry.
    _menuEntry?.remove();
    _menuEntry = null;
    _countdown.dispose();
    _menu.dispose();
    super.dispose();
  }

  void _onCountdownStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_committed && !_menuOpen) {
      if (_draftTouched) {
        _commit(_draftLabels, haptic: false);
        return;
      }
      // Elapsed untouched -> leave the like untagged. Token-guarded close in
      // case a newer offer already replaced us.
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

  Rect? _chipGlobalRect() {
    final box = _chipKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
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
    final rect = _chipGlobalRect();
    if (rect == null) return;
    HapticFeedback.selectionClick();
    _countdown.stop(); // pause: never time out with the menu open.
    setState(() => _menuOpen = true);
    _menuEntry = OverlayEntry(builder: (ctx) => _buildMenu(ctx, rect));
    Overlay.of(context, rootOverlay: true).insert(_menuEntry!);
    _menu.forward(from: 0);
  }

  void _closeMenu() {
    if (!_menuOpen) return;
    _menu.reverse();
    // Captured before the deferred callback so a mid-flight commit (from Save)
    // doesn't double-fire here.
    final shouldCommit = _draftTouched && !_committed;
    Future.delayed(_menuDuration, () {
      _menuEntry?.remove();
      _menuEntry = null;
      if (!mounted) return;
      setState(() => _menuOpen = false);
      if (shouldCommit && !_committed) {
        // PM: dismissing with picks already made should save immediately
        // instead of waiting out the countdown.
        _commit(_draftLabels, haptic: false);
        return;
      }
      // Resume the countdown from where it paused, unless the user committed.
      if (!_committed && _countdown.status != AnimationStatus.completed) {
        _countdown.forward();
      }
    });
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

    Future.delayed(const Duration(milliseconds: 640), () {
      if (mounted) ref.read(tagChipOfferProvider).close(widget.offer.token);
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        _toggleMenu();
      },
      child: SingleMotionBuilder(
        // Bouncy press feedback — spring beats AnimatedScale's linear ease.
        motion: const CupertinoMotion.bouncy(),
        value: _pressed ? 1.0 : 0.0,
        builder: (context, pressT, _) {
          return Transform.scale(
            scale: 1.0 - 0.05 * pressT,
            child: AnimatedBuilder(
              animation: _countdown,
              builder: (context, _) {
                final remaining =
                    _committed
                        ? 1.0
                        : (1 - _countdown.value).clamp(0.0, 1.0);
                return _chipBody(colors, _faceFor(colors), remaining);
              },
            ),
          );
        },
      ).animate(target: 1).fadeIn(duration: 260.ms, curve: Curves.easeOutCubic),
    );
  }

  Widget _chipBody(AppColors colors, _ChipFace face, double remaining) {
    final radius = 17.br;
    // Subtle accent glow under the chip, brightest while the countdown is
    // still draining, faded once the user commits.
    final glowAlpha = _committed ? 0.0 : 0.22 * remaining;
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
            accent: face.accent,
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
                _IconBubble(icon: face.icon, accent: face.accent),
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
                          color: face.accent,
                        )
                        .animate()
                        .scale(
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
    final panelWidth = 268.w;
    // Right-align under the chip, clamped on-screen.
    final right = (screenW - chipRect.right).clamp(
      8.w,
      (screenW - panelWidth - 8.w).clamp(8.w, screenW),
    );
    final top = chipRect.bottom + 8.h;
    final maxHeight = (media.size.height - top - 24.h).clamp(120.h, 460.h);

    return _TagDropdown(
      animation: _menu,
      top: top,
      right: right,
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
  const _IconBubble({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

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
      child: Icon(icon, size: dim * 0.62, color: accent),
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

/// The dropping menu: a dismiss barrier plus an anchored, animated panel that
/// reveals top-down (clip + fade + small drop) as [animation] runs forward.
class _TagDropdown extends StatefulWidget {
  const _TagDropdown({
    required this.animation,
    required this.top,
    required this.right,
    required this.width,
    required this.maxHeight,
    required this.initialLabels,
    required this.onChanged,
    required this.onCommit,
    required this.onDismiss,
  });

  final Animation<double> animation;
  final double top;
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
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = <String>{...normalizeLikeTagLabels(widget.initialLabels)};
  }

  void _toggle(String label) {
    final isSelected = _selected.contains(label);
    if (!isSelected && _selected.length >= kMaxLikeTagsPerGame) return;

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
    // Two curves: easeOutCubic for the panel enter (opens decisively), and
    // a sharper easeInCubic on reverse for a tight exit.
    final shellCurve = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
          ),
        ),
        Positioned(
          top: widget.top,
          right: widget.right,
          width: widget.width,
          child: AnimatedBuilder(
            animation: shellCurve,
            builder: (context, child) {
              final t = shellCurve.value.clamp(0.0, 1.0);
              // Anchor the scale at top-right (under the chip), so the panel
              // visually "grows out of" the trigger pill instead of dropping
              // from above.
              final scale = 0.86 + 0.14 * t;
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * -8),
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.topRight,
                    child: child,
                  ),
                ),
              );
            },
            child: _panel(colors),
          ),
        ),
      ],
    );
  }

  Widget _panel(AppColors colors) {
    final tags = kLikeTags;
    return Material(
      color: colors.surfaceElevated,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16.br),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(
            color: colors.dividerStrong.withValues(alpha: 0.55),
          ),
        ),
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
                            : '${_selected.length}/$kMaxLikeTagsPerGame selected',
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
                                color: colors.brand,
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                'Save',
                                style: AppTypography.textXsMedium.copyWith(
                                  color: colors.brand,
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
                child: GridView.builder(
                  padding: EdgeInsets.fromLTRB(10.w, 8.h, 10.w, 10.h),
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: tags.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 6.h,
                    crossAxisSpacing: 6.w,
                    mainAxisExtent: 34.h,
                  ),
                  itemBuilder: (_, i) {
                    final t = tags[i];
                    final selected = _selected.contains(t.label);
                    final disabled =
                        !selected &&
                        _selected.length >= kMaxLikeTagsPerGame;
                    return _TagSquare(
                          label: t.label,
                          accent: t.color,
                          selected: selected,
                          disabled: disabled,
                          onTap: disabled ? null : () => _toggle(t.label),
                        )
                        // Stagger reveal — each chip arrives ~22ms after the
                        // previous so the grid feels assembled, not slammed.
                        .animate()
                        .fadeIn(
                          delay: Duration(milliseconds: 60 + i * 22),
                          duration: 200.ms,
                          curve: Curves.easeOutCubic,
                        )
                        .moveY(
                          begin: 6,
                          end: 0,
                          delay: Duration(milliseconds: 60 + i * 22),
                          duration: 220.ms,
                          curve: Curves.easeOutCubic,
                        )
                        .scaleXY(
                          begin: 0.94,
                          end: 1.0,
                          delay: Duration(milliseconds: 60 + i * 22),
                          duration: 240.ms,
                          curve: Curves.easeOutBack,
                        );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable tag in the dropdown: text-only clickable square that wraps
/// alongside its siblings so all ten tags fit at a glance. Tag colour survives
/// as the selected-state accent (border + tinted fill) so the curated palette
/// still distinguishes tags without per-tag glyphs.
class _TagSquare extends StatelessWidget {
  const _TagSquare({
    required this.label,
    required this.accent,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool selected;
  final bool disabled;
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
      border = accent.withValues(alpha: 0.9);
      textColor = colors.textPrimary;
    } else if (disabled) {
      fill = colors.surfaceRecessed.withValues(alpha: 0.55);
      border = colors.dividerStrong.withValues(alpha: 0.35);
      textColor = colors.textPrimary.withValues(alpha: 0.42);
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
        splashColor:
            disabled ? Colors.transparent : accent.withValues(alpha: 0.12),
        highlightColor:
            disabled ? Colors.transparent : accent.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: border,
              width: selected ? 1.2 : 1.0,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.textXsMedium.copyWith(
              color: textColor,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

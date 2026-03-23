import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// A parent-child notification category row used inside [NotifPushCard].
///
/// Shows a label + adaptive toggle. When [enabled] is true, [AnimatedSize]
/// reveals three time-control mini-cards (Classical / Rapid / Blitz) with
/// a staggered slide-up + fade-in entry animation.
///
/// Each card shows the app's PNG time-control icon, the label, an animated
/// teal glow border, and a checkmark badge when selected.
///
/// Auto-selecting all chips when the parent is turned ON is handled by the
/// caller (provider setter), not here — this widget manages only animation.
class NotifCategoryTile extends StatefulWidget {
  const NotifCategoryTile({
    super.key,
    required this.label,
    required this.enabled,
    required this.onToggle,
    required this.interactive,
    required this.classical,
    required this.onClassical,
    required this.rapid,
    required this.onRapid,
    required this.blitz,
    required this.onBlitz,
  });

  final String label;
  final bool enabled;
  final VoidCallback onToggle;
  final bool interactive;
  final bool classical;
  final VoidCallback onClassical;
  final bool rapid;
  final VoidCallback onRapid;
  final bool blitz;
  final VoidCallback onBlitz;

  @override
  State<NotifCategoryTile> createState() => _NotifCategoryTileState();
}

class _NotifCategoryTileState extends State<NotifCategoryTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Staggered fade animations
  late final Animation<double> _fade0, _fade1, _fade2;
  // Staggered slide animations
  late final Animation<Offset> _slide0, _slide1, _slide2;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    final a0 = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.70, curve: Curves.easeOut),
    );
    final a1 = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.2, 0.85, curve: Curves.easeOut),
    );
    final a2 = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.4, 1.00, curve: Curves.easeOut),
    );

    _fade0 = a0;
    _fade1 = a1;
    _fade2 = a2;

    final slideBegin = const Offset(0, 0.35);
    _slide0 = Tween(begin: slideBegin, end: Offset.zero).animate(a0);
    _slide1 = Tween(begin: slideBegin, end: Offset.zero).animate(a1);
    _slide2 = Tween(begin: slideBegin, end: Offset.zero).animate(a2);

    if (widget.enabled) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(NotifCategoryTile old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !old.enabled) {
      _ctrl.forward(from: 0);
    } else if (!widget.enabled && old.enabled) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chipInteractive = widget.interactive && widget.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Parent row ────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: AppTypography.textMdMedium.copyWith(
                  color: widget.interactive ? kWhiteColor : kWhiteColor70,
                  fontSize: 13.f,
                ),
              ),
            ),
            Switch.adaptive(
              value: widget.enabled,
              thumbColor: WidgetStatePropertyAll(kPrimaryColor),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? kPrimaryColor.withValues(alpha: 0.35)
                    : kDividerColor.withValues(alpha: 0.5),
              ),
              onChanged: widget.interactive ? (_) => widget.onToggle() : null,
            ),
          ],
        ),

        // ── TC cards — animated, only shown when parent is ON ─────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: widget.enabled
              ? Padding(
                  padding: EdgeInsets.only(top: 12.h),
                  child: Row(
                    children: [
                      _TcCard(
                        assetPath: PngAsset.classicalIcon,
                        label: 'Classical',
                        selected: widget.classical,
                        onTap: widget.onClassical,
                        enabled: chipInteractive,
                        fade: _fade0,
                        slide: _slide0,
                      ),
                      SizedBox(width: 8.sp),
                      _TcCard(
                        assetPath: PngAsset.rapidIcon,
                        label: 'Rapid',
                        selected: widget.rapid,
                        onTap: widget.onRapid,
                        enabled: chipInteractive,
                        fade: _fade1,
                        slide: _slide1,
                      ),
                      SizedBox(width: 8.sp),
                      _TcCard(
                        assetPath: PngAsset.blitzIcon,
                        label: 'Blitz',
                        selected: widget.blitz,
                        onTap: widget.onBlitz,
                        enabled: chipInteractive,
                        fade: _fade2,
                        slide: _slide2,
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Private mini time-control card ─────────────────────────────────────────

class _TcCard extends StatelessWidget {
  const _TcCard({
    required this.assetPath,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.enabled,
    required this.fade,
    required this.slide,
  });

  final String assetPath;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  final Animation<double> fade;
  final Animation<Offset> slide;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: EdgeInsets.symmetric(vertical: 10.sp),
              decoration: BoxDecoration(
                color: selected
                    ? kPrimaryColor.withValues(alpha: 0.08)
                    : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(10.br),
                border: Border.all(
                  color: selected ? kPrimaryColor : const Color(0xFF333333),
                  width: selected ? 1.5 : 1.0,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: kPrimaryColor.withValues(alpha: 0.18),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ]
                    : [],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon + checkmark badge
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      AnimatedOpacity(
                        opacity: selected ? 1.0 : 0.35,
                        duration: const Duration(milliseconds: 200),
                        child: Image.asset(
                          assetPath,
                          width: 20.sp,
                          height: 20.sp,
                        ),
                      ),
                      Positioned(
                        top: -5,
                        right: -5,
                        child: AnimatedOpacity(
                          opacity: selected ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: kPrimaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check,
                              size: 7.sp,
                              color: kWhiteColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    label,
                    style: AppTypography.textSmRegular.copyWith(
                      fontSize: 10.f,
                      color: selected ? kWhiteColor : const Color(0xFF888888),
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

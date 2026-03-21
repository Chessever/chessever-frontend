import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/notification_settings/notif_filter_chip.dart';
import 'package:flutter/material.dart';

/// A parent-child notification category row used inside [NotifPushCard].
///
/// Shows a label + adaptive toggle.  When [enabled] is true an [AnimatedSize]
/// reveals three time-control filter chips: Classical, Rapid, Blitz.
///
/// Auto-selecting all chips when the parent is turned ON is handled by the
/// caller (provider setter), not here — this widget is fully stateless.
class NotifCategoryTile extends StatelessWidget {
  const NotifCategoryTile({
    super.key,
    required this.label,
    required this.enabled,
    required this.onToggle,
    required this.interactive,
    // Sub-filter state
    required this.classical,
    required this.onClassical,
    required this.rapid,
    required this.onRapid,
    required this.blitz,
    required this.onBlitz,
  });

  /// Category label, e.g. "Favorite Players".
  final String label;

  /// Whether the parent toggle is on.
  final bool enabled;

  /// Called when the parent toggle is tapped.
  final VoidCallback onToggle;

  /// Gates all interaction — false when push is globally off or prefs are
  /// still loading.
  final bool interactive;

  final bool classical;
  final VoidCallback onClassical;
  final bool rapid;
  final VoidCallback onRapid;
  final bool blitz;
  final VoidCallback onBlitz;

  @override
  Widget build(BuildContext context) {
    final chipInteractive = interactive && enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Parent row ──────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.textMdMedium.copyWith(
                  color: interactive ? kWhiteColor : kWhiteColor70,
                  fontSize: 13.f,
                ),
              ),
            ),
            Switch.adaptive(
              value: enabled,
              thumbColor: WidgetStatePropertyAll(kPrimaryColor),
              trackColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.selected)
                        ? kPrimaryColor.withValues(alpha: 0.35)
                        : kDividerColor.withValues(alpha: 0.5),
              ),
              onChanged: interactive ? (_) => onToggle() : null,
            ),
          ],
        ),

        // ── Sub-filter chips — animated, only shown when parent is ON ───────
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: enabled
              ? Padding(
                  padding: EdgeInsets.only(top: 10.h, left: 2.sp),
                  child: Wrap(
                    spacing: 8.sp,
                    runSpacing: 8.sp,
                    children: [
                      NotifFilterChip(
                        label: 'Classical',
                        selected: classical,
                        onTap: onClassical,
                        enabled: chipInteractive,
                      ),
                      NotifFilterChip(
                        label: 'Rapid',
                        selected: rapid,
                        onTap: onRapid,
                        enabled: chipInteractive,
                      ),
                      NotifFilterChip(
                        label: 'Blitz',
                        selected: blitz,
                        onTap: onBlitz,
                        enabled: chipInteractive,
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

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/notification_settings/notif_category_tile.dart';
import 'package:flutter/material.dart';

/// The top Push Notifications card.
///
/// When [enabled] is true the card expands to reveal two independent category
/// rows, each with its own Classical / Rapid / Blitz sub-filter chips:
///   • Favorite Players  → [fpClassical] [fpRapid] [fpBlitz]
///   • Starred Events    → [seClassical] [seRapid] [seBlitz]
///
/// All state and callbacks are passed in — this widget is fully stateless.
class NotifPushCard extends StatelessWidget {
  const NotifPushCard({
    super.key,
    // Master push toggle
    required this.enabled,
    required this.onChanged,
    // Global gate — false while push is off or prefs are loading
    required this.interactive,
    // Favourite Players category
    required this.fpEnabled,
    required this.onFpToggle,
    required this.fpClassical,
    required this.onFpClassical,
    required this.fpRapid,
    required this.onFpRapid,
    required this.fpBlitz,
    required this.onFpBlitz,
    // Starred Events category
    required this.seEnabled,
    required this.onSeToggle,
    required this.seClassical,
    required this.onSeClassical,
    required this.seRapid,
    required this.onSeRapid,
    required this.seBlitz,
    required this.onSeBlitz,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool interactive;

  // Favourite Players
  final bool fpEnabled;
  final VoidCallback onFpToggle;
  final bool fpClassical;
  final VoidCallback onFpClassical;
  final bool fpRapid;
  final VoidCallback onFpRapid;
  final bool fpBlitz;
  final VoidCallback onFpBlitz;

  // Starred Events
  final bool seEnabled;
  final VoidCallback onSeToggle;
  final bool seClassical;
  final VoidCallback onSeClassical;
  final bool seRapid;
  final VoidCallback onSeRapid;
  final bool seBlitz;
  final VoidCallback onSeBlitz;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 14.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kDividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Master toggle row ─────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Push Notifications',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Enable alerts for game starts, finishes, and live updates.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textPrimaryMuted,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
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
                onChanged: onChanged,
              ),
            ],
          ),

          // ── Category rows — only visible when push is enabled ─────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child:
                enabled
                    ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 16.h),

                        // Favourite Players
                        NotifCategoryTile(
                          label: 'Favorite Players',
                          enabled: fpEnabled,
                          onToggle: onFpToggle,
                          interactive: interactive,
                          classical: fpClassical,
                          onClassical: onFpClassical,
                          rapid: fpRapid,
                          onRapid: onFpRapid,
                          blitz: fpBlitz,
                          onBlitz: onFpBlitz,
                        ),

                        SizedBox(height: 14.h),
                        Divider(
                          color: kDividerColor.withValues(alpha: 0.3),
                          height: 1,
                        ),
                        SizedBox(height: 14.h),

                        // Starred Events
                        NotifCategoryTile(
                          label: 'Starred Events',
                          enabled: seEnabled,
                          onToggle: onSeToggle,
                          interactive: interactive,
                          classical: seClassical,
                          onClassical: onSeClassical,
                          rapid: seRapid,
                          onRapid: onSeRapid,
                          blitz: seBlitz,
                          onBlitz: onSeBlitz,
                        ),
                      ],
                    )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

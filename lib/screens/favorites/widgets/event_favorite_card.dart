import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../utils/app_typography.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/responsive_helper.dart';
import '../../../screens/group_event/model/tour_event_card_model.dart';
import '../../../screens/tour_detail/provider/tour_detail_mode_provider.dart';
import '../../../repository/supabase/group_broadcast/group_broadcast.dart';
import '../../../widgets/alert_dialog/alert_modal.dart';
import '../../../widgets/event_card/event_context_menu.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';

class EventFavoriteCard extends ConsumerWidget {
  final Map<String, dynamic> eventData;
  final VoidCallback? onRemoveFavorite;

  const EventFavoriteCard({
    super.key,
    required this.eventData,
    this.onRemoveFavorite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = eventData['title'] as String? ?? 'Unknown Event';
    final timeControl = eventData['timeControl'] as String? ?? '';
    final maxAvgElo = eventData['maxAvgElo'] as int? ?? 0;
    final dates = eventData['dates'] as String? ?? '';

    return Dismissible(
      key: Key(eventData['id']?.toString() ?? title),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: kRedColor,
          borderRadius: BorderRadius.circular(8.br),
        ),
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20.sp),
        child: Icon(
          Icons.delete_outline,
          color: context.colors.textPrimary,
          size: 24.ic,
        ),
      ),
      confirmDismiss: (direction) async {
        final allowed = await requireFullAuthGuard(context);
        if (!allowed) return false;
        if (!context.mounted) return false;

        HapticFeedback.mediumImpact();
        return await _showDeleteConfirmation(context, title);
      },
      onDismissed: (direction) {
        if (onRemoveFavorite != null) {
          onRemoveFavorite!();
        }
      },
      child: GestureDetector(
        onTap: () => _navigateToEvent(context, ref),
        onLongPressStart: (details) {
          onEventCardLongPress(
            context: context,
            ref: ref,
            model: _asCardModel(),
            globalPosition: details.globalPosition,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(8.br),
          ),
          padding: EdgeInsets.all(16.sp),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Event title
                    Text(
                      title,
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    SizedBox(height: 8.h),

                    // Event details
                    Row(
                      children: [
                        // Date
                        if (dates.isNotEmpty) ...[
                          Icon(
                            Icons.calendar_today,
                            size: 14.ic,
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          SizedBox(width: 4.w),
                          Text(
                            dates,
                            style: AppTypography.textSmRegular.copyWith(
                              color: context.colors.textPrimary.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],

                        // Time control
                        if (timeControl.isNotEmpty) ...[
                          if (dates.isNotEmpty) ...[
                            SizedBox(width: 8.w),
                            Container(
                              width: 4.w,
                              height: 4.h,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: context.colors.textPrimary.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            SizedBox(width: 8.w),
                          ],
                          _buildTimeControlIcon(context, timeControl),
                          SizedBox(width: 4.w),
                          Text(
                            timeControl,
                            style: AppTypography.textSmRegular.copyWith(
                              color: context.colors.textPrimary.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Average ELO
                    if (maxAvgElo > 0) ...[
                      SizedBox(height: 4.h),
                      Row(
                        children: [
                          Icon(
                            Icons.trending_up,
                            size: 14.ic,
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          SizedBox(width: 4.w),
                          Text(
                            'Avg ELO: $maxAvgElo',
                            style: AppTypography.textSmRegular.copyWith(
                              color: context.colors.textPrimary.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Remove favorite button
              GestureDetector(
                onTap: () async {
                  final allowed = await requireFullAuthGuard(context);
                  if (!allowed) return;
                  onRemoveFavorite?.call();
                },
                child: Container(
                  padding: EdgeInsets.all(8.sp),
                  child: Icon(Icons.star, size: 20.ic, color: kPrimaryColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToEvent(BuildContext context, WidgetRef ref) async {
    try {
      final eventId = eventData['id'] as String?;
      if (eventId == null) return;

      // Create a GroupBroadcast object from the event data
      final groupBroadcast = GroupBroadcast(
        id: eventId,
        createdAt: DateTime.now(),
        name: eventData['title'] as String? ?? 'Unknown Event',
        search: [eventData['title'] as String? ?? 'Unknown Event'],
        timeControl: eventData['timeControl'] as String?,
        maxAvgElo: eventData['maxAvgElo'] as int?,
        dateStart: null, // Could parse from eventData if needed
        dateEnd: null, // Could parse from eventData if needed
      );

      // Set the selected broadcast model
      ref.read(selectedBroadcastModelProvider.notifier).state = groupBroadcast;

      // Navigate to tournament detail screen
      if (context.mounted && ref.read(selectedBroadcastModelProvider) != null) {
        Navigator.pushNamed(context, '/tournament_detail_screen');
      }
    } catch (e) {
      // Handle navigation error silently
    }
  }

  GroupEventCardModel _asCardModel() {
    return GroupEventCardModel(
      id: eventData['id']?.toString() ?? '',
      title: eventData['title'] as String? ?? 'Unknown Event',
      dates: eventData['dates'] as String? ?? '',
      maxAvgElo: eventData['maxAvgElo'] as int? ?? 0,
      timeUntilStart: '',
      tourEventCategory: TourEventCategory.ongoing,
      timeControl: eventData['timeControl'] as String? ?? '',
      endDate: null,
      startDate: null,
    );
  }

  Future<bool?> _showDeleteConfirmation(
    BuildContext context,
    String eventTitle,
  ) {
    return showSmoothConfirmDialog(
      context: context,
      title: 'Remove from favorites?',
      message:
          'Are you sure you want to remove $eventTitle from your favorites?',
      confirmText: 'Remove',
      isDangerous: true,
    );
  }

  Widget _buildTimeControlIcon(BuildContext context, String timeControl) {
    final lowerTimeControl = timeControl.toLowerCase();
    String? assetPath;

    if (lowerTimeControl.contains('blitz')) {
      assetPath = 'assets/pngs/blitz.png';
    } else if (lowerTimeControl.contains('rapid')) {
      assetPath = 'assets/pngs/rapid.png';
    } else if (lowerTimeControl.contains('classic') ||
        lowerTimeControl.contains('standard')) {
      assetPath = 'assets/pngs/classical.png';
    } else {
      // Fallback to timer icon for unknown time controls
      return Icon(
        Icons.timer,
        size: 14.ic,
        color: context.colors.textPrimary.withValues(alpha: 0.7),
      );
    }

    return Image.asset(
      assetPath,
      width: 14.ic,
      height: 14.ic,
      fit: BoxFit.contain,
    );
  }
}

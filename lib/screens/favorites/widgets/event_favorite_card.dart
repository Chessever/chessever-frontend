import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../utils/app_typography.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/responsive_helper.dart';
import '../../../screens/tour_detail/provider/tour_detail_mode_provider.dart';
import '../../../repository/supabase/group_broadcast/group_broadcast.dart';

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
          color: kWhiteColor,
          size: 24.ic,
        ),
      ),
      confirmDismiss: (direction) async {
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
          HapticFeedback.lightImpact();
          _showContextMenu(context, details.globalPosition, title);
        },
        child: Container(
        decoration: BoxDecoration(
          color: kBlack2Color,
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
                    color: kWhiteColor,
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
                        color: kWhiteColor.withValues(alpha: 0.7),
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        dates,
                        style: AppTypography.textSmRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.7),
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
                            color: kWhiteColor.withValues(alpha: 0.5),
                          ),
                        ),
                        SizedBox(width: 8.w),
                      ],
                      _buildTimeControlIcon(timeControl),
                      SizedBox(width: 4.w),
                      Text(
                        timeControl,
                        style: AppTypography.textSmRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.7),
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
                        color: kWhiteColor.withValues(alpha: 0.7),
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        'Avg ELO: $maxAvgElo',
                        style: AppTypography.textSmRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.7),
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
            onTap: onRemoveFavorite,
            child: Container(
              padding: EdgeInsets.all(8.sp),
              child: Icon(
                Icons.star,
                size: 20.ic,
                color: kPrimaryColor,
              ),
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
        dateEnd: null,   // Could parse from eventData if needed
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

  void _showContextMenu(BuildContext context, Offset position, String eventTitle) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: kBlack2Color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.br),
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: kRedColor,
                size: 20.ic,
              ),
              SizedBox(width: 12.w),
              Text(
                'Remove from favorites',
                style: AppTypography.textSmRegular.copyWith(
                  color: kRedColor,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        _showDeleteConfirmation(context, eventTitle).then((confirmed) {
          if (confirmed == true && onRemoveFavorite != null) {
            HapticFeedback.mediumImpact();
            onRemoveFavorite!();
          }
        });
      }
    });
  }

  Future<bool?> _showDeleteConfirmation(BuildContext context, String eventTitle) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: kBlack2Color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.br),
          ),
          title: Text(
            'Remove from favorites?',
            style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
          ),
          content: Text(
            'Are you sure you want to remove $eventTitle from your favorites?',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.7),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Remove',
                style: AppTypography.textSmMedium.copyWith(color: kRedColor),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimeControlIcon(String timeControl) {
    final lowerTimeControl = timeControl.toLowerCase();
    IconData icon;
    Color iconColor;

    if (lowerTimeControl.contains('blitz')) {
      icon = Icons.bolt;
      iconColor = kRedColor;
    } else if (lowerTimeControl.contains('rapid')) {
      icon = Icons.flash_on;
      iconColor = Colors.orange;
    } else if (lowerTimeControl.contains('classic') || lowerTimeControl.contains('standard')) {
      icon = Icons.access_time;
      iconColor = kWhiteColor;
    } else {
      icon = Icons.timer;
      iconColor = kWhiteColor.withValues(alpha: 0.7);
    }

    return Icon(
      icon,
      size: 14.ic,
      color: iconColor,
    );
  }
}
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart'
    show SpacePlateArt;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/hub_tile.dart' show hubGutter;
import 'package:flutter/material.dart';

/// A Discovery destination in the existing compact event-card frame. Its
/// name and today's count live inside the card, without a separate heading.
class DiscoveryEventCard extends StatelessWidget {
  const DiscoveryEventCard({
    super.key,
    required this.title,
    required this.caption,
    required this.artSection,
    required this.onOpen,
    this.count,
    this.countQualifier,
    this.onRetry,
    this.centerContent = false,
  });

  final bool centerContent;
  final String title;
  final String caption;
  final SpaceSection artSection;
  final VoidCallback onOpen;
  final int? count;
  final String? countQualifier;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final imageWidth = MediaQuery.sizeOf(context).width < 360
        ? 108.w.clamp(70.0, 90.0)
        : 108.w;
    final imageHeight = imageWidth * 4 / 5;
    final countText = count == null
        ? null
        : '$count ${countQualifier == null ? '' : '$countQualifier '}'
              '${count == 1 ? 'game' : 'games'} today';
    final label = [title, ?countText, caption].join(', ');

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hubGutter),
      child: Semantics(
        button: true,
        label: label,
        onTap: onOpen,
        child: TappableScale(
          onTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8.br),
            ),
            padding: EdgeInsets.all(6.sp),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: imageHeight),
              child: Row(
                crossAxisAlignment: centerContent
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: SizedBox(
                      width: imageWidth,
                      height: imageHeight,
                      child: SpacePlateArt(section: artSection),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: centerContent ? 0 : 8.h,
                      ),
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.textSmMedium.copyWith(
                                color: colors.textPrimary,
                                height: 1.2,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            if (countText != null) ...[
                              Text(
                                countText,
                                style: AppTypography.textXsMedium.copyWith(
                                  color: colors.textPrimaryMuted,
                                ),
                              ),
                              SizedBox(height: 3.h),
                            ],
                            Text(
                              caption,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.textXsRegular.copyWith(
                                color: colors.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (onRetry != null)
                    IconButton(
                      tooltip: 'Retry $title',
                      onPressed: onRetry,
                      icon: Icon(
                        Icons.refresh_rounded,
                        size: 20.ic,
                        color: colors.iconSecondary,
                      ),
                    )
                  else
                    ExcludeSemantics(
                      child: SizedBox(
                        width: centerContent ? 28.w : 32,
                        height: imageHeight,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 20.ic,
                          color: colors.iconSecondary,
                        ),
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

import 'dart:math' as math;

import 'package:chessever2/screens/my_space/providers/my_space_content_providers.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Opaque, directly actionable content card used by every My Space rail.
class MySpaceEntityCard extends StatelessWidget {
  const MySpaceEntityCard({
    required this.item,
    required this.onPressed,
    super.key,
    this.width,
    this.height,
  });

  final MySpaceContentItem item;
  final VoidCallback? onPressed;
  final double? width;
  final double? height;

  static double preferredWidth(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - 52;
    return math.max(148, math.min(260, available));
  }

  /// Dynamic Type gets real vertical space instead of shrinking text or
  /// allowing the primary action to fall out of the card.
  static double preferredHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final scale = scaler.scale(16) / 16;
    return 300 + math.max(0, scale - 1) * 190;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    final cardWidth = width ?? preferredWidth(context);
    final cardHeight = height ?? preferredHeight(context);
    final enabled = onPressed != null && !item.isUnavailable;

    return Semantics(
      container: true,
      button: enabled,
      enabled: enabled,
      label: item.semanticLabel,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: context.colors.shadow,
                blurRadius: context.isLightTheme ? 16 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: context.colors.surface,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 104, child: _thumbnail(context)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.semanticEntityType,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium?.copyWith(
                                      color: context.colors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (item.isLocked)
                                  Icon(
                                    Icons.lock_rounded,
                                    color: context.colors.brand,
                                    size: 18,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Flexible(
                                    flex: 3,
                                    child: Text(
                                      item.title,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium?.copyWith(
                                        color: context.colors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        height: 1.15,
                                      ),
                                    ),
                                  ),
                                  if (item.subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Flexible(
                                      flex: 2,
                                      child: Text(
                                        item.subtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.copyWith(
                                          color: context.colors.textSecondary,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (item.status case final status?) ...[
                                    const SizedBox(height: 4),
                                    Flexible(
                                      child: Text(
                                        status,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall?.copyWith(
                                          color:
                                              item.isUnavailable
                                                  ? context.colors.danger
                                                  : item.isLocked
                                                  ? context.colors.brandMuted
                                                  : context.colors.textTertiary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.actionLabel,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge?.copyWith(
                                        color:
                                            enabled
                                                ? context.colors.brandMuted
                                                : context.colors.textTertiary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    enabled
                                        ? Icons.arrow_forward_rounded
                                        : Icons.block_rounded,
                                    color:
                                        enabled
                                            ? context.colors.brandMuted
                                            : context.colors.iconSecondary,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnail(BuildContext context) {
    final placeholder = _DeterministicPlaceholder(item: item);
    final imageUrl = item.imageUrl?.trim();

    return Stack(
      fit: StackFit.expand,
      children: [
        placeholder,
        if (imageUrl != null && imageUrl.isNotEmpty)
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return placeholder;
            },
            errorBuilder: (context, error, stackTrace) => placeholder,
          ),
        if (item.isLocked || item.isUnavailable)
          Positioned(
            top: 10,
            right: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.surfaceElevated,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: context.colors.divider),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.isLocked ? Icons.lock_rounded : Icons.info_outline,
                      color:
                          item.isLocked
                              ? context.colors.brand
                              : context.colors.danger,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.isLocked ? 'Premium' : 'Unavailable',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DeterministicPlaceholder extends StatelessWidget {
  const _DeterministicPlaceholder({required this.item});

  final MySpaceContentItem item;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.kind) {
      MySpaceEntityKind.analysis => Icons.analytics_outlined,
      MySpaceEntityKind.event => Icons.emoji_events_outlined,
      MySpaceEntityKind.database => Icons.storage_rounded,
      MySpaceEntityKind.folder => Icons.folder_outlined,
      MySpaceEntityKind.player => Icons.person_outline_rounded,
      MySpaceEntityKind.unavailable => Icons.link_off_rounded,
    };

    return ColoredBox(
      color: context.colors.surfaceRecessed,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: context.colors.divider),
          ),
          child: SizedBox.square(
            dimension: 54,
            child: Icon(
              icon,
              color:
                  item.isUnavailable
                      ? context.colors.dangerMuted
                      : context.colors.brandMuted,
              size: 27,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:chessever2/screens/my_space/domain/my_space_layout.dart';
import 'package:chessever2/screens/my_space/domain/my_space_shelf_state.dart';
import 'package:chessever2/screens/my_space/providers/my_space_content_providers.dart';
import 'package:chessever2/screens/my_space/widgets/my_space_entity_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:flutter/material.dart';

/// One independently resolved horizontal My Space rail.
class MySpaceShelf extends StatefulWidget {
  const MySpaceShelf({
    required this.descriptor,
    required this.title,
    required this.emptyDescription,
    required this.emptyActionLabel,
    required this.state,
    required this.onItemPressed,
    required this.onEmptyAction,
    super.key,
    this.onRetry,
  });

  final MySpaceShelfDescriptor descriptor;
  final String title;
  final String emptyDescription;
  final String emptyActionLabel;
  final MySpaceContentShelfState state;
  final ValueChanged<MySpaceContentItem> onItemPressed;
  final VoidCallback onEmptyAction;
  final VoidCallback? onRetry;

  @override
  State<MySpaceShelf> createState() => _MySpaceShelfState();
}

class _MySpaceShelfState extends State<MySpaceShelf> {
  late ScrollController _railController;

  @override
  void initState() {
    super.initState();
    _railController = ScrollController(keepScrollOffset: true);
  }

  @override
  void didUpdateWidget(covariant MySpaceShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.descriptor.id != widget.descriptor.id) {
      _railController.dispose();
      _railController = ScrollController(keepScrollOffset: true);
    }
  }

  @override
  void dispose() {
    _railController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = GlassMotion.resolveDuration(
      context,
      const Duration(milliseconds: 180),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShelfHeader(title: widget.title, count: _itemCount(widget.state)),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(
              key: ValueKey<Object>(_stateKey(widget.state)),
              child: _buildState(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildState(BuildContext context) {
    return switch (widget.state) {
      MySpaceShelfLoading<List<MySpaceContentItem>>() => _ShelfLoading(
        title: widget.title,
      ),
      MySpaceShelfData<List<MySpaceContentItem>>(:final data) =>
        data.isEmpty ? _empty() : _rail(data),
      MySpaceShelfPartial<List<MySpaceContentItem>>(:final data) =>
        data.isEmpty
            ? _error()
            : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _rail(data),
                const SizedBox(height: 8),
                _ShelfNotice(
                  icon: Icons.info_outline_rounded,
                  label: 'Some ${widget.title.toLowerCase()} could not load.',
                ),
              ],
            ),
      MySpaceShelfEmpty<List<MySpaceContentItem>>() => _empty(),
      MySpaceShelfError<List<MySpaceContentItem>>() => _error(),
      MySpaceShelfUnauthorized<List<MySpaceContentItem>>() =>
        _CompactShelfState(
          icon: Icons.lock_outline_rounded,
          title: '${widget.title} needs access',
          message: 'Sign in or unlock the source to use this shelf.',
          actionLabel: widget.emptyActionLabel,
          onAction: widget.onEmptyAction,
        ),
      MySpaceShelfRemoved<List<MySpaceContentItem>>() => _CompactShelfState(
        icon: Icons.link_off_rounded,
        title: '${widget.title} is unavailable',
        message: 'The source item was removed or is no longer available.',
        actionLabel: widget.emptyActionLabel,
        onAction: widget.onEmptyAction,
      ),
      MySpaceShelfOfflineWithCache<List<MySpaceContentItem>>(:final data) =>
        data.isEmpty
            ? _offline()
            : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _rail(data),
                const SizedBox(height: 8),
                const _ShelfNotice(
                  icon: Icons.cloud_off_outlined,
                  label: 'Showing saved offline content.',
                ),
              ],
            ),
      MySpaceShelfOfflineWithoutCache<List<MySpaceContentItem>>() => _offline(),
    };
  }

  Widget _rail(List<MySpaceContentItem> items) {
    final cardHeight = MySpaceEntityCard.preferredHeight(context);
    final cardWidth = MySpaceEntityCard.preferredWidth(context);
    return Semantics(
      container: true,
      label: '${widget.title}, ${items.length} items, horizontal list',
      child: SizedBox(
        height: cardHeight,
        child: ListView.separated(
          key: PageStorageKey<String>('my-space-rail-${widget.descriptor.id}'),
          controller: _railController,
          scrollDirection: Axis.horizontal,
          primary: false,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final item = items[index];
            return MySpaceEntityCard(
              key: ValueKey<String>('my-space-card-${item.id}'),
              item: item,
              width: cardWidth,
              height: cardHeight,
              onPressed:
                  item.isUnavailable ? null : () => widget.onItemPressed(item),
            );
          },
        ),
      ),
    );
  }

  Widget _empty() => _CompactShelfState(
    icon: _emptyIcon(widget.descriptor.type),
    title: '${widget.title} is ready when you are',
    message: widget.emptyDescription,
    actionLabel: widget.emptyActionLabel,
    onAction: widget.onEmptyAction,
  );

  Widget _error() => _CompactShelfState(
    icon: Icons.refresh_rounded,
    title: '${widget.title} could not load',
    message:
        'This shelf had a problem. Your other shelves are still available.',
    actionLabel: 'Retry',
    onAction: widget.onRetry,
  );

  Widget _offline() => _CompactShelfState(
    icon: Icons.cloud_off_outlined,
    title: '${widget.title} is offline',
    message: 'Reconnect to load this shelf.',
    actionLabel: 'Retry',
    onAction: widget.onRetry,
  );
}

class _ShelfHeader extends StatelessWidget {
  const _ShelfHeader({required this.title, required this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (count case final value?) ...[
            const SizedBox(width: 8),
            Semantics(
              label: '$value items',
              child: ExcludeSemantics(
                child: Text(
                  '$value',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: context.colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShelfLoading extends StatelessWidget {
  const _ShelfLoading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cardHeight = MySpaceEntityCard.preferredHeight(context);
    final cardWidth = MySpaceEntityCard.preferredWidth(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title loading',
      child: ExcludeSemantics(
        child: SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 3,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder:
                (context, index) => Container(
                  width: cardWidth,
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.colors.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 104, color: context.colors.skeleton),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SkeletonLine(width: cardWidth * 0.42),
                            const SizedBox(height: 12),
                            _SkeletonLine(width: cardWidth * 0.7, height: 18),
                            const SizedBox(height: 8),
                            _SkeletonLine(width: cardWidth * 0.54),
                          ],
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

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width, this.height = 12});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.skeleton,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _CompactShelfState extends StatelessWidget {
  const _CompactShelfState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final stackAction =
        MediaQuery.sizeOf(context).width < 360 || textScale > 1.3;
    final copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.colors.textSecondary,
            height: 1.25,
          ),
        ),
      ],
    );
    final action = TextButton(
      onPressed: onAction,
      style: TextButton.styleFrom(
        foregroundColor: context.colors.brandMuted,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: Text(
        actionLabel,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );

    return Semantics(
      container: true,
      label: '$title. $message',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 104),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.colors.divider),
            ),
            child:
                stackAction
                    ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _StateIcon(icon: icon),
                            const SizedBox(width: 12),
                            Expanded(child: copy),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Align(alignment: Alignment.centerRight, child: action),
                      ],
                    )
                    : Row(
                      children: [
                        _StateIcon(icon: icon),
                        const SizedBox(width: 12),
                        Expanded(child: copy),
                        const SizedBox(width: 8),
                        action,
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: context.colors.brandMuted, size: 24),
    );
  }
}

class _ShelfNotice extends StatelessWidget {
  const _ShelfNotice({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.surfaceRecessed,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: context.colors.iconSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.colors.textSecondary,
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

int? _itemCount(MySpaceContentShelfState state) => switch (state) {
  MySpaceShelfData<List<MySpaceContentItem>>(:final data) => data.length,
  MySpaceShelfPartial<List<MySpaceContentItem>>(:final data) => data.length,
  MySpaceShelfOfflineWithCache<List<MySpaceContentItem>>(:final data) =>
    data.length,
  _ => null,
};

Object _stateKey(MySpaceContentShelfState state) => switch (state) {
  MySpaceShelfData<List<MySpaceContentItem>>(:final data) => (
    'data',
    data.length,
  ),
  MySpaceShelfPartial<List<MySpaceContentItem>>(:final data) => (
    'partial',
    data.length,
  ),
  MySpaceShelfOfflineWithCache<List<MySpaceContentItem>>(:final data) => (
    'offline-cache',
    data.length,
  ),
  _ => state.runtimeType,
};

IconData _emptyIcon(MySpaceShelfType type) {
  if (type == MySpaceShelfType.continueShelf) return Icons.play_arrow_rounded;
  if (type == MySpaceShelfType.myLikes) return Icons.favorite_outline_rounded;
  if (type == MySpaceShelfType.savedEvents) {
    return Icons.emoji_events_outlined;
  }
  if (type == MySpaceShelfType.databases) return Icons.storage_rounded;
  if (type == MySpaceShelfType.savedStudies) return Icons.menu_book_outlined;
  if (type == MySpaceShelfType.favoritePlayers) {
    return Icons.people_outline_rounded;
  }
  return Icons.collections_bookmark_outlined;
}

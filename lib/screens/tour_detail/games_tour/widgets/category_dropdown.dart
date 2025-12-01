import 'dart:ui';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A beautiful stadium-chip style category dropdown with glass morphism effects
/// and smooth spring animations for selecting tournament categories.
class CategoryDropdown extends ConsumerWidget {
  const CategoryDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 38.h,
      child: ref.watch(tourDetailScreenProvider).when(
        data: (data) {
          if (data.tours.isEmpty) {
            return const SizedBox.shrink();
          }

          // Find selected tour
          final selectedTour = data.tours.firstWhere(
            (t) => t.tour.id == data.aboutTourModel.id,
            orElse: () => data.tours.first,
          );

          return _CategoryDropdownContent(
            categories: data.tours,
            selectedCategory: selectedTour,
            onChanged: (category) {
              ref
                  .read(tourDetailScreenProvider.notifier)
                  .updateSelection(category.tour.id);
            },
          );
        },
        error: (e, _) => Center(
          child: Text(
            'Error',
            style: AppTypography.textXsRegular.copyWith(color: kWhiteColor70),
          ),
        ),
        loading: () => SkeletonWidget(
          child: _StadiumChipButton(
            label: 'Loading...',
            isOpen: false,
            onTap: () {},
            showChevron: false,
          ),
        ),
      ),
    );
  }
}

class _CategoryDropdownContent extends HookConsumerWidget {
  final List<TourModel> categories;
  final TourModel selectedCategory;
  final ValueChanged<TourModel> onChanged;

  const _CategoryDropdownContent({
    required this.categories,
    required this.selectedCategory,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layerLink = useMemoized(() => LayerLink());
    final isOpen = useState(false);
    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 350),
    );

    // Spring-like curve for natural feel
    final animation = useMemoized(
      () => CurvedAnimation(
        parent: animationController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInQuart,
      ),
      [animationController],
    );

    useEffect(() {
      return () {
        if (isOpen.value) {
          isOpen.value = false;
        }
      };
    }, []);

    void openDropdown() {
      if (categories.length <= 1) return;

      HapticFeedbackService.selection();
      isOpen.value = true;
      animationController.forward();

      _showOverlay(
        context: context,
        layerLink: layerLink,
        isOpen: isOpen,
        animationController: animationController,
        animation: animation,
      );
    }

    void closeDropdown() {
      animationController.reverse().then((_) {
        if (isOpen.value) {
          isOpen.value = false;
        }
      });
    }

    return CompositedTransformTarget(
      link: layerLink,
      child: _StadiumChipButton(
        label: _extractCategoryName(selectedCategory.tour.name),
        status: selectedCategory.roundStatus,
        isOpen: isOpen.value,
        showChevron: categories.length > 1,
        onTap: () {
          if (isOpen.value) {
            closeDropdown();
          } else {
            openDropdown();
          }
        },
      ),
    );
  }

  void _showOverlay({
    required BuildContext context,
    required LayerLink layerLink,
    required ValueNotifier<bool> isOpen,
    required AnimationController animationController,
    required Animation<double> animation,
  }) {
    OverlayEntry? overlayEntry;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        isOpen.value = false;
        return;
      }

      final overlay = Overlay.of(context);
      final renderBox = context.findRenderObject() as RenderBox?;

      if (renderBox == null) {
        isOpen.value = false;
        return;
      }

      final size = renderBox.size;
      final offset = renderBox.localToGlobal(Offset.zero);
      final screenHeight = MediaQuery.of(context).size.height;
      final availableHeight = screenHeight - offset.dy - size.height - 32.sp;

      overlayEntry = OverlayEntry(
        builder: (context) => _DropdownOverlay(
          layerLink: layerLink,
          triggerSize: size,
          triggerOffset: offset,
          availableHeight: availableHeight,
          animation: animation,
          categories: categories,
          selectedCategory: selectedCategory,
          onSelect: (category) {
            HapticFeedbackService.selection();
            if (category.tour.id != selectedCategory.tour.id) {
              onChanged(category);
            }
            animationController.reverse().then((_) {
              isOpen.value = false;
            });
          },
          onDismiss: () {
            animationController.reverse().then((_) {
              isOpen.value = false;
            });
          },
        ),
      );

      overlay.insert(overlayEntry!);

      void removeOverlay() {
        try {
          if (overlayEntry?.mounted == true) {
            overlayEntry?.remove();
          }
        } catch (e) {
          overlayEntry?.dispose();
        }
      }

      isOpen.addListener(removeOverlay);
    });
  }

  String _extractCategoryName(String fullName) {
    // Extract category name - often the part after "|" or the last meaningful segment
    if (fullName.contains('|')) {
      return fullName.split('|').last.trim();
    }
    if (fullName.contains(':')) {
      return fullName.split(':').last.trim();
    }
    if (fullName.contains('-')) {
      final parts = fullName.split('-');
      if (parts.length > 1 && parts.last.trim().length < 20) {
        return parts.last.trim();
      }
    }
    // If name is too long, try to shorten it
    if (fullName.length > 18) {
      return '${fullName.substring(0, 15)}...';
    }
    return fullName;
  }
}

/// Stadium-shaped chip button that triggers the dropdown
class _StadiumChipButton extends StatelessWidget {
  final String label;
  final RoundStatus? status;
  final bool isOpen;
  final bool showChevron;
  final VoidCallback onTap;

  const _StadiumChipButton({
    required this.label,
    this.status,
    required this.isOpen,
    required this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 8.sp),
        decoration: BoxDecoration(
          // Stadium shape (fully rounded ends)
          borderRadius: BorderRadius.circular(100.br),
          // Subtle gradient background
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isOpen
                ? [
                    kPrimaryColor.withValues(alpha: 0.2),
                    kPrimaryColor.withValues(alpha: 0.08),
                  ]
                : [
                    kWhiteColor.withValues(alpha: 0.08),
                    kWhiteColor.withValues(alpha: 0.04),
                  ],
          ),
          // Glowing border effect
          border: Border.all(
            color: isOpen
                ? kPrimaryColor.withValues(alpha: 0.5)
                : kWhiteColor.withValues(alpha: 0.15),
            width: 1.2,
          ),
          // Subtle shadow for depth
          boxShadow: isOpen
              ? [
                  BoxShadow(
                    color: kPrimaryColor.withValues(alpha: 0.2),
                    blurRadius: 12.sp,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status indicator dot
            if (status != null) ...[
              _StatusDot(status: status!),
              SizedBox(width: 8.sp),
            ],
            // Category label
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 120.w),
              child: Text(
                label,
                style: AppTypography.textXsMedium.copyWith(
                  color: isOpen ? kPrimaryColor : kWhiteColor,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Chevron
            if (showChevron) ...[
              SizedBox(width: 6.sp),
              AnimatedRotation(
                turns: isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: isOpen
                      ? kPrimaryColor
                      : kWhiteColor.withValues(alpha: 0.7),
                  size: 18.ic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated status indicator dot with glow effect
class _StatusDot extends StatelessWidget {
  final RoundStatus status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    final isLive = status == RoundStatus.live;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 8.sp,
      height: 8.sp,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: isLive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 8.sp,
                  spreadRadius: 2.sp,
                ),
              ]
            : null,
      ),
      child: isLive
          ? _PulsingDot(color: color)
          : null,
    );
  }

  Color _getStatusColor() {
    switch (status) {
      case RoundStatus.live:
        return kRedColor;
      case RoundStatus.ongoing:
        return kGreenColor2;
      case RoundStatus.upcoming:
        return kPrimaryColor;
      case RoundStatus.completed:
        return kWhiteColor70;
    }
  }
}

/// Pulsing animation for live status
class _PulsingDot extends HookWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 1200),
    );

    useEffect(() {
      controller.repeat();
      return controller.stop;
    }, [controller]);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 1 - controller.value * 0.5),
          ),
        );
      },
    );
  }
}

/// The floating dropdown overlay with glass morphism effect
class _DropdownOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final Size triggerSize;
  final Offset triggerOffset;
  final double availableHeight;
  final Animation<double> animation;
  final List<TourModel> categories;
  final TourModel selectedCategory;
  final ValueChanged<TourModel> onSelect;
  final VoidCallback onDismiss;

  const _DropdownOverlay({
    required this.layerLink,
    required this.triggerSize,
    required this.triggerOffset,
    required this.availableHeight,
    required this.animation,
    required this.categories,
    required this.selectedCategory,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onDismiss,
      child: Stack(
        children: [
          // Full screen dismiss area
          Positioned.fill(child: Container(color: Colors.transparent)),
          // Dropdown positioned relative to trigger
          Positioned(
            left: triggerOffset.dx - 20.w,
            top: triggerOffset.dy + triggerSize.height + 8.sp,
            child: CompositedTransformFollower(
              link: layerLink,
              showWhenUnlinked: false,
              offset: Offset(-20.w, triggerSize.height + 8.sp),
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.9 + (animation.value * 0.1),
                    alignment: Alignment.topCenter,
                    child: Opacity(
                      opacity: animation.value,
                      child: child,
                    ),
                  );
                },
                child: _DropdownContent(
                  availableHeight: availableHeight,
                  animation: animation,
                  categories: categories,
                  selectedCategory: selectedCategory,
                  onSelect: onSelect,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Glass morphism dropdown content
class _DropdownContent extends StatelessWidget {
  final double availableHeight;
  final Animation<double> animation;
  final List<TourModel> categories;
  final TourModel selectedCategory;
  final ValueChanged<TourModel> onSelect;

  const _DropdownContent({
    required this.availableHeight,
    required this.animation,
    required this.categories,
    required this.selectedCategory,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20.br),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: availableHeight.clamp(150.h, 320.h),
            minWidth: 200.w,
            maxWidth: 280.w,
          ),
          decoration: BoxDecoration(
            // Glass effect background
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kBlack2Color.withValues(alpha: 0.9),
                kBlack2Color.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(20.br),
            border: Border.all(
              color: kWhiteColor.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24.sp,
                offset: Offset(0, 8.sp),
              ),
            ],
          ),
          child: ListView.builder(
            padding: EdgeInsets.symmetric(vertical: 8.sp),
            shrinkWrap: true,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final isSelected = category.tour.id == selectedCategory.tour.id;

              return _AnimatedCategoryItem(
                index: index,
                animation: animation,
                category: category,
                isSelected: isSelected,
                onTap: () => onSelect(category),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Staggered animated category item
class _AnimatedCategoryItem extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final TourModel category;
  final bool isSelected;
  final VoidCallback onTap;

  const _AnimatedCategoryItem({
    required this.index,
    required this.animation,
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Staggered delay for each item
    final itemDelay = index * 0.08;
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.5),
        (itemDelay + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 10 * (1 - itemAnimation.value)),
          child: Opacity(
            opacity: itemAnimation.value,
            child: child,
          ),
        );
      },
      child: _CategoryItem(
        category: category,
        isSelected: isSelected,
        onTap: onTap,
      ),
    );
  }
}

/// Individual category item with hover/selection effects
class _CategoryItem extends StatefulWidget {
  final TourModel category;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryItem({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_CategoryItem> createState() => _CategoryItemState();
}

class _CategoryItemState extends State<_CategoryItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 2.sp),
        padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 12.sp),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.br),
          color: widget.isSelected
              ? kPrimaryColor.withValues(alpha: 0.15)
              : _isPressed
                  ? kWhiteColor.withValues(alpha: 0.05)
                  : Colors.transparent,
          border: widget.isSelected
              ? Border.all(
                  color: kPrimaryColor.withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          children: [
            // Status indicator
            _StatusDot(status: widget.category.roundStatus),
            SizedBox(width: 12.sp),
            // Category info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _extractDisplayName(widget.category.tour.name),
                    style: AppTypography.textSmMedium.copyWith(
                      color: widget.isSelected ? kPrimaryColor : kWhiteColor,
                      fontWeight: widget.isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.sp),
                  Text(
                    _getStatusText(widget.category.roundStatus),
                    style: AppTypography.textXxsRegular.copyWith(
                      color: _getStatusTextColor(widget.category.roundStatus),
                    ),
                  ),
                ],
              ),
            ),
            // Selection checkmark
            if (widget.isSelected)
              Container(
                width: 20.sp,
                height: 20.sp,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kPrimaryColor,
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: kWhiteColor,
                  size: 12.ic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _extractDisplayName(String fullName) {
    // Extract meaningful category name
    if (fullName.contains('|')) {
      return fullName.split('|').last.trim();
    }
    if (fullName.contains(':')) {
      return fullName.split(':').last.trim();
    }
    return fullName;
  }

  String _getStatusText(RoundStatus status) {
    switch (status) {
      case RoundStatus.live:
        return 'LIVE NOW';
      case RoundStatus.ongoing:
        return 'In progress';
      case RoundStatus.upcoming:
        return 'Coming soon';
      case RoundStatus.completed:
        return 'Completed';
    }
  }

  Color _getStatusTextColor(RoundStatus status) {
    switch (status) {
      case RoundStatus.live:
        return kRedColor;
      case RoundStatus.ongoing:
        return kGreenColor2;
      case RoundStatus.upcoming:
        return kPrimaryColor;
      case RoundStatus.completed:
        return kWhiteColor70;
    }
  }
}

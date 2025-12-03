import 'dart:async';
import 'dart:math' as math;
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:sprung/sprung.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/droplet_animation_curves.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// A beautiful stadium-chip style combo dropdown with glass morphism effects
/// combining Categories and Rounds in a side-by-side layout.
class CategoryDropdown extends ConsumerWidget {
  const CategoryDropdown({
    super.key,
    this.constrainWidth = true,
  });

  final bool constrainWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tourDetailAsync = ref.watch(tourDetailScreenProvider);
    final roundsAsync = ref.watch(gamesAppBarProvider);

    return SizedBox(
      height: 38.h,
      child: tourDetailAsync.when(
        data: (tourData) {
          if (tourData.tours.isEmpty) {
            return const SizedBox.shrink();
          }

          // Find selected tour/category
          final selectedTour = tourData.tours.firstWhere(
            (t) => t.tour.id == tourData.aboutTourModel.id,
            orElse: () => tourData.tours.first,
          );

          // Get rounds data
          final rounds = roundsAsync.valueOrNull?.gamesAppBarModels ?? [];
          final selectedRoundId = roundsAsync.valueOrNull?.selectedId;
          final selectedRound = rounds.isNotEmpty && selectedRoundId != null
              ? rounds.firstWhere(
                  (r) => r.id == selectedRoundId,
                  orElse: () => rounds.first,
                )
              : null;

          return _CategoryDropdownContent(
            categories: tourData.tours,
            selectedCategory: selectedTour,
            rounds: rounds,
            selectedRound: selectedRound,
            constrainWidth: constrainWidth,
            onCategoryChanged: (category) {
              ref
                  .read(tourDetailScreenProvider.notifier)
                  .updateSelection(category.tour.id);
            },
            onRoundChanged: (round) {
              ref.read(gamesAppBarProvider.notifier).select(round);
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
            constrainWidth: constrainWidth,
          ),
        ),
      ),
    );
  }
}

class _CategoryDropdownContent extends HookConsumerWidget {
  final List<TourModel> categories;
  final TourModel selectedCategory;
  final List<GamesAppBarModel> rounds;
  final GamesAppBarModel? selectedRound;
  final bool constrainWidth;
  final ValueChanged<TourModel> onCategoryChanged;
  final ValueChanged<GamesAppBarModel> onRoundChanged;

  const _CategoryDropdownContent({
    required this.categories,
    required this.selectedCategory,
    required this.rounds,
    required this.selectedRound,
    required this.constrainWidth,
    required this.onCategoryChanged,
    required this.onRoundChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layerLink = useMemoized(() => LayerLink());
    final isOpen = useState(false);
    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 200), // Faster for snappy feel
    );

    // Droplet-style spring curves for snappy, bubbly feel
    final animation = useMemoized(
      () => CurvedAnimation(
        parent: animationController,
        curve: DropletCurves.openPop,
        reverseCurve: DropletCurves.close,
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

    // Show dropdown if we have multiple categories OR multiple rounds
    final hasMultipleOptions = categories.length > 1 || rounds.length > 1;

    void openDropdown() {
      if (!hasMultipleOptions) return;

      HapticFeedbackService.selection();
      isOpen.value = true;
      animationController.forward();

      _showOverlay(
        context: context,
        layerLink: layerLink,
        isOpen: isOpen,
        animationController: animationController,
        animation: animation,
        ref: ref,
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
        status: selectedRound?.roundStatus ?? selectedCategory.roundStatus,
        isOpen: isOpen.value,
        showChevron: hasMultipleOptions,
        constrainWidth: constrainWidth,
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
    required WidgetRef ref,
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
      final screenSize = MediaQuery.of(context).size;
      final availableHeight = screenSize.height - offset.dy - size.height - 32.sp;

      overlayEntry = OverlayEntry(
        builder: (context) => _DropdownOverlay(
          layerLink: layerLink,
          triggerSize: size,
          triggerOffset: offset,
          screenWidth: screenSize.width,
          availableHeight: availableHeight,
          animation: animation,
          categories: categories,
          selectedCategory: selectedCategory,
          rounds: rounds,
          selectedRound: selectedRound,
          onCategorySelect: (category) {
            HapticFeedbackService.selection();
            if (category.tour.id != selectedCategory.tour.id) {
              onCategoryChanged(category);
            }
            // Menu stays open - close via button only
          },
          onRoundSelect: (round) {
            HapticFeedbackService.selection();
            onRoundChanged(round);
            // Menu stays open - close via button only
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
/// Features a subtle "fluid shimmer" animation hinting at long-press interaction
class _StadiumChipButton extends HookWidget {
  final String label;
  final RoundStatus? status;
  final bool isOpen;
  final bool showChevron;
  final bool constrainWidth;
  final VoidCallback onTap;

  const _StadiumChipButton({
    required this.label,
    this.status,
    required this.isOpen,
    required this.onTap,
    this.showChevron = true,
    this.constrainWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    // Shimmer animation that hints at long-press interactivity
    final shimmerController = useAnimationController(
      duration: const Duration(milliseconds: 3000),
    );

    // Start the shimmer loop when not open
    useEffect(() {
      if (!isOpen) {
        shimmerController.repeat();
      } else {
        shimmerController.stop();
      }
      return null;
    }, [isOpen]);

    final shimmerValue = useAnimation(shimmerController);

    final button = AnimatedBuilder(
      animation: shimmerController,
      builder: (context, child) {
        return CustomPaint(
          painter: isOpen ? null : _FluidShimmerPainter(
            progress: shimmerValue,
            shimmerColor: kPrimaryColor.withValues(alpha: 0.4),
            borderRadius: 100.br,
          ),
          child: child,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
        decoration: BoxDecoration(
          // Stadium shape (fully rounded ends)
          borderRadius: BorderRadius.circular(100.br),
          // Flat solid background
          color: isOpen
              ? kPrimaryColor.withValues(alpha: 0.15)
              : kWhiteColor.withValues(alpha: 0.06),
          // Clean border
          border: Border.all(
            color: isOpen
                ? kPrimaryColor.withValues(alpha: 0.4)
                : kWhiteColor.withValues(alpha: 0.12),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status indicator dot
            if (status == RoundStatus.live) ...[
              _StatusDot(status: status!),
              SizedBox(width: 8.sp),
            ],
            // Category label only
            Flexible(
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
                curve: Curves.easeOutCubic,
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

    return GestureDetector(
      onTap: onTap,
      child: constrainWidth
          ? ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 160.w),
              child: button,
            )
          : button,
    );
  }
}

/// Paints a subtle shimmer that travels around the stadium border
/// Creates a "fluid waiting" effect hinting at long-press interactivity
class _FluidShimmerPainter extends CustomPainter {
  final double progress;
  final Color shimmerColor;
  final double borderRadius;

  _FluidShimmerPainter({
    required this.progress,
    required this.shimmerColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Create a sweep gradient that travels around the border
    final sweepAngle = progress * 2 * math.pi;

    final gradient = SweepGradient(
      center: Alignment.center,
      startAngle: sweepAngle,
      endAngle: sweepAngle + math.pi * 0.5,
      colors: [
        shimmerColor.withValues(alpha: 0),
        shimmerColor,
        shimmerColor.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_FluidShimmerPainter oldDelegate) {
    return progress != oldDelegate.progress;
  }
}

/// Animated status indicator dot with glow effect
class _StatusDot extends StatelessWidget {
  final RoundStatus status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final isLive = status == RoundStatus.live;

    if (!isLive) {
      return const SizedBox.shrink();
    }

    final color = kPrimaryColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 8.sp,
      height: 8.sp,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        // Flat design - no glow/shadow
      ),
      child: isLive
          ? _PulsingDot(color: color)
          : null,
    );
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
/// Shows side-by-side Categories and Rounds columns
class _DropdownOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final Size triggerSize;
  final Offset triggerOffset;
  final double screenWidth;
  final double availableHeight;
  final Animation<double> animation;
  final List<TourModel> categories;
  final TourModel selectedCategory;
  final List<GamesAppBarModel> rounds;
  final GamesAppBarModel? selectedRound;
  final ValueChanged<TourModel> onCategorySelect;
  final ValueChanged<GamesAppBarModel> onRoundSelect;
  final VoidCallback onDismiss;

  const _DropdownOverlay({
    required this.layerLink,
    required this.triggerSize,
    required this.triggerOffset,
    required this.screenWidth,
    required this.availableHeight,
    required this.animation,
    required this.categories,
    required this.selectedCategory,
    required this.rounds,
    required this.selectedRound,
    required this.onCategorySelect,
    required this.onRoundSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate dropdown width based on content
    final dropdownWidth = (screenWidth - 32.w).clamp(280.w, 360.w);
    // Center the dropdown horizontally
    final leftOffset = (screenWidth - dropdownWidth) / 2;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onDismiss,
      child: Stack(
        children: [
          // Full screen dismiss area
          Positioned.fill(child: Container(color: Colors.transparent)),
          // Dropdown positioned centered
          Positioned(
            left: leftOffset,
            top: triggerOffset.dy + triggerSize.height + 8.sp,
            child: Material(
              type: MaterialType.transparency,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final progress = animation.value.clamp(0.0, 1.0);
                  return Transform.scale(
                    scale: 0.92 + (progress * 0.08),
                    alignment: Alignment.topCenter,
                    child: Opacity(
                      opacity: progress,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: dropdownWidth,
                  constraints: BoxConstraints(maxHeight: availableHeight.clamp(200.0, 400.0)),
                  decoration: BoxDecoration(
                    color: kBlack2Color.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16.br),
                    border: Border.all(
                      color: kPrimaryColor.withValues(alpha: 0.25),
                      width: 1.0,
                    ),
                  ),
                  child: _DropdownContent(
                    width: dropdownWidth,
                    availableHeight: availableHeight,
                    animation: animation,
                    categories: categories,
                    selectedCategory: selectedCategory,
                    rounds: rounds,
                    selectedRound: selectedRound,
                    onCategorySelect: onCategorySelect,
                    onRoundSelect: onRoundSelect,
                    onDismiss: onDismiss,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Glass morphism dropdown content with side-by-side Categories and Rounds
/// Tracks PENDING selections until user clicks Save
class _DropdownContent extends StatefulWidget {
  final double width;
  final double availableHeight;
  final Animation<double> animation;
  final List<TourModel> categories;
  final TourModel selectedCategory;
  final List<GamesAppBarModel> rounds;
  final GamesAppBarModel? selectedRound;
  final ValueChanged<TourModel> onCategorySelect;
  final ValueChanged<GamesAppBarModel> onRoundSelect;
  final VoidCallback onDismiss;

  const _DropdownContent({
    required this.width,
    required this.availableHeight,
    required this.animation,
    required this.categories,
    required this.selectedCategory,
    required this.rounds,
    required this.selectedRound,
    required this.onCategorySelect,
    required this.onRoundSelect,
    required this.onDismiss,
  });

  @override
  State<_DropdownContent> createState() => _DropdownContentState();
}

class _DropdownContentState extends State<_DropdownContent> {
  // Pending selections - not applied until Save
  late TourModel _pendingCategory;
  GamesAppBarModel? _pendingRound;

  @override
  void initState() {
    super.initState();
    _pendingCategory = widget.selectedCategory;
    _pendingRound = widget.selectedRound;
  }

  bool get _hasChanges {
    final categoryChanged = _pendingCategory.tour.id != widget.selectedCategory.tour.id;
    final roundChanged = _pendingRound?.id != widget.selectedRound?.id;
    return categoryChanged || roundChanged;
  }

  void _handleSave() {
    HapticFeedbackService.medium();

    // Apply pending selections
    if (_pendingCategory.tour.id != widget.selectedCategory.tour.id) {
      widget.onCategorySelect(_pendingCategory);
    }
    if (_pendingRound != null && _pendingRound?.id != widget.selectedRound?.id) {
      widget.onRoundSelect(_pendingRound!);
    }

    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final hasCategories = widget.categories.length > 1;
    final hasRounds = widget.rounds.isNotEmpty;

    // Note: Border, clipping, and background are handled by parent container
    return Container(
      width: widget.width,
      constraints: BoxConstraints(
        maxHeight: widget.availableHeight.clamp(200.h, 380.h),
      ),
      // Flat design - no blur, no gradient
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Save button
            Padding(
              padding: EdgeInsets.fromLTRB(16.sp, 12.sp, 12.sp, 4.sp),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Title hint
                  Text(
                    'Select',
                    style: AppTypography.textXsMedium.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.4),
                      letterSpacing: 0.5,
                    ),
                  ),
                  // Save button - flat design
                  GestureDetector(
                    onTap: _handleSave,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 8.sp),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20.br),
                        // Flat solid color - no gradient or shadow
                        color: _hasChanges
                            ? kPrimaryColor
                            : kWhiteColor.withValues(alpha: 0.08),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_rounded,
                            size: 16.ic,
                            color: _hasChanges
                                ? kWhiteColor
                                : kWhiteColor.withValues(alpha: 0.5),
                          ),
                          SizedBox(width: 4.sp),
                          Text(
                            'Save',
                            style: AppTypography.textXsMedium.copyWith(
                              color: _hasChanges
                                  ? kWhiteColor
                                  : kWhiteColor.withValues(alpha: 0.5),
                              fontWeight: _hasChanges ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content columns
            Flexible(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Categories Column
                  if (hasCategories)
                    Expanded(
                      child: _CategoriesColumn(
                        animation: widget.animation,
                        categories: widget.categories,
                        selectedCategory: _pendingCategory,
                        onSelect: (category) {
                          setState(() => _pendingCategory = category);
                        },
                      ),
                    ),
                  // Divider between columns
                  if (hasCategories && hasRounds)
                    Container(
                      width: 1,
                      color: kWhiteColor.withValues(alpha: 0.1),
                      margin: EdgeInsets.symmetric(vertical: 12.h),
                    ),
                  // Rounds Column
                  if (hasRounds)
                    Expanded(
                      child: _RoundsColumn(
                        animation: widget.animation,
                        rounds: widget.rounds,
                        selectedRound: _pendingRound,
                        onSelect: (round) {
                          setState(() => _pendingRound = round);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

/// Categories column with floating liquid selection indicator
class _CategoriesColumn extends StatefulWidget {
  final Animation<double> animation;
  final List<TourModel> categories;
  final TourModel selectedCategory;
  final ValueChanged<TourModel> onSelect;

  const _CategoriesColumn({
    required this.animation,
    required this.categories,
    required this.selectedCategory,
    required this.onSelect,
  });

  @override
  State<_CategoriesColumn> createState() => _CategoriesColumnState();
}

class _CategoriesColumnState extends State<_CategoriesColumn> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  final List<GlobalKey> _itemKeys = [];

  bool _isDragging = false;
  int _currentIndex = 0;
  Timer? _scrollTimer;

  // Target Y position for motor spring animation
  double _targetY = 0.0;

  // Measured dimensions - total item height (including margin) and selector height (excluding margin)
  double _measuredTotalItemHeight = 60.0; // Fallback
  double _measuredSelectorHeight = 56.0;  // Fallback (total - margin)

  // Measured vertical margin (updated after first measurement)
  double _verticalMargin = 4.0; // Fallback: 2.sp * 2 ≈ 4

  double get _totalItemHeight => _measuredTotalItemHeight;

  @override
  void initState() {
    super.initState();

    // Create keys for each item
    _itemKeys.clear();
    for (var i = 0; i < widget.categories.length; i++) {
      _itemKeys.add(GlobalKey());
    }

    // Find initial selected index
    _currentIndex = widget.categories.indexWhere(
      (c) => c.tour.id == widget.selectedCategory.tour.id,
    );
    if (_currentIndex < 0) _currentIndex = 0;

    _targetY = _currentIndex * _measuredTotalItemHeight;

    // Measure actual item height after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureItemHeight();
    });
  }

  void _measureItemHeight() {
    if (_itemKeys.isNotEmpty && _itemKeys.first.currentContext != null) {
      final box = _itemKeys.first.currentContext!.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final totalHeight = box.size.height;
        // Calculate actual vertical margin in current context
        final actualVerticalMargin = 2.sp * 2;
        // The selector should cover the content area (total height minus vertical margin)
        final selectorHeight = totalHeight - actualVerticalMargin;

        if ((totalHeight - _measuredTotalItemHeight).abs() > 1) {
          setState(() {
            _measuredTotalItemHeight = totalHeight;
            _measuredSelectorHeight = selectorHeight;
            _verticalMargin = actualVerticalMargin;
            _targetY = _currentIndex * totalHeight;
          });
        }
      }
    }
  }

  @override
  void didUpdateWidget(_CategoriesColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCategory.tour.id != oldWidget.selectedCategory.tour.id) {
      final newIndex = widget.categories.indexWhere(
        (c) => c.tour.id == widget.selectedCategory.tour.id,
      );
      if (newIndex >= 0) {
        _animateToIndex(newIndex);
      }
    }
  }

  void _animateToIndex(int index) {
    if (index == _currentIndex && !_isDragging) return;

    setState(() {
      _currentIndex = index;
      _targetY = index * _totalItemHeight;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollTimer?.cancel();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    HapticFeedbackService.heavy();
    setState(() {
      _isDragging = true;
    });
    _updateIndexFromPosition(details.globalPosition);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    _updateIndexFromPosition(details.globalPosition);
  }

  void _updateIndexFromPosition(Offset globalPosition) {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;

    final localPos = listBox.globalToLocal(globalPosition);
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;

    // Calculate which item we're hovering over - direct position tracking
    final adjustedY = localPos.dy + scrollOffset;
    final newIndex = (adjustedY / _totalItemHeight).floor().clamp(0, widget.categories.length - 1);

    if (newIndex != _currentIndex) {
      HapticFeedbackService.selection();
      _animateToIndex(newIndex);
    }

    // Auto-scroll when near edges
    _handleEdgeScroll(localPos.dy, listBox.size.height);
  }

  void _handleEdgeScroll(double localY, double listHeight) {
    _scrollTimer?.cancel();

    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    const edgeThreshold = 50.0;

    if (localY < edgeThreshold && _scrollController.offset > 0) {
      final speed = ((edgeThreshold - localY) / edgeThreshold) * _totalItemHeight * 0.5;
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
        if (!_scrollController.hasClients) return;
        final newScroll = (_scrollController.offset - speed).clamp(0.0, maxScroll);
        _scrollController.jumpTo(newScroll);
      });
    } else if (localY > listHeight - edgeThreshold && _scrollController.offset < maxScroll) {
      final speed = ((localY - (listHeight - edgeThreshold)) / edgeThreshold) * _totalItemHeight * 0.5;
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
        if (!_scrollController.hasClients) return;
        final newScroll = (_scrollController.offset + speed).clamp(0.0, maxScroll);
        _scrollController.jumpTo(newScroll);
      });
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    _scrollTimer?.cancel();

    if (_isDragging && _currentIndex >= 0 && _currentIndex < widget.categories.length) {
      HapticFeedbackService.medium();
      widget.onSelect(widget.categories[_currentIndex]);
    }

    setState(() {
      _isDragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: EdgeInsets.fromLTRB(14.sp, 12.sp, 14.sp, 8.sp),
          child: Text(
            'Categories',
            style: AppTypography.textXxsMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
        ),
        // Stack for list + floating selection overlay + drag gesture
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: _handleDragStart,
            onVerticalDragUpdate: _handleDragUpdate,
            onVerticalDragEnd: _handleDragEnd,
            child: Stack(
              children: [
                // List of items
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: ListView.builder(
                    key: _listKey,
                    controller: _scrollController,
                    physics: _isDragging ? const NeverScrollableScrollPhysics() : null,
                    padding: EdgeInsets.only(bottom: 8.sp),
                    itemCount: widget.categories.length,
                    itemBuilder: (context, index) {
                      final category = widget.categories[index];
                      final isSelected = index == _currentIndex;

                      // Ensure we have a key for this index
                      while (_itemKeys.length <= index) {
                        _itemKeys.add(GlobalKey());
                      }

                      return KeyedSubtree(
                        key: _itemKeys[index],
                        child: _CategoryItemSimple(
                          index: index,
                          animation: widget.animation,
                          category: category,
                          isSelected: isSelected,
                          isDragging: _isDragging,
                          onTap: () {
                            _animateToIndex(index);
                            widget.onSelect(category);
                          },
                        ),
                      );
                    },
                  ),
                ),
              // Floating water droplet selection indicator with Motor spring physics
              Positioned.fill(
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: _scrollController,
                    builder: (context, _) {
                      final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;

                      return SingleMotionBuilder(
                        motion: _isDragging
                            ? CupertinoMotion.snappy() // Faster when dragging
                            : CupertinoMotion.bouncy(), // Bouncier on tap selection
                        value: _targetY - scrollOffset,
                        builder: (context, animatedY, _) {
                          // Add top margin offset so selector starts at content, not at margin
                          // Item margin is 2.sp on top, so we offset by half the total vertical margin
                          final selectorY = animatedY + (_verticalMargin / 2);
                          return CustomPaint(
                            painter: _DropletSelectionPainter(
                              y: selectorY,
                              height: _measuredSelectorHeight,
                              morphProgress: _isDragging ? 0.5 : 0.0,
                              isDragging: _isDragging,
                              baseColor: kPrimaryColor,
                              horizontalMargin: 8.sp,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Simple category item without drag handlers - drag is handled at list level
class _CategoryItemSimple extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final TourModel category;
  final bool isSelected;
  final bool isDragging;
  final VoidCallback onTap;

  const _CategoryItemSimple({
    required this.index,
    required this.animation,
    required this.category,
    required this.isSelected,
    required this.isDragging,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final itemDelay = index * 0.06;
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.4),
        (itemDelay + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 10 * (1 - clampedValue)),
          child: Opacity(
            opacity: clampedValue,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
          padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 10.sp),
          color: Colors.transparent,
          child: Row(
          children: [
            // Live indicator
            if (category.roundStatus == RoundStatus.live) ...[
              _StatusDot(status: category.roundStatus),
              SizedBox(width: 8.sp),
            ],
            // Category name
            Expanded(
              child: Text(
                _extractShortName(category.tour.name),
                style: AppTypography.textXsMedium.copyWith(
                  color: isSelected ? kPrimaryColor : kWhiteColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  String _extractShortName(String fullName) {
    if (fullName.contains('|')) {
      return fullName.split('|').last.trim();
    }
    if (fullName.contains(':')) {
      return fullName.split(':').last.trim();
    }
    if (fullName.length > 20) {
      return '${fullName.substring(0, 17)}...';
    }
    return fullName;
  }
}

/// Rounds column with floating liquid selection indicator
class _RoundsColumn extends StatefulWidget {
  final Animation<double> animation;
  final List<GamesAppBarModel> rounds;
  final GamesAppBarModel? selectedRound;
  final ValueChanged<GamesAppBarModel> onSelect;

  const _RoundsColumn({
    required this.animation,
    required this.rounds,
    required this.selectedRound,
    required this.onSelect,
  });

  @override
  State<_RoundsColumn> createState() => _RoundsColumnState();
}

class _RoundsColumnState extends State<_RoundsColumn> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  final List<GlobalKey> _itemKeys = [];

  bool _isDragging = false;
  int _currentIndex = 0;
  Timer? _scrollTimer;

  // Target Y position for motor spring animation
  double _targetY = 0.0;

  // Measured dimensions - total item height (including margin) and selector height (excluding margin)
  double _measuredTotalItemHeight = 52.0; // Fallback
  double _measuredSelectorHeight = 48.0;  // Fallback (total - margin)

  // Measured vertical margin (updated after first measurement)
  double _verticalMargin = 4.0; // Fallback: 2.sp * 2 ≈ 4

  double get _totalItemHeight => _measuredTotalItemHeight;

  @override
  void initState() {
    super.initState();

    // Create keys for each item
    _itemKeys.clear();
    for (var i = 0; i < widget.rounds.length; i++) {
      _itemKeys.add(GlobalKey());
    }

    // Find initial selected index
    _currentIndex = widget.rounds.indexWhere(
      (r) => r.id == widget.selectedRound?.id,
    );
    if (_currentIndex < 0) _currentIndex = 0;

    _targetY = _currentIndex * _measuredTotalItemHeight;

    // Measure actual item height after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureItemHeight();
    });
  }

  void _measureItemHeight() {
    if (_itemKeys.isNotEmpty && _itemKeys.first.currentContext != null) {
      final box = _itemKeys.first.currentContext!.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final totalHeight = box.size.height;
        // Calculate actual vertical margin in current context
        final actualVerticalMargin = 2.sp * 2;
        // The selector should cover the content area (total height minus vertical margin)
        final selectorHeight = totalHeight - actualVerticalMargin;

        if ((totalHeight - _measuredTotalItemHeight).abs() > 1) {
          setState(() {
            _measuredTotalItemHeight = totalHeight;
            _measuredSelectorHeight = selectorHeight;
            _verticalMargin = actualVerticalMargin;
            _targetY = _currentIndex * totalHeight;
          });
        }
      }
    }
  }

  @override
  void didUpdateWidget(_RoundsColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedRound?.id != oldWidget.selectedRound?.id) {
      final newIndex = widget.rounds.indexWhere(
        (r) => r.id == widget.selectedRound?.id,
      );
      if (newIndex >= 0) {
        _animateToIndex(newIndex);
      }
    }
  }

  void _animateToIndex(int index) {
    if (index == _currentIndex && !_isDragging) return;

    setState(() {
      _currentIndex = index;
      _targetY = index * _totalItemHeight;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollTimer?.cancel();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    HapticFeedbackService.heavy();
    setState(() {
      _isDragging = true;
    });
    _updateIndexFromPosition(details.globalPosition);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    _updateIndexFromPosition(details.globalPosition);
  }

  void _updateIndexFromPosition(Offset globalPosition) {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;

    final localPos = listBox.globalToLocal(globalPosition);
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;

    // Calculate which item we're hovering over - direct position tracking
    final adjustedY = localPos.dy + scrollOffset;
    final newIndex = (adjustedY / _totalItemHeight).floor().clamp(0, widget.rounds.length - 1);

    if (newIndex != _currentIndex) {
      HapticFeedbackService.selection();
      _animateToIndex(newIndex);
    }

    // Auto-scroll when near edges
    _handleEdgeScroll(localPos.dy, listBox.size.height);
  }

  void _handleEdgeScroll(double localY, double listHeight) {
    _scrollTimer?.cancel();

    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    const edgeThreshold = 50.0;

    if (localY < edgeThreshold && _scrollController.offset > 0) {
      final speed = ((edgeThreshold - localY) / edgeThreshold) * _totalItemHeight * 0.5;
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
        if (!_scrollController.hasClients) return;
        final newScroll = (_scrollController.offset - speed).clamp(0.0, maxScroll);
        _scrollController.jumpTo(newScroll);
      });
    } else if (localY > listHeight - edgeThreshold && _scrollController.offset < maxScroll) {
      final speed = ((localY - (listHeight - edgeThreshold)) / edgeThreshold) * _totalItemHeight * 0.5;
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
        if (!_scrollController.hasClients) return;
        final newScroll = (_scrollController.offset + speed).clamp(0.0, maxScroll);
        _scrollController.jumpTo(newScroll);
      });
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    _scrollTimer?.cancel();

    if (_isDragging && _currentIndex >= 0 && _currentIndex < widget.rounds.length) {
      HapticFeedbackService.medium();
      widget.onSelect(widget.rounds[_currentIndex]);
    }

    setState(() {
      _isDragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: EdgeInsets.fromLTRB(14.sp, 12.sp, 14.sp, 8.sp),
          child: Text(
            'Rounds',
            style: AppTypography.textXxsMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
        ),
        // Stack for list + floating selection overlay + drag gesture
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: _handleDragStart,
            onVerticalDragUpdate: _handleDragUpdate,
            onVerticalDragEnd: _handleDragEnd,
            child: Stack(
              children: [
                // List of items
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: ListView.builder(
                    key: _listKey,
                    controller: _scrollController,
                    physics: _isDragging ? const NeverScrollableScrollPhysics() : null,
                    padding: EdgeInsets.only(bottom: 8.sp),
                    itemCount: widget.rounds.length,
                    itemBuilder: (context, index) {
                      final round = widget.rounds[index];
                      final isSelected = index == _currentIndex;

                      // Ensure we have a key for this index
                      while (_itemKeys.length <= index) {
                        _itemKeys.add(GlobalKey());
                      }

                      return KeyedSubtree(
                        key: _itemKeys[index],
                        child: _RoundItemSimple(
                          index: index,
                          animation: widget.animation,
                          round: round,
                          isSelected: isSelected,
                          isDragging: _isDragging,
                          onTap: () {
                            _animateToIndex(index);
                            widget.onSelect(round);
                          },
                        ),
                      );
                    },
                  ),
                ),
              // Floating water droplet selection indicator with Motor spring physics
              Positioned.fill(
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: _scrollController,
                    builder: (context, _) {
                      final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;

                      return SingleMotionBuilder(
                        motion: _isDragging
                            ? CupertinoMotion.snappy() // Faster when dragging
                            : CupertinoMotion.bouncy(), // Bouncier on tap selection
                        value: _targetY - scrollOffset,
                        builder: (context, animatedY, _) {
                          // Add top margin offset so selector starts at content, not at margin
                          // Item margin is 2.sp on top, so we offset by half the total vertical margin
                          final selectorY = animatedY + (_verticalMargin / 2);
                          return CustomPaint(
                            painter: _DropletSelectionPainter(
                              y: selectorY,
                              height: _measuredSelectorHeight,
                              morphProgress: _isDragging ? 0.5 : 0.0,
                              isDragging: _isDragging,
                              baseColor: kPrimaryColor,
                              horizontalMargin: 6.sp,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Simple round item without drag handlers - drag is handled at list level
class _RoundItemSimple extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final GamesAppBarModel round;
  final bool isSelected;
  final bool isDragging;
  final VoidCallback onTap;

  const _RoundItemSimple({
    required this.index,
    required this.animation,
    required this.round,
    required this.isSelected,
    required this.isDragging,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = round.roundStatus == RoundStatus.live;
    final itemDelay = index * 0.06;
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.4),
        (itemDelay + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 10 * (1 - clampedValue)),
          child: Opacity(
            opacity: clampedValue,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
          padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 10.sp),
          color: Colors.transparent,
          child: Row(
          children: [
            // Round info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    round.name,
                    style: AppTypography.textXsMedium.copyWith(
                      color: isSelected ? kPrimaryColor : kWhiteColor,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.sp),
                  Text(
                    round.formattedStartDate,
                    style: AppTypography.textXxsRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.5),
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            SizedBox(width: 6.sp),
            // Status icon
            _RoundStatusIcon(
              status: round.roundStatus,
              showLive: isLive,
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// Simplified round item - just content, selection handled by overlay (legacy)
class _RoundItem extends StatefulWidget {
  final int index;
  final Animation<double> animation;
  final GamesAppBarModel round;
  final bool isSelected;
  final bool isDragging;
  final VoidCallback onTap;
  final ValueChanged<LongPressStartDetails> onLongPressStart;
  final ValueChanged<LongPressMoveUpdateDetails> onLongPressMoveUpdate;
  final ValueChanged<LongPressEndDetails> onLongPressEnd;

  const _RoundItem({
    required this.index,
    required this.animation,
    required this.round,
    required this.isSelected,
    required this.isDragging,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
  });

  @override
  State<_RoundItem> createState() => _RoundItemState();
}

class _RoundItemState extends State<_RoundItem> {
  @override
  Widget build(BuildContext context) {
    final isLive = widget.round.roundStatus == RoundStatus.live;

    // Staggered animation for entrance
    final itemDelay = widget.index * 0.06;
    final itemAnimation = CurvedAnimation(
      parent: widget.animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.4),
        (itemDelay + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 10 * (1 - clampedValue)),
          child: Opacity(
            opacity: clampedValue,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPressStart: widget.onLongPressStart,
        onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
        onLongPressEnd: widget.onLongPressEnd,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
          padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 10.sp),
          color: Colors.transparent,
          child: Row(
            children: [
              // Round info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.round.name,
                      style: AppTypography.textXsMedium.copyWith(
                        color: widget.isSelected ? kPrimaryColor : kWhiteColor,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2.sp),
                    Text(
                      widget.round.formattedStartDate,
                      style: AppTypography.textXxsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 6.sp),
              // Status icon
              _RoundStatusIcon(
                status: widget.round.roundStatus,
                showLive: isLive,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draggable round item - long press to grab and drag for selection (legacy)
class _DraggableRoundItem extends StatefulWidget {
  final int index;
  final Animation<double> animation;
  final GamesAppBarModel round;
  final bool isSelected;
  final bool isHovered;
  final bool isDragging;
  final VoidCallback onTap;
  final ValueChanged<LongPressStartDetails> onLongPressStart;
  final ValueChanged<LongPressMoveUpdateDetails> onLongPressMoveUpdate;
  final ValueChanged<LongPressEndDetails> onLongPressEnd;

  const _DraggableRoundItem({
    required this.index,
    required this.animation,
    required this.round,
    required this.isSelected,
    required this.isHovered,
    required this.isDragging,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
  });

  @override
  State<_DraggableRoundItem> createState() => _DraggableRoundItemState();
}

class _DraggableRoundItemState extends State<_DraggableRoundItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isLive = widget.round.roundStatus == RoundStatus.live;

    // Staggered animation for entrance
    final itemDelay = widget.index * 0.06;
    final itemAnimation = CurvedAnimation(
      parent: widget.animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.4),
        (itemDelay + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    // Bubbly scale when hovered during drag
    final scale = widget.isHovered && widget.isDragging ? 1.05 : 1.0;

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 10 * (1 - clampedValue)),
          child: Opacity(
            opacity: clampedValue,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        onLongPressStart: widget.onLongPressStart,
        onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
        onLongPressEnd: widget.onLongPressEnd,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          curve: Sprung.custom(damping: 15, stiffness: 300),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
            padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 10.sp),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10.br),
              color: widget.isSelected
                  ? kPrimaryColor.withValues(alpha: 0.15)
                  : widget.isHovered
                      ? kPrimaryColor.withValues(alpha: 0.20)
                      : _isPressed
                          ? kWhiteColor.withValues(alpha: 0.05)
                          : Colors.transparent,
              border: (widget.isSelected || widget.isHovered)
                  ? Border.all(
                      color: kPrimaryColor.withValues(alpha: widget.isHovered ? 0.4 : 0.25),
                      width: 1.0,
                    )
                  : null,
              // Flat design - no shadow
            ),
            child: Row(
              children: [
                // Round info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.round.name,
                        style: AppTypography.textXsMedium.copyWith(
                          color: (widget.isSelected || widget.isHovered)
                              ? kPrimaryColor
                              : kWhiteColor,
                          fontWeight: (widget.isSelected || widget.isHovered)
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.sp),
                      Text(
                        widget.round.formattedStartDate,
                        style: AppTypography.textXxsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.5),
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 6.sp),
                // Status icon
                _RoundStatusIcon(
                  status: widget.round.roundStatus,
                  showLive: isLive,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round status icon (check, live dot, calendar)
class _RoundStatusIcon extends StatelessWidget {
  final RoundStatus status;
  final bool showLive;

  const _RoundStatusIcon({
    required this.status,
    this.showLive = false,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case RoundStatus.completed:
        return Icon(
          Icons.check_circle_rounded,
          color: kWhiteColor.withValues(alpha: 0.4),
          size: 16.ic,
        );
      case RoundStatus.live:
        if (!showLive) {
          return const SizedBox.shrink();
        }
        return _StatusDot(status: RoundStatus.live);
      case RoundStatus.ongoing:
        return Icon(
          Icons.schedule_rounded,
          color: kWhiteColor.withValues(alpha: 0.6),
          size: 14.ic,
        );
      case RoundStatus.upcoming:
        return Icon(
          Icons.calendar_today_rounded,
          color: kWhiteColor.withValues(alpha: 0.6),
          size: 14.ic,
        );
    }
  }
}

/// Draggable category item - long press to grab and drag for selection
class _DraggableCategoryItem extends StatefulWidget {
  final int index;
  final Animation<double> animation;
  final TourModel category;
  final bool isSelected;
  final bool isHovered;
  final bool isDragging;
  final VoidCallback onTap;
  final ValueChanged<LongPressStartDetails> onLongPressStart;
  final ValueChanged<LongPressMoveUpdateDetails> onLongPressMoveUpdate;
  final ValueChanged<LongPressEndDetails> onLongPressEnd;

  const _DraggableCategoryItem({
    required this.index,
    required this.animation,
    required this.category,
    required this.isSelected,
    required this.isHovered,
    required this.isDragging,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
  });

  @override
  State<_DraggableCategoryItem> createState() => _DraggableCategoryItemState();
}

class _DraggableCategoryItemState extends State<_DraggableCategoryItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isLive = widget.category.roundStatus == RoundStatus.live;

    // Staggered animation for entrance
    final itemDelay = widget.index * 0.08;
    final itemAnimation = CurvedAnimation(
      parent: widget.animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.5),
        (itemDelay + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    // Bubbly scale when hovered during drag
    final scale = widget.isHovered && widget.isDragging ? 1.05 : 1.0;

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 10 * (1 - clampedValue)),
          child: Opacity(
            opacity: clampedValue,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        onLongPressStart: widget.onLongPressStart,
        onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
        onLongPressEnd: widget.onLongPressEnd,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          curve: Sprung.custom(damping: 15, stiffness: 300),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 2.sp),
            padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 12.sp),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.br),
              color: widget.isSelected
                  ? kPrimaryColor.withValues(alpha: 0.15)
                  : widget.isHovered
                      ? kPrimaryColor.withValues(alpha: 0.20)
                      : _isPressed
                          ? kWhiteColor.withValues(alpha: 0.05)
                          : Colors.transparent,
              border: (widget.isSelected || widget.isHovered)
                  ? Border.all(
                      color: kPrimaryColor.withValues(alpha: widget.isHovered ? 0.4 : 0.25),
                      width: 1.0,
                    )
                  : null,
              // Flat design - no shadow
            ),
            child: Row(
              children: [
                // Status indicator
                if (isLive) ...[
                  _StatusDot(status: widget.category.roundStatus),
                  SizedBox(width: 12.sp),
                ],
                // Category info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _extractDisplayName(widget.category.tour.name),
                        style: AppTypography.textSmMedium.copyWith(
                          color: (widget.isSelected || widget.isHovered)
                              ? kPrimaryColor
                              : kWhiteColor,
                          fontWeight: (widget.isSelected || widget.isHovered)
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
        ),
      ),
    );
  }

  String _extractDisplayName(String fullName) {
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
        return kPrimaryColor;
      case RoundStatus.ongoing:
        return kWhiteColor70;
      case RoundStatus.upcoming:
        return kWhiteColor70;
      case RoundStatus.completed:
        return kWhiteColor70;
    }
  }
}

/// Liquid/water droplet selection indicator painter
/// Creates a morphing rectangle with organic blob-like borders
class _DropletSelectionPainter extends CustomPainter {
  final double y;
  final double height;
  final double morphProgress;
  final bool isDragging;
  final Color baseColor;
  final double horizontalMargin;

  _DropletSelectionPainter({
    required this.y,
    required this.height,
    required this.morphProgress,
    required this.isDragging,
    required this.baseColor,
    required this.horizontalMargin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - (horizontalMargin * 2);
    final h = height;
    final x = horizontalMargin;
    final baseRadius = 12.0;

    // Calculate morph distortion
    final distortionEnvelope = math.sin(morphProgress * math.pi);
    final distortion = distortionEnvelope * 0.6; // Reduce overall distortion
    final maxBulge = math.min(w, h) * 0.06;
    final bulge = distortion * maxBulge;

    // Phase offset for wobble effect
    final phaseOffset = morphProgress * math.pi * 2.5;

    // Build the blob path
    final path = Path();
    final r = baseRadius.clamp(0.0, math.min(w, h) / 2);

    if (bulge.abs() < 0.5) {
      // Simple rounded rect when no distortion
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(r),
      ));
    } else {
      // Morphing blob shape
      final topBulge = bulge * math.sin(phaseOffset) * 0.7;
      final rightBulge = bulge * math.sin(phaseOffset + math.pi * 0.5) * 0.5;
      final bottomBulge = bulge * math.sin(phaseOffset + math.pi) * 0.8;
      final leftBulge = bulge * math.sin(phaseOffset + math.pi * 1.5) * 0.5;
      final cornerExpand = bulge * 0.4 * math.cos(phaseOffset * 0.8);

      path.moveTo(x + r + cornerExpand, y);

      // Top edge
      path.quadraticBezierTo(
        x + w / 2, y - topBulge,
        x + w - r - cornerExpand, y,
      );

      // Top-right corner
      final trCornerOffset = cornerExpand * 0.7;
      path.quadraticBezierTo(
        x + w + trCornerOffset, y - trCornerOffset,
        x + w, y + r + cornerExpand,
      );

      // Right edge
      path.quadraticBezierTo(
        x + w + rightBulge, y + h / 2,
        x + w, y + h - r - cornerExpand,
      );

      // Bottom-right corner
      final brCornerOffset = cornerExpand * 0.7;
      path.quadraticBezierTo(
        x + w + brCornerOffset, y + h + brCornerOffset,
        x + w - r - cornerExpand, y + h,
      );

      // Bottom edge
      path.quadraticBezierTo(
        x + w / 2, y + h + bottomBulge,
        x + r + cornerExpand, y + h,
      );

      // Bottom-left corner
      final blCornerOffset = cornerExpand * 0.7;
      path.quadraticBezierTo(
        x - blCornerOffset, y + h + blCornerOffset,
        x, y + h - r - cornerExpand,
      );

      // Left edge
      path.quadraticBezierTo(
        x - leftBulge, y + h / 2,
        x, y + r + cornerExpand,
      );

      // Top-left corner
      final tlCornerOffset = cornerExpand * 0.7;
      path.quadraticBezierTo(
        x - tlCornerOffset, y - tlCornerOffset,
        x + r + cornerExpand, y,
      );

      path.close();
    }

    // Flat solid fill - no gradient
    final fillPaint = Paint()
      ..color = baseColor.withValues(alpha: isDragging ? 0.20 : 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Clean border stroke - no glow
    final borderPaint = Paint()
      ..color = baseColor.withValues(alpha: isDragging ? 0.5 : 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isDragging ? 1.5 : 1.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(_DropletSelectionPainter oldDelegate) {
    return y != oldDelegate.y ||
        height != oldDelegate.height ||
        morphProgress != oldDelegate.morphProgress ||
        isDragging != oldDelegate.isDragging ||
        baseColor != oldDelegate.baseColor;
  }
}

/// Simplified category item - just content, no selection styling (handled by overlay)
class _CategoryItem extends StatefulWidget {
  final int index;
  final Animation<double> animation;
  final TourModel category;
  final bool isSelected;
  final bool isDragging;
  final VoidCallback onTap;
  final ValueChanged<LongPressStartDetails> onLongPressStart;
  final ValueChanged<LongPressMoveUpdateDetails> onLongPressMoveUpdate;
  final ValueChanged<LongPressEndDetails> onLongPressEnd;

  const _CategoryItem({
    required this.index,
    required this.animation,
    required this.category,
    required this.isSelected,
    required this.isDragging,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
  });

  @override
  State<_CategoryItem> createState() => _CategoryItemState();
}

class _CategoryItemState extends State<_CategoryItem> {
  @override
  Widget build(BuildContext context) {
    final isLive = widget.category.roundStatus == RoundStatus.live;

    // Staggered animation for entrance
    final itemDelay = widget.index * 0.08;
    final itemAnimation = CurvedAnimation(
      parent: widget.animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.5),
        (itemDelay + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 10 * (1 - clampedValue)),
          child: Opacity(
            opacity: clampedValue,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPressStart: widget.onLongPressStart,
        onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
        onLongPressEnd: widget.onLongPressEnd,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 2.sp),
          padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 12.sp),
          // Transparent - selection is drawn by CustomPainter overlay
          color: Colors.transparent,
          child: Row(
            children: [
              // Status indicator
              if (isLive) ...[
                _StatusDot(status: widget.category.roundStatus),
                SizedBox(width: 12.sp),
              ],
              // Category info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _extractDisplayName(widget.category.tour.name),
                      style: AppTypography.textSmMedium.copyWith(
                        color: widget.isSelected ? kPrimaryColor : kWhiteColor,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
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
      ),
    );
  }

  String _extractDisplayName(String fullName) {
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
        return kPrimaryColor;
      case RoundStatus.ongoing:
        return kWhiteColor70;
      case RoundStatus.upcoming:
        return kWhiteColor70;
      case RoundStatus.completed:
        return kWhiteColor70;
    }
  }
}


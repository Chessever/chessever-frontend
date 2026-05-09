import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/droplet_animation_curves.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Scroll to a specific round from widget context (ensures correct ProviderScope)
void _scrollToRoundFromWidget(WidgetRef ref, String roundId) {
  final scopeId = ref.read(gamesTourScrollScopeProvider);
  final scrollNotifier = ref.read(gamesTourScrollProvider(scopeId).notifier);
  final controller = scrollNotifier.scrollController;

  // Calculate the index using the app bar provider
  final itemIndex = ref
      .read(gamesAppBarProvider.notifier)
      .calculateRoundIndex(roundId);

  print(
    '🎯 Widget scroll - scopeId: $scopeId, roundId: $roundId, index: $itemIndex, attached: ${controller.isAttached}',
  );

  if (itemIndex < 0) {
    print('❌ Widget scroll - round not found in visible rounds');
    return;
  }

  // Mark that we're doing a programmatic scroll
  scrollNotifier.startProgrammaticScroll(targetRoundId: roundId);

  // Use post-frame callback to ensure the widget tree is ready
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Retry a few times in case controller isn't attached yet
    _attemptScroll(controller, scrollNotifier, itemIndex, roundId, 0);
  });
}

/// Attempt to scroll with retries
void _attemptScroll(
  ItemScrollController controller,
  dynamic scrollNotifier,
  int itemIndex,
  String roundId,
  int attempt,
) {
  const maxAttempts = 5;
  const retryDelay = Duration(milliseconds: 100);

  if (controller.isAttached) {
    try {
      controller.jumpTo(index: itemIndex, alignment: 0.0);
      print('✅ Widget scroll - jumpTo completed (attempt: $attempt)');
    } catch (e) {
      print('❌ Widget scroll - jumpTo failed: $e');
    }
    scrollNotifier.endProgrammaticScroll();
  } else if (attempt < maxAttempts) {
    print(
      '⏳ Widget scroll - controller not attached, retrying (attempt: ${attempt + 1})',
    );
    Future.delayed(retryDelay, () {
      _attemptScroll(
        controller,
        scrollNotifier,
        itemIndex,
        roundId,
        attempt + 1,
      );
    });
  } else {
    print('❌ Widget scroll - gave up after $maxAttempts attempts');
    scrollNotifier.endProgrammaticScroll();
  }
}

/// A beautiful stadium-chip style combo dropdown with glass morphism effects.
/// Single vertical ListView with expandable categories containing nested rounds.
/// Tapping a category or round immediately switches to it (no Save button).
class CategoryDropdown extends ConsumerWidget {
  const CategoryDropdown({super.key, this.constrainWidth = true});

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
          final selectedRound =
              rounds.isNotEmpty && selectedRoundId != null
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
              // Select the round in the provider
              ref.read(gamesAppBarProvider.notifier).select(round);
              // Also trigger scroll directly from widget context (has correct scope)
              _scrollToRoundFromWidget(ref, round.id);
            },
          );
        },
        error:
            (e, _) => Center(
              child: Text(
                'Error',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textPrimaryMuted,
                ),
              ),
            ),
        loading:
            () => SkeletonWidget(
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
      duration: const Duration(milliseconds: 200),
    );

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

    // Track when opened for tablet phantom tap protection
    final openedAt = DateTime.now();
    if (ResponsiveHelper.isTablet) {
      TabletPopupState.markOpen();
    }

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
      final availableHeight =
          screenSize.height - offset.dy - size.height - 32.sp;

      overlayEntry = OverlayEntry(
        builder:
            (context) => _DropdownOverlay(
              layerLink: layerLink,
              triggerSize: size,
              triggerOffset: offset,
              screenWidth: screenSize.width,
              availableHeight: availableHeight,
              animation: animation,
              categories: categories,
              openedAt: openedAt,
              onCategorySelect: (category) {
                HapticFeedbackService.selection();
                onCategoryChanged(category);
                // Close immediately after selection
                if (ResponsiveHelper.isTablet) {
                  TabletPopupState.markClosed();
                }
                animationController.reverse().then((_) {
                  isOpen.value = false;
                });
              },
              onCategoryChange: (category) {
                // Select category WITHOUT closing dropdown (for expand arrow)
                HapticFeedbackService.selection();
                onCategoryChanged(category);
                // Don't close - let the dropdown stay open to show loaded rounds
              },
              onRoundSelect: (round) {
                print('🟢 onRoundSelect called: ${round.name} (${round.id})');
                HapticFeedbackService.selection();
                onRoundChanged(round);
                // Close immediately after selection
                if (ResponsiveHelper.isTablet) {
                  TabletPopupState.markClosed();
                }
                animationController.reverse().then((_) {
                  isOpen.value = false;
                });
              },
              onDismiss: () {
                if (ResponsiveHelper.isTablet) {
                  TabletPopupState.markClosed();
                }
                animationController.reverse().then((_) {
                  isOpen.value = false;
                });
              },
            ),
      );

      overlay.insert(overlayEntry!);

      void removeOverlay() {
        try {
          if (ResponsiveHelper.isTablet) {
            TabletPopupState.markClosed();
          }
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
    // Extract just the category part if formatted with separator
    if (fullName.contains('|')) {
      return fullName.split('|').last.trim();
    }
    if (fullName.contains(':')) {
      return fullName.split(':').last.trim();
    }

    // Look for common category patterns like "Boards X-Y" or "Boards X+"
    final boardsMatch = RegExp(
      r'(Boards?\s+\d+[\-\+]?\d*\+?)$',
      caseSensitive: false,
    ).firstMatch(fullName);
    if (boardsMatch != null) {
      return boardsMatch.group(0)!.trim();
    }

    // Look for patterns like "Group A", "Section B", "Division 1"
    final groupMatch = RegExp(
      r'((?:Group|Section|Division|Category)\s+\w+)$',
      caseSensitive: false,
    ).firstMatch(fullName);
    if (groupMatch != null) {
      return groupMatch.group(0)!.trim();
    }

    // Don't truncate - let the marquee handle long text
    return fullName;
  }
}

/// Stadium-shaped chip button that triggers the dropdown
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
    final shimmerController = useAnimationController(
      duration: const Duration(milliseconds: 3000),
    );

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
          painter:
              isOpen
                  ? null
                  : _FluidShimmerPainter(
                    progress: shimmerValue,
                    shimmerColor: kPrimaryColor.withValues(alpha: 0.4),
                    borderRadius: 12.br,
                  ),
          child: child,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.br),
          color:
              isOpen
                  ? kPrimaryColor.withValues(alpha: 0.15)
                  : context.colors.textPrimary.withValues(alpha: 0.06),
          border: Border.all(
            color:
                isOpen
                    ? kPrimaryColor.withValues(alpha: 0.4)
                    : context.colors.textPrimary.withValues(alpha: 0.12),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == RoundStatus.live) ...[
              _LiveDot(),
              SizedBox(width: 8.sp),
            ],
            Flexible(
              child: _MarqueeText(
                text: label,
                style: AppTypography.textXsMedium.copyWith(
                  color: isOpen ? kPrimaryColor : kWhiteColor,
                  letterSpacing: 0.3,
                ),
                continuous: false, // Single cycle for chip button
              ),
            ),
            if (showChevron) ...[
              SizedBox(width: 6.sp),
              AnimatedRotation(
                turns: isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color:
                      isOpen
                          ? kPrimaryColor
                          : context.colors.textPrimary.withValues(alpha: 0.7),
                  size: 18.ic,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // Chip width - wider now that the search icon no longer sits in the app
    // bar, giving the event name more room to breathe.
    final chipMaxWidth = ResponsiveHelper.isTablet ? 480.0 : 260.w;

    return GestureDetector(
      onTap: onTap,
      child:
          constrainWidth
              ? ConstrainedBox(
                constraints: BoxConstraints(maxWidth: chipMaxWidth),
                child: button,
              )
              : button,
    );
  }
}

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

    final paint =
        Paint()
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

/// Auto-scrolling text widget for long text that doesn't fit.
/// - Forward scroll only (no ping-pong)
/// - Single cycle when [continuous] is false
/// - Continuous forward cycles when [continuous] is true (for open menus)
class _MarqueeText extends HookWidget {
  final String text;
  final TextStyle style;
  final bool continuous;

  const _MarqueeText({
    required this.text,
    required this.style,
    this.continuous = false,
  });

  @override
  Widget build(BuildContext context) {
    final scrollController = useScrollController();
    final hasCompletedCycle = useRef(false);
    final isDisposed = useRef(false);

    // Cleanup on dispose
    useEffect(() {
      return () {
        isDisposed.value = true;
      };
    }, []);

    // Reset cycle flag when text changes or continuous mode changes
    useEffect(() {
      hasCompletedCycle.value = false;
      if (scrollController.hasClients) {
        scrollController.jumpTo(0);
      }
      return null;
    }, [text, continuous]);

    // Calculate scroll duration based on distance - consistent speed
    Duration _getScrollDuration(double distance) {
      // Speed: ~20 pixels per second (very slow, readable)
      const pixelsPerSecond = 20.0;
      final seconds = (distance / pixelsPerSecond).clamp(3.0, 15.0);
      return Duration(milliseconds: (seconds * 1000).round());
    }

    // Animation function - forward only, smooth and slow
    void runAnimation() async {
      if (isDisposed.value) return;
      if (!scrollController.hasClients) return;

      final maxScroll = scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;

      // For non-continuous: only run once
      if (!continuous && hasCompletedCycle.value) return;

      // Initial delay - let user see the start
      await Future.delayed(const Duration(seconds: 2));
      if (isDisposed.value || !scrollController.hasClients) return;

      if (continuous) {
        // Continuous mode: loop forever (forward only)
        while (!isDisposed.value && scrollController.hasClients) {
          final currentMax = scrollController.position.maxScrollExtent;
          if (currentMax <= 0) break;

          // Slow, smooth scroll forward - speed based on distance
          try {
            await scrollController.animateTo(
              currentMax,
              duration: _getScrollDuration(currentMax),
              curve: Curves.easeInOut,
            );
          } catch (_) {
            break;
          }

          if (isDisposed.value || !scrollController.hasClients) break;

          // Pause at end to read
          await Future.delayed(const Duration(seconds: 2));
          if (isDisposed.value || !scrollController.hasClients) break;

          // Reset to start
          scrollController.jumpTo(0);

          // Pause before next cycle
          await Future.delayed(const Duration(seconds: 1));
        }
      } else {
        // Single cycle mode - same slow timing
        final currentMax = scrollController.position.maxScrollExtent;
        if (currentMax > 0) {
          try {
            // Slow, smooth scroll forward - speed based on distance
            await scrollController.animateTo(
              currentMax,
              duration: _getScrollDuration(currentMax),
              curve: Curves.easeInOut,
            );

            if (isDisposed.value || !scrollController.hasClients) return;

            // Pause at end to read
            await Future.delayed(const Duration(seconds: 2));
            if (isDisposed.value || !scrollController.hasClients) return;

            // Reset to start
            scrollController.jumpTo(0);

            hasCompletedCycle.value = true;
          } catch (_) {
            // Animation interrupted
          }
        }
      }
    }

    // Start animation after layout
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isDisposed.value) return;
        if (!scrollController.hasClients) return;

        final maxScroll = scrollController.position.maxScrollExtent;
        if (maxScroll > 0) {
          runAnimation();
        }
      });
      return null;
    }, [text, continuous]);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure if text overflows
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final needsScroll = textPainter.width > constraints.maxWidth;

        if (!needsScroll) {
          // Text fits - show normally, no animation needed
          return Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        // Text overflows - show scrolling marquee
        return ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: const [0.0, 0.03, 0.97, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.only(left: 2.sp, right: 6.sp),
              child: Text(text, style: style, maxLines: 1),
            ),
          ),
        );
      },
    );
  }
}

/// Pulsing live indicator dot
class _LiveDot extends HookWidget {
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
          width: 8.sp,
          height: 8.sp,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kPrimaryColor.withValues(alpha: 1 - controller.value * 0.3),
          ),
        );
      },
    );
  }
}

/// The floating dropdown overlay
class _DropdownOverlay extends ConsumerWidget {
  final LayerLink layerLink;
  final Size triggerSize;
  final Offset triggerOffset;
  final double screenWidth;
  final double availableHeight;
  final Animation<double> animation;
  final List<TourModel> categories;
  final DateTime openedAt;
  final ValueChanged<TourModel> onCategorySelect;
  final ValueChanged<TourModel> onCategoryChange; // Select without closing
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
    required this.openedAt,
    required this.onCategorySelect,
    required this.onCategoryChange,
    required this.onRoundSelect,
    required this.onDismiss,
  });

  /// Check if enough time has passed to allow dismissal (tablet phantom tap protection)
  bool _canDismiss() {
    if (!ResponsiveHelper.isTablet) return true;
    const minOpenDuration = Duration(milliseconds: 600);
    final elapsed = DateTime.now().difference(openedAt);
    return elapsed >= minOpenDuration;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch providers directly to get live data when category changes
    final tourDetailAsync = ref.watch(tourDetailScreenProvider);
    final roundsAsync = ref.watch(gamesAppBarProvider);

    final tourData = tourDetailAsync.valueOrNull;
    final selectedCategory =
        tourData != null
            ? (categories.firstWhere(
              (t) => t.tour.id == tourData.aboutTourModel.id,
              orElse: () => categories.first,
            ))
            : categories.first;

    final rounds = roundsAsync.valueOrNull?.gamesAppBarModels ?? [];
    final selectedRoundId = roundsAsync.valueOrNull?.selectedId;
    final selectedRound =
        rounds.isNotEmpty && selectedRoundId != null
            ? rounds.firstWhere(
              (r) => r.id == selectedRoundId,
              orElse: () => rounds.first,
            )
            : null;

    // Wider dropdown for better readability - use available horizontal space
    final minWidth = ResponsiveHelper.isTablet ? 400.0 : 300.w;
    final maxWidth = ResponsiveHelper.isTablet ? 600.0 : 400.w;
    final dropdownWidth = (screenWidth - 32.w).clamp(minWidth, maxWidth);
    final leftOffset = (screenWidth - dropdownWidth) / 2;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        // Tablet phantom tap protection - ignore taps that come too soon after opening
        if (!_canDismiss()) {
          debugPrint(
            '🛡️ CATEGORY DROPDOWN: dismiss blocked - opened too recently',
          );
          return;
        }
        onDismiss();
      },
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.transparent)),
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
                    child: Opacity(opacity: progress, child: child),
                  );
                },
                child: GestureDetector(
                  // Block taps from reaching the dismiss handler
                  onTap: () {},
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: dropdownWidth,
                    constraints: BoxConstraints(
                      maxHeight: availableHeight.clamp(100.0, 350.0),
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16.br),
                      border: Border.all(
                        color: context.colors.textPrimary.withValues(alpha: 0.08),
                        width: 1.0,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16.br),
                      child: _DropdownContent(
                        animation: animation,
                        categories: categories,
                        selectedCategory: selectedCategory,
                        rounds: rounds,
                        selectedRound: selectedRound,
                        onCategorySelect: onCategorySelect,
                        onCategoryChange: onCategoryChange,
                        onRoundSelect: onRoundSelect,
                      ),
                    ),
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

/// Dropdown content with expandable categories and draggable droplet selector
class _DropdownContent extends StatefulWidget {
  final Animation<double> animation;
  final List<TourModel> categories;
  final TourModel selectedCategory;
  final List<GamesAppBarModel> rounds;
  final GamesAppBarModel? selectedRound;
  final ValueChanged<TourModel> onCategorySelect;
  final ValueChanged<TourModel>
  onCategoryChange; // Select without closing dropdown
  final ValueChanged<GamesAppBarModel> onRoundSelect;

  const _DropdownContent({
    required this.animation,
    required this.categories,
    required this.selectedCategory,
    required this.rounds,
    required this.selectedRound,
    required this.onCategorySelect,
    required this.onCategoryChange,
    required this.onRoundSelect,
  });

  @override
  State<_DropdownContent> createState() => _DropdownContentState();
}

class _DropdownContentState extends State<_DropdownContent> {
  // Track which category is expanded (only one at a time)
  String? _expandedCategoryId;

  // Scroll controller for the list
  final ScrollController _scrollController = ScrollController();

  // For droplet selection - track which item is selected
  int _selectedFlatIndex = 0;
  double _targetY = 0.0;
  bool _isDragging = false;
  bool _pointerStartedOnSelector = false;
  Offset? _dragStartPosition;
  Offset? _lastPointerPosition;

  // Flag to prevent selection when arrow is tapped
  bool _arrowWasTapped = false;

  // Item measurements - smaller, more compact
  double _categoryItemHeight = 44.0;
  double _roundItemHeight = 40.0;
  final Map<int, GlobalKey> _itemKeys = {};

  // Flat list of all visible items for droplet tracking
  List<_DropdownItem> _flatItems = [];

  @override
  void didUpdateWidget(covariant _DropdownContent oldWidget) {
    super.didUpdateWidget(oldWidget);

    final categoriesChanged =
        !const ListEquality().equals(
          oldWidget.categories.map((c) => c.tour.id).toList(),
          widget.categories.map((c) => c.tour.id).toList(),
        );
    final roundsChanged =
        !const ListEquality().equals(
          oldWidget.rounds.map((r) => r.id).toList(),
          widget.rounds.map((r) => r.id).toList(),
        );
    final selectionChanged =
        oldWidget.selectedRound?.id != widget.selectedRound?.id ||
        oldWidget.selectedCategory.tour.id != widget.selectedCategory.tour.id;

    if (categoriesChanged || roundsChanged || selectionChanged) {
      _buildFlatItems();
      _findSelectedIndex();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureItems();
        _scrollToSelected();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Start with all categories collapsed
    // When user expands a category that matches games listview selection,
    // the indicator will move to the correct round
    _expandedCategoryId = null;
    _buildFlatItems();
    _findSelectedIndex();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureItems();
      _scrollToSelected();
    });
  }

  void _buildFlatItems() {
    _flatItems = [];
    final hasMultipleCategories = widget.categories.length > 1;

    if (hasMultipleCategories) {
      for (final category in widget.categories) {
        _flatItems.add(
          _DropdownItem(type: _ItemType.category, category: category),
        );

        // Add rounds if this category is expanded AND is the currently selected one
        // (rounds are loaded based on the selected tour)
        // When user expands a non-selected category, it triggers selection which
        // causes widget to rebuild with new selectedCategory and rounds
        final isSelectedCategory =
            category.tour.id == widget.selectedCategory.tour.id;
        final isExpanded = _expandedCategoryId == category.tour.id;

        if (isExpanded && isSelectedCategory) {
          for (final round in widget.rounds) {
            _flatItems.add(
              _DropdownItem(
                type: _ItemType.round,
                round: round,
                parentCategoryId: category.tour.id,
              ),
            );
          }
        }
      }
    } else {
      // Only one category - show rounds directly
      for (final round in widget.rounds) {
        _flatItems.add(_DropdownItem(type: _ItemType.round, round: round));
      }
    }
  }

  void _findSelectedIndex() {
    final hasMultipleCategories = widget.categories.length > 1;

    if (hasMultipleCategories) {
      // When category is expanded, prioritize finding the selected round
      // This syncs the indicator with the games listview scroll position
      final isSelectedCategoryExpanded =
          _expandedCategoryId == widget.selectedCategory.tour.id;

      if (isSelectedCategoryExpanded && widget.selectedRound != null) {
        // Try to find the selected round first
        final roundIndex = _flatItems.indexWhere(
          (item) =>
              item.type == _ItemType.round &&
              item.round?.id == widget.selectedRound?.id,
        );
        if (roundIndex >= 0) {
          _selectedFlatIndex = roundIndex;
          _updateTargetY();
          return;
        }
      }

      // Fall back to selecting the category
      _selectedFlatIndex = _flatItems.indexWhere(
        (item) =>
            item.type == _ItemType.category &&
            item.category?.tour.id == widget.selectedCategory.tour.id,
      );
    } else {
      // Find the selected round
      _selectedFlatIndex = _flatItems.indexWhere(
        (item) =>
            item.type == _ItemType.round &&
            item.round?.id == widget.selectedRound?.id,
      );
    }

    if (_selectedFlatIndex < 0) _selectedFlatIndex = 0;
    _updateTargetY();
  }

  void _measureItems() {
    double? measuredCategoryHeight;
    double? measuredRoundHeight;

    for (int i = 0; i < _flatItems.length; i++) {
      final key = _itemKeys[i];
      final context = key?.currentContext;
      if (context == null) continue;

      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;

      if (_flatItems[i].type == _ItemType.category &&
          measuredCategoryHeight == null) {
        measuredCategoryHeight = box.size.height;
      } else if (_flatItems[i].type == _ItemType.round &&
          measuredRoundHeight == null) {
        measuredRoundHeight = box.size.height;
      }

      if (measuredCategoryHeight != null && measuredRoundHeight != null) break;
    }

    if (measuredCategoryHeight != null) {
      _categoryItemHeight = measuredCategoryHeight;
    }
    if (measuredRoundHeight != null) {
      _roundItemHeight = measuredRoundHeight;
    }
    _updateTargetY();
  }

  void _updateTargetY() {
    double y = 0;
    for (int i = 0; i < _selectedFlatIndex && i < _flatItems.length; i++) {
      y +=
          _flatItems[i].type == _ItemType.category
              ? _categoryItemHeight
              : _roundItemHeight;
    }
    setState(() {
      _targetY = y;
    });
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final maxScroll = _scrollController.position.maxScrollExtent;

    final selectedHeight =
        _flatItems.isNotEmpty && _selectedFlatIndex < _flatItems.length
            ? (_flatItems[_selectedFlatIndex].type == _ItemType.category
                ? _categoryItemHeight
                : _roundItemHeight)
            : _categoryItemHeight;

    final itemCenter = _targetY + (selectedHeight / 2);
    final targetScroll = itemCenter - (viewportHeight / 2);
    final clampedScroll = targetScroll.clamp(0.0, maxScroll);

    _scrollController.jumpTo(clampedScroll);
  }

  void _toggleExpand(String categoryId) {
    HapticFeedbackService.light();

    final isCurrentlyExpanded = _expandedCategoryId == categoryId;
    final isSelectedCategory = categoryId == widget.selectedCategory.tour.id;

    if (isCurrentlyExpanded) {
      // Collapsing - just collapse, no selection change
      setState(() {
        _expandedCategoryId = null;
        _buildFlatItems();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureItems();
      });
    } else {
      // Expanding
      if (isSelectedCategory) {
        // Expanding the already-selected category - just expand and show rounds
        setState(() {
          _expandedCategoryId = categoryId;
          _buildFlatItems();
          _findSelectedIndex();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _measureItems();
          _scrollToSelected();
        });
      } else {
        // Expanding a NON-selected category - select it first (loads rounds), keep dropdown open
        setState(() {
          _expandedCategoryId = categoryId;
        });
        // Find the category and trigger selection without closing
        final category = widget.categories.firstWhere(
          (c) => c.tour.id == categoryId,
          orElse: () => widget.selectedCategory,
        );
        widget.onCategoryChange(category);
        // The widget will rebuild with new rounds after selection
      }
    }
  }

  double _getItemHeight(int index) {
    if (index < 0 || index >= _flatItems.length) return _categoryItemHeight;
    return _flatItems[index].type == _ItemType.category
        ? _categoryItemHeight
        : _roundItemHeight;
  }

  double _getYForIndex(int index) {
    double y = 0;
    for (int i = 0; i < index && i < _flatItems.length; i++) {
      y += _getItemHeight(i);
    }
    return y;
  }

  int _getIndexFromY(double y) {
    double accum = 0;
    for (int i = 0; i < _flatItems.length; i++) {
      final h = _getItemHeight(i);
      if (y < accum + h) return i;
      accum += h;
    }
    return _flatItems.length - 1;
  }

  bool _isOnSelector(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;

    final localPos = box.globalToLocal(globalPosition);
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    final selectorVisualTop =
        _targetY - scrollOffset + 6.sp; // Account for padding
    final selectorHeight = _getItemHeight(_selectedFlatIndex);
    final selectorVisualBottom = selectorVisualTop + selectorHeight;

    const tolerance = 12.0;
    return localPos.dy >= (selectorVisualTop - tolerance) &&
        localPos.dy <= (selectorVisualBottom + tolerance);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _dragStartPosition = event.position;
    _lastPointerPosition = event.position;
    _pointerStartedOnSelector = _isOnSelector(event.position);
    // Wait for a small move before entering drag mode to avoid treating taps
    // (e.g., on the expand arrow) as selections.
    _isDragging = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_dragStartPosition == null) return;

    _lastPointerPosition = event.position;

    // Only enter drag mode after a slight movement when the pointer started on the selector
    if (_pointerStartedOnSelector && !_isDragging) {
      final delta = (event.position - _dragStartPosition!).distance;
      const dragStartThreshold = 6.0;
      if (delta >= dragStartThreshold) {
        HapticFeedbackService.heavy();
        if (mounted) setState(() => _isDragging = true);
      }
    }

    if (_isDragging) {
      _updateIndexFromPosition(event.position);
      _handleEdgeScroll(event.position);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    // Skip selection if arrow was tapped
    if (_arrowWasTapped) {
      _arrowWasTapped = false;
      if (mounted) setState(() => _isDragging = false);
      _lastPointerPosition = null;
      _dragStartPosition = null;
      _pointerStartedOnSelector = false;
      return;
    }

    if (_isDragging) {
      HapticFeedbackService.medium();
      // Select the item at current index
      if (_selectedFlatIndex >= 0 && _selectedFlatIndex < _flatItems.length) {
        final item = _flatItems[_selectedFlatIndex];
        if (item.type == _ItemType.category && item.category != null) {
          widget.onCategorySelect(item.category!);
        } else if (item.type == _ItemType.round && item.round != null) {
          // Select the parent category ONLY if it's different from current
          if (item.parentCategoryId != null &&
              item.parentCategoryId != widget.selectedCategory.tour.id) {
            final parentCategory = widget.categories.firstWhere(
              (c) => c.tour.id == item.parentCategoryId,
              orElse: () => widget.selectedCategory,
            );
            widget.onCategorySelect(parentCategory);
          }
          widget.onRoundSelect(item.round!);
        }
      }
    }
    if (mounted) setState(() => _isDragging = false);
    _lastPointerPosition = null;
    _dragStartPosition = null;
    _pointerStartedOnSelector = false;
  }

  // Called by arrow button to prevent selection
  void _onArrowTapped() {
    _arrowWasTapped = true;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (mounted) setState(() => _isDragging = false);
    _lastPointerPosition = null;
    _dragStartPosition = null;
    _pointerStartedOnSelector = false;
  }

  void _updateIndexFromPosition(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPos = box.globalToLocal(globalPosition);
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    final adjustedY = localPos.dy + scrollOffset - 6.sp; // Account for padding
    final newIndex = _getIndexFromY(adjustedY).clamp(0, _flatItems.length - 1);

    if (newIndex != _selectedFlatIndex) {
      HapticFeedbackService.selection();
      setState(() {
        _selectedFlatIndex = newIndex;
        _targetY = _getYForIndex(newIndex);
      });
    }
  }

  void _handleEdgeScroll(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !_scrollController.hasClients) return;

    final localPos = box.globalToLocal(globalPosition);
    final listHeight = box.size.height;
    final maxScroll = _scrollController.position.maxScrollExtent;

    const edgeThreshold = 60.0;
    const scrollSpeed = 10.0;

    if (localPos.dy < edgeThreshold && _scrollController.offset > 0) {
      final intensity = 1.0 - (localPos.dy / edgeThreshold);
      final scrollAmount = scrollSpeed * intensity;
      final newScroll = (_scrollController.offset - scrollAmount).clamp(
        0.0,
        maxScroll,
      );
      _scrollController.jumpTo(newScroll);
      _updateIndexFromPosition(globalPosition);
    } else if (localPos.dy > listHeight - edgeThreshold &&
        _scrollController.offset < maxScroll) {
      final intensity = 1.0 - ((listHeight - localPos.dy) / edgeThreshold);
      final scrollAmount = scrollSpeed * intensity;
      final newScroll = (_scrollController.offset + scrollAmount).clamp(
        0.0,
        maxScroll,
      );
      _scrollController.jumpTo(newScroll);
      _updateIndexFromPosition(globalPosition);
    }
  }

  void _animateToIndex(int index) {
    if (index == _selectedFlatIndex && !_isDragging) return;
    setState(() {
      _selectedFlatIndex = index;
      _targetY = _getYForIndex(index);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMultipleCategories = widget.categories.length > 1;

    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: Stack(
        children: [
          // Scrollable list - shrinkWrap to fit content
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView.builder(
              controller: _scrollController,
              physics:
                  _isDragging ? const NeverScrollableScrollPhysics() : null,
              shrinkWrap: true,
              padding: EdgeInsets.symmetric(vertical: 6.sp),
              itemCount: _flatItems.length,
              itemBuilder: (context, index) {
                final item = _flatItems[index];
                final isSelected = index == _selectedFlatIndex;

                // Create key for measurement
                _itemKeys[index] ??= GlobalKey();

                if (item.type == _ItemType.category) {
                  final category = item.category!;
                  final isExpanded = _expandedCategoryId == category.tour.id;
                  final hasRounds = widget.rounds.isNotEmpty;

                  return KeyedSubtree(
                    key: _itemKeys[index],
                    child: _CategoryRow(
                      index: index,
                      animation: widget.animation,
                      category: category,
                      isSelected: isSelected,
                      isExpanded: isExpanded,
                      hasRounds: hasRounds,
                      onTap: () {
                        _animateToIndex(index);
                        // Switch to this category
                        widget.onCategorySelect(category);
                      },
                      onToggleExpand: () {
                        // ONLY expand/collapse, don't select category
                        _toggleExpand(category.tour.id);
                      },
                      onArrowTapped: _onArrowTapped,
                    ),
                  );
                } else {
                  final round = item.round!;
                  final isNested = hasMultipleCategories;
                  final parentCategoryId = item.parentCategoryId;

                  return KeyedSubtree(
                    key: _itemKeys[index],
                    child: _RoundRow(
                      index: index,
                      animation: widget.animation,
                      round: round,
                      isSelected: isSelected,
                      isNested: isNested,
                      onTap: () {
                        _animateToIndex(index);
                        // Select the parent category ONLY if it's different from current
                        // This prevents unnecessary tour reload which loses round selection
                        if (parentCategoryId != null &&
                            parentCategoryId !=
                                widget.selectedCategory.tour.id) {
                          final parentCategory = widget.categories.firstWhere(
                            (c) => c.tour.id == parentCategoryId,
                            orElse: () => widget.selectedCategory,
                          );
                          // When switching categories, we need to select both category AND round
                          // The round selection is passed via userSelectedRoundProvider so it persists
                          widget.onCategorySelect(parentCategory);
                        }
                        // Select the round (this also sets userSelectedRoundProvider for sticky selection)
                        widget.onRoundSelect(round);
                      },
                    ),
                  );
                }
              },
            ),
          ),

          // Floating droplet selector
          Positioned.fill(
            child: ClipRect(
              child: IgnorePointer(
                child: ListenableBuilder(
                  listenable: _scrollController,
                  builder: (context, _) {
                    final scrollOffset =
                        _scrollController.hasClients
                            ? _scrollController.offset
                            : 0.0;
                    final selectorHeight = _getItemHeight(_selectedFlatIndex);
                    // Keep indicator centered within the row regardless of item height
                    final indicatorInset = 2.sp;
                    final indicatorHeight = (selectorHeight -
                            indicatorInset * 2)
                        .clamp(0.0, double.infinity);

                    return SingleMotionBuilder(
                      motion:
                          _isDragging
                              ? CupertinoMotion.snappy()
                              : CupertinoMotion.bouncy(),
                      value: _targetY - scrollOffset + 6.sp + indicatorInset,
                      // Account for list padding and center the indicator vertically
                      builder: (context, animatedY, _) {
                        return CustomPaint(
                          painter: _DropletSelectionPainter(
                            y: animatedY,
                            height: indicatorHeight,
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
          ),
        ],
      ),
    );
  }
}

enum _ItemType { category, round }

class _DropdownItem {
  final _ItemType type;
  final TourModel? category;
  final GamesAppBarModel? round;
  final String? parentCategoryId;

  _DropdownItem({
    required this.type,
    this.category,
    this.round,
    this.parentCategoryId,
  });
}

/// Category row with expand/collapse arrow
class _CategoryRow extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final TourModel category;
  final bool isSelected;
  final bool isExpanded;
  final bool hasRounds;
  final VoidCallback onTap;
  final VoidCallback onToggleExpand;
  final VoidCallback onArrowTapped;

  const _CategoryRow({
    required this.index,
    required this.animation,
    required this.category,
    required this.isSelected,
    required this.isExpanded,
    required this.hasRounds,
    required this.onTap,
    required this.onToggleExpand,
    required this.onArrowTapped,
  });

  @override
  Widget build(BuildContext context) {
    final itemDelay = index * 0.05;
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
          offset: Offset(0, 12 * (1 - clampedValue)),
          child: Opacity(opacity: clampedValue, child: child),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 10.sp),
        color: Colors.transparent,
        child: Row(
          children: [
            // Tappable area for category selection (live dot + name)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Row(
                  children: [
                    // Live indicator
                    if (category.roundStatus == RoundStatus.live) ...[
                      _LiveDot(),
                      SizedBox(width: 8.sp),
                    ],
                    // Category name
                    Expanded(
                      child: _MarqueeText(
                        text: _extractName(category.tour.name),
                        style: AppTypography.textSmMedium.copyWith(
                          color: isSelected ? kPrimaryColor : kWhiteColor,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                        continuous: true, // Continuous in open dropdown
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Expand/collapse arrow - SEPARATE tap target
            if (hasRounds) ...[
              SizedBox(width: 8.sp),
              GestureDetector(
                onTapDown: (_) => onArrowTapped(),
                onTap: onToggleExpand,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.all(6.sp),
                  child: AnimatedRotation(
                    turns: isExpanded ? -0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20.ic,
                      color:
                          isExpanded
                              ? kWhiteColor
                              : context.colors.textPrimary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _extractName(String fullName) {
    // Extract just the category part if formatted with separator
    if (fullName.contains('|')) {
      return fullName.split('|').last.trim();
    }
    if (fullName.contains(':')) {
      return fullName.split(':').last.trim();
    }

    // Look for common category patterns like "Boards X-Y" or "Boards X+"
    final boardsMatch = RegExp(
      r'(Boards?\s+\d+[\-\+]?\d*\+?)$',
      caseSensitive: false,
    ).firstMatch(fullName);
    if (boardsMatch != null) {
      return boardsMatch.group(0)!.trim();
    }

    // Look for patterns like "Group A", "Section B", "Division 1"
    final groupMatch = RegExp(
      r'((?:Group|Section|Division|Category)\s+\w+)$',
      caseSensitive: false,
    ).firstMatch(fullName);
    if (groupMatch != null) {
      return groupMatch.group(0)!.trim();
    }

    // Don't truncate - let the marquee/ellipsis handle overflow
    return fullName;
  }
}

/// Round row (can be nested under a category)
class _RoundRow extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final GamesAppBarModel round;
  final bool isSelected;
  final bool isNested;
  final VoidCallback onTap;

  const _RoundRow({
    required this.index,
    required this.animation,
    required this.round,
    required this.isSelected,
    required this.isNested,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final itemDelay = index * 0.04;
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
          offset: Offset(0, 8 * (1 - clampedValue)),
          child: Opacity(opacity: clampedValue, child: child),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.only(
            left: isNested ? 28.sp : 14.sp,
            right: 14.sp,
            top: 8.sp,
            bottom: 8.sp,
          ),
          color: Colors.transparent,
          child: Row(
            children: [
              // Live indicator
              if (round.roundStatus == RoundStatus.live) ...[
                _LiveDot(),
                SizedBox(width: 8.sp),
              ],
              // Round name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MarqueeText(
                      text: round.name,
                      style: AppTypography.textSmRegular.copyWith(
                        color:
                            isSelected
                                ? kPrimaryColor
                                : context.colors.textPrimary.withValues(alpha: 0.85),
                        fontWeight:
                            isSelected ? FontWeight.w500 : FontWeight.w400,
                      ),
                      continuous: true, // Continuous in open dropdown
                    ),
                    if (round.formattedRoundDateTime.isNotEmpty)
                      Text(
                        round.formattedRoundDateTime,
                        style: AppTypography.textXxsRegular.copyWith(
                          color:
                              isSelected
                                  ? kPrimaryColor.withValues(alpha: 0.7)
                                  : context.colors.textPrimary.withValues(alpha: 0.5),
                          fontSize: 10.sp,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Water droplet selection indicator painter
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

    // Calculate morph distortion for organic feel
    final distortionEnvelope = math.sin(morphProgress * math.pi);
    final distortion = distortionEnvelope * 0.5;
    final maxBulge = math.min(w, h) * 0.05;
    final bulge = distortion * maxBulge;

    final phaseOffset = morphProgress * math.pi * 2.5;

    final path = Path();
    final r = baseRadius.clamp(0.0, math.min(w, h) / 2);

    if (bulge.abs() < 0.5) {
      path.addRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
      );
    } else {
      final topBulge = bulge * math.sin(phaseOffset) * 0.7;
      final rightBulge = bulge * math.sin(phaseOffset + math.pi * 0.5) * 0.5;
      final bottomBulge = bulge * math.sin(phaseOffset + math.pi) * 0.8;
      final leftBulge = bulge * math.sin(phaseOffset + math.pi * 1.5) * 0.5;
      final cornerExpand = bulge * 0.4 * math.cos(phaseOffset * 0.8);

      path.moveTo(x + r + cornerExpand, y);
      path.quadraticBezierTo(
        x + w / 2,
        y - topBulge,
        x + w - r - cornerExpand,
        y,
      );

      final trCornerOffset = cornerExpand * 0.7;
      path.quadraticBezierTo(
        x + w + trCornerOffset,
        y - trCornerOffset,
        x + w,
        y + r + cornerExpand,
      );

      path.quadraticBezierTo(
        x + w + rightBulge,
        y + h / 2,
        x + w,
        y + h - r - cornerExpand,
      );

      final brCornerOffset = cornerExpand * 0.7;
      path.quadraticBezierTo(
        x + w + brCornerOffset,
        y + h + brCornerOffset,
        x + w - r - cornerExpand,
        y + h,
      );

      path.quadraticBezierTo(
        x + w / 2,
        y + h + bottomBulge,
        x + r + cornerExpand,
        y + h,
      );

      final blCornerOffset = cornerExpand * 0.7;
      path.quadraticBezierTo(
        x - blCornerOffset,
        y + h + blCornerOffset,
        x,
        y + h - r - cornerExpand,
      );

      path.quadraticBezierTo(x - leftBulge, y + h / 2, x, y + r + cornerExpand);

      final tlCornerOffset = cornerExpand * 0.7;
      path.quadraticBezierTo(
        x - tlCornerOffset,
        y - tlCornerOffset,
        x + r + cornerExpand,
        y,
      );

      path.close();
    }

    // Fill
    final fillPaint =
        Paint()
          ..color = baseColor.withValues(alpha: isDragging ? 0.18 : 0.10)
          ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Border
    final borderPaint =
        Paint()
          ..color = baseColor.withValues(alpha: isDragging ? 0.45 : 0.30)
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

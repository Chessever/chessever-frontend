import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_match_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Dropdown for navigating between matches in knockout tournaments
/// Shows current match based on scroll position and allows jumping to specific matches
class KnockoutMatchDropdown extends ConsumerWidget {
  const KnockoutMatchDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 38.h,
      width: 120.w,
      child: _KnockoutMatchDropdownContent(),
    );
  }
}

class _KnockoutMatchDropdownContent extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchScrollState = ref.watch(knockoutMatchScrollProvider);
    final matches = ref.read(knockoutMatchScrollProvider.notifier).getMatchHeaders();

    if (matches.isEmpty) {
      return const SizedBox.shrink();
    }

    // Find the selected match (either user-selected or auto-tracked from scroll)
    final selectedMatchKey = matchScrollState.selectedMatchKey ?? matchScrollState.visibleMatchKey;
    final selectedMatch = matches.firstWhere(
      (m) => m.matchKey == selectedMatchKey,
      orElse: () => matches.first,
    );

    return _MatchDropdown(
      matches: matches,
      selectedMatch: selectedMatch,
      onChanged: (match) {
        // User selected a match - scroll to it
        ref.read(knockoutMatchScrollProvider.notifier).selectMatch(match.matchKey);
        _scrollToMatch(ref, match.matchKey);
      },
    );
  }

  void _scrollToMatch(WidgetRef ref, String matchKey) {
    final scrollController = ref.read(gamesTourScrollProvider);
    final itemIndex = ref.read(knockoutMatchScrollProvider.notifier).calculateMatchHeaderIndex(matchKey);

    if (scrollController.isAttached) {
      try {
        scrollController.scrollTo(
          index: itemIndex,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.0, // Position at top
        );
      } catch (e) {
        // Fallback to jumpTo
        scrollController.jumpTo(index: itemIndex, alignment: 0.0);
      }
    }
  }
}

class _MatchDropdown extends HookConsumerWidget {
  final List<MatchHeaderModel> matches;
  final MatchHeaderModel selectedMatch;
  final ValueChanged<MatchHeaderModel> onChanged;

  const _MatchDropdown({
    required this.matches,
    required this.selectedMatch,
    required this.onChanged,
  });

  Widget _buildMatchRow(MatchHeaderModel match, bool isSelected) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Match title (shortened for dropdown)
                  Text(
                    _shortenMatchTitle(match.matchTitle),
                    style: AppTypography.textXsRegular.copyWith(
                      color: isSelected ? kPrimaryColor : kWhiteColor,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.h),
                  // Score
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 5.w,
                          vertical: 1.h,
                        ),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3.br),
                        ),
                        child: Text(
                          match.scoreDisplay,
                          style: AppTypography.textXsRegular.copyWith(
                            color: kPrimaryColor,
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        '${match.games.length}g',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor70,
                          fontSize: 9.sp,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            // Status icon
            if (match.isComplete)
              SvgPicture.asset(
                SvgAsset.check,
                width: 14.w,
                height: 14.h,
                colorFilter: const ColorFilter.mode(
                  Colors.green,
                  BlendMode.srcIn,
                ),
              )
            else
              SvgPicture.asset(
                SvgAsset.selectedSvg,
                width: 14.w,
                height: 14.h,
              ),
          ],
        ),
      ],
    );
  }

  String _shortenMatchTitle(String title) {
    // "Player1 vs Player2" -> "P1 vs P2" or shortened names
    final parts = title.split(' vs ');
    if (parts.length == 2) {
      final name1 = _shortenName(parts[0]);
      final name2 = _shortenName(parts[1]);
      return '$name1 vs $name2';
    }
    return title;
  }

  String _shortenName(String name) {
    // If name is too long, take first name or abbreviate
    if (name.length <= 12) return name;

    final nameParts = name.split(' ');
    if (nameParts.length > 1) {
      // Return first name + last initial
      return '${nameParts[0]} ${nameParts.last[0]}.';
    }

    return '${name.substring(0, 10)}...';
  }

  void _showOverlay(
    BuildContext context,
    LayerLink layerLink,
    ValueNotifier<bool> isOpen,
  ) {
    OverlayEntry? overlayEntry;
    final sortedMatches = List<MatchHeaderModel>.from(matches);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
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
        final availableHeight =
            MediaQuery.of(context).size.height - offset.dy - size.height - 20;

        overlayEntry = OverlayEntry(
          builder: (context) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => isOpen.value = false,
            child: Stack(
              children: [
                Positioned(
                  left: offset.dx,
                  top: offset.dy + size.height,
                  width: 240.w,
                  child: CompositedTransformFollower(
                    link: layerLink,
                    showWhenUnlinked: false,
                    offset: Offset(-60.w, size.height),
                    child: Material(
                      color: Colors.transparent,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: availableHeight,
                          minWidth: size.width,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: kBlack2Color,
                            borderRadius: BorderRadius.circular(20.br),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 8.h),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: sortedMatches.length,
                            separatorBuilder: (context, index) {
                              return Padding(
                                padding: EdgeInsets.symmetric(vertical: 5.h),
                                child: DividerWidget(),
                              );
                            },
                            itemBuilder: (context, index) {
                              final match = sortedMatches[index];
                              final isSelected = match.matchKey == selectedMatch.matchKey;

                              return InkWell(
                                onTap: () {
                                  onChanged(match);
                                  isOpen.value = false;
                                },
                                child: Container(
                                  color: isSelected
                                      ? kBlack2Color.withValues(alpha: 0.5)
                                      : Colors.transparent,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12.w,
                                    vertical: 6.h,
                                  ),
                                  child: _buildMatchRow(match, isSelected),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
        overlayEntry!.addListener(() {
          if (!overlayEntry!.mounted) {
            isOpen.removeListener(removeOverlay);
          }
        });
      } catch (e) {
        isOpen.value = false;
        if (overlayEntry?.mounted == true) {
          try {
            overlayEntry?.remove();
          } catch (_) {
            overlayEntry?.dispose();
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layerLink = useMemoized(() => LayerLink());
    final isOpen = useState(false);

    useEffect(() {
      return () {
        try {
          if (isOpen.value) {
            isOpen.value = false;
          }
        } catch (e) {
          // Silently ignore disposal errors
        }
      };
    }, []);

    return CompositedTransformTarget(
      link: layerLink,
      child: InkWell(
        splashColor: Colors.transparent,
        onTap: () {
          try {
            if (matches.length <= 1) return;

            if (isOpen.value) {
              isOpen.value = false;
            } else {
              isOpen.value = true;
              _showOverlay(context, layerLink, isOpen);
            }
          } catch (e) {
            isOpen.value = false;
          }
        },
        child: Container(
          height: 32.h,
          width: 250.w,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _shortenMatchTitle(selectedMatch.matchTitle),
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                        fontSize: 11.sp,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      selectedMatch.scoreDisplay,
                      style: AppTypography.textXsRegular.copyWith(
                        color: kPrimaryColor,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (matches.length > 1)
                Container(
                  padding: EdgeInsets.all(2.sp),
                  decoration: BoxDecoration(
                    boxShadow: kElevationToShadow[9],
                    color: kWhiteColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.keyboard_arrow_down_outlined,
                    color: kWhiteColor70,
                    size: 18.ic,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

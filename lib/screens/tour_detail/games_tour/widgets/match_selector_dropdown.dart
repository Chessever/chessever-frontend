import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Dropdown selector for navigating between matches in knockout tournaments
class MatchSelectorDropdown extends ConsumerWidget {
  final Function(String matchKey)? onMatchSelected;

  const MatchSelectorDropdown({super.key, this.onMatchSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 38.h,
      width: 180.w,
      child: ref
          .watch(gamesTourScreenProvider)
          .when(
            data: (gamesData) {
              final allGames = gamesData.gamesTourModels;

              // Group games by matches
              final matchesMap =
                  KnockoutMatchDetector.groupByMatchesAcrossAllRounds(allGames);

              // Convert to list of match headers using the detector's helper
              final matches =
                  matchesMap.entries.map((entry) {
                    final matchKey = entry.key;
                    final matchGames = entry.value;
                    return KnockoutMatchDetector.createMatchHeader(
                      matchKey,
                      matchGames,
                    );
                  }).toList();

              // Sort matches by completion status and name
              matches.sort((a, b) {
                // Show incomplete matches first
                if (a.isComplete != b.isComplete) {
                  return a.isComplete ? 1 : -1;
                }
                return a.matchTitle.compareTo(b.matchTitle);
              });

              return _MatchDropdown(
                matches: matches,
                onChanged: (match) {
                  onMatchSelected?.call(match.matchKey);
                },
              );
            },
            error:
                (e, _) => Center(
                  child: Text(
                    'Error loading matches',
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor70,
                    ),
                  ),
                ),
            loading: () => const SizedBox.shrink(),
          ),
    );
  }
}

class _MatchDropdown extends HookConsumerWidget {
  final List<MatchHeaderModel> matches;
  final ValueChanged<MatchHeaderModel> onChanged;

  const _MatchDropdown({required this.matches, required this.onChanged});

  Widget _buildMatchRow(MatchHeaderModel match) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                match.matchTitle,
                style: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 2.h),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 6.w,
                      vertical: 2.h,
                    ),
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4.br),
                    ),
                    child: Text(
                      match.scoreDisplay,
                      style: AppTypography.textXsRegular.copyWith(
                        color: kPrimaryColor,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Text(
                    '${match.games.length} ${match.games.length == 1 ? 'game' : 'games'}',
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor70,
                      fontSize: 10.sp,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(width: 8.w),
        if (match.isComplete)
          SvgPicture.asset(
            SvgAsset.check,
            width: 14.w,
            height: 14.h,
            colorFilter: const ColorFilter.mode(Colors.green, BlendMode.srcIn),
          )
        else
          SvgPicture.asset(SvgAsset.selectedSvg, width: 14.w, height: 14.h),
      ],
    );
  }

  void _showOverlay(
    BuildContext context,
    LayerLink layerLink,
    ValueNotifier<bool> isOpen,
    ValueNotifier<int> selectedIndex,
  ) {
    OverlayEntry? overlayEntry;
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
          builder:
              (context) => GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => isOpen.value = false,
                child: Stack(
                  children: [
                    Positioned(
                      left: offset.dx,
                      top: offset.dy + size.height,
                      width: 280.w,
                      child: CompositedTransformFollower(
                        link: layerLink,
                        showWhenUnlinked: false,
                        offset: Offset(-50.w, size.height),
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
                                itemCount: matches.length,
                                separatorBuilder: (context, index) {
                                  return Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 5.h,
                                    ),
                                    child: DividerWidget(),
                                  );
                                },
                                itemBuilder: (context, index) {
                                  final match = matches[index];
                                  final isSelected =
                                      index == selectedIndex.value;

                                  return InkWell(
                                    onTap: () {
                                      selectedIndex.value = index;
                                      onChanged(match);
                                      isOpen.value = false;
                                    },
                                    child: Container(
                                      color:
                                          isSelected
                                              ? kBlack2Color.withValues(
                                                alpha: 0.5,
                                              )
                                              : Colors.transparent,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12.w,
                                        vertical: 6.h,
                                      ),
                                      child: _buildMatchRow(match),
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
    final selectedIndex = useState(0);

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

    if (matches.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedMatch =
        matches[selectedIndex.value.clamp(0, matches.length - 1)];

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
              _showOverlay(context, layerLink, isOpen, selectedIndex);
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
                      selectedMatch.matchTitle,
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

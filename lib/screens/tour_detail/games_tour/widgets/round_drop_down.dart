import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RoundDropDown extends ConsumerWidget {
  const RoundDropDown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 38.h,
      width: 120.w,
      child: ref
          .watch(gamesAppBarProvider)
          .when(
            data: (data) {
              print(
                'Selected Round ${data.gamesAppBarModels.firstWhere((a) => a.id == data.selectedId, orElse: () => data.gamesAppBarModels.first).name}',
              );
              return _RoundDropdown(
                rounds: data.gamesAppBarModels,
                selectedRoundId: data.selectedId,
                onChanged: (model) {
                  ref.read(gamesAppBarProvider.notifier).select(model);
                },
              );
            },
            error: (e, _) {
              return Center(
                child: Text(
                  'Error loading rounds',
                  style: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor70,
                  ),
                ),
              );
            },
            loading: () {
              final loadingRound = GamesAppBarViewModel(
                gamesAppBarModels: [
                  GamesAppBarModel(
                    id: 'loading',
                    name: 'Loading...',
                    roundStatus: RoundStatus.upcoming,
                    startsAt: DateTime.now(),
                  ),
                ],
                selectedId: 'loading',
              );
              return SkeletonWidget(
                child: _RoundDropdown(
                  rounds: loadingRound.gamesAppBarModels,
                  selectedRoundId: loadingRound.gamesAppBarModels.first.id,
                  onChanged: (_) {},
                ),
              );
            },
          ),
    );
  }
}

class _RoundDropdown extends HookConsumerWidget {
  final List<GamesAppBarModel> rounds;
  final String? selectedRoundId;
  final ValueChanged<GamesAppBarModel> onChanged;

  const _RoundDropdown({
    required this.rounds,
    required this.selectedRoundId,
    required this.onChanged,
  });

  Widget _buildRow(GamesAppBarModel round, bool showDivider) {
    Widget trailingIcon;
    switch (round.roundStatus) {
      case RoundStatus.completed:
        trailingIcon = SvgPicture.asset(
          SvgAsset.check,
          width: 16.w,
          height: 16.h,
        );
        break;
      case RoundStatus.live:
      case RoundStatus.ongoing:
        trailingIcon = SvgPicture.asset(
          SvgAsset.selectedSvg,
          width: 16.w,
          height: 16.h,
        );
        break;
      case RoundStatus.upcoming:
        trailingIcon = SvgPicture.asset(
          SvgAsset.calendarIcon,
          width: 16.w,
          height: 16.h,
        );
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    round.name,
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    round.formattedStartDate,
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor70,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            trailingIcon,
          ],
        ),
        if (showDivider)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 5.h),
            child: DividerWidget(),
          ),
      ],
    );
  }

  void _showOverlay(
    BuildContext context,
    LayerLink layerLink,
    ValueNotifier<bool> isOpen,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      final overlay = Overlay.of(context);

      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final size = renderBox.size;
      final offset = renderBox.localToGlobal(Offset.zero);

      final availableHeight =
          MediaQuery.of(context).size.height - offset.dy - size.height - 20;

      final reversedRounds = rounds.reversed.toList();

      final entry = OverlayEntry(
        builder:
            (context) => GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => isOpen.value = false,
              child: Stack(
                children: [
                  Positioned(
                    left: offset.dx,
                    top: offset.dy + size.height,
                    width: 225.w,
                    child: CompositedTransformFollower(
                      link: layerLink,
                      showWhenUnlinked: false,
                      offset: Offset(-28.w, size.height),
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
                              itemCount: reversedRounds.length,
                              separatorBuilder: (context, index) {
                                return Padding(
                                  padding: EdgeInsets.symmetric(vertical: 5.h),
                                  child: DividerWidget(),
                                );
                              },
                              itemBuilder: (context, index) {
                                final round = reversedRounds[index];
                                final isSelected = round.id == selectedRoundId;

                                return InkWell(
                                  onTap: () {
                                    if (!isSelected) {
                                      onChanged(round);
                                    }
                                    isOpen.value = false;
                                  },
                                  child: Container(
                                    color:
                                        isSelected
                                            ? kBlack2Color.withOpacity(0.5)
                                            : Colors.transparent,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12.w,
                                      vertical: 4.h,
                                    ),
                                    child: _buildRow(round, false),
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

      overlay.insert(entry);

      void removeListener() {
        if (entry.mounted) {
          entry.remove();
        }
      }

      isOpen.addListener(removeListener);

      entry.addListener(() {
        if (!entry.mounted) {
          isOpen.removeListener(removeListener);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layerLink = useMemoized(() => LayerLink());
    final isOpen = useState(false);
    final reversedRounds = rounds.reversed.toList();
    final selected = reversedRounds.firstWhere(
      (r) => r.id == selectedRoundId,
      orElse:
          () =>
              rounds.isNotEmpty
                  ? reversedRounds.first
                  : GamesAppBarModel(
                    id: 'default',
                    name: 'No rounds',
                    roundStatus: RoundStatus.upcoming,
                    startsAt: DateTime.now(),
                  ),
    );

    return CompositedTransformTarget(
      link: layerLink,
      child: InkWell(
        splashColor: Colors.transparent,
        onTap: () {
          if (rounds.length <= 1) return;
          if (isOpen.value) {
            isOpen.value = false;
          } else {
            isOpen.value = true;
            _showOverlay(context, layerLink, isOpen);
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
                child: Text(
                  selected.name,
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (rounds.length > 1)
                Container(
                  padding: EdgeInsets.all(2.sp),
                  decoration: BoxDecoration(
                    boxShadow: kElevationToShadow[9],
                    color: kWhiteColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.keyboard_arrow_down_outlined,
                    color: kWhiteColor70,
                    size: 20.ic,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

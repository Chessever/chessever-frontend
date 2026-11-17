import 'dart:math' as math;

import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/category_dropdown.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';

class GamesAppBarWidget extends ConsumerWidget {
  const GamesAppBarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tourDetailAsync = ref.watch(tourDetailScreenProvider);
    final reach = AppBarIconSurface.bareReach;
    return tourDetailAsync.when(
      data: (tourData) {
        final hasTours = tourData.tours.isNotEmpty;

        return Row(
          children: [
            SizedBox(width: 16.w),
            Semantics(
              label: 'Back button',
              child: IconButton(
                iconSize: 24.ic,
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
              ),
            ),
            if (hasTours) ...[
              Expanded(
                child: Padding(
                  // The view toggle's tap target reaches past where its tile
                  // ended, so the dropdown's slot gives that back and keeps
                  // its width.
                  padding: EdgeInsetsDirectional.only(
                    start: 12.w,
                    end: math.max(0, 12.w - reach),
                  ),
                  child: const Center(child: CategoryDropdown()),
                ),
              ),
              // Bare glyphs (Trello #1420): no tile behind the view toggle
              // or the ⋮. Each sits where its tile used to, on a 44pt target.
              Semantics(
                label: 'Toggle chessboard view',
                child: AppBarIcons(
                  image: SvgAsset.chase_grid,
                  boxed: false,
                  onTap: () {
                    ref.read(gamesListViewModeSwitcher).toggleViewMode();
                  },
                ),
              ),
              SizedBox(width: math.max(0, 18.w - 2 * reach)),
              Semantics(
                label: 'More options',
                child: TournamentMenuButton(tourData: tourData, boxed: false),
              ),
              SizedBox(width: math.max(0, 20.w - reach)),
            ],
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error:
          (e, _) => Center(
            child: Text(
              'Error loading tours',
              style: AppTypography.textXsRegular.copyWith(color: context.colors.textPrimaryMuted),
            ),
          ),
    );
  }
}

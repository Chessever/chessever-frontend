import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';
import 'package:chessever2/widgets/icons/analysis_board_icon.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 24.h + MediaQuery.of(context).viewPadding.top),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Search bar
                Expanded(
                  flex: 7,
                  child: Hero(
                    tag: 'search_bar',
                    child: SimpleSearchBar(
                      controller: _searchController,
                      hintText: 'Search Library',
                      onChanged: (value) {
                        // Handle search
                      },
                      onMenuTap: () {
                        // Handle menu tap
                        print('Menu tapped');
                      },
                      onFilterTap: () {
                        // Show the filter popup
                        showDialog(
                          context: context,
                          barrierColor: kLightBlack,
                          builder: (context) => const FilterPopup(),
                        );
                      },
                    ),
                  ),
                ),

                // Small spacing between search bar and dropdown
                SizedBox(width: 16.w),
                Container(
                  padding: EdgeInsets.all(8.br),
                  decoration: _boxDecoration,
                  child: AnalysisBoardIcon(size: 24.ic),
                ),
                SizedBox(width: 16.w),
                _PlusIcon(),
              ],
            ),
          ),
          Spacer(),
          _ComingSoonWidget(),
          Spacer(),
        ],
      ),
    );
  }
}

class _ComingSoonWidget extends StatelessWidget {
  const _ComingSoonWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SvgWidget(SvgAsset.bookIcon, width: 64.w, height: 64.h),
        SizedBox(height: 12.h),
        Text(
          'Library Coming Soon',
          style: AppTypography.textLgMedium.copyWith(color: kWhiteColor),
        ),
        SizedBox(width: 8.w),
        Text(
          'Your personal library will be\navailable in a future update.',
          style: AppTypography.textMdRegular.copyWith(color: kInactiveTabColor),
        ),
      ],
    );
  }
}

final _boxDecoration = BoxDecoration(
  color: kBlack2Color,
  borderRadius: BorderRadius.circular(2.br),
);

class _PlusIcon extends StatelessWidget {
  const _PlusIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8.sp),
      decoration: _boxDecoration,
      child: Icon(Icons.add_rounded, color: Colors.white, size: 24.ic),
    );
  }
}

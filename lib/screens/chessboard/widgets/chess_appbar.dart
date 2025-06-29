import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

class ChessMatchAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBackPressed;
  final VoidCallback? onSettingsPressed;
  final VoidCallback? onMoreOptionsPressed;

  const ChessMatchAppBar({
    required this.title,
    this.onBackPressed,
    this.onSettingsPressed,
    this.onMoreOptionsPressed,
    super.key,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: SvgWidget(
          height: 20.h,
          width: 20.w,
          'assets/svgs/left_arrow.svg',
          semanticsLabel: 'Back',
        ),
        onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: AppTypography.textSmBold.copyWith(color: Colors.white),
          ),
          SizedBox(width: 7),
          SvgWidget(
            height: 20.h,
            width: 20.w,
            'assets/svgs/arrow_down.svg',
            semanticsLabel: 'Back',
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          // icon: Icon(Icons.create_new_folder_outlined),
          icon: SvgWidget(
            height: 20.h,
            width: 20.w,
            'assets/svgs/folderPlus.svg',
            semanticsLabel: 'Settings',
          ),
          onPressed: onSettingsPressed,
        ),
        IconButton(
          // icon: Icon(Icons.share),
          icon: SvgWidget(
            height: 20.h,
            width: 20.w,
            'assets/svgs/share.svg',
            semanticsLabel: 'Share',
          ),
          onPressed: onMoreOptionsPressed,
        ),
      ],
    );
  }
}

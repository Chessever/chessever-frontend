import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

class CompletedEventMenu extends StatelessWidget {
  final VoidCallback? onDownloadTournament;
  final VoidCallback? onAddToLibrary;

  const CompletedEventMenu({
    Key? key,
    this.onDownloadTournament,
    this.onAddToLibrary,
  }) : super(key: key);

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: ResponsiveHelper.bottomSheetConstraints,
      // On tablets, disable barrier tap to prevent phantom tap dismissals
      isDismissible: !ResponsiveHelper.isTablet,
      enableDrag: true,
      builder:
          (context) => Container(
            decoration:  BoxDecoration(
              color: context.colors.background,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.download,
                    color: context.colors.iconPrimary,
                  ),
                  title: Text(
                    'Download Tournament PGN',
                    style: TextStyle(color: context.colors.textPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onDownloadTournament?.call();
                  },
                ),
                DividerWidget(),
                ListTile(
                  leading: Icon(
                    Icons.library_add_outlined,
                    color: context.colors.iconPrimary,
                  ),
                  title: Text(
                    'Add to Library',
                    style: TextStyle(color: context.colors.textPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onAddToLibrary?.call();
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.more_vert,
        color:
            context.isLightTheme ? context.colors.iconSecondary : Colors.grey,
        size: 24,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: () => _showMenu(context),
    );
  }
}

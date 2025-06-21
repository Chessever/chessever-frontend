// import 'package:flutter/material.dart';
// import 'package:hooks_riverpod/hooks_riverpod.dart';
// import 'package:chessever2/utils/app_typography.dart';
// import 'package:chessever2/theme/app_theme.dart';
// import '../providers/board_settings_provider.dart';
// import 'board_color_dialog.dart';

// class BoardSettingsDialog extends ConsumerWidget {
//   const BoardSettingsDialog({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final boardSettings = ref.watch(boardSettingsProvider);

//     return Dialog(
//       backgroundColor: Colors.transparent,
//       insetPadding: const EdgeInsets.symmetric(
//         horizontal: 24.0,
//         vertical: 24.0,
//       ),
//       child: Container(
//         width: 180.5,
//         decoration: BoxDecoration(
//           color: Colors.black,
//           borderRadius: BorderRadius.circular(
//             20,
//           ), // Updated corner radius to 20px
//         ),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             _buildMenuItem(
//               icon: Icons.palette_outlined,
//               title: 'Set board colour',
//               onPressed: () {
//                 showDialog(
//                   context: context,
//                   builder: (context) => const BoardColorDialog(),
//                 );
//               },
//               showChevron: false,
//             ),
//             const Divider(height: 1, thickness: 0.5, color: Color(0xFF2C2C2E)),
//             _buildSwitchItem(
//               title: 'Evaluation bar',
//               value: boardSettings.showEvaluationBar,
//               onChanged: (value) {
//                 ref.read(boardSettingsProvider.notifier).toggleEvaluationBar();
//               },
//             ),
//             const Divider(height: 1, thickness: 0.5, color: Color(0xFF2C2C2E)),
//             _buildSwitchItem(
//               title: 'Sound',
//               value: boardSettings.soundEnabled,
//               onChanged: (value) {
//                 ref.read(boardSettingsProvider.notifier).toggleSound();
//               },
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildMenuItem({
//     IconData? icon,
//     Widget? customIcon,
//     required String title,
//     required VoidCallback onPressed,
//     required bool showChevron,
//   }) {
//     return SizedBox(
//       height: 36,
//       child: ListTile(
//         contentPadding: const EdgeInsets.only(left: 12),
//         minLeadingWidth: 40,
//         horizontalTitleGap: 4, // Gap between icon and text as specified
//         dense: true,
//         leading:
//             customIcon ??
//             Icon(
//               icon!,
//               color: kWhiteColor,
//               size: 20,
//             ), // Updated icon size to 20x20
//         title: Text(
//           title,
//           style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
//           textAlign: TextAlign.left,
//         ),
//         trailing:
//             showChevron
//                 ? const Padding(
//                   padding: EdgeInsets.only(right: 12),
//                   child: Icon(
//                     Icons.chevron_right_outlined,
//                     color: kWhiteColor,
//                     size: 20, // Updated icon size to 20x20
//                   ),
//                 )
//                 : null,
//         onTap: onPressed,
//         titleAlignment:
//             ListTileTitleAlignment
//                 .center, // Ensures text is centered vertically
//       ),
//     );
//   }

//   Widget _buildSwitchItem({
//     required String title,
//     required bool value,
//     required ValueChanged<bool> onChanged,
//   }) {
//     return SizedBox(
//       height: 36,
//       child: ListTile(
//         contentPadding: const EdgeInsets.only(left: 12, right: 12),
//         dense: true,
//         title: Text(
//           title,
//           style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
//         ),
//         trailing: SizedBox(
//           width: 24, // Exact width of 24px
//           height: 14.6, // Exact height of 14.6px
//           child: FittedBox(
//             fit: BoxFit.fill,
//             child: Switch(
//               value: value,
//               onChanged: onChanged,
//               activeColor: Colors.white,
//               activeTrackColor: kPrimaryColor,
//               inactiveThumbColor: Colors.white,
//               inactiveTrackColor: Colors.grey.withOpacity(0.3),
//               materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
//             ),
//           ),
//         ),
//         onTap: () => onChanged(!value),
//         // Add vertical alignment for the title
//         titleAlignment: ListTileTitleAlignment.center,
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import '../providers/board_settings_provider.dart';
import 'board_color_dialog.dart';

class BoardSettingsDialog extends ConsumerWidget {
  const BoardSettingsDialog({Key? key}) : super(key: key);

  // Add a static method to show the dialog with a transparent barrier
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.transparent, // This prevents the black background
      builder: (context) => const BoardSettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettings = ref.watch(boardSettingsProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24.0,
        vertical: 24.0,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: kPopUpColor.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMenuItem(
              icon: Icons.palette_outlined,
              title: 'Set board colour',
              onPressed: () {
                showDialog(
                  context: context,
                  barrierColor: Colors.transparent,
                  builder: (context) => const BoardColorDialog(),
                );
              },
              showChevron: false,
            ),
            const Divider(height: 1, thickness: 0.5, color: Color(0xFF2C2C2E)),
            _buildSwitchItem(
              title: 'Evaluation bar',
              value: boardSettings.showEvaluationBar,
              onChanged: (value) {
                ref.read(boardSettingsProvider.notifier).toggleEvaluationBar();
              },
            ),
            const Divider(height: 1, thickness: 0.5, color: Color(0xFF2C2C2E)),
            _buildSwitchItem(
              title: 'Sound',
              value: boardSettings.soundEnabled,
              onChanged: (value) {
                ref.read(boardSettingsProvider.notifier).toggleSound();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    IconData? icon,
    Widget? customIcon,
    required String title,
    required VoidCallback onPressed,
    required bool showChevron,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 12),
      minLeadingWidth: 40,
      horizontalTitleGap: 4,
      leading: customIcon ?? Icon(icon!, color: kWhiteColor, size: 20),
      title: Text(
        title,
        style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
      ),
      trailing:
          showChevron
              ? const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.chevron_right_outlined,
                  color: kWhiteColor,
                  size: 20,
                ),
              )
              : null,
      onTap: onPressed,
      titleAlignment: ListTileTitleAlignment.center,
    );
  }

  Widget _buildSwitchItem({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      height: 36,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 12),
        dense: true,
        title: Text(
          title,
          style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
        ),
        trailing: SizedBox(
          width: 24,
          height: 14.6,
          child: FittedBox(
            fit: BoxFit.fill,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: kPrimaryColor,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.grey.withOpacity(0.3),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        onTap: () => onChanged(!value),
        titleAlignment: ListTileTitleAlignment.center,
      ),
    );
  }
}

import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/screens/chessboard/chess_board_settings_page.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/settings_menu.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';

class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(20.sp)),
        color: kPopUpColor,
      ),
      child: SettingsMenu(
        boardSettingsIcon: SvgWidget(
          height: 20.h,
          width: 20.w,
          SvgAsset.boardSettings,
        ),
        onBoardSettingsPressed: () async {
          final allowed = await requireFullAuthGuard(context);
          if (!allowed || !context.mounted) return;

          // Close the current bottom sheet first
          Navigator.of(context).pop();
          if (!context.mounted) return;

          // Navigate to the full ChessBoardSettingsPage
          Navigator.of(context).push(
            ChessBoardSettingsPage.route(),
          );
        },
        onDeleteAccountPressed: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete Account'),
              content: const Text(
                'Are you sure you want to delete your account? This action cannot be undone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(context).pop(); // Close settings
                    
                    try {
                      await ref.read(authStateProvider.notifier).deleteAccount();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to delete account: $e')),
                        );
                      }
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: kRedColor),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

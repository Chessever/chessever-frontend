import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/chessboard/chess_board_settings_page.dart';
import 'package:chessever2/screens/chessboard/chess_board_notification_settings_page.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/settings_menu.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';

class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      key: e2eKey(E2eIds.settingsRoot),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(20.sp)),
        color: context.colors.popup,
      ),
      child: SettingsMenu(
        boardSettingsIcon: SvgWidget(
          height: 20.h,
          width: 20.w,
          SvgAsset.boardSettings,
        ),
        notificationSettingsIcon: Icon(
          Icons.notifications_active_outlined,
          color: context.colors.iconPrimary,
          size: 20.h,
        ),
        onBoardSettingsPressed: () async {
          final allowed = await requireFullAuthGuard(context);
          if (!allowed || !context.mounted) return;

          // Close the current bottom sheet first
          Navigator.of(context).pop();
          if (!context.mounted) return;

          // Navigate to the full ChessBoardSettingsPage
          Navigator.of(context).push(ChessBoardSettingsPage.route());
        },
        onNotificationSettingsPressed: () async {
          final allowed = await requireFullAuthGuard(context);
          if (!allowed || !context.mounted) return;

          // Close the current bottom sheet first
          Navigator.of(context).pop();
          if (!context.mounted) return;

          Navigator.of(
            context,
          ).push(ChessBoardNotificationSettingsPage.route());
        },
        onDeleteAccountPressed: () {
          showDialog(
            context: context,
            builder:
                (context) => Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          ResponsiveHelper.isTablet ? 400 : double.infinity,
                    ),
                    child: AlertDialog(
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
                              await ref
                                  .read(authStateProvider.notifier)
                                  .deleteAccount();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Failed to delete account: $e',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: context.colors.danger,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                ),
          );
        },
      ),
    );
  }
}

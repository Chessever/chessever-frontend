import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import '../providers/board_settings_provider.dart';
import 'board_color_dialog.dart';

class BoardSettingsDialog extends ConsumerWidget {
  const BoardSettingsDialog({Key? key}) : super(key: key);

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
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
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
      leading: customIcon ?? Icon(icon!, color: kWhiteColor, size: 24),
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
                  size: 24,
                ),
              )
              : null,
      onTap: onPressed,
    );
  }

  Widget _buildSwitchItem({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.only(left: 12, right: 12),
      title: Text(
        title,
        style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: Colors.white,
      activeTrackColor: kPrimaryColor,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: Colors.grey.withOpacity(0.3),
    );
  }
}

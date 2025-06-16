import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/board_settings_provider.dart';
import 'color_picker_dialog.dart';
import 'piece_style_dialog.dart';
import 'settings_dialog.dart';

class BoardSettingsDialog extends ConsumerWidget {
  const BoardSettingsDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettings = ref.watch(boardSettingsProvider);

    return SettingsDialog(
      title: 'Board settings',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSettingItem(
            icon: Icons.palette,
            title: 'Set board colour',
            trailing: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: boardSettings.boardColor,
                shape: BoxShape.circle,
              ),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder:
                    (context) => ColorPickerDialog(
                      selectedColor: boardSettings.boardColor,
                      onColorSelected: (color) {
                        ref
                            .read(boardSettingsProvider.notifier)
                            .setBoardColor(color);
                      },
                    ),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildSettingItem(
            icon: Icons.sports_esports,
            title: 'Piece style',
            trailing: Text(
              boardSettings.pieceStyle.display,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => const PieceStyleDialog(),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildSwitchItem(
            title: 'Evaluation bar',
            value: boardSettings.showEvaluationBar,
            onChanged: (value) {
              ref.read(boardSettingsProvider.notifier).toggleEvaluationBar();
            },
          ),
          const SizedBox(height: 16),
          _buildSwitchItem(
            title: 'Sound',
            value: boardSettings.soundEnabled,
            onChanged: (value) {
              ref.read(boardSettingsProvider.notifier).toggleSound();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const Spacer(),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchItem({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.cyan,
          activeTrackColor: Colors.cyan.withOpacity(0.3),
        ),
      ],
    );
  }
}

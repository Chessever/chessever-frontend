import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import '../providers/board_settings_provider.dart';
import 'board_color_dialog.dart';

class BoardSettingsDialog extends ConsumerWidget {
  const BoardSettingsDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettings = ref.watch(boardSettingsProvider);

    return GestureDetector(
      // Close the dialog when tapping outside
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          // Backdrop filter for blur effect
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),
          ),
          // Dialog content
          Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 24.0,
            ),
            // Prevent dialog from closing when clicking on the dialog itself
            child: GestureDetector(
              onTap: () {}, // Absorb the tap
              child: Container(
                width: 180.5,
                decoration: BoxDecoration(
                  color: kPopUpColor,
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
                        Navigator.pop(
                          context,
                        ); // Close the current dialog first
                        BoardColorBottomSheet.show(context);
                      },
                      showChevron: false,
                    ),
                    const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Color(0xFF2C2C2E),
                    ),
                    _buildSwitchItem(
                      title: 'Evaluation bar',
                      value: boardSettings.showEvaluationBar,
                      onChanged: (value) {
                        ref
                            .read(boardSettingsProvider.notifier)
                            .toggleEvaluationBar();
                      },
                    ),
                    const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Color(0xFF2C2C2E),
                    ),
                    _buildSwitchItem(
                      title: 'Sound',
                      value: boardSettings.soundEnabled,
                      onChanged: (_) {
                        // Use separate reference to prevent cross-interference
                        ref.read(boardSettingsProvider.notifier).toggleSound();
                      },
                    ),
                    const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Color(0xFF2C2C2E),
                    ),
                    _buildSwitchItem(
                      title: 'Chat',
                      value: boardSettings.chatEnabled,
                      onChanged: (_) {
                        // Use separate reference to prevent cross-interference
                        ref.read(boardSettingsProvider.notifier).toggleChat();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
    return Container(
      height: 36,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              customIcon ?? Icon(icon!, color: kWhiteColor, size: 20),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'InterDisplay',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: kWhiteColor,
                  ),
                ),
              ),
              if (showChevron)
                Icon(
                  Icons.chevron_right_outlined,
                  color: kWhiteColor,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchItem({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      height: 36,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'InterDisplay',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: kWhiteColor,
                  ),
                ),
              ),
              SizedBox(
                width: 34,
                height: 20,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: Switch.adaptive(
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
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/board_settings_provider.dart';
import 'settings_card.dart';
import 'settings_dialog.dart';
import 'settings_item.dart';

class PieceStyleDialog extends ConsumerWidget {
  const PieceStyleDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettings = ref.watch(boardSettingsProvider);

    return SettingsDialog(
      title: 'Piece style',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsCard(
            children:
                PieceStyle.values.map((style) {
                  final isSelected = style == boardSettings.pieceStyle;

                  return SettingsItem(
                    title: style.display,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.sports_esports,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    trailing:
                        isSelected
                            ? const Icon(
                              Icons.check_circle,
                              color: Colors.cyan,
                              size: 20,
                            )
                            : null,
                    onTap: () {
                      ref
                          .read(boardSettingsProvider.notifier)
                          .setPieceStyle(style);
                      Navigator.of(context).pop();
                    },
                    showDivider: style != PieceStyle.values.last,
                  );
                }).toList(),
          ),

          const SizedBox(height: 16),

          // Button to close dialog without changing
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.grey),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

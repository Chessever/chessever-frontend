import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/board_settings_provider_new.dart';

/// Keep scan review consistent with the user's board and make orientation clear.
class BoardScanPreview extends ConsumerWidget {
  const BoardScanPreview({super.key, required this.size, required this.fen});

  final double size;
  final String fen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(boardSettingsProviderNew).valueOrNull ??
        const BoardSettingsNew();
    return StaticChessboard(
      size: size,
      orientation: Side.white,
      fen: fen,
      settings: StaticChessboardSettings(
        colorScheme: settings.colorScheme,
        pieceAssets: settings.pieceAssets,
        enableCoordinates: true,
      ),
    );
  }
}

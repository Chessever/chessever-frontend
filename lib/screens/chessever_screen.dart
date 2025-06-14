import 'package:chessever2/widgets/blur_background.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChesseverScreen extends ConsumerWidget {
  const ChesseverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [const BlurBackground()],
      ),
    );
  }
}

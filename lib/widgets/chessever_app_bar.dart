import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';

class ChessEverAppBar extends StatelessWidget {
  const ChessEverAppBar({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 20),
        IconButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24),
        ),
        Spacer(),
        Text(
          title,
          style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
        ),
        Spacer(),
        SizedBox(width: 44),
      ],
    );
  }
}

import 'package:flutter/material.dart';

const _blueColor = Color(0xFF6B939F);
const _greyColor = Color(0xFFD1E9E9);

class AnalysisBoardIcon extends StatelessWidget {
  const AnalysisBoardIcon({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              height: size / 2,
              width: size / 2,
              color: _blueColor,
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Container(
              height: size / 2,
              width: size / 2,
              color: _greyColor,
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              height: size / 2,
              width: size / 2,
              color: _greyColor,
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              height: size / 2,
              width: size / 2,
              color: _blueColor,
            ),
          ),
        ],
      ),
    );
  }
}

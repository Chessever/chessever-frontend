import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

const _botvinnikAsset = 'assets/svgs/botvinnik.svg';

class BotvinnikIcon extends StatelessWidget {
  const BotvinnikIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconColor =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return SvgWidget(
      _botvinnikAsset,
      height: size,
      width: size,
      colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
      fallback: Icon(Icons.smart_toy_outlined, size: size, color: iconColor),
    );
  }
}

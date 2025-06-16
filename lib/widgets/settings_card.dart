import 'package:flutter/material.dart';

class SettingsCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final Color backgroundColor;
  final double? borderRadius;

  const SettingsCard({
    Key? key,
    this.title,
    required this.children,
    this.padding,
    this.backgroundColor = const Color(0xFF0C0C0E),
    this.borderRadius,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 360;
    final bool isLargeScreen = screenSize.width > 600;

    // Determine appropriate spacing based on screen size
    final double titleFontSize = isSmallScreen ? 12 : (isLargeScreen ? 16 : 14);
    final EdgeInsets titlePadding = EdgeInsets.only(
      left: isSmallScreen ? 12 : 16,
      bottom: isSmallScreen ? 6 : 8,
      top: isSmallScreen ? 12 : 16,
    );
    final EdgeInsets cardMargin = EdgeInsets.symmetric(
      horizontal: isSmallScreen ? 4 : 8,
      vertical: isSmallScreen ? 3 : 4,
    );
    final double effectiveBorderRadius =
        borderRadius ?? (isSmallScreen ? 8.0 : (isLargeScreen ? 16.0 : 12.0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: titlePadding,
            child: Text(
              title!,
              style: TextStyle(
                color: Colors.grey,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Card(
          color: backgroundColor,
          margin: cardMargin,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(effectiveBorderRadius),
          ),
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

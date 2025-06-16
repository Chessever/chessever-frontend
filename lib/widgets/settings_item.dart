import 'package:flutter/material.dart';

class SettingsItem extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final bool showDivider;

  const SettingsItem({
    Key? key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding,
    this.showDivider = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 360;
    final bool isLargeScreen = screenSize.width > 600;

    // Determine appropriate padding based on screen size
    final EdgeInsetsGeometry effectivePadding =
        padding ??
        EdgeInsets.symmetric(
          vertical: isSmallScreen ? 8.0 : (isLargeScreen ? 16.0 : 12.0),
          horizontal: isSmallScreen ? 12.0 : (isLargeScreen ? 20.0 : 16.0),
        );

    // Determine appropriate icon size based on screen size
    final double iconSize = isSmallScreen ? 20 : (isLargeScreen ? 28 : 24);

    // Determine appropriate text sizes based on screen size
    final double titleSize = isSmallScreen ? 14 : (isLargeScreen ? 18 : 16);
    final double subtitleSize = isSmallScreen ? 12 : (isLargeScreen ? 16 : 14);

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: effectivePadding,
            child: Row(
              children: [
                if (leading != null) ...[
                  SizedBox(
                    width: iconSize * 1.5,
                    height: iconSize * 1.5,
                    child: leading,
                  ),
                  SizedBox(width: isSmallScreen ? 12 : 16),
                ] else if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: iconSize),
                  SizedBox(width: isSmallScreen ? 12 : 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: subtitleSize,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            color: const Color(0xFF2A2A2A),
            height: 1,
            indent: isSmallScreen ? 12 : 16,
            endIndent: isSmallScreen ? 12 : 16,
          ),
      ],
    );
  }
}

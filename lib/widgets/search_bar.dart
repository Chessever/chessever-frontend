import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ChesseverSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final bool autofocus;
  final VoidCallback? onSearchTap;
  final bool fillBackground;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const ChesseverSearchBar({
    Key? key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search',
    this.autofocus = false,
    this.onSearchTap,
    this.fillBackground = true,
    this.padding = const EdgeInsets.all(8.0),
    this.borderRadius = 8.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: padding,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: autofocus,
        style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16.0),
        decoration: InputDecoration(
          filled: fillBackground,
          fillColor: isDark ? kBlack2Color : Colors.white,
          hintText: hintText,
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
          prefixIcon: GestureDetector(
            onTap: onSearchTap,
            child: Icon(
              Icons.search,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            borderSide: BorderSide(
              color: kPrimaryColor.withOpacity(0.5),
              width: 1.0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            borderSide: const BorderSide(color: kPrimaryColor, width: 2.0),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            borderSide: BorderSide(
              color: theme.colorScheme.onSurface.withOpacity(0.2),
              width: 1.0,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 12.0,
            horizontal: 16.0,
          ),
        ),
        cursorColor: kPrimaryColor,
      ),
    );
  }
}

import 'package:flutter/material.dart';

class ColorPickerDialog extends StatelessWidget {
  final Color selectedColor;
  final Function(Color) onColorSelected;

  const ColorPickerDialog({
    Key? key,
    required this.selectedColor,
    required this.onColorSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Determine screen size for responsive layout
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 360;
    final bool isLargeScreen = screenSize.width > 600;

    // Predefined board colors
    final List<Color> boardColors = [
      Colors.brown,
      Colors.green[800]!,
      Colors.blue[900]!,
      Colors.grey[800]!,
      Colors.purple[900]!,
      Colors.teal[900]!,
    ];

    // Adjust sizes based on screen dimensions
    final double titleFontSize = isSmallScreen ? 16 : (isLargeScreen ? 22 : 18);
    final double spacing = isSmallScreen ? 12 : (isLargeScreen ? 24 : 16);
    final double padding = isSmallScreen ? 12 : 16;
    final double borderRadius = isSmallScreen ? 12 : 16;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 24 : 32,
        vertical: isSmallScreen ? 24 : 32,
      ),
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0C0E),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select board color',
              style: TextStyle(
                color: Colors.white,
                fontSize: titleFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: spacing),
            GridView.builder(
              shrinkWrap: true,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isSmallScreen ? 2 : 3,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              itemCount: boardColors.length,
              itemBuilder: (context, index) {
                final color = boardColors[index];
                final isSelected = color.value == selectedColor.value;

                return GestureDetector(
                  onTap: () {
                    onColorSelected(color);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border:
                          isSelected
                              ? Border.all(
                                color: Colors.cyan,
                                width: isSmallScreen ? 2 : 3,
                              )
                              : null,
                    ),
                    child:
                        isSelected
                            ? Center(
                              child: Icon(
                                Icons.check,
                                color: Colors.white,
                                size: isSmallScreen ? 20 : 24,
                              ),
                            )
                            : null,
                  ),
                );
              },
            ),
            SizedBox(height: spacing),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.grey),
                  padding: EdgeInsets.symmetric(
                    vertical: isSmallScreen ? 8 : 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

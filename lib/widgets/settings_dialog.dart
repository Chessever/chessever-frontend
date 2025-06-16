import 'package:flutter/material.dart';

class SettingsDialog extends StatelessWidget {
  final String title;
  final Widget child;

  const SettingsDialog({Key? key, required this.title, required this.child})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 360;
    final bool isLargeScreen = screenSize.width > 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 16.0 : (isLargeScreen ? 48.0 : 20.0),
        vertical: isSmallScreen ? 16.0 : 24.0,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isLargeScreen ? 500 : double.infinity,
          maxHeight: screenSize.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: isSmallScreen ? 12.0 : 16.0),
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 16 : (isLargeScreen ? 22 : 18),
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Container(
                  padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(
                      isSmallScreen ? 12 : 16,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

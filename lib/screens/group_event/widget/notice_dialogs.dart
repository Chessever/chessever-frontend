import 'package:flutter/material.dart';

void showSimpleDialog({
  required BuildContext context,
  String title = 'Notice',
  required String message,
  String buttonText = 'OK',
}) {
  showDialog(
    context: context,
    builder:
        (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(buttonText),
            ),
          ],
        ),
  );
}

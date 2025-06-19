import 'package:flutter/material.dart';

class ScreenWrapper extends StatelessWidget {
  const ScreenWrapper({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

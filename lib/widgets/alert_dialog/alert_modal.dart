import 'package:flutter/material.dart';

void showAlertModal({required BuildContext context, required Widget child}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height,
          width: MediaQuery.of(ctx).size.width,
          child: child,
        );
      },
    );

import 'package:flutter/material.dart';

class GenericErrorWidget extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const GenericErrorWidget({super.key, this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message != null && message!.isNotEmpty
                  ? 'Error: $message'
                  : 'Something went wrong',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class NotificationPermissionStep extends StatefulWidget {
  const NotificationPermissionStep({required this.onContinue, super.key});

  final Future<void> Function() onContinue;

  @override
  State<NotificationPermissionStep> createState() =>
      _NotificationPermissionStepState();
}

class _NotificationPermissionStepState
    extends State<NotificationPermissionStep> {
  bool _isContinuing = false;

  Future<void> _continue() async {
    if (_isContinuing) return;
    setState(() => _isContinuing = true);
    try {
      await widget.onContinue();
    } finally {
      if (mounted) setState(() => _isContinuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.notifications_active_outlined,
                    size: 44,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Never miss a game from your favorites',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Turn on notifications to know when your favorite players begin playing.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    height: 1.45,
                    color: colors.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isContinuing ? null : _continue,
                    child:
                        _isContinuing
                            ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

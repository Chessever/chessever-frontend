import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// App-wide loading indicator using package [GlassProgressIndicator].
///
/// Prefer this over raw [CircularProgressIndicator] / [LinearProgressIndicator]
/// on glass-modernized screens so loading matches liquid-glass chrome.
class GlassLoading extends StatelessWidget {
  const GlassLoading.circular({
    super.key,
    this.size = 28,
    this.color,
    this.useOwnLayer = true,
  }) : _linear = false,
       value = null;

  const GlassLoading.linear({
    super.key,
    this.value,
    this.color,
    this.useOwnLayer = true,
  }) : _linear = true,
       size = 0;

  final bool _linear;
  final double size;
  final double? value;
  final Color? color;
  final bool useOwnLayer;

  @override
  Widget build(BuildContext context) {
    if (_linear) {
      return GlassProgressIndicator.linear(
        value: value,
        color: color,
        useOwnLayer: useOwnLayer,
      );
    }
    return GlassProgressIndicator.circular(
      value: value,
      size: size,
      color: color,
      useOwnLayer: useOwnLayer,
    );
  }
}

/// Centered full-area loading placeholder.
class GlassLoadingPage extends StatelessWidget {
  const GlassLoadingPage({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GlassLoading.circular(size: 32),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

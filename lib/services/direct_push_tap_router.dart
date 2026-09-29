import 'package:flutter/services.dart';

/// Shares de-duplication between native scene/delegate and Firebase callbacks.
/// A tap is routed even when transient tester pushes have no delivery ID.
class DirectPushTapRouter {
  static const channel = MethodChannel('com.chessever/push_taps');
  final _handled = <String>{};

  void open(
    String? messageId,
    Map<String, dynamic> data,
    void Function(Map<String, dynamic>) onOpen,
  ) {
    if (messageId != null && messageId.isNotEmpty) {
      if (!_handled.add(messageId)) return;
      if (_handled.length > 64) _handled.remove(_handled.first);
    }
    onOpen(data);
  }

  Future<void> initializeNative(
    void Function(Map<String, dynamic>) onOpen,
  ) async {
    void accept(dynamic value) {
      if (value is! Map || value['data'] is! Map) return;
      open(
        value['messageId'] as String?,
        Map<String, dynamic>.from(value['data'] as Map),
        onOpen,
      );
    }

    channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationOpened') accept(call.arguments);
    });
    // Install the live handler before draining the launch tap to avoid a gap.
    try {
      accept(await channel.invokeMethod<dynamic>('takeInitialTap'));
    } on MissingPluginException {
      // Older native shells (hot reload) still have the Firebase callbacks.
    }
  }
}

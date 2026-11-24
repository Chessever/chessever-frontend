import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Subscribe before re-reading so a change during the initial load or while
/// disconnected is picked up. Notifications carry no saved-analysis data.
VoidCallback listenForLikeChanges(
  SupabaseClient client,
  String topic,
  VoidCallback refresh, {
  bool private = true,
}) {
  final channel = client.channel(
    topic,
    opts: RealtimeChannelConfig(private: private),
  );
  final lifecycle = AppLifecycleListener(onResume: refresh);
  var disposed = false;
  channel
      .onBroadcast(
        event: 'changed',
        callback: (_) {
          if (!disposed) refresh();
        },
      )
      .subscribe((status, _) {
        if (!disposed && status == RealtimeSubscribeStatus.subscribed) {
          refresh();
        }
      });
  return () {
    disposed = true;
    lifecycle.dispose();
    unawaited(client.removeChannel(channel));
  };
}

/// A burst of committed writes only needs one fresh read.
Stream<int> gameLikeChanges(SupabaseClient client, String likeId) {
  late final StreamController<int> controller;
  VoidCallback? stop;
  Timer? timer;
  var revision = 0;
  controller = StreamController<int>(
    onListen: () {
      stop = listenForLikeChanges(client, 'game-likes:$likeId', () {
        timer?.cancel();
        timer = Timer(const Duration(milliseconds: 100), () {
          controller.add(++revision);
        });
      }, private: false);
    },
    onCancel: () {
      timer?.cancel();
      stop?.call();
    },
  );
  return controller.stream;
}

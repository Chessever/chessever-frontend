import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The sound sink the Feed player talks to. Production reads the shared
/// [FeedSfx.instance]; widget tests override it with a silent fake so no audio
/// plugin is touched.
final feedSfxProvider = Provider<FeedSfx>((ref) => FeedSfx.instance);

/// Runs one sound call without letting an audio failure reach the player.
/// Feed is still watchable muted; a sound error must never stop playback.
void feedSfxSafely(void Function() call) {
  try {
    call();
  } catch (error, stack) {
    debugPrint('[Feed] sound call failed: $error\n$stack');
  }
}

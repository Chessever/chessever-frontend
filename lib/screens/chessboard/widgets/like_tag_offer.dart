import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A live "tag this game" offer surfaced right after a fresh like.
///
/// Carries everything the AppBar tag chip needs to render and persist: the
/// liked game's [likeId] (the write key for `setTagsForLikeId`), any tags the
/// game already carries ([initialTags], so a re-like reads back continuously),
/// and a monotonic [token] so a brand-new like cleanly supersedes a still-open
/// offer from the previous one.
@immutable
class TagOffer {
  const TagOffer({
    required this.likeId,
    required this.initialTags,
    required this.token,
  });

  final String likeId;
  final List<String> initialTags;
  final int token;
}

/// Bridges the board's double-tap-to-like handler (buried deep in the chess
/// board screen state) to the AppBar tag chip without prop-drilling — the same
/// shape as [LikeFlightAnchor]/`likeFlightAnchorProvider`.
///
/// The board calls [open] once the flying heart has docked; the AppBar listens
/// on [current] and swaps its action icons for the chip. The chip itself calls
/// [close] when the user picks a tag or the countdown elapses.
class TagChipOfferController {
  /// The active offer, or `null` when the toolbar should show its normal icons.
  final ValueNotifier<TagOffer?> current = ValueNotifier<TagOffer?>(null);

  int _token = 0;

  /// Begin (or replace) an offer for [likeId]. Bumps the token so the chip
  /// rebuilds fresh and any in-flight previous offer is dropped.
  void open(String likeId, List<String> initialTags) {
    current.value = TagOffer(
      likeId: likeId,
      initialTags: List<String>.unmodifiable(initialTags),
      token: ++_token,
    );
  }

  /// Close the offer carrying [token]. The token guard means a late countdown
  /// timeout from a superseded offer can't dismiss the current one.
  void close(int token) {
    if (current.value?.token == token) current.value = null;
  }

  void dispose() => current.dispose();
}

/// Shared, non-autoDispose so the board handler and the AppBar resolve to the
/// same instance (the chip is keyed off this single [ValueNotifier]).
final tagChipOfferProvider = Provider<TagChipOfferController>((ref) {
  final controller = TagChipOfferController();
  ref.onDispose(controller.dispose);
  return controller;
});

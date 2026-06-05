import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Lifecycle of the chained "like" → save-button-fill animation.
///
/// idle      → no animation in flight. Save button renders its normal disk
///             (with a small heart badge if the current game is liked).
/// bursting  → the big board heart-burst is playing. Save button slot remains
///             the normal save/edit action; it is only used as a flight target.
/// flying    → the burst's main heart has shrunk and is tweening across the
///             screen toward the save-button slot via an Overlay.
/// landed    → the heart just landed in the slot. The slot stays as the
///             save/edit icon with a small red badge when the game is liked.
enum LikeFlightPhase { idle, bursting, flying, landed }

/// Per-board anchor that lets the board's double-tap-to-like handler talk
/// to the AppBar save button widget without prop-drilling. The save button
/// widget attaches [saveButtonKey] to its icon container so the flight
/// animation can compute the on-screen target rect.
class LikeFlightAnchor {
  LikeFlightAnchor({String? debugLabel}) {
    _debugLabel = debugLabel;
  }

  late final String? _debugLabel;

  /// Attached to the save button's icon container. The flight overlay reads
  /// `renderBox.localToGlobal(Offset.zero)` off this to find its target.
  late final GlobalKey saveButtonKey = GlobalKey(
    debugLabel:
        _debugLabel == null
            ? 'likeFlight.saveButton'
            : 'likeFlight.saveButton.$_debugLabel',
  );

  /// Attached to the small heart badge glyph on the save button. The flight
  /// overlay docks the big flying heart onto THIS rect (center + size) so the
  /// arriving heart lands exactly where — and at the same size as — the badge
  /// it turns into. The badge keeps its layout size even while scaled to 0
  /// (AnimatedScale is a transform), so this rect is measurable mid-flight.
  late final GlobalKey heartBadgeKey = GlobalKey(
    debugLabel:
        _debugLabel == null
            ? 'likeFlight.heartBadge'
            : 'likeFlight.heartBadge.$_debugLabel',
  );

  /// Drives the save button's own state machine — see [LikeFlightPhase].
  final ValueNotifier<LikeFlightPhase> phase = ValueNotifier<LikeFlightPhase>(
    LikeFlightPhase.idle,
  );

  Rect? saveButtonGlobalRect() {
    final ctx = saveButtonKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  /// Global rect of the small heart badge — the precise dock target for the
  /// flying heart. Returns null if the badge isn't laid out yet (caller falls
  /// back to [saveButtonGlobalRect]).
  Rect? heartBadgeGlobalRect() {
    final ctx = heartBadgeKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _logPhase(LikeFlightPhase p) {
    if (kDebugMode) debugPrint('[HeartFlight] phase=${p.name}');
  }

  void start() {
    phase.value = LikeFlightPhase.bursting;
    _logPhase(phase.value);
  }

  void beginFlight() {
    phase.value = LikeFlightPhase.flying;
    _logPhase(phase.value);
  }

  void land() {
    phase.value = LikeFlightPhase.landed;
    _logPhase(phase.value);
  }

  void reset() {
    phase.value = LikeFlightPhase.idle;
    _logPhase(phase.value);
  }

  void dispose() => phase.dispose();
}

/// Page-scoped anchor. Not autoDispose: a board page and its app-bar save
/// button must resolve to the same instance, but adjacent PageView pages must
/// not share GlobalKeys while the swipe tutorial programmatically drags pages.
final likeFlightAnchorProvider = Provider.family<LikeFlightAnchor, String>((
  ref,
  anchorId,
) {
  final anchor = LikeFlightAnchor(debugLabel: anchorId);
  ref.onDispose(anchor.dispose);
  return anchor;
});

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A list controller that can put its list at an offset during the list's
/// next layout ([settleAt]), before that frame paints, or keep it there
/// through every layout for a while ([holdAt]).
///
/// The Favorites and Countrymen Games lists use it as a search replaces the
/// list under the reader: the hits start at their top, and the plain list
/// comes back where it was left. A jump after the frame would paint one
/// frame of the new games at the old offset first; this lands the offset in
/// the frame the games change in, so nothing flickers. Only the offset
/// moves: the list is never rebuilt.
class SettlingScrollController extends ScrollController {
  double? _target;

  /// [_target] is kept through every layout until [release] ([holdAt]).
  bool _held = false;

  /// The list has been laid out once at [_target] this frame.
  bool _tried = false;

  /// A held frame after the first: the list already knows its extent
  /// around [_target], so it follows it within that extent.
  bool _rearmed = false;

  bool _endOfFrameScheduled = false;

  /// Puts the list at [offset] (within its content) in the next layout.
  /// Dropped if the reader is scrolling it then: their hand wins.
  ///
  /// Call it as the games change: their rebuild lays the list out again in
  /// the next frame, and that layout lands at [offset]. It does not notify
  /// the controller's listeners, so nothing reads the old rows at the new
  /// place (a load-more check, say).
  void settleAt(double offset) => _arm(offset, held: false);

  /// Keeps the list at [offset], or as near as its content allows, in every
  /// layout until [release] (or the reader scrolls it).
  ///
  /// For a header above the list that springs shorter or taller: the list
  /// keeps its place under it instead of bouncing off its end as the room
  /// changes, and is back at [offset] once the room allows it.
  void holdAt(double offset) => _arm(offset, held: true);

  /// Ends a [holdAt]. A [settleAt] still to land is left alone.
  void release() {
    if (!_held) return;
    _drop();
  }

  void _arm(double offset, {required bool held}) {
    if (positions.length != 1) return;
    if (position is! _SettlingScrollPosition) return;
    _target = offset;
    _held = held;
    _tried = false;
    _rearmed = false;
    _scheduleEndOfFrame();
  }

  void _drop() {
    _target = null;
    _held = false;
    _tried = false;
    _rearmed = false;
  }

  /// Never carried into a later layout, unless held.
  void _scheduleEndOfFrame() {
    if (_endOfFrameScheduled) return;
    _endOfFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _endOfFrameScheduled = false;
      if (_held && _target != null) {
        _tried = false;
        _rearmed = true;
        _scheduleEndOfFrame();
      } else {
        _drop();
      }
    });
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SettlingScrollPosition(
      owner: this,
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _SettlingScrollPosition extends ScrollPositionWithSingleContext {
  _SettlingScrollPosition({
    required this.owner,
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  final SettlingScrollController owner;

  /// Closer than this is already there: no second layout for it.
  static const double _tolerance = 0.01;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final target = owner._target;
    if (target != null) {
      final maxExtent = math.max(minScrollExtent, maxScrollExtent);
      if (activity is! IdleScrollActivity) {
        // The reader's hand wins.
        owner._drop();
      } else {
        if (!owner._tried) {
          owner._tried = true;
          // The layout-time correction: the viewport lays out again at the
          // target in this same frame. A list whose games just changed only
          // knows how far it reaches around where it was laid out (the old
          // games' place), so it is not clamped to this pass's extent. A
          // held list already knows its end, and follows it.
          final wanted = owner._rearmed
              ? target.clamp(minScrollExtent, maxExtent).toDouble()
              : math.max(minScrollExtent, target);
          if ((wanted - pixels).abs() > _tolerance) {
            correctPixels(wanted);
            return false;
          }
        }
        if (!owner._held) owner._target = null;
        // Laid out at the target: within the games it now knows of.
        final settled = pixels.clamp(minScrollExtent, maxExtent).toDouble();
        if (settled != pixels) {
          correctPixels(settled);
          return false;
        }
      }
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Centralised scroll-cache configuration for the app's list/feed views.
///
/// Flutter's default cache extent is only 250 logical pixels — smaller than a
/// single game/event card. A card scrolled just out of view is therefore
/// disposed and then rebuilt from scratch when scrolled back into view
/// (chess boards re-render, images reload, async work re-runs, layout jumps).
///
/// Expressing the cache as a multiple of the viewport keeps a screenful alive
/// in each scroll direction regardless of device size, so normal up/down
/// scrolling no longer reloads neighbouring items.
const ScrollCacheExtent kListScrollCacheExtent = ScrollCacheExtent.viewport(1.5);

/// For lists of heavier board cards: one full screen in each direction. Enough
/// to stop reload-on-scroll for the typical viewport while bounding memory.
const ScrollCacheExtent kBoardListScrollCacheExtent =
    ScrollCacheExtent.viewport(1.0);

/// Pixel cache extent (~1.5 screens) for widgets that only accept a raw double
/// instead of a [ScrollCacheExtent] — e.g. `ScrollablePositionedList`'s
/// `minCacheExtent`.
double listCacheExtentPixels(BuildContext context) =>
    MediaQuery.sizeOf(context).height * 1.5;

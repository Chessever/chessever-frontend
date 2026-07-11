import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Shared [GlobalKey] on the bracket viewport's [RepaintBoundary].
///
/// The bracket screen ([KnockoutBracketScreen]) attaches this key to a
/// `RepaintBoundary` wrapping its `InteractiveViewer`, so whatever the user has
/// panned/zoomed into ("the selected canvas area") is exactly what the boundary
/// paints. The tournament menu's "Share brackets" action reads the same key and
/// snapshots that live viewport via `RenderRepaintBoundary.toImage`.
///
/// A plain (kept-alive, non-family) [Provider] so both the bracket screen and
/// the app-bar menu resolve the identical key instance for the session.
final bracketShareBoundaryKeyProvider = Provider<GlobalKey>(
  (ref) => GlobalKey(debugLabel: 'bracket-share-boundary'),
);

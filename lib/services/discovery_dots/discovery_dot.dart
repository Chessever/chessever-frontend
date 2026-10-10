import 'dart:convert';

/// One remotely published "look here" dot.
///
/// A dot points at a [target] surface (a tab, a tile, a drawer row) and may
/// light a [trail] of surfaces the user has to pass through to reach it, so a
/// feature three taps deep can still be found from the first screen.
class DiscoveryDot {
  const DiscoveryDot({
    required this.id,
    required this.rev,
    required this.target,
    this.trail = const [],
    this.message,
  });

  /// Stable name of the campaign. Dismissals are remembered against it.
  final String id;

  /// Raised by the admin console to show a dismissed dot again.
  final int rev;

  /// Anchor id of the surface being pointed at.
  final String target;

  /// Anchor ids on the way to [target], outermost first.
  final List<String> trail;

  /// Shown once when the target is reached. Null dismisses silently.
  final String? message;
}

/// Reads the Remote Config value. Anything malformed is dropped entry by
/// entry, so one bad row published from the console never hides the others
/// and never throws into the UI.
List<DiscoveryDot> parseDiscoveryDots(String raw) {
  if (raw.trim().isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  final rows = decoded is Map<String, dynamic> ? decoded['dots'] : null;
  if (rows is! List) return const [];

  final dots = <DiscoveryDot>[];
  final ids = <String>{};
  for (final row in rows) {
    if (row is! Map<String, dynamic>) continue;
    final id = row['id'];
    final target = row['target'];
    final rev = row['rev'];
    if (id is! String || id.isEmpty || id.contains('@')) continue;
    if (target is! String || target.isEmpty) continue;
    if (rev is! int || rev < 1) continue;
    if (row['enabled'] == false) continue;
    if (!ids.add(id)) continue;
    final trail = row['trail'];
    final message = row['message'];
    dots.add(
      DiscoveryDot(
        id: id,
        rev: rev,
        target: target,
        trail: trail is List
            ? [
                for (final hop in trail)
                  if (hop is String && hop.isNotEmpty && hop != target) hop,
              ]
            : const [],
        message: message is String && message.trim().isNotEmpty
            ? message.trim()
            : null,
      ),
    );
  }
  return dots;
}

/// Key under which passing one hop of a trail is remembered. The dot's own id
/// (no `@`) is the key for having reached the target.
String discoveryDotHopKey(DiscoveryDot dot, String anchor) =>
    '${dot.id}@$anchor';

/// Whether [dot] lights the surface [anchor], given what this device has
/// already acknowledged ([seen] maps a key to the revision it was seen at).
///
/// Reaching the target retires the whole dot, trail included. Passing a hop
/// retires only that hop, so the next surface on the way stays lit.
bool discoveryDotShowsAt(
  DiscoveryDot dot,
  String anchor,
  Map<String, int> seen,
) {
  if ((seen[dot.id] ?? 0) >= dot.rev) return false;
  if (anchor == dot.target) return true;
  if (!dot.trail.contains(anchor)) return false;
  return (seen[discoveryDotHopKey(dot, anchor)] ?? 0) < dot.rev;
}

/// Every anchor that should currently show a dot.
Set<String> litDiscoveryAnchors(
  List<DiscoveryDot> dots,
  Map<String, int> seen,
) {
  final lit = <String>{};
  for (final dot in dots) {
    for (final anchor in [dot.target, ...dot.trail]) {
      if (discoveryDotShowsAt(dot, anchor, seen)) lit.add(anchor);
    }
  }
  return lit;
}

/// What tapping [anchor] changes: the keys to remember, and the message of a
/// target that was just reached (the first one, if several dots share it).
({Map<String, int> seen, String? message}) acknowledgeDiscoveryAnchor(
  List<DiscoveryDot> dots,
  String anchor,
  Map<String, int> seen,
) {
  final next = {...seen};
  String? message;
  for (final dot in dots) {
    if (!discoveryDotShowsAt(dot, anchor, seen)) continue;
    if (anchor == dot.target) {
      next[dot.id] = dot.rev;
      message ??= dot.message;
    } else {
      next[discoveryDotHopKey(dot, anchor)] = dot.rev;
    }
  }
  return (seen: next, message: message);
}

final _nonIdChars = RegExp('[^a-z0-9]+');
final _edgeUnderscores = RegExp(r'^_+|_+$');

/// Anchor id of a labelled surface inside [scope]: `home.tab` + "My Space" is
/// `home.tab.my_space`. The admin console's surface catalog lists these ids,
/// so renaming a tab label renames its anchor.
String discoveryDotId(String scope, String label) {
  final slug = label
      .toLowerCase()
      .replaceAll(_nonIdChars, '_')
      .replaceAll(_edgeUnderscores, '');
  return '$scope.$slug';
}

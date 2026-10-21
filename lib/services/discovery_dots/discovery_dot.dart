import 'dart:convert';

const discoveryNudgeLabelMax = 8;
const discoveryNudgeMessageMax = 140;
const discoveryNudgeMessagesMax = 5;

class DiscoveryNudgeMessage {
  const DiscoveryNudgeMessage({required this.body, this.actionUrl});
  final String body;
  final Uri? actionUrl;
}

String? discoveryNudgeLabel(Object? raw) {
  if (raw is! String) return null;
  final label = raw.trim();
  if (label.isEmpty ||
      label.runes.length > discoveryNudgeLabelMax ||
      RegExp(r'\s').hasMatch(label)) {
    return null;
  }
  return label;
}

DiscoveryNudgeMessage? _readMessage(Object? raw) {
  if (raw is! Map) return null;
  final body = raw['body'];
  if (body is! String ||
      body.trim().isEmpty ||
      body.runes.length > discoveryNudgeMessageMax) {
    return null;
  }
  final link = raw['action_url'];
  final uri = link is String ? Uri.tryParse(link.trim()) : null;
  return DiscoveryNudgeMessage(
    body: body.trim(),
    actionUrl:
        uri != null &&
            uri.scheme == 'https' &&
            uri.host.contains('.') &&
            uri.userInfo.isEmpty &&
            uri.port == 443
        ? uri
        : null,
  );
}

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
    this.label,
    this.messages = const [],
    this.audienceId,
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
  final String? label;
  final List<DiscoveryNudgeMessage> messages;

  /// Who the dot is for: the id of an admin console audience, null for
  /// everyone. The filters behind it stay on the server, since they can list
  /// people; see `match_editorial_audiences`.
  final String? audienceId;

  bool get targeted => audienceId != null;

  List<DiscoveryNudgeMessage> get tooltipMessages => messages.isNotEmpty
      ? messages
      : message == null
      ? const []
      : [DiscoveryNudgeMessage(body: message!)];
}

/// Reads the Remote Config value. Anything malformed is dropped entry by
/// entry, so one bad row published from the console never hides the others
/// and never throws into the UI.
///
/// Dots for everyone are under `dots`. Dots for an audience are under
/// `targeted`, each with an `audience_id`; builds before audiences never read
/// it, so they never show a dot meant for someone else. A targeted row without
/// a readable audience id is damaged and dropped, never shown to everyone.
List<DiscoveryDot> parseDiscoveryDots(String raw) {
  if (raw.trim().isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map<String, dynamic>) return const [];
  final dots = <DiscoveryDot>[];
  final ids = <String>{};
  void read(Object? rows, {required bool targeted}) {
    if (rows is! List) return;
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final audienceId = row['audience_id'];
      if (targeted &&
          (audienceId is! String ||
              !_discoveryAudienceId.hasMatch(audienceId))) {
        continue;
      }
      final dot = _readDot(
        row,
        audienceId: targeted ? audienceId as String : null,
      );
      if (dot != null && ids.add(dot.id)) dots.add(dot);
    }
  }

  read(decoded['dots'], targeted: false);
  read(decoded['targeted'], targeted: true);
  return dots;
}

/// The admin console's audience ids: 64 random hex characters, saying
/// nothing about who the audience is.
final _discoveryAudienceId = RegExp(r'^[0-9a-f]{64}$');

DiscoveryDot? _readDot(
  Map<String, dynamic> row, {
  required String? audienceId,
}) {
  final id = row['id'];
  final target = row['target'];
  final rev = row['rev'];
  if (id is! String || id.isEmpty || id.contains('@')) return null;
  if (target is! String || target.isEmpty) return null;
  if (rev is! int || rev < 1) return null;
  if (row['enabled'] == false) return null;
  final trail = row['trail'];
  final message = row['message'];
  final rawMessages = row['messages'];
  final messages = rawMessages is List
      ? [
          for (final raw in rawMessages.take(discoveryNudgeMessagesMax))
            if (_readMessage(raw) case final parsed?) parsed,
        ]
      : <DiscoveryNudgeMessage>[];
  return DiscoveryDot(
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
    label: discoveryNudgeLabel(row['label']),
    messages: messages,
    audienceId: audienceId,
  );
}

/// The dots this person sees: every dot for everyone, and the targeted dots
/// whose ids the server matched. Unknown membership ([matched] null) shows
/// no targeted dot.
List<DiscoveryDot> visibleDiscoveryDots(
  List<DiscoveryDot> dots,
  Set<String>? matched,
) => [
  for (final dot in dots)
    if (!dot.targeted || (matched?.contains(dot.id) ?? false)) dot,
];

/// Key under which passing one hop of a trail is remembered. The dot's own id
/// (no `@`) is the key for having reached the target.
String discoveryDotHopKey(DiscoveryDot dot, String anchor) =>
    '${dot.id}@$anchor';

/// Whether [dot] lights the surface [anchor], given what this device has
/// already acknowledged ([seen] maps a key to the revision it was seen at).
///
/// Reaching the target retires the whole dot, trail included. Passing a hop
/// retires that hop and every hop before it (see [acknowledgeDiscoveryAnchor]),
/// so the next surface on the way stays lit.
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
/// target that was just reached, plus the full stack when campaigns share it.
({Map<String, int> seen, String? message, List<DiscoveryNudgeMessage> messages})
acknowledgeDiscoveryAnchor(
  List<DiscoveryDot> dots,
  String anchor,
  Map<String, int> seen,
) {
  final next = {...seen};
  final messages = <DiscoveryNudgeMessage>[];
  for (final dot in dots) {
    if (!discoveryDotShowsAt(dot, anchor, seen)) continue;
    if (anchor == dot.target) {
      next[dot.id] = dot.rev;
      messages.addAll(dot.tooltipMessages);
    } else {
      // Standing on a hop means the user is past every hop before it, however
      // they got here: the bottom bar's Home never needs its own tap once the
      // My Space tile has been reached.
      for (final hop in dot.trail.take(dot.trail.indexOf(anchor) + 1)) {
        next[discoveryDotHopKey(dot, hop)] = dot.rev;
      }
    }
  }
  return (
    seen: next,
    message: messages.isEmpty ? null : messages.first.body,
    messages: messages,
  );
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

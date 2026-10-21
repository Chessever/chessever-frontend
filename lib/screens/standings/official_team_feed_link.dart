/// Joins an official (Chess-Results / Info64) team row to the broadcast's own
/// team labels, so an expanded row can find its players and matches.
///
/// Organizers publish "University of Texas at Dallas-A" while the board feed
/// labels the same squad "UTD". Joining on the official spelling found nothing.
///
/// Resolution, per official team:
/// 1. Published members (FIDE id, else folded name) select feed players
///    directly. Squads that share one feed label (A and B under "UTD") can
///    only be told apart this way.
/// 2. The exact (case-insensitive) label, as before.
/// 3. A folded match: the same words, the same words without a squad suffix,
///    or their initials ("Texas Tech University-A" -> "TTU"). The label must
///    be claimed by this official team alone. A label shared by two squads is
///    never handed to either, so one squad never shows the other's boards.
library;

class OfficialTeamFeedLink {
  /// The broadcast team label the row's boards and players carry.
  final String label;

  /// Player keys ([feedPlayerKeys]) of this squad, or null when every player
  /// under [label] belongs to it.
  final Set<String>? members;

  final Map<String, int> memberFideIdsByName;

  const OfficialTeamFeedLink({
    required this.label,
    this.members,
    this.memberFideIdsByName = const {},
  });

  bool includes({required String? team, int? fideId, required String name}) {
    if (team == null || foldTeamLabel(team) != foldTeamLabel(label)) {
      return false;
    }
    final squad = members;
    if (squad == null) return true;
    final keys = feedPlayerKeys(fideId: fideId, name: name, team: team);
    if (fideId != null && fideId > 0 && squad.contains('fide:$fideId')) {
      return true;
    }
    return keys.any((key) {
      if (!key.startsWith('name:') || !squad.contains(key)) return false;
      final publishedId = memberFideIdsByName[key];
      return publishedId != 0 &&
          (fideId == null ||
              fideId <= 0 ||
              publishedId == null ||
              publishedId == fideId);
    });
  }
}

/// A published squad member: FIDE id and/or name as the organizer wrote it.
typedef OfficialTeamMember = ({int? fideId, String? name});

/// Members carried on an official team row, when the source publishes them.
List<OfficialTeamMember> officialTeamMembers(dynamic raw) {
  if (raw is! List) return const [];
  final out = <OfficialTeamMember>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final rawId = item['fideId'];
    final id = rawId is num
        ? rawId.toInt()
        : rawId is String
        ? int.tryParse(rawId.trim())
        : null;
    final name = item['name'];
    final fideId = id != null && id > 0 ? id : null;
    final cleanName = name is String && name.trim().isNotEmpty
        ? name.trim()
        : null;
    if (fideId == null && cleanName == null) continue;
    out.add((fideId: fideId, name: cleanName));
  }
  return out;
}

String foldTeamLabel(String value) => _words(value).join(' ');

/// Identity keys for one player: FIDE id when known, plus the name's word set
/// without the feed's team prefix ("UTD Samant Aditya S" == "Samant, Aditya S").
Set<String> feedPlayerKeys({int? fideId, required String name, String? team}) {
  final teamWords = team == null ? const <String>[] : _words(team);
  var words = _words(name);
  if (teamWords.isNotEmpty &&
      words.length > teamWords.length &&
      List.generate(
        teamWords.length,
        (i) => words[i] == teamWords[i],
      ).every((matches) => matches)) {
    words = words.sublist(teamWords.length);
  }
  words.sort();
  return {
    if (fideId != null && fideId > 0) 'fide:$fideId',
    if (words.isNotEmpty) 'name:${words.join(' ')}',
  };
}

/// Links each official team to a feed label. Teams with no safe link are
/// absent from the result.
Map<String, OfficialTeamFeedLink> linkOfficialTeamsToFeed({
  required List<({String name, List<OfficialTeamMember> members})> official,
  required List<({String? team, int? fideId, String name})> feedPlayers,
  Iterable<String> extraFeedLabels = const [],
}) {
  final labels = <String, String>{}; // folded -> first spelling seen
  for (final label in [
    for (final p in feedPlayers)
      if (p.team != null) p.team!,
    ...extraFeedLabels,
  ]) {
    final key = foldTeamLabel(label);
    if (key.isNotEmpty) labels.putIfAbsent(key, () => label.trim());
  }

  final links = <String, OfficialTeamFeedLink>{};
  final pending = <String>[];
  for (final team in official) {
    final link = _linkByMembers(team.members, feedPlayers);
    if (link != null) {
      links[team.name] = link;
      continue;
    }
    final exact = labels[foldTeamLabel(team.name)];
    if (exact != null) {
      links[team.name] = OfficialTeamFeedLink(label: exact);
      continue;
    }
    pending.add(team.name);
  }

  // Every pending row that could mean a label claims it, so an ambiguous
  // row blocks the label rather than leaving it to a lucky neighbour.
  final claimed = <String, List<String>>{};
  final hitsOf = <String, List<String>>{};
  for (final name in pending) {
    final hits = labels.keys
        .where((label) => _foldedMatch(name, label))
        .toList();
    hitsOf[name] = hits;
    for (final label in hits) {
      claimed.putIfAbsent(label, () => []).add(name);
    }
  }
  // A label already joined exactly, or by members, belongs to that row.
  final taken = {for (final l in links.values) foldTeamLabel(l.label)};
  for (final name in pending) {
    final hits = hitsOf[name]!;
    if (hits.length != 1) continue;
    final label = hits.single;
    if (claimed[label]!.length == 1 && !taken.contains(label)) {
      links[name] = OfficialTeamFeedLink(label: labels[label]!);
    }
  }
  return links;
}

OfficialTeamFeedLink? _linkByMembers(
  List<OfficialTeamMember> members,
  List<({String? team, int? fideId, String name})> feedPlayers,
) {
  if (members.isEmpty) return null;
  final labels = <String, String>{};
  final keys = <String>{};
  final idsByName = <String, int>{};
  for (final p in feedPlayers) {
    final team = p.team;
    if (team == null || team.trim().isEmpty) continue;
    final own = feedPlayerKeys(fideId: p.fideId, name: p.name, team: team);
    final hit = members.any((member) {
      if (member.fideId != null && p.fideId != null && p.fideId! > 0) {
        return member.fideId == p.fideId;
      }
      return feedPlayerKeys(name: member.name ?? '').any(own.contains);
    });
    if (!hit) continue;
    labels.putIfAbsent(foldTeamLabel(team), () => team.trim());
    keys.addAll(own);
    if (p.fideId != null && p.fideId! > 0) {
      for (final key in own.where((key) => key.startsWith('name:'))) {
        idsByName.update(
          key,
          (id) => id == p.fideId ? id : 0,
          ifAbsent: () => p.fideId!,
        );
      }
    }
  }
  // Members spread over several feed labels means the join is wrong.
  if (labels.length != 1) return null;
  return OfficialTeamFeedLink(
    label: labels.values.single,
    members: keys,
    memberFideIdsByName: idsByName,
  );
}

const _stopWords = {
  'of',
  'at',
  'the',
  'and',
  'de',
  'del',
  'des',
  'du',
  'da',
  'di',
  'la',
  'le',
  'el',
  'y',
  'e',
  'et',
  'und',
};

bool _foldedMatch(String official, String foldedLabel) {
  final words = _words(official);
  final label = foldedLabel.split(' ');
  final squad = _squadSplit(words);
  final labelSquad = _squadSplit(label);
  // Same squad letter on both sides, or no squad letter on the label.
  final bases = <List<String>>[
    if (labelSquad == null) ...[words, if (squad != null) squad.base],
    if (labelSquad != null &&
        squad != null &&
        squad.suffix == labelSquad.suffix)
      squad.base,
  ];
  final labelBase = labelSquad?.base ?? label;
  for (final base in bases) {
    if (_sameWordSet(base, labelBase)) return true;
    if (labelBase.length == 1 && labelBase.single.length >= 2) {
      final initials = base
          .where((w) => !_stopWords.contains(w))
          .map((w) => w[0])
          .join();
      if (initials.length >= 2 && initials == labelBase.single) return true;
    }
  }
  return false;
}

bool _sameWordSet(List<String> a, List<String> b) =>
    a.isNotEmpty &&
    a.toSet().length == b.toSet().length &&
    a.toSet().containsAll(b);

/// "University of Texas at Dallas-A" -> base [...dallas], suffix "a".
({List<String> base, String suffix})? _squadSplit(List<String> words) {
  if (words.length < 2) return null;
  final last = words.last;
  if (!RegExp(r'^(?:[a-h]|[1-9])$').hasMatch(last)) return null;
  return (base: words.sublist(0, words.length - 1), suffix: last);
}

List<String> _words(String value) => RegExp(
  r'[\p{L}\p{M}\p{N}]+',
  unicode: true,
).allMatches(_fold(value)).map((m) => m[0]!).toList();

String _fold(String value) {
  const accents = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'ą': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'ę': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ø': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ñ': 'n',
    'ç': 'c',
    'ć': 'c',
    'č': 'c',
    'ł': 'l',
    'ń': 'n',
    'ś': 's',
    'š': 's',
    'ź': 'z',
    'ż': 'z',
    'ž': 'z',
    'ğ': 'g',
    'ı': 'i',
    'ş': 's',
    'ř': 'r',
    'ý': 'y',
  };
  final lower = value.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    out.write(accents[ch] ?? ch);
  }
  return out.toString();
}

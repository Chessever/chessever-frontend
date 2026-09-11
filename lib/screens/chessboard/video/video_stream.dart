// Public read contract mirrored from the web broadcast video modules.

import 'video_languages.dart';

enum VideoPlatform { youtube, twitch, kick }

class VideoSource {
  const VideoSource(this.platform, this.id, this.url);
  final VideoPlatform platform;
  final String id;
  final Uri url;

  static VideoSource parse(String input) {
    final uri = Uri.parse(input.trim());
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasPort) {
      throw const FormatException('Expected a public HTTPS video URL');
    }
    final host = uri.host;
    String? id;
    if (host == 'youtu.be') {
      id = RegExp(r'^/([\w-]{11})/?$').firstMatch(uri.path)?.group(1);
    } else if (const [
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
    ].contains(host)) {
      id =
          uri.path == '/watch'
              ? uri.queryParameters['v']
              : RegExp(r'^/live/([\w-]{11})/?$').firstMatch(uri.path)?.group(1);
    }
    if (id != null && RegExp(r'^[\w-]{11}$').hasMatch(id)) {
      return VideoSource(
        VideoPlatform.youtube,
        id,
        Uri.https('www.youtube.com', '/watch', {'v': id}),
      );
    }
    if (const ['twitch.tv', 'www.twitch.tv', 'm.twitch.tv'].contains(host)) {
      id =
          RegExp(
            r'^/([a-zA-Z0-9_]{1,25})/?$',
          ).firstMatch(uri.path)?.group(1)?.toLowerCase();
      if (id != null &&
          !const [
            'directory',
            'downloads',
            'videos',
            'settings',
            'subscriptions',
            'jobs',
            'search',
          ].contains(id)) {
        return VideoSource(
          VideoPlatform.twitch,
          id,
          Uri.https('www.twitch.tv', '/$id'),
        );
      }
    }
    if (const ['kick.com', 'www.kick.com'].contains(host)) {
      id =
          RegExp(
            r'^/([a-zA-Z0-9_-]{1,50})/?$',
          ).firstMatch(uri.path)?.group(1)?.toLowerCase();
      if (id != null &&
          !const [
            'categories',
            'search',
            'following',
            'browse',
            'dashboard',
            'settings',
            'login',
            'signup',
            'video',
            'videos',
            'clips',
          ].contains(id)) {
        return VideoSource(
          VideoPlatform.kick,
          id,
          Uri.https('kick.com', '/$id'),
        );
      }
    }
    throw const FormatException('Unsupported video URL');
  }

  String get providerName => switch (platform) {
    VideoPlatform.youtube => 'YouTube',
    VideoPlatform.twitch => 'Twitch',
    VideoPlatform.kick => 'Kick',
  };
}

class VideoAudience {
  const VideoAudience(this.channelId, this.count, this.checkedOn);
  final String channelId;
  final int? count;
  final String checkedOn;
  static VideoAudience? read(dynamic json, VideoPlatform platform) {
    if (json is! Map) return null;
    final channel = json['channelId'];
    final count = json['count'];
    final date = json['checkedOn'];
    final pattern =
        platform == VideoPlatform.youtube ? r'^UC[\w-]{22}$' : r'^\d{1,30}$';
    if (channel is! String ||
        !RegExp(pattern).hasMatch(channel) ||
        (count != null && (count is! int || count < 0)) ||
        date is! String ||
        DateTime.tryParse(date) == null) {
      return null;
    }
    return VideoAudience(channel, count as int?, date);
  }
}

class EventVideoStream {
  const EventVideoStream({
    required this.id,
    required this.label,
    required this.source,
    this.countryCode,
    this.language,
    this.title = '',
    this.description = '',
    this.preferred = false,
    this.audience,
  });
  final String id, label, title, description;
  final VideoSource source;
  final String? countryCode, language;
  final bool preferred;
  final VideoAudience? audience;
  String get identity => '$id:${source.url}';
  String get displayName {
    final parts = label.split(' · ');
    return parts.length == 2 &&
            videoLanguages.any(
              (l) => l.names.contains(parts.last.trim().toLowerCase()),
            )
        ? parts.first.trim()
        : label;
  }

  VideoLanguage? get inferredLanguage {
    final code = language?.trim().toLowerCase().split(RegExp('[-_]')).first;
    for (final item in videoLanguages) {
      if (item.code == code) return item;
    }
    final text = '$title $description $label';
    for (final item in videoLanguages) {
      for (final name in item.names) {
        if (RegExp(
          '(^|[^\\p{L}])${RegExp.escape(name)}([^\\p{L}]|\$)',
          unicode: true,
          caseSensitive: false,
        ).hasMatch(text)) {
          return item;
        }
      }
    }
    return null;
  }

  String get languageKey =>
      inferredLanguage?.code ??
      (countryCode == null ? 'stream-$id' : 'country-$countryCode');
  String? get flagCode => countryCode ?? inferredLanguage?.country;
  String get languageLabel =>
      inferredLanguage?.label ??
      (countryCode == null
          ? 'Language unknown'
          : videoCountryNames[countryCode]!);

  EventVideoStream withRanking(EventVideoStream previous) => EventVideoStream(
    id: id,
    label: label,
    source: source,
    countryCode: countryCode,
    language: language,
    title: title,
    description: description,
    preferred: previous.preferred,
    audience: previous.audience,
  );

  static List<EventVideoStream> readList(dynamic input) {
    if (input is! List) return const [];
    final ids = <String>{};
    final sources = <String>{};
    final result = <EventVideoStream>[];
    for (final raw in input.take(50)) {
      try {
        if (raw is! Map ||
            raw['url'] is! String ||
            (raw['url'] as String).length > 2048) {
          continue;
        }
        final source = VideoSource.parse(raw['url'] as String);
        if (raw['provider'] != null &&
            raw['provider'] != source.platform.name) {
          continue;
        }
        final country = (raw['countryCode'] as String?)?.trim().toUpperCase();
        final flag = country == null || country.isEmpty ? null : country;
        if (flag != null && !videoCountryNames.containsKey(flag)) continue;
        final id = raw['id'] ?? '${source.platform.name}-${source.id}';
        final label =
            raw['label'] == null || raw['label'] == ''
                ? videoCountryNames[flag]
                : raw['label'];
        if (id is! String ||
            !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id) ||
            label is! String ||
            label.trim().isEmpty ||
            label.trim().length > 100) {
          continue;
        }
        final preferred = raw['preferred'];
        if (preferred != null && preferred is! bool) continue;
        final publication =
            raw['publication'] is Map ? raw['publication'] as Map : const {};
        final stream = EventVideoStream(
          id: id,
          label: label.trim(),
          source: source,
          countryCode: flag,
          language: publication['language'] as String?,
          title: publication['title'] as String? ?? '',
          description: publication['description'] as String? ?? '',
          preferred: preferred == true,
          audience: VideoAudience.read(raw['audience'], source.platform),
        );
        if (ids.contains(id) || sources.contains(source.url.toString())) {
          continue;
        }
        ids.add(id);
        sources.add(source.url.toString());
        result.add(stream);
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return result;
  }
}

/// Same priority as web: English groups, group audience, name; within groups,
/// preferred, audience, name. Channel audiences are never counted twice.
List<EventVideoStream> orderVideoStreams(List<EventVideoStream> streams) {
  final groups = <String, List<EventVideoStream>>{};
  final observations = <String, VideoAudience>{};
  String channel(EventVideoStream s) =>
      '${s.source.platform.name}:${s.audience?.channelId}';
  for (final stream in streams) {
    (groups[stream.languageKey] ??= []).add(stream);
    final a = stream.audience;
    if (a == null) continue;
    final old = observations[channel(stream)];
    if (old == null ||
        a.checkedOn.compareTo(old.checkedOn) > 0 ||
        (a.checkedOn == old.checkedOn && (a.count ?? -1) > (old.count ?? -1))) {
      observations[channel(stream)] = a;
    }
  }
  int count(EventVideoStream s) => observations[channel(s)]?.count ?? -1;
  int total(List<EventVideoStream> group) {
    final seen = <String>{};
    var total = 0;
    var known = false;
    for (final s in group) {
      if (count(s) >= 0 && seen.add(channel(s))) {
        total += count(s);
        known = true;
      }
    }
    return known ? total : -1;
  }

  int nameCompare(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());
  // Group display name comes from its first source entry, before sorting.
  final labels = {
    for (final entry in groups.entries)
      entry.key: entry.value.first.languageLabel,
  };
  for (final group in groups.values) {
    group.sort((a, b) {
      var c = (b.preferred ? 1 : 0).compareTo(a.preferred ? 1 : 0);
      if (c == 0) c = count(b).compareTo(count(a));
      if (c == 0) c = nameCompare(a.displayName, b.displayName);
      return c == 0 ? nameCompare(a.id, b.id) : c;
    });
  }
  final keys =
      groups.keys.toList()..sort((a, b) {
        var c = (b == 'en' ? 1 : 0).compareTo(a == 'en' ? 1 : 0);
        if (c == 0) c = total(groups[b]!).compareTo(total(groups[a]!));
        if (c == 0) c = nameCompare(labels[a]!, labels[b]!);
        return c == 0 ? nameCompare(a, b) : c;
      });
  return [for (final key in keys) ...groups[key]!];
}

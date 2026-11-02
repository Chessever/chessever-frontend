import '../../../utils/analysis_video_order.dart';
import '../../../utils/youtube_video.dart';
// Public read contract mirrored from the web broadcast video modules.

import 'video_languages.dart';

// Compiled once, shared by all streams. These patterns preserve Unicode word
// boundaries and the language priority used by the web contract.
final _languagePatterns = {
  for (final language in videoLanguages)
    language.code: [
      for (final name in language.names)
        RegExp(
          '(^|[^\\p{L}])${RegExp.escape(name)}([^\\p{L}]|\$)',
          unicode: true,
          caseSensitive: false,
        ),
    ],
};

enum VideoPlatform { youtube, twitch, kick }

class VideoSource {
  const VideoSource(this.platform, this.id, this.url);
  final VideoPlatform platform;
  final String id;
  final Uri url;

  static VideoSource parse(String input, {bool strict = false}) {
    final uri = Uri.parse(input.trim());
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasPort) {
      throw const FormatException('Expected a public HTTPS video URL');
    }
    final host = uri.host;
    String? id;
    if (const {
      'youtu.be',
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
      'youtube-nocookie.com',
      'www.youtube-nocookie.com',
    }.contains(host)) {
      try {
        final video = YoutubeVideo.parse(input);
        return VideoSource(VideoPlatform.youtube, video.id, video.url);
      } on FormatException {
        if (strict) rethrow;
        // Legacy broadcasts ignored unrelated/invalid playback query values.
        final legacyId = host == 'youtu.be'
            ? RegExp(r'^/([\w-]{11})/?$').firstMatch(uri.path)?.group(1)
            : uri.path == '/watch'
            ? uri.queryParameters['v']
            : RegExp(r'^/live/([\w-]{11})/?$').firstMatch(uri.path)?.group(1);
        if (legacyId == null || !RegExp(r'^[\w-]{11}$').hasMatch(legacyId)) {
          rethrow;
        }
        return VideoSource(
          VideoPlatform.youtube,
          legacyId,
          Uri.https('www.youtube.com', '/watch', {'v': legacyId}),
        );
      }
    }
    if (const ['twitch.tv', 'www.twitch.tv', 'm.twitch.tv'].contains(host)) {
      id = RegExp(
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

enum VideoClientPlatform { web, mobile, desktop }

class EventVideoStream {
  EventVideoStream({
    required this.id,
    required this.label,
    required this.source,
    this.countryCode,
    this.authorName,
    this.analysis = false,
    this.authorId,
    this.followed = false,
    this.publishedAt,
    this.authorAvatarUrl,
    this.language,
    this.title = '',
    this.description = '',
    this.preferred = false,
    this.platforms,
    this.audience,
  });
  final String id, label, title, description;
  final VideoSource source;
  final String? countryCode, language;
  final String? authorName, authorAvatarUrl, authorId, publishedAt;
  final bool followed;
  AnalysisVideoRank get analysisRank => (
    followed: followed,
    language: language,
    publishedAt: publishedAt,
    label: label,
    id: id,
  );
  /// Analysis sources can be attached without identifying an author.
  final bool analysis;
  bool get isAnalysis => analysis || authorName != null;
  final bool preferred;
  final Set<VideoClientPlatform>? platforms;
  bool supportsPlatform(VideoClientPlatform platform) =>
      platforms == null || platforms!.contains(platform);
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

  // Metadata is immutable. Selector sorting, flags and labels used to replay
  // the same language detection (and compile its regexes) on every access.
  // Cache null too: unidentified streams previously did the most work.
  late final VideoLanguage? inferredLanguage = _resolveLanguage();

  VideoLanguage? _resolveLanguage() {
    final code = language?.trim().toLowerCase().split(RegExp('[-_]')).first;
    for (final item in videoLanguages) {
      if (item.code == code) return item;
    }
    // An analysis video always shows a language, as a flag like the event
    // streams: its own, else English. Its title is the author's, not a hint.
    if (isAnalysis) return videoLanguages.firstWhere((l) => l.code == 'en');
    final text = '$title $description $label';
    for (final item in videoLanguages) {
      for (final pattern in _languagePatterns[item.code]!) {
        if (pattern.hasMatch(text)) {
          return item;
        }
      }
    }
    return null;
  }

  String get languageKey => isAnalysis
      ? 'analysis-$id'
      : inferredLanguage?.code ??
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
    authorName: authorName,
    analysis: analysis,
    authorId: authorId,
    followed: followed,
    publishedAt: publishedAt,
    authorAvatarUrl: authorAvatarUrl,
    language: language,
    title: title,
    description: description,
    preferred: previous.preferred,
    platforms: platforms,
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
        final source = VideoSource.parse(
          raw['url'] as String,
          strict: raw['kind'] == 'analysis',
        );
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
        Set<VideoClientPlatform>? platforms;
        if (raw.containsKey('platforms')) {
          final values = raw['platforms'];
          if (values is! List ||
              values.any(
                (p) =>
                    !VideoClientPlatform.values.any(
                      (platform) => platform.name == p,
                    ),
              )) {
            continue;
          }
          platforms =
              VideoClientPlatform.values
                  .where((p) => values.contains(p.name))
                  .toSet();
        }
        final language =
            raw.containsKey('language')
                ? raw['language']
                : publication['language'];
        if (language != null && (language is! String || language.length > 80)) {
          continue;
        }
        final stream = EventVideoStream(
          id: id,
          label: label.trim(),
          source: source,
          analysis: raw['kind'] == 'analysis',
          authorId: raw['kind']=='analysis' && raw['authorId'] is String ? raw['authorId'] as String : null,
          followed: raw['followed'] == true,
          publishedAt: raw['kind']=='analysis' && raw['publishedAt'] is String ? raw['publishedAt'] as String : null,
          authorName: raw['kind'] == 'analysis' && raw['authorName'] is String
              ? raw['authorName'] as String
              : null,
          authorAvatarUrl:
              raw['kind'] == 'analysis' && raw['authorAvatarUrl'] is String
              ? raw['authorAvatarUrl'] as String
              : null,
          countryCode: flag,
          platforms: platforms,
          language: (language as String?)?.trim(),
          title: publication['title'] as String? ?? '',
          description: publication['description'] as String? ?? '',
          preferred: preferred == true,
          audience: VideoAudience.read(raw['audience'], source.platform),
        );
        if (ids.contains(id) ||
            (!stream.isAnalysis && sources.contains(source.url.toString()))) {
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

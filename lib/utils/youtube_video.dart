/// Per-game YouTube playback settings. Kept in parity with the web/API parser.
class YoutubeVideo {
  const YoutubeVideo({
    required this.id,
    this.start = 0,
    this.end,
    this.autoplay = false,
    this.muted = false,
    this.loop = false,
    this.captions = false,
    this.captionLanguage = '',
    this.playerLanguage = '',
  });

  final String id;
  final int start;
  final int? end;
  final bool autoplay, muted, loop, captions;
  final String captionLanguage, playerLanguage;

  static int time(String input) {
    final value = input.trim().toLowerCase();
    int? seconds = int.tryParse(value);
    if (seconds == null && RegExp(r'^\d+(?::[0-5]\d){1,2}$').hasMatch(value)) {
      seconds = value
          .split(':')
          .fold<int>(0, (sum, part) => sum * 60 + int.parse(part));
    }
    if (seconds == null) {
      final match = RegExp(
        r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$',
      ).firstMatch(value);
      if (match != null && value.isNotEmpty) {
        seconds =
            (int.tryParse(match[1] ?? '') ?? 0) * 3600 +
            (int.tryParse(match[2] ?? '') ?? 0) * 60 +
            (int.tryParse(match[3] ?? '') ?? 0);
      }
    }
    if (seconds == null || seconds < 0 || seconds > 2147483647) {
      throw const FormatException('Use seconds, mm:ss, hh:mm:ss, or 1h2m3s.');
    }
    return seconds;
  }

  static String formatTime(int value) => value >= 3600
      ? '${value ~/ 3600}:${((value ~/ 60) % 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}'
      : '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';

  static YoutubeVideo parse(String input) {
    if (input.trim().length > 2048) {
      throw const FormatException('Use a shorter video URL.');
    }
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        !const {
          'youtu.be',
          'youtube.com',
          'www.youtube.com',
          'm.youtube.com',
          'youtube-nocookie.com',
          'www.youtube-nocookie.com',
        }.contains(uri.host)) {
      throw const FormatException('Enter a YouTube HTTPS video URL.');
    }
    final path = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final id = uri.host == 'youtu.be' && path.length == 1
        ? path.first
        : uri.path == '/watch'
        ? uri.queryParameters['v']
        : path.length == 2 &&
              const {'embed', 'live', 'shorts'}.contains(path.first)
        ? path.last
        : null;
    if (id == null || !RegExp(r'^[\w-]{11}$').hasMatch(id)) {
      throw const FormatException('Link to one YouTube video.');
    }
    final q = uri.queryParameters;
    final fragment = Uri.splitQueryString(uri.fragment);
    final start = time(q['start'] ?? q['t'] ?? fragment['t'] ?? '0');
    final end = q.containsKey('end') ? time(q['end']!) : null;
    if (end != null && end <= start) {
      throw const FormatException('End time must be after start time.');
    }
    bool flag(String key) {
      if (!q.containsKey(key)) return false;
      if (q[key] != '0' && q[key] != '1') {
        throw FormatException('$key must be 0 or 1.');
      }
      return q[key] == '1';
    }

    String language(String key) {
      final value = q[key] ?? '';
      if (value.isNotEmpty &&
          !RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(value)) {
        throw const FormatException('Use a language code such as en or pt-BR.');
      }
      return value;
    }

    return YoutubeVideo(
      id: id,
      start: start,
      end: end,
      autoplay: flag('autoplay'),
      muted: flag('mute'),
      loop: flag('loop'),
      captions: flag('cc_load_policy'),
      captionLanguage: language('cc_lang_pref'),
      playerLanguage: language('hl'),
    );
  }

  Map<String, String> get parameters => {
    if (start != 0) 'start': '$start',
    if (end != null) 'end': '$end',
    if (autoplay) 'autoplay': '1',
    if (muted) 'mute': '1',
    if (loop) 'loop': '1',
    if (captions) 'cc_load_policy': '1',
    if (captionLanguage.isNotEmpty) 'cc_lang_pref': captionLanguage,
    if (playerLanguage.isNotEmpty) 'hl': playerLanguage,
  };
  Uri get url =>
      Uri.https('www.youtube.com', '/watch', {'v': id, ...parameters});
}
